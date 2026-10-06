import {
  BufferJSON,
  normalizeMessageContent,
  getContentType,
  WAMessageStatus,
  WAMessageStubType,
  getAggregateVotesInPollMessage,
  aesDecryptGCM,
  hmacSign,
  proto,
} from "@whiskeysockets/baileys";
import { hash } from "./security.js";
export const pack = (enc, v) =>
  enc.seal(JSON.stringify(v, BufferJSON.replacer));
export const unpack = (enc, v) => JSON.parse(enc.open(v), BufferJSON.reviver);
export const normalizeJid = (value) =>
  typeof value === "string" ? value.replace(/:\d+@/, "@") : value;
export function timestampSeconds(value) {
  if (typeof value === "object" && value !== null && "low" in value)
    return (value.high >>> 0) * 4294967296 + (value.low >>> 0);
  const n = Number(value?.toString?.() || value);
  return Number.isFinite(n) ? n : Math.floor(Date.now() / 1000);
}
export function describeMessage(message) {
  const m = normalizeMessageContent(message) || {},
    kind = getContentType(m) || "unknown";
  const value = m[kind] || {};
  return {
    type: kind.replace(/Message(V\d+)?$/, ""),
    text:
      m.conversation ||
      value.text ||
      value.caption ||
      value.name ||
      value.displayName ||
      "",
    hasMedia: [
      "imageMessage",
      "videoMessage",
      "audioMessage",
      "documentMessage",
      "stickerMessage",
    ].includes(kind),
    mimetype: value.mimetype || "",
    filename: value.fileName || "",
    pollOptions: value.options?.map((x) => x.optionName) || [],
    durationSeconds: Number(value.seconds) || 0,
    location: ["locationMessage", "liveLocationMessage"].includes(kind)
      ? { latitude: value.degreesLatitude, longitude: value.degreesLongitude,
          name: value.name || "", address: value.address || "" } : null,
    contacts: kind === "contactMessage" ? [{ name: value.displayName || "Contact", vcard: value.vcard || "" }]
      : kind === "contactsArrayMessage" ? (value.contacts || []).map(c => ({ name: c.displayName || "Contact", vcard: c.vcard || "" })) : [],
    quotedText: value.contextInfo?.quotedMessage
      ? (value.contextInfo.quotedMessage.conversation || value.contextInfo.quotedMessage.extendedTextMessage?.text || value.contextInfo.quotedMessage.imageMessage?.caption || "Quoted message").slice(0, 500) : "",
  };
}
const IGNORED = new Set(["senderKeyDistributionMessage", "pollUpdateMessage", "keepInChatMessage", "encReactionMessage", "messageContextInfo", "reactionMessage", "protocolMessage", "commentMessage", "encCommentMessage", "secretEncryptedMessage", "encEventResponseMessage", "placeholderMessage", "botInvokeMessage", "messageHistoryBundle", "peerDataOperationRequestMessage", "peerDataOperationRequestResponseMessage"]);
const JUNK_SHORT = new Set([...IGNORED].map((k) => k.replace(/Message$/, "")));
export const isJunkType = (t) => !!t && (JUNK_SHORT.has(t) || IGNORED.has(t));
export function previewOf(info) {
  if (info.text) return info.text;
  const t = info.type;
  const map = { audio: "\ud83c\udfa4 Voice message", image: "\ud83d\udcf7 Photo", video: "\ud83c\udfa5 Video", document: "\ud83d\udcc4 " + (info.filename || "Document"), location: "\ud83d\udccd Location", liveLocation: "\ud83d\udccd Live location", contact: "\ud83d\udc64 Contact", contacts: "\ud83d\udc64 Contact", poll: "\ud83d\udcca Poll", pollCreation: "\ud83d\udcca Poll", sticker: "Sticker" };
  return map[t] || (t ? t.charAt(0).toUpperCase() + t.slice(1) : "Message");
}
export function unwrapEdited(m) {
  let cur = m;
  for (let i = 0; i < 5 && cur; i++) {
    if (cur.protocolMessage?.editedMessage) { cur = cur.protocolMessage.editedMessage; continue; }
    if (cur.editedMessage?.message) { cur = cur.editedMessage.message; continue; }
    if (cur.editedMessage) { cur = cur.editedMessage; continue; }
    if (cur.message) { cur = cur.message; continue; }
    break;
  }
  return cur || m;
}
export function unwrapMessage(msg) {
  let cur = msg;
  for (let i = 0; i < 5 && cur; i++) {
    if (cur.deviceSentMessage?.message) { cur = cur.deviceSentMessage.message; continue; }
    if (cur.ephemeralMessage?.message) { cur = cur.ephemeralMessage.message; continue; }
    if (cur.viewOnceMessage?.message) { cur = cur.viewOnceMessage.message; continue; }
    if (cur.viewOnceMessageV2?.message) { cur = cur.viewOnceMessageV2.message; continue; }
    if (cur.viewOnceMessageV2Extension?.message) { cur = cur.viewOnceMessageV2Extension.message; continue; }
    if (cur.documentWithCaptionMessage?.message) { cur = cur.documentWithCaptionMessage.message; continue; }
    break;
  }
  return cur || msg;
}
export function extractMessageSecret(obj) {
  if (!obj || typeof obj !== "object") return null;
  if (obj.messageSecret) return obj.messageSecret;
  if (obj.messageContextInfo?.messageSecret) return obj.messageContextInfo.messageSecret;
  if (obj.message) {
    const s = extractMessageSecret(obj.message);
    if (s) return s;
  }
  for (const k of Object.keys(obj)) {
    const val = obj[k];
    if (val && typeof val === "object") {
      if (val.messageSecret) return val.messageSecret;
      if (val.contextInfo?.messageSecret) return val.contextInfo.messageSecret;
    }
  }
  return null;
}
function toBuf(val) {
  if (!val) return Buffer.alloc(0);
  if (Buffer.isBuffer(val)) return val;
  if (val instanceof Uint8Array) return Buffer.from(val.buffer, val.byteOffset, val.byteLength);
  if (val?.type === "Buffer" && Array.isArray(val?.data)) return Buffer.from(val.data);
  if (Array.isArray(val)) return Buffer.from(val);
  if (typeof val === "string") {
    const trimmed = val.trim();
    if (/^[0-9a-fA-F]+$/.test(trimmed) && trimmed.length % 2 === 0 && trimmed.length >= 24) {
      return Buffer.from(trimmed, "hex");
    }
    if (/^[A-Za-z0-9+/=_-]+$/.test(trimmed) && (trimmed.length % 4 === 0 || trimmed.includes("=") || trimmed.length >= 16)) {
      try {
        const decoded = Buffer.from(trimmed, "base64");
        if (decoded.length > 0) return decoded;
      } catch {}
    }
    return Buffer.from(val, "utf8");
  }
  return Buffer.from(val);
}
export function decryptSecretEncryptedMessage(secretEnc, targetInfo) {
  const encPayload = toBuf(secretEnc?.encPayload || secretEnc?.encPayloadBytes || secretEnc?.payload || secretEnc?.ciphertext);
  const encIv = toBuf(secretEnc?.encIv || secretEnc?.encIV || secretEnc?.iv);
  const secret = toBuf(targetInfo?.secret);
  const id = String(targetInfo?.id || "");
  if (!encPayload.length || !encIv.length || !secret.length || !id) return null;
  const toBinary = (txt) => (Buffer.isBuffer(txt) ? txt : Buffer.from(txt || ""));

  const candidates = [
    ...(Array.isArray(targetInfo.candidates) ? targetInfo.candidates : []),
    targetInfo.origSender,
    targetInfo.sender,
    targetInfo.remoteJid,
    targetInfo.participant,
    targetInfo.targetSender,
  ].filter(Boolean);

  const jidVariants = new Set();
  for (const s of candidates) {
    if (typeof s !== "string") continue;
    jidVariants.add(s);
    jidVariants.add(s.replace(/:\d+@/, "@"));
    const user = s.split("@")[0].split(":")[0];
    if (user) {
      jidVariants.add(user);
      jidVariants.add(`${user}@s.whatsapp.net`);
      jidVariants.add(`${user}@lid`);
    }
  }

  const editTypes = ["Message Edit", "Event Edit", "Poll Edit"];
  for (const origJid of jidVariants) {
    for (const modJid of jidVariants) {
      for (const editType of editTypes) {
        try {
          const sign = Buffer.concat([
            toBinary(id),
            toBinary(origJid),
            toBinary(modJid),
            toBinary(editType),
            new Uint8Array([1]),
          ]);
          const key = hmacSign(secret, new Uint8Array(32));
          const decKey = hmacSign(sign, key);
          let decrypted = null;
          try {
            decrypted = aesDecryptGCM(encPayload, decKey, encIv, Buffer.from(""));
          } catch {
            try {
              const aad = toBinary(`${id}\u0000${modJid}`);
              decrypted = aesDecryptGCM(encPayload, decKey, encIv, aad);
            } catch {}
          }
          if (decrypted) {
            return proto.Message.decode(decrypted);
          }
        } catch {}
      }
    }
  }
  return null;
}
export function createInbox(store, enc, notify = () => {}) {
  const seenNames = new Map();
  const tell = (instance, event) => { try { notify(instance, event); } catch {} };
  async function rowsFor(instance, waId) {
    return store.query("inbox", { instanceId: instance.id, lookupKey: waId, limit: 10 });
  }
  async function markDeleted(instance, waId) {
    const rows = await rowsFor(instance, waId);
    const nowIso = new Date().toISOString();
    for (const row of rows) await store.patch("inbox", row.id, { deleted: true, deletedAt: nowIso });
    if (rows[0]) {
      const resolvedChatId = await resolve(instance, rows[0].chatId);
      const chat = (await store.get("chats", hash(instance.id + ":" + rows[0].chatId))) ||
                   (await store.get("chats", hash(instance.id + ":" + resolvedChatId)));
      if (chat?.lastMessageId === waId) {
        const stored = await load(instance.id, waId);
        let previewText = "🚫 This message was deleted";
        if (stored?.message) {
          const info = describeMessage(stored.message);
          const orig = previewOf(info);
          if (orig) previewText = "🚫 " + orig;
        }
        await store.patch("chats", chat.id, { lastPreview: enc.seal(previewText) });
      }
      for (const cid of new Set([rows[0].chatId, resolvedChatId])) {
        tell(instance, { type: "update", chatId: cid, waId });
      }
    }
  }
  async function applyEdit(instance, waId, edited) {
    if (!edited) return;
    edited = unwrapEdited(edited);
    const rows = await rowsFor(instance, waId);
    if (!rows.length) return;
    let stored = await load(instance.id, waId);
    if (!stored && rows[0]?.data) {
      try {
        const data = unpack(enc, rows[0].data);
        stored = data?.key
          ? data
          : {
              key: { id: waId, remoteJid: rows[0].chatId, fromMe: !!rows[0].fromMe },
              message: data?.message || data,
            };
      } catch {}
    }
    const newInfo = describeMessage(edited);
    const prevInfo = stored?.message ? describeMessage(stored.message) : { text: rows[0].text || "", type: rows[0].type || "text" };
    const prevText = prevInfo.text || "";
    const newText = newInfo.text || "";

    if (prevText && newText && prevText === newText && rows[0].edited) {
      return;
    }

    const nowIso = new Date().toISOString();

    if (stored) {
      stored.message = edited;
      await store.set("wa-message:" + instance.id, waId, {
        id: waId, chatId: rows[0].chatId, fromMe: !!stored.key?.fromMe, data: pack(enc, stored),
      });
    }

    for (const row of rows) {
      const existingEdits = Array.isArray(row.edits) ? row.edits : [];
      const originalText = row.originalText || prevText || "";
      const edits = (prevText && prevText !== newText)
        ? [...existingEdits, { text: prevText, at: nowIso }]
        : (existingEdits.length ? existingEdits : (prevText ? [{ text: prevText, at: nowIso }] : []));
      await store.patch("inbox", row.id, {
        type: newInfo.type || row.type,
        data: stored ? pack(enc, stored) : row.data,
        edited: true,
        editedAt: nowIso,
        originalText,
        edits,
      });
    }
    const resolvedChatId = await resolve(instance, rows[0].chatId);
    for (const cid of new Set([rows[0].chatId, resolvedChatId])) {
      const chat = await store.get("chats", hash(instance.id + ":" + cid));
      if (chat?.lastMessageId === waId) await store.patch("chats", chat.id, { lastPreview: enc.seal(previewOf(newInfo)) });
      tell(instance, { type: "update", chatId: cid, waId });
    }
  }
  async function react(instance, reactions) {
    for (const { key, reaction } of reactions || []) {
      if (!key?.id) continue;
      const rows = await rowsFor(instance, key.id);
      const who = normalizeJid(reaction?.key?.participant || (reaction?.key?.fromMe ? "me" : reaction?.key?.remoteJid)) || "me";
      for (const row of rows)
        await store.patch("inbox", row.id, (r) => {
          const reactions = { ...(r.reactions || {}) };
          if (reaction?.text) reactions[reaction?.key?.fromMe ? "me" : who] = reaction.text;
          else delete reactions[reaction?.key?.fromMe ? "me" : who];
          return { ...r, reactions };
        });
      if (rows[0]) tell(instance, { type: "update", chatId: rows[0].chatId, waId: key.id });
    }
  }
  async function protocol(instance, pm) {
    const target = pm?.key?.id || pm?.targetMessageKey?.id || (typeof pm?.key === "string" ? pm.key : null);
    const t = pm?.type;
    if (!target) return;
    if (t === 0 || t === "REVOKE") await markDeleted(instance, target);
    else if (t === 14 || t === "MESSAGE_EDIT" || pm?.editedMessage) await applyEdit(instance, target, pm.editedMessage);
  }
  async function load(instanceId, waId) {
    let row = await store.get("wa-message:" + instanceId, waId);
    if (!row) {
      const rows = await store.query("inbox", {
        instanceId,
        lookupKey: waId,
        limit: 1,
      });
      if (rows[0]) row = rows[0];
    }
    if (!row) {
      const rows = await store.query("messages", {
        instanceId,
        lookupKey: waId,
        limit: 1,
      });
      if (rows[0]) row = rows[0];
    }
    const rawData = row.data || row.payload;
    if (!rawData) return null;
    try {
      const data = typeof rawData === "string" ? unpack(enc, rawData) : rawData;
      return data?.key
        ? data
        : {
            key: { id: waId, remoteJid: row.chatId || row.to, fromMe: !!row.fromMe },
            message: data?.message || data,
          };
    } catch {
      return null;
    }
  }
  async function alias(instance, lid, pn) {
    lid = normalizeJid(lid);
    pn = normalizeJid(pn);
    if (!lid?.endsWith("@lid") || !pn?.endsWith("@s.whatsapp.net")) return;
    const id = hash(instance.id + ":" + lid),
      previous = await store.get("wa-alias", id);
    if (previous?.pn === pn) return;
    await store.set("wa-alias", id, {
      id,
      instanceId: instance.id,
      userId: instance.userId,
      lid,
      pn,
      lookupKey: lid,
      createdAt: previous?.createdAt || new Date().toISOString(),
    });
  }
  async function resolve(instance, value) {
    const j = normalizeJid(value);
    if (j?.endsWith("@lid")) {
      const a = await store.get("wa-alias", hash(instance.id + ":" + j));
      if (a?.pn) return a.pn;
    }
    return j;
  }
  async function persist(instance, m, { notify = false } = {}) {
    if (!m.key?.id || !m.key.remoteJid || !m.message) return false;
    const unwrappedMsg = unwrapMessage(m.message);
    const raw = normalizeMessageContent(unwrappedMsg) || unwrappedMsg || {},
      rawKind = getContentType(raw);
    const sem = raw.secretEncryptedMessage ||
                m.message?.secretEncryptedMessage ||
                unwrappedMsg?.secretEncryptedMessage;
    if (sem) {
      const targetId = sem.targetMessageKey?.id;
      if (targetId) {
        const orig = await load(instance.id, targetId);
        const origRows = orig ? [] : await rowsFor(instance, targetId);
        const origData = orig || (origRows[0]?.data ? unpack(enc, origRows[0].data) : null);
        const secret = extractMessageSecret(origData) ||
                       extractMessageSecret(origRows[0]) ||
                       extractMessageSecret(m);
        if (secret) {
          const candidates = [
            sem.targetMessageKey?.participant,
            sem.targetMessageKey?.remoteJid,
            m.key.participant,
            m.key.remoteJid,
            m.key.participantAlt,
            m.key.remoteJidAlt,
            origData?.key?.participant,
            origData?.key?.remoteJid,
            origRows[0]?.chatId,
          ].filter(Boolean);
          const decrypted = decryptSecretEncryptedMessage(sem, { secret, id: targetId, candidates });
          if (decrypted) {
            await applyEdit(instance, targetId, decrypted);
            return false;
          }
        }
      }
      return false;
    }
    const pm = raw.protocolMessage ||
               m.message?.protocolMessage ||
               m.message?.editedMessage?.message?.protocolMessage ||
               m.message?.editedMessage?.protocolMessage ||
               raw.editedMessage?.message?.protocolMessage ||
               raw.editedMessage?.protocolMessage;
    if (pm) { await protocol(instance, pm); return false; }
    if (rawKind === "protocolMessage") { await protocol(instance, raw.protocolMessage); return false; }
    if (rawKind === "editedMessage" || m.message?.editedMessage || raw?.editedMessage) {
      const targetId = pm?.key?.id ||
                       pm?.targetMessageKey?.id ||
                       m.message?.messageContextInfo?.messageAssociation?.parentMessageKey?.id ||
                       raw?.messageContextInfo?.messageAssociation?.parentMessageKey?.id ||
                       m.message?.extendedTextMessage?.contextInfo?.stanzaId ||
                       raw?.extendedTextMessage?.contextInfo?.stanzaId ||
                       m.message?.editedMessage?.message?.extendedTextMessage?.contextInfo?.stanzaId ||
                       m.message?.editedMessage?.contextInfo?.stanzaId;
      const unwrapped = unwrapEdited(m.message);
      if (targetId) {
        await applyEdit(instance, targetId, unwrapped);
        return false;
      }
      const existing = (await rowsFor(instance, m.key.id)).length > 0;
      if (existing) {
        await applyEdit(instance, m.key.id, unwrapped);
        return false;
      }
      return false;
    }
    if (rawKind === "reactionMessage") {
      await react(instance, [{ key: raw.reactionMessage.key, reaction: { text: raw.reactionMessage.text, key: m.key } }]);
      return false;
    }
    if (!rawKind || IGNORED.has(rawKind)) return false;
    const remote = normalizeJid(m.key.remoteJid),
      altJid = m.key.remoteJidAlt || m.key.senderPn || m.key.participantPn;
    if (remote.endsWith("@lid") && altJid) await alias(instance, remote, altJid);
    const part = normalizeJid(m.key.participant),
      partAlt = m.key.participantAlt || m.key.participantPn;
    if (part?.endsWith("@lid") && partAlt) await alias(instance, part, partAlt);
    const whoJid = part || (!remote.endsWith("@g.us") ? remote : "");
    if (whoJid && !m.key.fromMe && m.pushName) {
      const nk = hash(instance.id + ":" + whoJid);
      if (seenNames.get(nk) !== m.pushName) {
        seenNames.set(nk, m.pushName);
        await store.set("wa-names", nk, { id: nk, instanceId: instance.id, userId: instance.userId, lookupKey: whoJid, jid: whoJid, name: m.pushName, createdAt: new Date().toISOString() });
      }
    }
    const chatId = await resolve(instance, remote),
      ts = timestampSeconds(m.messageTimestamp);
    const createdAt = new Date(
      (ts || Math.floor(Date.now() / 1000)) * 1000,
    ).toISOString();
    const id = hash(instance.id + ":" + chatId + ":" + m.key.id),
      info = describeMessage(m.message);
    await store.set("wa-message:" + instance.id, m.key.id, {
      id: m.key.id,
      chatId,
      fromMe: !!m.key.fromMe,
      data: pack(enc, m),
    });
    const previous = await store.get("inbox", id);
    const fresh = await store.insert("inbox", id, {
      id,
      waId: m.key.id,
      instanceId: instance.id,
      userId: instance.userId,
      chatId,
      fromMe: !!m.key.fromMe,
      status: m.key.fromMe ? "sent" : "received",
      type: info.type,
      createdAt,
      data: pack(enc, m),
      lookupKey: m.key.id,
    });
    if (!fresh && previous && m.message) {
      await store.patch("inbox", id, {
        type: info.type,
        data: pack(enc, m),
      });
      await store.patch("chats", hash(instance.id + ":" + chatId), {
        lastPreview: enc.seal(previewOf(info)),
        lastMessageId: m.key.id,
      });
      tell(instance, { type: "message", chatId, waId: m.key.id, fromMe: !!m.key.fromMe, notify });
    }
    const chatKey = hash(instance.id + ":" + chatId);
    await store.insert("chats", chatKey, {
      id: chatKey,
      instanceId: instance.id,
      userId: instance.userId,
      chatId,
      name: chatId,
      unread: 0,
      createdAt,
    });
    await store.patch("chats", chatKey, (c) => {
      if (Date.parse(c.createdAt) > Date.parse(createdAt))
        return {
          ...c,
          unread: (c.unread || 0) + (fresh && notify && !m.key.fromMe ? 1 : 0),
        };
      return {
        ...c,
        name:
          (!m.key.fromMe && !chatId.endsWith("@g.us") && m.pushName) || c.name,
        lastMessageId: m.key.id,
        lastPreview: enc.seal(previewOf(info)),
        createdAt,
        unread: (c.unread || 0) + (fresh && notify && !m.key.fromMe ? 1 : 0),
      };
    });
    if (fresh) tell(instance, { type: "message", chatId, waId: m.key.id, fromMe: !!m.key.fromMe, notify });
    return fresh;
  }
  async function receipt(instance, updates) {
    for (const { key, update } of updates) {
      if (!key?.id) continue;
      const entries = await store.query("inbox", {
        instanceId: instance.id,
        lookupKey: key.id,
        limit: 10,
      });
      let status;
      const code = update.status;
      if (code === WAMessageStatus.DELIVERY_ACK) status = "delivered";
      if (code === WAMessageStatus.READ) status = "read";
      if (code === WAMessageStatus.PLAYED) status = "played";
      if (code === WAMessageStatus.ERROR) status = "failed";
      if (status) {
        const rank = { sent: 1, delivered: 2, read: 3, played: 4 };
        const apply = (r) =>
          rank[r.status] > rank[status] ? r : { ...r, status };
        for (const row of entries) await store.patch("inbox", row.id, apply);
        for (const row of await store.query("messages", {
          instanceId: instance.id,
          lookupKey: key.id,
          limit: 10,
        }))
          await store.patch("messages", row.id, apply);
        const receiptId = hash(instance.id + ":" + key.id);
        await store.insert("receipts", receiptId, {
          id: key.id,
          instanceId: instance.id,
          status,
          createdAt: new Date().toISOString(),
        });
        await store.patch("receipts", receiptId, apply);
      }
      if (update.messageStubType === WAMessageStubType.REVOKE) await markDeleted(instance, key.id);
      const unwrappedUpdateMsg = unwrapMessage(update.message || update.update?.message);
      const sem = unwrappedUpdateMsg?.secretEncryptedMessage ||
                  update.message?.secretEncryptedMessage ||
                  update.update?.message?.secretEncryptedMessage;
      let editHandled = false;
      if (sem) {
        const targetId = sem.targetMessageKey?.id || key.id;
        const orig = await load(instance.id, targetId);
        const origRows = orig ? [] : await rowsFor(instance, targetId);
        const origData = orig || (origRows[0]?.data ? unpack(enc, origRows[0].data) : null);
        const secret = extractMessageSecret(origData) ||
                       extractMessageSecret(origRows[0]);
        if (secret) {
          const candidates = [
            sem.targetMessageKey?.participant,
            sem.targetMessageKey?.remoteJid,
            key.participant,
            key.remoteJid,
            key.participantAlt,
            key.remoteJidAlt,
            origData?.key?.participant,
            origData?.key?.remoteJid,
            origRows[0]?.chatId,
          ].filter(Boolean);
          const decrypted = decryptSecretEncryptedMessage(sem, { secret, id: targetId, candidates });
          if (decrypted) {
            await applyEdit(instance, targetId, decrypted);
            editHandled = true;
          }
        }
      }
      const isEdit = (update.messageStubType && (update.messageStubType === 14 || update.messageStubType === "MESSAGE_EDIT")) ||
                     !!update.message?.editedMessage ||
                     !!update.update?.message?.editedMessage ||
                     !!unwrappedUpdateMsg?.editedMessage ||
                     !!update.message?.protocolMessage?.editedMessage ||
                     !!unwrappedUpdateMsg?.protocolMessage?.editedMessage ||
                     (update.message?.protocolMessage?.type === 14 || update.message?.protocolMessage?.type === "MESSAGE_EDIT") ||
                     (unwrappedUpdateMsg?.protocolMessage?.type === 14 || unwrappedUpdateMsg?.protocolMessage?.type === "MESSAGE_EDIT");
      if (!editHandled && isEdit) {
        const targetId = update.message?.protocolMessage?.key?.id ||
                         unwrappedUpdateMsg?.protocolMessage?.key?.id ||
                         sem?.targetMessageKey?.id ||
                         key.id;
        const payload = update.message?.editedMessage?.message ||
                        update.message?.editedMessage ||
                        unwrappedUpdateMsg?.editedMessage?.message ||
                        unwrappedUpdateMsg?.editedMessage ||
                        update.message?.protocolMessage?.editedMessage ||
                        unwrappedUpdateMsg?.protocolMessage?.editedMessage ||
                        unwrappedUpdateMsg ||
                        update.message;
        await applyEdit(instance, targetId, payload);
        editHandled = true;
      } else if (!editHandled && update.message) {
        const info = describeMessage(update.message);
        if (entries.length) {
          for (const row of entries) {
            const raw = unpack(enc, row.data) || {};
            raw.message = update.message;
            await store.patch("inbox", row.id, {
              type: info.type,
              data: pack(enc, raw),
            });
            await store.patch("chats", hash(instance.id + ":" + row.chatId), {
              lastPreview: enc.seal(previewOf(info)),
              lastMessageId: key.id,
            });
            tell(instance, { type: "message", chatId: row.chatId, waId: key.id, fromMe: !!row.fromMe });
          }
        } else if (key.remoteJid) {
          await persist(instance, { key, message: update.message, messageTimestamp: update.messageTimestamp }, { notify: true });
        }
      }
      if (status && entries[0]) tell(instance, { type: "update", chatId: entries[0].chatId, waId: key.id });
      if (update.pollUpdates) {
        const creator = await load(instance.id, key.id);
        if (creator) {
          creator.pollUpdates = [
            ...(creator.pollUpdates || []),
            ...update.pollUpdates,
          ];
          await store.set("wa-message:" + instance.id, key.id, {
            id: key.id,
            chatId: creator.key.remoteJid,
            fromMe: !!creator.key.fromMe,
            data: pack(enc, creator),
          });
        }
      }
    }
  }
  async function contact(instance, c) {
    if (c.lid && c.id) await alias(instance, c.lid, c.id);
    if (c.id?.endsWith("@lid") && (c.phoneNumber || c.jid)) {
      const pn = c.phoneNumber || c.jid;
      await alias(instance, c.id, pn.includes("@") ? pn : pn + "@s.whatsapp.net");
    }
    const id = hash(instance.id + ":" + c.id),
      previous = await store.get("contacts", id);
    await store.set("contacts", id, {
      ...previous,
      ...c,
      id,
      chatId: c.id,
      instanceId: instance.id,
      userId: instance.userId,
      lookupKey: c.id,
      createdAt: previous?.createdAt || new Date().toISOString(),
      consent: previous?.consent || false,
      optedOut: previous?.optedOut || false,
    });
    const chatKey = hash(instance.id + ":" + (await resolve(instance, c.id)));
    const existingChat = await store.get("chats", chatKey);
    if (existingChat && (c.name || c.notify))
      await store.patch("chats", chatKey, { name: c.name || c.notify });
  }
  async function chat(instance, c) {
    if (!c.id) return;
    const chatId = await resolve(instance, c.id);
    const id = hash(instance.id + ":" + chatId);
    await store.insert("chats", id, {
      id,
      instanceId: instance.id,
      userId: instance.userId,
      chatId,
      name: c.name || chatId,
      unread: 0,
      createdAt: new Date(
        timestampSeconds(c.conversationTimestamp || 0) * 1000,
      ).toISOString(),
    });
    await store.patch("chats", id, {
      ...(c.name ? { name: c.name } : {}),
      ...(c.archived !== undefined ? { archived: c.archived } : {}),
      ...(c.pinned !== undefined ? { pinned: !!c.pinned } : {}),
    });
  }
  const dto = (row) => {
    const m = unpack(enc, row.data) || {};
    const desc = describeMessage(m.message);
    return {
      id: row.id,
      waId: row.waId,
      chatId: row.chatId,
      fromMe: row.fromMe,
      status: row.status,
      createdAt: row.createdAt,
      ...desc,
      participant: m.key?.participant || "",
      participantAlt: m.key?.participantAlt || m.key?.participantPn || m.key?.senderPn || "",
      name: m.pushName || "",
      deleted: !!row.deleted,
      deletedAt: row.deletedAt || null,
      edited: !!row.edited,
      editedAt: row.editedAt || null,
      originalText: row.originalText || null,
      edits: Array.isArray(row.edits) ? row.edits : [],
      starred: !!row.starred,
      reactions: row.reactions || {},
    };
  };
  return {
    load,
    persist,
    receipt,
    react,
    markDeleted,
    contact,
    chat,
    dto,
    alias,
    resolve,
    applyEdit,
    load,
    async votes(instance, id) {
      const m = await load(instance.id, id);
      return m
        ? getAggregateVotesInPollMessage(
            { message: m.message, pollUpdates: m.pollUpdates },
            instance.phone + "@s.whatsapp.net",
          )
        : [];
    },
  };
}
