import test from "node:test";
import assert from "node:assert/strict";
import { openStore } from "../src/store.js";
test(
  "MySQL: persistence, indexes, atomic transitions, pagination and exclusive worker lease",
  { skip: !process.env.MYSQL_HOST },
  async () => {
    let store = await openStore();
    try {
      await store.set("mysql-test", "first", {
        id: "first",
        instanceId: "number",
        userId: "owner",
        status: "queued",
        createdAt: "2026-10-01T01:00:00Z",
        sendAt: 100,
      });
      assert.equal(
        await store.insert("mysql-test", "first", { id: "duplicate" }),
        false,
      );
      await store.set("mysql-test", "second", {
        id: "second",
        instanceId: "number",
        userId: "owner",
        status: "queued",
        createdAt: "2026-10-01T01:00:00Z",
        sendAt: 200,
      });
      assert.equal(
        (
          await store.query("mysql-test", {
            instanceId: "number",
            status: "queued",
            dueBefore: 150,
          })
        ).length,
        1,
      );
      const claims = await Promise.all(
        Array.from({ length: 5 }, () =>
          store.transition("mysql-test", "first", "queued", {
            id: "first",
            instanceId: "number",
            userId: "owner",
            status: "sending",
            createdAt: "2026-10-01T01:00:00Z",
          }),
        ),
      );
      assert.equal(claims.filter(Boolean).length, 1);
      await assert.rejects(openStore(), /Another Zelon server/);
      await store.close();
      store = await openStore();
      assert.equal((await store.get("mysql-test", "first")).status, "sending");
      const page = await store.query("mysql-test", {
        instanceId: "number",
        limit: 1,
      });
      assert.equal(page[0].id, "second");
      const next = await store.query("mysql-test", {
        instanceId: "number",
        limit: 1,
        before: Date.parse(page[0].createdAt),
        beforeKey: page[0].id,
      });
      assert.equal(next[0].id, "first");
      await store.set("mysql-test", "chat-job", {
        id: "chat-job",
        instanceId: "number",
        userId: "owner",
        chatId: "97450000000@s.whatsapp.net",
        campaignId: "campaign",
        lookupKey: "wa-id",
        status: "queued",
        createdAt: "2026-10-02T00:00:00Z",
      });
      assert.equal(
        (
          await store.query("mysql-test", {
            instanceId: "number",
            chatId: "97450000000@s.whatsapp.net",
            campaignId: "campaign",
            lookupKey: "wa-id",
          })
        ).length,
        1,
      );
      await store.patch("mysql-test", "chat-job", (r) => ({
        ...r,
        counter: (r.counter || 0) + 1,
      }));
      assert.equal((await store.get("mysql-test", "chat-job")).counter, 1);
      assert.equal(
        (await store.stats("mysql-test", { instanceId: "number" })).queued,
        2,
      );
      await store.health();
      await store.clearNamespace("mysql-test");
      assert.equal((await store.all("mysql-test")).length, 0);
    } finally {
      await store.close();
    }
  },
);
