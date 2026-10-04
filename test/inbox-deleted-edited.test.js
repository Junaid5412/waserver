import test from "node:test";
import assert from "node:assert/strict";
import { createInbox, pack } from "../src/inbox.js";

function mockStore() {
  const map = new Map();
  return {
    async get(ns, key) { return map.get(ns + ":" + key); },
    async set(ns, key, val) { map.set(ns + ":" + key, val); },
    async patch(ns, key, patch) {
      const cur = map.get(ns + ":" + key) || {};
      const updated = typeof patch === "function" ? patch(cur) : { ...cur, ...patch };
      map.set(ns + ":" + key, updated);
      return updated;
    },
    async query(ns, q) {
      const res = [];
      for (const [k, v] of map.entries()) {
        if (!k.startsWith(ns + ":")) continue;
        let match = true;
        if (q?.instanceId && v.instanceId !== q.instanceId) match = false;
        if (q?.lookupKey && v.lookupKey !== q.lookupKey && v.waId !== q.lookupKey) match = false;
        if (match) res.push(v);
      }
      return res;
    },
  };
}

const enc = {
  seal: (v) => v,
  open: (v) => v,
};

test("markDeleted preserves message content and sets deleted: true and deletedAt timestamp in dto", async () => {
  const store = mockStore();
  const inbox = createInbox(store, enc);
  const instance = { id: "inst-1" };
  const waId = "msg-del-1";
  const rawMsg = { key: { id: waId, remoteJid: "123@s.whatsapp.net", fromMe: false }, message: { conversation: "Secret message" } };
  
  await store.set("wa-message:inst-1", waId, { id: waId, chatId: "123@s.whatsapp.net", fromMe: false, data: pack(enc, rawMsg) });
  const row = {
    id: "row-1",
    instanceId: "inst-1",
    lookupKey: waId,
    waId,
    chatId: "123@s.whatsapp.net",
    fromMe: false,
    status: "delivered",
    createdAt: new Date().toISOString(),
    data: pack(enc, rawMsg),
  };
  await store.set("inbox", "row-1", row);

  await inbox.markDeleted(instance, waId);
  const updatedRow = await store.get("inbox", "row-1");
  assert.equal(updatedRow.deleted, true);
  assert.ok(updatedRow.deletedAt);

  const dto = inbox.dto(updatedRow);
  assert.equal(dto.deleted, true);
  assert.equal(dto.text, "Secret message");
  assert.ok(dto.deletedAt);
});

test("applyEdit captures originalText, preserves history in edits, and returns them in dto", async () => {
  const store = mockStore();
  const inbox = createInbox(store, enc);
  const instance = { id: "inst-1" };
  const waId = "msg-edit-1";
  const rawMsg = { key: { id: waId, remoteJid: "123@s.whatsapp.net", fromMe: true }, message: { conversation: "Hello old text" } };

  await store.set("wa-message:inst-1", waId, { id: waId, chatId: "123@s.whatsapp.net", fromMe: true, data: pack(enc, rawMsg) });
  const row = {
    id: "row-edit-1",
    instanceId: "inst-1",
    lookupKey: waId,
    waId,
    chatId: "123@s.whatsapp.net",
    fromMe: true,
    status: "delivered",
    createdAt: new Date().toISOString(),
    data: pack(enc, rawMsg),
  };
  await store.set("inbox", "row-edit-1", row);

  await inbox.applyEdit(instance, waId, { conversation: "Hello new text" });
  let updatedRow = await store.get("inbox", "row-edit-1");
  assert.equal(updatedRow.edited, true);
  assert.equal(updatedRow.originalText, "Hello old text");
  assert.equal(updatedRow.edits.length, 1);
  assert.equal(updatedRow.edits[0].text, "Hello old text");

  let dto = inbox.dto(updatedRow);
  assert.equal(dto.edited, true);
  assert.equal(dto.text, "Hello new text");
  assert.equal(dto.originalText, "Hello old text");
  assert.equal(dto.edits.length, 1);

  // Second edit
  await inbox.applyEdit(instance, waId, { conversation: "Hello third text" });
  updatedRow = await store.get("inbox", "row-edit-1");
  assert.equal(updatedRow.originalText, "Hello old text");
  assert.equal(updatedRow.edits.length, 2);
  assert.equal(updatedRow.edits[1].text, "Hello new text");

  dto = inbox.dto(updatedRow);
  assert.equal(dto.text, "Hello third text");
  assert.equal(dto.originalText, "Hello old text");
  assert.equal(dto.edits.length, 2);
});

test("applyEdit recovers message data when wa-message: cache row is missing", async () => {
  const store = mockStore();
  const inbox = createInbox(store, enc);
  const instance = { id: "inst-1" };
  const waId = "msg-no-wamessage-1";
  const rawMsg = { key: { id: waId, remoteJid: "456@s.whatsapp.net", fromMe: false }, message: { conversation: "First original text" } };

  // Only stored in 'inbox', NOT in 'wa-message:inst-1'
  const row = {
    id: "row-no-wa-1",
    instanceId: "inst-1",
    lookupKey: waId,
    waId,
    chatId: "456@s.whatsapp.net",
    fromMe: false,
    status: "received",
    createdAt: new Date().toISOString(),
    data: pack(enc, rawMsg),
  };
  await store.set("inbox", "row-no-wa-1", row);

  await inbox.applyEdit(instance, waId, { conversation: "Second edited text" });
  const updatedRow = await store.get("inbox", "row-no-wa-1");
  assert.equal(updatedRow.edited, true);
  assert.equal(updatedRow.originalText, "First original text");
  assert.equal(updatedRow.edits.length, 1);
  assert.equal(updatedRow.edits[0].text, "First original text");

  const dto = inbox.dto(updatedRow);
  assert.equal(dto.edited, true);
  assert.equal(dto.text, "Second edited text");
  assert.equal(dto.originalText, "First original text");
});

