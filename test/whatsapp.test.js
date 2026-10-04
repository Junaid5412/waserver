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
