import test from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import { aesEncryptGCM, hmacSign, proto } from "@whiskeysockets/baileys";
import { createInbox, pack, decryptSecretEncryptedMessage } from "../src/inbox.js";

function mockStore() {
  const map = new Map();
  return {
    async get(ns, key) { return map.get(ns + ":" + key); },
    async set(ns, key, val) { map.set(ns + ":" + key, val); },
    async insert(ns, key, val) {
      const full = ns + ":" + key;
      if (map.has(full)) return false;
      map.set(full, val);
      return true;
    },
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

test("decryptSecretEncryptedMessage successfully decrypts WhatsApp edited message payload", async () => {
  const secret = crypto.randomBytes(32);
  const targetId = "3EB0ABC123DEF456";
  const sender = "1234567890:1@s.whatsapp.net";
  const sign = Buffer.concat([
    Buffer.from(targetId),
    Buffer.from(sender),
    Buffer.from(sender),
    Buffer.from("Message Edit"),
    new Uint8Array([1]),
  ]);
  const key = hmacSign(secret, new Uint8Array(32));
  const encKey = hmacSign(sign, key);
  const iv = crypto.randomBytes(12);
  const originalProto = proto.Message.encode({ conversation: "Encrypted edited text" }).finish();
  const encPayload = aesEncryptGCM(originalProto, encKey, iv, Buffer.from(""));
  const secretEnc = { encPayload, encIv: iv };

  const decrypted = decryptSecretEncryptedMessage(secretEnc, { secret, id: targetId, sender });
  assert.ok(decrypted);
  assert.equal(decrypted.conversation, "Encrypted edited text");
});

test("persist handles incoming counterparty edit via secretEncryptedMessage", async () => {
  const store = mockStore();
  let updatedEvent = null;
  const inbox = createInbox(store, enc, (inst, ev) => { updatedEvent = ev; });
  const instance = { id: "inst-1", userId: "user-1" };
  const targetId = "COUNTERPARTY_MSG_1";
  const counterpartyJid = "9876543210@s.whatsapp.net";
  const secret = crypto.randomBytes(32);

  // 1. Initial message from counterparty
  const initialMsg = {
    key: { id: targetId, remoteJid: counterpartyJid, fromMe: false },
    message: {
      conversation: "Hello from counterparty (original)",
      messageContextInfo: { messageSecret: secret },
    },
    messageTimestamp: Math.floor(Date.now() / 1000),
  };
  await inbox.persist(instance, initialMsg);

  // 2. Incoming edit arrives as secretEncryptedMessage under a new stanza ID
  const sign = Buffer.concat([
    Buffer.from(targetId),
    Buffer.from(counterpartyJid),
    Buffer.from(counterpartyJid),
    Buffer.from("Message Edit"),
    new Uint8Array([1]),
  ]);
  const key = hmacSign(secret, new Uint8Array(32));
  const encKey = hmacSign(sign, key);
  const iv = crypto.randomBytes(12);
  const editedProto = proto.Message.encode({ conversation: "Hello from counterparty (EDITED!)" }).finish();
  const encPayload = aesEncryptGCM(editedProto, encKey, iv, Buffer.from(""));

  const editMsgStanza = {
    key: { id: "STANZA_EDIT_999", remoteJid: counterpartyJid, fromMe: false },
    message: {
      secretEncryptedMessage: {
        targetMessageKey: { id: targetId, remoteJid: counterpartyJid, fromMe: false },
        encPayload,
        encIv: iv,
      },
    },
    messageTimestamp: Math.floor(Date.now() / 1000) + 5,
  };

  const persistResult = await inbox.persist(instance, editMsgStanza);
  assert.equal(persistResult, false, "Edit stanzas should not be inserted as duplicate messages");

  // 3. Verify original message row was updated
  const rows = await store.query("inbox", { instanceId: instance.id, lookupKey: targetId });
  assert.equal(rows.length, 1);
  const row = rows[0];
  assert.equal(row.edited, true);
  assert.equal(row.originalText, "Hello from counterparty (original)");
  assert.equal(row.edits.length, 1);
  assert.equal(row.edits[0].text, "Hello from counterparty (original)");

  const dto = inbox.dto(row);
  assert.equal(dto.edited, true);
  assert.equal(dto.text, "Hello from counterparty (EDITED!)");
  assert.equal(dto.originalText, "Hello from counterparty (original)");

  // 4. Verify no spurious message exists for STANZA_EDIT_999
  const spuriousRows = await store.query("inbox", { instanceId: instance.id, lookupKey: "STANZA_EDIT_999" });
  assert.equal(spuriousRows.length, 0);

  // 5. Verify notify update event was fired
  assert.ok(updatedEvent);
  assert.equal(updatedEvent.type, "update");
  assert.equal(updatedEvent.waId, targetId);
});

test("persist handles incoming counterparty edit via protocolMessage with different stanza ID", async () => {
  const store = mockStore();
  const inbox = createInbox(store, enc);
  const instance = { id: "inst-1", userId: "user-1" };
  const targetId = "COUNTERPARTY_PM_1";
  const counterpartyJid = "5551234@s.whatsapp.net";

  const initialMsg = {
    key: { id: targetId, remoteJid: counterpartyJid, fromMe: false },
    message: { conversation: "Original text before PM edit" },
    messageTimestamp: Math.floor(Date.now() / 1000),
  };
  await inbox.persist(instance, initialMsg);

  const pmEditStanza = {
    key: { id: "STANZA_PM_888", remoteJid: counterpartyJid, fromMe: false },
    message: {
      protocolMessage: {
        type: 14,
        key: { id: targetId, remoteJid: counterpartyJid, fromMe: false },
        editedMessage: { conversation: "Updated text via protocolMessage" },
      },
    },
    messageTimestamp: Math.floor(Date.now() / 1000) + 10,
  };

  const persistResult = await inbox.persist(instance, pmEditStanza);
  assert.equal(persistResult, false);

  const rows = await store.query("inbox", { instanceId: instance.id, lookupKey: targetId });
  assert.equal(rows.length, 1);
  const dto = inbox.dto(rows[0]);
  assert.equal(dto.edited, true);
  assert.equal(dto.text, "Updated text via protocolMessage");
  assert.equal(dto.originalText, "Original text before PM edit");

  const spuriousRows = await store.query("inbox", { instanceId: instance.id, lookupKey: "STANZA_PM_888" });
  assert.equal(spuriousRows.length, 0);
});

test("receipt handles secretEncryptedMessage update for counterparty message", async () => {
  const store = mockStore();
  const inbox = createInbox(store, enc);
  const instance = { id: "inst-1", userId: "user-1" };
  const targetId = "MSG_RECEIPT_SECRET_1";
  const counterpartyJid = "777888999@s.whatsapp.net";
  const secret = crypto.randomBytes(32);

  const initialMsg = {
    key: { id: targetId, remoteJid: counterpartyJid, fromMe: false },
    message: {
      conversation: "Receipt original message",
      messageContextInfo: { messageSecret: secret },
    },
    messageTimestamp: Math.floor(Date.now() / 1000),
  };
  await inbox.persist(instance, initialMsg);

  const sign = Buffer.concat([
    Buffer.from(targetId),
    Buffer.from(counterpartyJid),
    Buffer.from(counterpartyJid),
    Buffer.from("Message Edit"),
    new Uint8Array([1]),
  ]);
  const key = hmacSign(secret, new Uint8Array(32));
  const encKey = hmacSign(sign, key);
  const iv = crypto.randomBytes(12);
  const editedProto = proto.Message.encode({ conversation: "Receipt decrypted edited message!" }).finish();
  const encPayload = aesEncryptGCM(editedProto, encKey, iv, Buffer.from(""));

  await inbox.receipt(instance, [
    {
      key: { id: "STANZA_UPDATE_1", remoteJid: counterpartyJid, fromMe: false },
      update: {
        message: {
          secretEncryptedMessage: {
            targetMessageKey: { id: targetId, remoteJid: counterpartyJid, fromMe: false },
            encPayload,
            encIv: iv,
          },
        },
      },
    },
  ]);

  const rows = await store.query("inbox", { instanceId: instance.id, lookupKey: targetId });
  assert.equal(rows.length, 1);
  const dto = inbox.dto(rows[0]);
  assert.equal(dto.edited, true);
  assert.equal(dto.text, "Receipt decrypted edited message!");
  assert.equal(dto.originalText, "Receipt original message");
});

test("persist handles incoming counterparty edit where messageSecret is unpacked as a base64 string", async () => {
  const store = mockStore();
  const inbox = createInbox(store, enc);
  const instance = { id: "inst-1", userId: "user-1" };
  const targetId = "MSG_BASE64_SECRET";
  const counterpartyJid = "923001234567@s.whatsapp.net";
  const rawSecret = crypto.randomBytes(32);
  const base64Secret = rawSecret.toString("base64");

  // Initial message stored with messageSecret as base64 string (typical when deserialized from JSON/store)
  const initialMsg = {
    key: { id: targetId, remoteJid: counterpartyJid, fromMe: false },
    message: {
      conversation: "Original base64 text",
      messageContextInfo: { messageSecret: base64Secret },
    },
    messageTimestamp: Math.floor(Date.now() / 1000),
  };
  await inbox.persist(instance, initialMsg);

  // Incoming edit encrypted with raw 32-byte secret
  const sign = Buffer.concat([
    Buffer.from(targetId),
    Buffer.from(counterpartyJid),
    Buffer.from(counterpartyJid),
    Buffer.from("Message Edit"),
    new Uint8Array([1]),
  ]);
  const key = hmacSign(rawSecret, new Uint8Array(32));
  const encKey = hmacSign(sign, key);
  const iv = crypto.randomBytes(12);
  const editedProto = proto.Message.encode({ conversation: "Decrypted with base64 secret!" }).finish();
  const encPayload = aesEncryptGCM(editedProto, encKey, iv, Buffer.from(""));

  const editMsgStanza = {
    key: { id: "STANZA_BASE64_EDIT", remoteJid: counterpartyJid, fromMe: false },
    message: {
      secretEncryptedMessage: {
        targetMessageKey: { id: targetId, remoteJid: counterpartyJid, fromMe: false },
        encPayload,
        encIv: iv,
      },
    },
    messageTimestamp: Math.floor(Date.now() / 1000) + 2,
  };

  const persistResult = await inbox.persist(instance, editMsgStanza);
  assert.equal(persistResult, false);

  const rows = await store.query("inbox", { instanceId: instance.id, lookupKey: targetId });
  assert.equal(rows.length, 1);
  const dto = inbox.dto(rows[0]);
  assert.equal(dto.edited, true);
  assert.equal(dto.text, "Decrypted with base64 secret!");
  assert.equal(dto.originalText, "Original base64 text");
});

test("persist handles incoming counterparty edit across PN and LID JID variations", async () => {
  const store = mockStore();
  const inbox = createInbox(store, enc);
  const instance = { id: "inst-1", userId: "user-1" };
  const targetId = "MSG_PN_LID_1";
  const pnJid = "923009999999@s.whatsapp.net";
  const lidJid = "555555555555555@lid";
  const secret = crypto.randomBytes(32);

  // Original was received with PN
  const initialMsg = {
    key: { id: targetId, remoteJid: pnJid, fromMe: false },
    message: {
      conversation: "Before cross-JID edit",
      messageContextInfo: { messageSecret: secret },
    },
    messageTimestamp: Math.floor(Date.now() / 1000),
  };
  await inbox.persist(instance, initialMsg);

  // WhatsApp derives HKDF with origSender = PN, modSender = LID
  const sign = Buffer.concat([
    Buffer.from(targetId),
    Buffer.from(pnJid),
    Buffer.from(lidJid),
    Buffer.from("Message Edit"),
    new Uint8Array([1]),
  ]);
  const key = hmacSign(secret, new Uint8Array(32));
  const encKey = hmacSign(sign, key);
  const iv = crypto.randomBytes(12);
  const editedProto = proto.Message.encode({ conversation: "Cross-JID edit succeeded!" }).finish();
  const encPayload = aesEncryptGCM(editedProto, encKey, iv, Buffer.from(""));

  // Edit arrives from LID
  const editMsgStanza = {
    key: { id: "STANZA_LID_EDIT", remoteJid: lidJid, fromMe: false },
    message: {
      secretEncryptedMessage: {
        targetMessageKey: { id: targetId, remoteJid: pnJid, fromMe: false },
        encPayload,
        encIv: iv,
      },
    },
    messageTimestamp: Math.floor(Date.now() / 1000) + 3,
  };

  const persistResult = await inbox.persist(instance, editMsgStanza);
  assert.equal(persistResult, false);

  const rows = await store.query("inbox", { instanceId: instance.id, lookupKey: targetId });
  assert.equal(rows.length, 1);
  const dto = inbox.dto(rows[0]);
  assert.equal(dto.edited, true);
  assert.equal(dto.text, "Cross-JID edit succeeded!");
  assert.equal(dto.originalText, "Before cross-JID edit");
});

test("persist handles incoming edit wrapped in deviceSentMessage", async () => {
  const store = mockStore();
  const inbox = createInbox(store, enc);
  const instance = { id: "inst-1", userId: "user-1" };
  const targetId = "MSG_WRAPPED_DEVICE_1";
  const counterpartyJid = "11223344@s.whatsapp.net";
  const secret = crypto.randomBytes(32);

  const initialMsg = {
    key: { id: targetId, remoteJid: counterpartyJid, fromMe: false },
    message: {
      conversation: "Original text before device edit",
      messageContextInfo: { messageSecret: secret },
    },
    messageTimestamp: Math.floor(Date.now() / 1000),
  };
  await inbox.persist(instance, initialMsg);

  const sign = Buffer.concat([
    Buffer.from(targetId),
    Buffer.from(counterpartyJid),
    Buffer.from(counterpartyJid),
    Buffer.from("Message Edit"),
    new Uint8Array([1]),
  ]);
  const key = hmacSign(secret, new Uint8Array(32));
  const encKey = hmacSign(sign, key);
  const iv = crypto.randomBytes(12);
  const editedProto = proto.Message.encode({ conversation: "Edited from another device!" }).finish();
  const encPayload = aesEncryptGCM(editedProto, encKey, iv, Buffer.from(""));

  const editMsgStanza = {
    key: { id: "STANZA_DEVICE_EDIT_1", remoteJid: counterpartyJid, fromMe: false },
    message: {
      deviceSentMessage: {
        message: {
          secretEncryptedMessage: {
            targetMessageKey: { id: targetId, remoteJid: counterpartyJid, fromMe: false },
            encPayload,
            encIv: iv,
          },
        },
      },
    },
    messageTimestamp: Math.floor(Date.now() / 1000) + 4,
  };

  const persistResult = await inbox.persist(instance, editMsgStanza);
  assert.equal(persistResult, false);

  const rows = await store.query("inbox", { instanceId: instance.id, lookupKey: targetId });
  assert.equal(rows.length, 1);
  const dto = inbox.dto(rows[0]);
  assert.equal(dto.edited, true);
  assert.equal(dto.text, "Edited from another device!");
  assert.equal(dto.originalText, "Original text before device edit");
});



