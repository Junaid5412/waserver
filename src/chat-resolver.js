import { hash } from "./security.js";
import { normalizeJid } from "./inbox.js";

const isPn = (j) => /@s\.whatsapp\.net$/.test(j || "");
const isLid = (j) => /@lid$/.test(j || "");
const isGroup = (j) => /@g\.us$/.test(j || "");
const looksLikeJid = (n) =>
  !n || /@(s\.whatsapp\.net|lid|g\.us|broadcast|newsletter)$/.test(n) || /^\+?\d{5,}$/.test(n);
const digits = (j) => String(j || "").split("@")[0];

/**
 * Presents WhatsApp's several identifiers for the same person (phone JID, @lid
 * JID, device-suffixed JID) as one conversation, and resolves display names from
 * the device's own contacts, group subjects and push names.
 */
export function createChatResolver({ store, wa }) {
  const groupCache = new Map();

  async function context(instance) {
    const [contacts, aliases] = await Promise.all([
      store.query("contacts", { instanceId: instance.id, limit: 1000 }),
      store.query("wa-alias", { instanceId: instance.id, limit: 1000 }),
    ]);
    const lidToPn = new Map(),
      names = new Map();
    for (const a of aliases) lidToPn.set(a.lid, a.pn);
    for (const c of contacts) {
      const id = normalizeJid(c.chatId || c.id);
      if (!id) continue;
      if (c.lid && isPn(id)) lidToPn.set(normalizeJid(c.lid), id);
      if (isLid(id) && c.phoneNumber)
        lidToPn.set(id, String(c.phoneNumber).includes("@") ? c.phoneNumber : c.phoneNumber + "@s.whatsapp.net");
      const display = c.name || c.notify || c.verifiedName || "";
      if (display && !names.has(id)) names.set(id, display);
    }
    const canon = (j) => {
      const n = normalizeJid(j);
      return lidToPn.get(n) || n;
    };
    const nameFor = (j) => {
      const n = normalizeJid(j),
        c = canon(n);
      return names.get(c) || names.get(n) || "";
    };
    const labelFor = (j) => {
      const c = canon(j);
      if (isPn(c)) return "+" + digits(c);
      if (isLid(c)) return "WhatsApp user";
      return /^\d{5,}@(s\.whatsapp\.net)?$/.test(c) ? "+" + digits(c) : "WhatsApp user";
    };
    return { canon, nameFor, labelFor, lidToPn };
  }

  async function groupMap(instance) {
    const hit = groupCache.get(instance.id);
    if (hit && Date.now() - hit.at < 300000) return hit.map;
    try {
      const all = await wa.active(instance.id).groupFetchAllParticipating();
      const map = {};
      for (const g of Object.values(all || {}))
        map[g.id] = { subject: g.subject || "", size: g.participants?.length || 0 };
      groupCache.set(instance.id, { at: Date.now(), map });
      return map;
    } catch {
      return hit?.map || {};
    }
  }

  async function list(instance, rows) {
    const ctx = await context(instance);
    const merged = new Map();
    const join = (cur, r) => {
      cur.aliases.add(r.chatId);
      cur.unread = (cur.unread || 0) + (r.unread || 0);
      if (Date.parse(r.createdAt) > Date.parse(cur.createdAt)) {
        cur.lastPreview = r.lastPreview;
        cur.createdAt = r.createdAt;
        cur.lastMessageId = r.lastMessageId;
      }
      cur.pinned = cur.pinned || r.pinned;
      cur.archived = cur.archived && r.archived;
      if (looksLikeJid(cur.name) && !looksLikeJid(r.name)) cur.name = r.name;
    };
    for (const r of rows) {
      const cid = ctx.canon(r.chatId),
        cur = merged.get(cid);
      if (cur) join(cur, r);
      else merged.set(cid, { ...r, chatId: cid, aliases: new Set([r.chatId, cid]) });
    }
    let groups = null;
    for (const entry of merged.values()) {
      let name = ctx.nameFor(entry.chatId);
      for (const a of entry.aliases) name ||= ctx.nameFor(a);
      if (!name && !looksLikeJid(entry.name)) name = entry.name;
      if (!name && isGroup(entry.chatId)) {
        groups ||= await groupMap(instance);
        name = groups[entry.chatId]?.subject || "";
        if (groups[entry.chatId]) entry.participants = groups[entry.chatId].size;
      }
      entry.kind = isGroup(entry.chatId) ? "group" : "contact";
      entry.phone = isPn(entry.chatId) ? "+" + digits(entry.chatId) : "";
      entry.name = name || (entry.kind === "group" ? "Group " + digits(entry.chatId).slice(-6) : ctx.labelFor(entry.chatId));
      entry.hasName = !!name;
    }
    // Last resort: an unlinked @lid chat whose name matches exactly one phone chat.
    const byName = new Map();
    for (const e of merged.values())
      if (e.hasName && isPn(e.chatId)) {
        const k = e.name.trim().toLowerCase();
        byName.set(k, byName.has(k) ? null : e);
      }
    for (const [cid, e] of [...merged]) {
      if (!isLid(cid) || !e.hasName) continue;
      const target = byName.get(e.name.trim().toLowerCase());
      if (!target) continue;
      for (const a of e.aliases) target.aliases.add(a);
      join(target, { ...e, chatId: cid });
      merged.delete(cid);
    }
    return [...merged.values()]
      .map((e) => ({ ...e, aliases: [...e.aliases] }))
      .sort((a, b) => (b.pinned ? 1 : 0) - (a.pinned ? 1 : 0) || Date.parse(b.createdAt) - Date.parse(a.createdAt));
  }

  async function aliasesOf(instance, chatId) {
    const rows = await store.query("chats", { instanceId: instance.id, limit: 1000 });
    const n = normalizeJid(chatId);
    const found = (await list(instance, rows)).find((e) => e.aliases.includes(n) || e.chatId === n);
    return found ? found.aliases : [n];
  }

  return { context, list, aliasesOf, groupMap, key: (instance, chat) => hash(instance.id + ":" + chat) };
}
