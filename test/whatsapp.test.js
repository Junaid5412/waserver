import test from "node:test";
import assert from "node:assert/strict";
import { gateway } from "../src/whatsapp.js";
function fixture(versionFetcher) {
  const records = new Map();
  const instance = { id: "test-instance", status: "disconnected" };
  records.set("instances:" + instance.id, instance);
  const store = {
    async get(ns, key) { return records.get(ns + ":" + key); },
    async set(ns, key, value) { records.set(ns + ":" + key, value); },
    async patch(ns, key, value) { Object.assign(records.get(ns + ":" + key), value); },
    async clearNamespace(ns) {
      for (const k of Array.from(records.keys())) {
        if (k.startsWith(ns + ":")) records.delete(k);
      }
    },
  };
  let options;
  const handlers = {};
  const socket = { ev: { on(event, handler) { handlers[event] = handler; } }, end() {} };
  const wa = gateway(store, { seal: value => value, open: value => value }, async () => {}, {
    versionFetcher, socketFactory(config) { options = config; return socket; },
  });
  return { wa, instance, handlers, records, store, get options() { return options; } };
}
test("WhatsApp uses fetched protocol, publishes QR and clears it on open", async () => {
  const f = fixture(async () => ({ isLatest: true, version: [2, 3000, 123456] }));
  await f.wa.connect(f.instance);
  assert.deepEqual(f.options.version, [2, 3000, 123456]);
  await f.handlers["connection.update"]({ qr: "mock WhatsApp linking challenge" });
  assert.match(f.wa.qr(f.instance.id), /^data:image\/png;base64,/);
  assert.equal(f.instance.status, "awaiting_qr");
  await f.handlers["connection.update"]({ connection: "open" });
  assert.equal(f.instance.status, "connected");
  assert.equal(f.wa.qr(f.instance.id), undefined);
  await f.wa.shutdown();
});
test("Version fetch failure is visible and does not silently use stale protocol", async () => {
  const f = fixture(async () => ({ isLatest: false, version: [2, 3000, 1] }));
  await assert.rejects(f.wa.connect(f.instance), /current WhatsApp Web version/);
  assert.equal(f.options, undefined);
  assert.equal(f.instance.status, "disconnected");
  assert.match(f.instance.connectionError, /outbound HTTPS/);
});
test("Logged out disconnect clears auth namespace so new QR can be requested", async () => {
  const f = fixture(async () => ({ isLatest: true, version: [2, 3000, 123456] }));
  await f.wa.connect(f.instance);
  await f.handlers["connection.update"]({ connection: "open" });
  f.instance.phone = "123456789";
  f.records.set("auth:" + f.instance.id + ":creds", { data: JSON.stringify({ registered: true }) });
  
  // Simulate WhatsApp 401 logged out
  await f.handlers["connection.update"]({
    connection: "close",
    lastDisconnect: { error: { output: { statusCode: 401 } } },
  });
  assert.equal(f.instance.status, "disconnected");
  assert.equal(f.instance.phone, null);
  assert.match(f.instance.connectionError, /logged out/i);
  assert.equal(f.records.has("auth:" + f.instance.id + ":creds"), false);

  // Calling reset with forceClean clears any remnant auth and error
  await f.wa.reset(f.instance, true);
  assert.equal(f.instance.connectionError, null);
  await f.wa.shutdown();
});
test("1:1 sends go to the recipient's LID, groups refresh sender keys, failures fall back", async () => {
  const records = new Map();
  const instance = { id: "lid-instance", status: "disconnected" };
  records.set("instances:" + instance.id, instance);
  const store = {
    async get(ns, key) { return records.get(ns + ":" + key); },
    async set(ns, key, value) { records.set(ns + ":" + key, value); },
    async patch(ns, key, value) { Object.assign(records.get(ns + ":" + key), value); },
    async clearNamespace() {},
  };
  const sent = [], keySets = [], aliases = [];
  const socket = {
    ev: { on() {} }, end() {},
    user: { id: "97400000000:3@s.whatsapp.net" },
    authState: { keys: { async set(data) { keySets.push(data); } } },
    signalRepository: { lidMapping: { async getLIDForPN(pn) {
      if (pn === "97411111111@s.whatsapp.net") return "123456789012345@lid";
      if (pn === "97422222222@s.whatsapp.net") throw Error("usync failed");
      return null;
    } } },
    async sendMessage(jid, content, options) { sent.push({ jid, options }); return { key: { id: "X", remoteJid: jid } }; },
  };
  const wa = gateway(store, { seal: (v) => v, open: (v) => v }, async () => {}, {
    versionFetcher: async () => ({ isLatest: true, version: [2, 3000, 1] }),
    socketFactory: () => socket,
    inbox: { async alias(inst, lid, pn) { aliases.push([inst.id, lid, pn]); } },
  });
  await wa.connect(instance);
  await socket.sendMessage("97411111111@s.whatsapp.net", { text: "hi" });
  await socket.sendMessage("97422222222@s.whatsapp.net", { text: "hi" });
  await socket.sendMessage("97433333333@s.whatsapp.net", { text: "hi" });
  await socket.sendMessage("97400000000@s.whatsapp.net", { text: "note to self" });
  await socket.sendMessage("555@lid", { text: "hi" });
  await socket.sendMessage("status@broadcast", { text: "s" }, { statusJidList: ["97411111111@s.whatsapp.net", "97433333333@s.whatsapp.net"] });
  await socket.sendMessage("120363000000000000@g.us", { text: "g1" });
  await socket.sendMessage("120363000000000000@g.us", { text: "g2" });
  assert.deepEqual(sent.map((s) => s.jid), [
    "123456789012345@lid",
    "97422222222@s.whatsapp.net",
    "97433333333@s.whatsapp.net",
    "97400000000@s.whatsapp.net",
    "555@lid",
    "status@broadcast",
    "120363000000000000@g.us",
    "120363000000000000@g.us",
  ]);
  assert.deepEqual(sent[5].options.statusJidList, ["123456789012345@lid", "97433333333@s.whatsapp.net"]);
  assert.deepEqual(aliases[0], [instance.id, "123456789012345@lid", "97411111111@s.whatsapp.net"]);
  // Sender-key memory is cleared once for the group, not on every send.
  assert.deepEqual(keySets, [{ "sender-key-memory": { "120363000000000000@g.us": null } }]);
  await wa.shutdown();
});
