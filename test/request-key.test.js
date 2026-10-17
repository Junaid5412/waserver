import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { requestKey, apiRequestKey } from "../src/request-key.js";

test("Rate limits handle Unix requests without IP and preserve IPv6 subnet keys", () => {
  assert.equal(requestKey({ ip: undefined }), "127.0.0.1");
  assert.equal(requestKey({ ip: "203.0.113.12" }), "203.0.113.12");
  assert.equal(requestKey({ ip: "2001:db8::1" }), requestKey({ ip: "2001:db8::2" }));
  assert.doesNotThrow(() => createHash("sha256").update(requestKey({})).digest("hex"));
  assert.equal(requestKey({ headers: { "x-forwarded-for": "attacker" } }), "127.0.0.1");
});

test("Signed-in API clients are rate limited per token, others per IP", () => {
  const a = "a".repeat(64), b = "b".repeat(64);
  const keyA = apiRequestKey({ ip: undefined, headers: { authorization: "Bearer " + a } });
  const keyB = apiRequestKey({ ip: undefined, headers: { authorization: "Bearer " + b } });
  assert.notEqual(keyA, keyB);
  assert.equal(keyA, apiRequestKey({ ip: "203.0.113.9", headers: { authorization: "Bearer " + a } }));
  assert.equal(apiRequestKey({ ip: undefined, headers: { authorization: "Bearer short" } }), "127.0.0.1");
  assert.equal(apiRequestKey({ ip: "203.0.113.12", headers: {} }), "203.0.113.12");
});
