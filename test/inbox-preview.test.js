import test from "node:test";
import assert from "node:assert/strict";
import { isJunkType, previewOf } from "../src/inbox.js";

test("system message types are treated as junk", () => {
  for (const t of ["comment", "encComment", "secretEncrypted", "pollUpdate", "protocol", "commentMessage"]) assert.equal(isJunkType(t), true, t);
  for (const t of ["text", "audio", "image", "document", "location", "poll", "conversation"]) assert.equal(isJunkType(t), false, t);
});

test("previews are human readable", () => {
  assert.equal(previewOf({ text: "hello", type: "text" }), "hello");
  assert.match(previewOf({ type: "audio" }), /Voice message/);
  assert.match(previewOf({ type: "document", filename: "a.pdf" }), /a\.pdf/);
  assert.match(previewOf({ type: "location" }), /Location/);
});