test("applyEdit and unwrapEdited unwrap Baileys nested editedMessage structures", async () => {
  const store = mockStore();
  const inbox = createInbox(store, enc);
  const instance = { id: "inst-1" };
  const waId = "msg-nested-1";
  const rawMsg = { key: { id: waId, remoteJid: "456@s.whatsapp.net", fromMe: false }, message: { conversation: "Original unedited" } };

  await store.set("wa-message:inst-1", waId, { id: waId, chatId: "456@s.whatsapp.net", fromMe: false, data: pack(enc, rawMsg) });
  const row = {
    id: "row-nested-1",
    instanceId: "inst-1",
    lookupKey: waId,
    waId,
    chatId: "456@s.whatsapp.net",
    fromMe: false,
    status: "received",
    createdAt: new Date().toISOString(),
    data: pack(enc, rawMsg),
  };
  await store.set("inbox", "row-nested-1", row);

  // Baileys style nested editedMessage
  await inbox.applyEdit(instance, waId, {
    editedMessage: {
      message: {
        extendedTextMessage: { text: "Unwrapped text successfully" }
      }
    }
  });

  const updatedRow = await store.get("inbox", "row-nested-1");
  assert.equal(updatedRow.edited, true);
  const dto = inbox.dto(updatedRow);
  assert.equal(dto.text, "Unwrapped text successfully");
  assert.equal(dto.originalText, "Original unedited");
});

test("receipt handles messages.update with Baileys MESSAGE_EDIT payload", async () => {
  const store = mockStore();
  const inbox = createInbox(store, enc);
  const instance = { id: "inst-1" };
  const waId = "msg-receipt-edit-1";
  const rawMsg = { key: { id: waId, remoteJid: "789@s.whatsapp.net", fromMe: false }, message: { conversation: "Old message text" } };

  await store.set("wa-message:inst-1", waId, { id: waId, chatId: "789@s.whatsapp.net", fromMe: false, data: pack(enc, rawMsg) });
  const row = {
    id: "row-receipt-1",
    instanceId: "inst-1",
    lookupKey: waId,
    waId,
    chatId: "789@s.whatsapp.net",
    fromMe: false,
    status: "delivered",
    createdAt: new Date().toISOString(),
    data: pack(enc, rawMsg),
  };
  await store.set("inbox", "row-receipt-1", row);

  await inbox.receipt(instance, [
    {
      key: { id: waId, remoteJid: "789@s.whatsapp.net", fromMe: false },
      update: {
        message: {
          editedMessage: {
            message: {
              conversation: "Edited via receipt"
            }
          }
        },
        messageTimestamp: Math.floor(Date.now() / 1000)
      }
    }
  ]);

  const updatedRow = await store.get("inbox", "row-receipt-1");
  assert.equal(updatedRow.edited, true);
  assert.equal(updatedRow.originalText, "Old message text");

  const dto = inbox.dto(updatedRow);
  assert.equal(dto.edited, true);
  assert.equal(dto.text, "Edited via receipt");
  assert.equal(dto.originalText, "Old message text");
});

test("a message that is edited and then deleted preserves both edited history and deleted flag", async () => {
  const store = mockStore();
  const inbox = createInbox(store, enc);
  const instance = { id: "inst-1" };
  const waId = "msg-edit-then-del-1";
  const rawMsg = { key: { id: waId, remoteJid: "123@s.whatsapp.net", fromMe: false }, message: { conversation: "Initial message" } };

  await store.set("wa-message:inst-1", waId, { id: waId, chatId: "123@s.whatsapp.net", fromMe: false, data: pack(enc, rawMsg) });
  const row = {
    id: "row-edit-del-1",
    instanceId: "inst-1",
    lookupKey: waId,
    waId,
    chatId: "123@s.whatsapp.net",
    fromMe: false,
    status: "delivered",
    createdAt: new Date().toISOString(),
    data: pack(enc, rawMsg),
  };
  await store.set("inbox", "row-edit-del-1", row);

  // Edit it
  await inbox.applyEdit(instance, waId, { conversation: "Edited version" });
  // Delete it
  await inbox.markDeleted(instance, waId);

  const updatedRow = await store.get("inbox", "row-edit-del-1");
  assert.equal(updatedRow.edited, true);
  assert.equal(updatedRow.deleted, true);
  assert.equal(updatedRow.originalText, "Initial message");

  const dto = inbox.dto(updatedRow);
  assert.equal(dto.edited, true);
  assert.equal(dto.deleted, true);
  assert.equal(dto.text, "Edited version");
  assert.equal(dto.originalText, "Initial message");
  assert.ok(dto.deletedAt);
  assert.ok(dto.editedAt);
});

