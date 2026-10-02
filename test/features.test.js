import test from "node:test";
import assert from "node:assert/strict";
import express from "express";
import { randomBytes, createHash } from "node:crypto";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { openStore } from "../src/store.js";
import { cipher, hash } from "../src/security.js";
import { createMediaStore, CHUNK_SIZE } from "../src/media.js";
import { createInbox, timestampSeconds } from "../src/inbox.js";
import { createAutomation } from "../src/automation.js";
import { createFeatures } from "../src/features.js";
import {
  buildContent,
  messageSchema,
  validateMessage,
} from "../src/content.js";
import { createWorker } from "../src/worker.js";
async function fixture(t) {
  const dir = await mkdtemp(tmpdir() + "/zelon-features-");
  process.env.SQLITE_PATH = dir + "/db";
  const store = await openStore(),
    enc = cipher(randomBytes(32).toString("base64"));
  t.after(async () => {
    await store.close();
    await rm(dir, { recursive: true });
  });
  const instance = {
    id: "instance-a",
    userId: "user-a",
    phone: "97450000000",
    status: "connected",
    createdAt: new Date().toISOString(),
  };
  await store.set("instances", instance.id, instance);
  const inbox = createInbox(store, enc),
    media = createMediaStore(store, enc),
    calls = [];
  const socket = {
    user: { id: "97450000000:1@s.whatsapp.net" },
    sendMessage: async (to, content, options) => {
      calls.push({ to, content, options });
      return {
        key: { id: "sent-" + calls.length, remoteJid: to, fromMe: true },
        message: content,
        messageTimestamp: Math.floor(Date.now() / 1000),
      };
    },
    readMessages: async (keys) => calls.push({ read: keys }),
    chatModify: async (mod, chat) => calls.push({ mod, chat }),
    star: async () => {},
    sendPresenceUpdate: async () => {},
  };
  const wa = {
    active: () => socket,
    recordSent: async (x, m) => inbox.persist(x, m),
    disconnect: async () => {},
    connect: async () => {},
    pairingCode: async () => "12345678",
  };
  return { store, enc, instance, inbox, media, wa, calls };
}
test("Chunk media persists, validates sizes and content, isolates tenants, streams encrypted bytes", async (t) => {
  const f = await fixture(t);
  const bytes = randomBytes(CHUNK_SIZE + 31),
    item = await f.media.create(f.instance, {
      filename: "data.bin",
      size: bytes.length,
      mimetype: "application/octet-stream",
    });
  await assert.rejects(
    f.media.complete(f.instance, item.id),
    (e) => e.status === 409,
  );
  await assert.rejects(
    f.media.chunk(f.instance, item.id, 0, bytes.subarray(0, 10)),
    (e) => e.status === 400,
  );
  await f.media.chunk(f.instance, item.id, 0, bytes.subarray(0, CHUNK_SIZE));
  await f.media.chunk(f.instance, item.id, 0, bytes.subarray(0, CHUNK_SIZE));
  await assert.rejects(
    f.media.chunk(f.instance, item.id, 0, randomBytes(CHUNK_SIZE)),
    (e) => e.status === 409,
  );
  await f.media.chunk(f.instance, item.id, 1, bytes.subarray(CHUNK_SIZE));
  const ready = await f.media.complete(f.instance, item.id);
  assert.equal(ready.digest, createHash("sha256").update(bytes).digest("hex"));
  assert.deepEqual(await f.media.buffer(f.instance, item.id), bytes);
  await assert.rejects(
    f.media.owned({ ...f.instance, id: "other" }, item.id),
    (e) => e.status === 404,
  );
  const raw = await f.store.get("media-chunks:" + item.id, "00000000");
  assert(!raw.data.includes(bytes.subarray(0, 50).toString("base64")));
  const built = await buildContent(f.media, f.inbox.load)(
    { type: "document", to: "97450000000@s.whatsapp.net", mediaId: item.id },
    f.instance,
  );
  const streamed = [];
  for await (const c of built.content.document.stream) streamed.push(c);
  assert.deepEqual(Buffer.concat(streamed), bytes);
});
test("Inbox deduplicates history, decrypts typed content, tracks unread and outgoing receipts", async (t) => {
  const f = await fixture(t),
    chat = "97450000001@s.whatsapp.net";
  const m = {
    key: { id: "incoming1", remoteJid: chat, fromMe: false },
    pushName: "A <script>",
    message: { conversation: "hello" },
    messageTimestamp: 1700000000,
  };
  assert.equal(await f.inbox.persist(f.instance, m, { notify: true }), true);
  assert.equal(await f.inbox.persist(f.instance, m, { notify: true }), false);
  assert.equal(
    (await f.store.get("chats", hash(f.instance.id + ":" + chat))).unread,
    1,
  );
  assert.equal(
    f.inbox.dto((await f.store.query("inbox", { chatId: chat }))[0]).text,
    "hello",
  );
  assert.deepEqual((await f.inbox.load(f.instance.id, m.key.id)).key, m.key);
  await f.store.set("messages", "job", {
    id: "job",
    instanceId: f.instance.id,
    waId: "outgoing1",
    status: "sent",
  });
  await f.inbox.receipt(f.instance, [
    { key: { id: "outgoing1" }, update: { status: 4 } },
  ]);
  assert.equal((await f.store.get("messages", "job")).status, "read");
  await f.inbox.receipt(f.instance, [
    { key: { id: "outgoing1" }, update: { status: 3 } },
  ]);
  assert.equal((await f.store.get("messages", "job")).status, "read");
  assert.equal(timestampSeconds({ low: 1700000000, high: 0 }), 1700000000);
});
test("Auto replies personalize and obey cooldown; STOP creates a durable opt-out even for unknown contacts", async (t) => {
  const f = await fixture(t),
    auto = createAutomation(f.store, f.enc),
    chat = "97450000001@s.whatsapp.net";
  await f.store.set("rules", "r", {
    id: "r",
    instanceId: f.instance.id,
    status: "enabled",
    match: "contains",
    keyword: "hi",
    reply: "Hello {{name}}: {{message}}",
    cooldownSeconds: 60,
    stopAfterMatch: true,
  });
  const m = (id) => ({
    key: { id, remoteJid: chat, fromMe: false },
    pushName: "Sam",
    message: { conversation: "hi there" },
  });
  await Promise.all([auto(f.instance, m("a")), auto(f.instance, m("b"))]);
  const rows = await f.store.query("messages", { instanceId: f.instance.id });
  assert.equal(rows.length, 1);
  assert.equal(
    JSON.parse(f.enc.open(rows[0].payload)).text,
    "Hello Sam: hi there",
  );
  await auto(f.instance, { ...m("stop"), message: { conversation: "STOP" } });
  assert.equal(
    (await f.store.get("contacts", hash(f.instance.id + ":" + chat))).optedOut,
    true,
  );
  await auto(f.instance, m("c"));
  assert.equal(
    (await f.store.query("messages", { instanceId: f.instance.id })).length,
    1,
  );
});
test("Feature API campaigns deduplicate, preserve opt-outs, pause/resume/cancel and enforce ownership", async (t) => {
  const f = await fixture(t);
  const app = express();
  app.use(express.json());
  app.use((req, res, next) => {
    req.instance = f.instance;
    req.user = { id: f.instance.userId };
    next();
  });
  const wrap = (fn) => (req, res, next) =>
    Promise.resolve(fn(req, res, next)).catch(next);
  app.use(createFeatures({ ...f, wrap, page: () => ({ limit: 100 }) }));
  app.use((e, req, res, next) =>
    res.status(e.status || 400).json({ error: e.message }),
  );
  const server = app.listen(0, "127.0.0.1");
  await new Promise((r) => server.once("listening", r));
  t.after(() => new Promise((r) => server.close(r)));
  const origin = "http://127.0.0.1:" + server.address().port;
  const call = async (url, method = "GET", body, key) => {
    const r = await fetch(origin + url, {
      method,
      headers: {
        "Content-Type": "application/json",
        ...(key ? { "Idempotency-Key": key } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
    });
    return { status: r.status, data: await r.json() };
  };
  const blocked = await call("/contacts", "POST", {
    phone: "+97450000002",
    name: "Opted out",
    optedOut: true,
  });
  await call("/contacts/import", "POST", {
    contacts: [{ phone: "+97450000002", name: "Imported" }],
  });
  assert((await f.store.get("contacts", blocked.data.id)).optedOut);
  const input = {
    name: "Welcome",
    recipients: ["+97450000001", "+97450000002", "+97450000001"],
    message: { type: "text", text: "Hello {{phone}}" },
    intervalSeconds: 1,
    consentConfirmed: true,
  };
  const c = await call("/campaigns", "POST", input, "campaign-test-key");
  assert.equal(c.status, 201);
  assert.equal(c.data.total, 2);
  assert.equal(c.data.skipped, 1);
  assert.equal(
    (await call("/campaigns", "POST", input, "campaign-test-key")).status,
    200,
  );
  assert.equal(
    (
      await call(
        "/campaigns",
        "POST",
        { ...input, name: "Changed" },
        "campaign-test-key",
      )
    ).status,
    409,
  );
  assert.equal(
    (await f.store.query("messages", { campaignId: c.data.id })).length,
    1,
  );
  await call("/campaigns/" + c.data.id, "PUT", { status: "paused" });
  assert.equal(
    (await f.store.query("messages", { campaignId: c.data.id }))[0].status,
    "paused",
  );
  await createWorker(
    f.store,
    f.enc,
    f.wa,
    buildContent(f.media, f.inbox.load),
  )();
  assert.equal(f.calls.length, 0);
  await call("/campaigns/" + c.data.id, "PUT", { status: "running" });
  assert.equal(
    (await f.store.query("messages", { campaignId: c.data.id }))[0].status,
    "queued",
  );
  await call("/campaigns/" + c.data.id, "PUT", { status: "cancelled" });
  assert.equal(
    (await f.store.query("messages", { campaignId: c.data.id }))[0].status,
    "cancelled",
  );
  assert.equal(
    (await call("/campaigns/" + c.data.id, "PUT", { status: "running" }))
      .status,
    409,
  );
  await f.store.set("rules", "foreign", { id: "foreign", instanceId: "other" });
  assert.equal((await call("/rules/foreign", "DELETE")).status, 404);
  await f.store.set("media", "foreign", {
    id: "foreign",
    instanceId: "other",
    userId: "other",
  });
  assert.equal((await call("/media/foreign/download")).status, 404);
  assert.equal(
    (await call("/campaigns", "POST", { ...input, consentConfirmed: false }))
      .status,
    400,
  );
});
test("Message validation scopes references, requires valid content and supports quotes and mentions", async (t) => {
  const f = await fixture(t);
  await assert.rejects(
    validateMessage(
      f.instance,
      messageSchema.parse({
        to: "+97450000001",
        type: "poll",
        text: "Choose",
        options: ["A", "B"],
        selectableCount: 3,
      }),
      f.media,
      f.inbox.load,
    ),
    (e) => e.status === 400,
  );
  await assert.rejects(
    validateMessage(
      f.instance,
      messageSchema.parse({
        to: "+97450000001",
        type: "forward",
        forwardId: "foreign",
      }),
      f.media,
      f.inbox.load,
    ),
    (e) => e.status === 404,
  );
  const d = messageSchema.parse({
    to: "+97450000001",
    type: "text",
    text: "Hi",
    mentions: ["+97450000002"],
  });
  await validateMessage(f.instance, d, f.media, f.inbox.load);
  assert.equal(d.mentions[0], "97450000002@s.whatsapp.net");
});

test("Worker rechecks opt-outs before queued campaigns and automatic replies send", async (t) => {
  const f = await fixture(t);
  const to = "97450000001@s.whatsapp.net";
  await f.store.set("contacts", hash(f.instance.id + ":" + to), {
    optedOut: true,
  });
  await f.store.set("campaigns", "c", { id: "c", status: "running" });
  for (const [id, extra] of [
    ["campaign", { campaignId: "c" }],
    ["auto", { automationRuleId: "r" }],
  ])
    await f.store.set("messages", id, {
      id,
      ...extra,
      instanceId: f.instance.id,
      status: "queued",
      to,
      sendAt: Date.now() - 1000,
      createdAt: new Date().toISOString(),
      payload: f.enc.seal(JSON.stringify({ to, type: "text", text: "Skip" })),
    });
  await createWorker(
    f.store,
    f.enc,
    f.wa,
    buildContent(f.media, f.inbox.load),
  )();
  assert.equal(f.calls.length, 0);
  assert.equal(
    (await f.store.query("messages", { status: "cancelled" })).length,
    2,
  );
});
