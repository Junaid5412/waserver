import test from "node:test";
import assert from "node:assert/strict";
import { gateway } from "../src/whatsapp.js";
import { createChatResolver } from "../src/chat-resolver.js";
import { normalizeJid } from "../src/inbox.js";

test("Logging out succeeds even if WhatsApp closes the socket mid-logout", async () => {
  const records = new Map();
  const instance = { id: "i1", status: "connected", phone: "97451200749", connectionError: "old" };
  records.set("instances:i1", instance);
  const store = {
    async get(ns, key) { return records.get(ns + ":" + key); },
    async set(ns, key, value) { records.set(ns + ":" + key, value); },
    async patch(ns, key, value) { Object.assign(records.get(ns + ":" + key), value); },
    async clearNamespace() {},
  };
  let ended = false;
  const handlers = {};
  const socket = {
    ev: { on(e, h) { handlers[e] = h; } },
    end() { ended = true; },
    async logout() { throw new Error("Connection Closed"); },
  };
  const wa = gateway(store, { seal: (v) => v, open: (v) => v }, async () => {}, {
    versionFetcher: async () => ({ isLatest: true, version: [2, 3000, 1] }),
    socketFactory: () => socket,
  });
  await wa.connect(instance);
  await handlers["connection.update"]({ connection: "open" });
  await wa.disconnect(instance, true);
  assert.equal(instance.status, "disconnected");
  assert.equal(instance.connectionError, null);
  assert.equal(instance.phone, null);
  assert(ended);
  await wa.shutdown();
});

function fakeStore({ chats = [], contacts = [], aliases = [] }) {
  return { async query(ns) { return { chats, contacts, "wa-alias": aliases }[ns] || []; } };
}
const row = (chatId, extra = {}) => ({ id: "row-" + chatId, chatId, name: chatId, unread: 0, createdAt: "2026-10-01T10:00:00.000Z", ...extra });

test("normalizeJid removes device suffixes", () => {
  assert.equal(normalizeJid("97450000001:12@s.whatsapp.net"), "97450000001@s.whatsapp.net");
  assert.equal(normalizeJid("123-456@g.us"), "123-456@g.us");
});

test("One person with phone, device and @lid identifiers is shown as one conversation with the device contact name", async () => {
  const store = fakeStore({
    chats: [
      row("97450000001@s.whatsapp.net", { unread: 1, lastPreview: "old", createdAt: "2026-10-01T10:00:00.000Z" }),
      row("97450000001:7@s.whatsapp.net", { unread: 2, lastPreview: "newer", createdAt: "2026-10-01T11:00:00.000Z" }),
      row("555111@lid", { unread: 3, lastPreview: "newest", createdAt: "2026-10-01T12:00:00.000Z" }),
      row("123456@g.us"),
    ],
    contacts: [{ chatId: "97450000001@s.whatsapp.net", name: "Sam Saved", lid: "555111@lid" }],
  });
  const wa = { active: () => ({ groupFetchAllParticipating: async () => ({ "123456@g.us": { id: "123456@g.us", subject: "Family", participants: [{}, {}, {}] } }) }) };
  const resolver = createChatResolver({ store, wa });
  const list = await resolver.list({ id: "i1" }, store.query ? await store.query("chats") : []);
  const people = list.filter((c) => c.kind === "contact");
  assert.equal(people.length, 1);
  assert.equal(people[0].name, "Sam Saved");
  assert.equal(people[0].chatId, "97450000001@s.whatsapp.net");
  assert.equal(people[0].unread, 6);
  assert.equal(people[0].lastPreview, "newest");
  assert.equal(people[0].phone, "+97450000001");
  assert.deepEqual(new Set(people[0].aliases), new Set(["97450000001@s.whatsapp.net", "97450000001:7@s.whatsapp.net", "555111@lid"]));
  const group = list.find((c) => c.kind === "group");
  assert.equal(group.name, "Family");
  assert.equal(group.participants, 3);
});

test("Unnamed chats fall back to a readable phone number instead of a raw JID", async () => {
  const store = fakeStore({ chats: [row("97450000009@s.whatsapp.net")] });
  const resolver = createChatResolver({ store, wa: { active: () => { throw new Error("offline"); } } });
  const [chat] = await resolver.list({ id: "i1" }, await store.query("chats"));
  assert.equal(chat.name, "+97450000009");
});
