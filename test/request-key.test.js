import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { requestKey } from "../src/request-key.js";

test("Rate limits handle Unix requests without IP and preserve IPv6 subnet keys", () => {
  assert.equal(requestKey({ ip: undefined }), "127.0.0.1");
  assert.equal(requestKey({ ip: "203.0.113.12" }), "203.0.113.12");
  assert.equal(requestKey({ ip: "2001:db8::1" }), requestKey({ ip: "2001:db8::2" }));
  assert.doesNotThrow(() => createHash("sha256").update(requestKey({})).digest("hex"));
  assert.equal(requestKey({ headers: { "x-forwarded-for": "attacker" } }), "127.0.0.1");
});
