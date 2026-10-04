import {
  BufferJSON,
  normalizeMessageContent,
  getContentType,
  WAMessageStatus,
  getAggregateVotesInPollMessage,
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
export function createInbox(store, enc) {
  async function load(instanceId, waId) {
    const row = await store.get("wa-message:" + instanceId, waId);
    if (!row) return null;
    const data = unpack(enc, row.data);
    return data.key
      ? data
      : {
          key: { id: waId, remoteJid: row.chatId, fromMe: row.fromMe },
          message: data,
        };
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
    const remote = normalizeJid(m.key.remoteJid),
      altJid = m.key.remoteJidAlt || m.key.senderPn || m.key.participantPn;
    if (remote.endsWith("@lid") && altJid) await alias(instance, remote, altJid);
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
    if (!fresh && previous && m.message)
      await store.patch("inbox", id, { data: pack(enc, m) });
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
        lastPreview: enc.seal(info.text || "[" + info.type + "]"),
        createdAt,
        unread: (c.unread || 0) + (fresh && notify && !m.key.fromMe ? 1 : 0),
      };
    });
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
    const m = unpack(enc, row.data);
    return {
      id: row.id,
      waId: row.waId,
      chatId: row.chatId,
      fromMe: row.fromMe,
      status: row.status,
      createdAt: row.createdAt,
      ...describeMessage(m.message),
      participant: m.key?.participant || "",
      name: m.pushName || "",
    };
  };
  return {
    load,
    persist,
    receipt,
    contact,
    chat,
    dto,
    alias,
    resolve,
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
