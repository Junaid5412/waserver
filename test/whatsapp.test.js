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
  };
  let options;
  const handlers = {};
  const socket = { ev: { on(event, handler) { handlers[event] = handler; } }, end() {} };
  const wa = gateway(store, { seal: value => value, open: value => value }, async () => {}, {
    versionFetcher, socketFactory(config) { options = config; return socket; },
  });
  return { wa, instance, handlers, get options() { return options; } };
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
