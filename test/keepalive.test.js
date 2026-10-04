import test from "node:test";
import assert from "node:assert/strict";
import { createKeepAlive } from "../src/keepalive.js";
const mem = () => {
  const d = new Map();
  return {
    get: async (n, k) => d.get(n + k),
    set: async (n, k, v) => { d.set(n + k, v); },
    query: async () => [],
  };
};
test("keep-alive pings /health and reports status", async () => {
  const urls = [];
  const k = createKeepAlive({
    store: mem(), origin: "https://x.example/", wa: { has: () => true, connect: async () => {} },
    fetcher: async (u) => { urls.push(u); return { ok: true, status: 200 }; },
    enabled: false, minutes: 5,
  });
  await k.tick("test");
  assert.deepEqual(urls, ["https://x.example/health"]);
  assert.equal(k.status().lastOk, true);
  k.stop();
});
test("keep-alive records failures", async () => {
  const k = createKeepAlive({
    store: mem(), origin: "https://x.example", wa: { has: () => true, connect: async () => {} },
    fetcher: async () => { throw new Error("down"); }, enabled: false,
  });
  await k.tick("test");
  assert.equal(k.status().lastOk, false);
  k.stop();
});
