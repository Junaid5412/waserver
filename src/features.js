import express from "express";
import { z } from "zod";
import { randomUUID } from "node:crypto";
import { once } from "node:events";
import {
  downloadMediaMessage,
  jidNormalizedUser,
} from "@whiskeysockets/baileys";
import pino from "pino";
import { timestampSeconds, describeMessage } from "./inbox.js";
import { hash, jid, token } from "./security.js";
import { fail } from "./errors.js";
import { messageSchema, validateMessage } from "./content.js";
import { enqueueMessage } from "./messages.js";
import { renderTemplate } from "./automation.js";
import { MAX_MEDIA_BYTES, CHUNK_SIZE } from "./media.js";
const safeName = (v) =>
  String(v)
    .replace(/[\r\n]/g, "")
    .replace(/[^\w. -]/g, "_")
    .slice(0, 150) || "download";
const groupId = (v) => {
  const id = jid(v);
  if (!id.endsWith("@g.us")) fail(400, "Group JID required");
  return id;
};
export function createFeatures({ store, enc, wa, inbox, media, wrap, page }) {
  const router = express.Router({ mergeParams: true });
  router.use((req, res, next) => {
    if (
      req.apiInstance &&
      ["/pairing-code", "/archive", "/restart", "/webhook/rotate"].includes(
        req.path,
      )
    )
      return res
        .status(403)
        .json({ error: "Use a dashboard session for this operation" });
    next();
  });
  router.get(
    "/analytics",
    wrap(async (req, res) =>
      res.json({
        messages: await store.stats("messages", {
          instanceId: req.instance.id,
        }),
        webhooks: await store.stats("hooks", { instanceId: req.instance.id }),
        inbox: await store.stats("inbox", { instanceId: req.instance.id }),
        campaigns: await store.stats("campaigns", {
          instanceId: req.instance.id,
        }),
      }),
    ),
  );
  router.get("/state", (req, res) =>
    res.json({
      id: req.instance.id,
      status: req.instance.status,
      phone: req.instance.phone || null,
      webhookEnabled: !!req.instance.webhookUrl,
      maxMediaBytes: MAX_MEDIA_BYTES,
    }),
  );
  router.get("/settings", (req, res) =>
    res.json({
      sendIntervalMs: req.instance.sendIntervalMs || 0,
      webhookEvents: req.instance.webhookEvents || [],
      maxMediaBytes: MAX_MEDIA_BYTES,
    }),
  );
  router.put(
    "/settings",
    wrap(async (req, res) => {
      const d = z
        .object({
          sendIntervalMs: z.number().int().min(0).max(60000).optional(),
          webhookEvents: z
            .array(
              z.enum([
                "message",
                "receipt",
                "connection",
                "group",
                "group-participants",
                "presence",
                "call",
                "history",
                "error",
              ]),
            )
            .optional(),
        })
        .parse(req.body);
      await store.patch("instances", req.instance.id, d);
      res.json({ ok: true });
    }),
  );
  router.post(
    "/pairing-code",
    wrap(async (req, res) => {
      const { phone } = z
        .object({ phone: z.string().regex(/^\+?[1-9]\d{6,14}$/) })
        .parse(req.body);
      res.json({ code: await wa.pairingCode(req.instance, phone) });
    }),
  );
  router.post(
    "/restart",
    wrap(async (req, res) => {
      await wa.disconnect(req.instance, false);
      await wa.connect(req.instance);
      res.json({ ok: true });
    }),
  );
  router.post(
    "/archive",
    wrap(async (req, res) => {
      await wa.disconnect(req.instance, false);
      await store.patch("instances", req.instance.id, {
        archived: true,
        activeKeyId: "revoked",
      });
      res.json({ ok: true });
    }),
  );
  router.get(
    "/media",
    wrap(async (req, res) =>
      res.json(
        (
          await store.query("media", {
            instanceId: req.instance.id,
            ...page(req.query),
          })
        ).filter((m) => m.status !== "archived"),
      ),
    ),
  );
  router.post(
    "/media",
    wrap(async (req, res) =>
      res.status(201).json(await media.create(req.instance, req.body)),
    ),
  );
  router.put(
    "/media/:mediaId/chunks/:index",
    express.raw({ type: "application/octet-stream", limit: CHUNK_SIZE + 100 }),
    wrap(async (req, res) =>
      res.json(
        await media.chunk(
          req.instance,
          req.params.mediaId,
          Number(req.params.index),
          req.body,
        ),
      ),
    ),
  );
  router.post(
    "/media/:mediaId/complete",
    wrap(async (req, res) =>
      res.json(await media.complete(req.instance, req.params.mediaId)),
    ),
  );
  router.get(
    "/media/:mediaId/download",
    wrap(async (req, res) => {
      const m = await media.owned(req.instance, req.params.mediaId);
      if (m.status !== "ready") fail(409, "Upload has not been finalized");
      res.set({
        "Content-Type": m.mimetype,
        "Content-Length": String(m.size),
        "Content-Disposition": `attachment; filename="${safeName(m.filename)}"`,
      });
      for await (const chunk of media.stream(req.instance, m.id)) {
        if (res.destroyed) break;
        if (!res.write(chunk))
          await Promise.race([once(res, "drain"), once(res, "close")]);
      }
      res.end();
    }),
  );
  router.get(
    "/chats",
    wrap(async (req, res) => {
      let rows = await store.query("chats", {
        instanceId: req.instance.id,
        ...page(req.query),
      });
      const search = String(req.query.search || "").toLowerCase();
      res.json(
        rows
          .filter(
            (c) =>
              !search ||
              (c.name + " " + c.chatId).toLowerCase().includes(search),
          )
          .map((c) => ({
            ...c,
            lastPreview: c.lastPreview ? enc.open(c.lastPreview) : "",
          })),
      );
    }),
  );
  router.get(
    "/chats/:chat/messages",
    wrap(async (req, res) => {
      const chat = jid(req.params.chat);
      res.json(
        (
          await store.query("inbox", {
            instanceId: req.instance.id,
            chatId: chat,
            ...page(req.query),
          })
        ).map(inbox.dto),
      );
    }),
  );
  router.put(
    "/chats/:chat/settings",
    wrap(async (req, res) => {
      const chat = jid(req.params.chat),
        d = z
          .object({
            archive: z.boolean().optional(),
            pin: z.boolean().optional(),
            muteUntil: z.iso.datetime().nullable().optional(),
            read: z.boolean().optional(),
          })
          .parse(req.body),
        s = wa.active(req.instance.id);
      const c = await store.get("chats", hash(req.instance.id + ":" + chat));
      if (!c) fail(404, "Chat not found");
      const last = c.lastMessageId
        ? await inbox.load(req.instance.id, c.lastMessageId)
        : null;
      const lastMessages = last
        ? [
            {
              key: last.key,
              messageTimestamp: timestampSeconds(last.messageTimestamp),
            },
          ]
        : [];
      if (d.archive !== undefined)
        await s.chatModify({ archive: d.archive, lastMessages }, chat);
      if (d.pin !== undefined) await s.chatModify({ pin: d.pin }, chat);
      if (d.muteUntil !== undefined)
        await s.chatModify(
          { mute: d.muteUntil ? Date.parse(d.muteUntil) : null },
          chat,
        );
      if (d.read) {
        if (last) await s.readMessages([last.key]);
        await store.patch("chats", c.id, { unread: 0 });
      }
      await store.patch("chats", c.id, {
        ...(d.archive !== undefined ? { archived: d.archive } : {}),
        ...(d.pin !== undefined ? { pinned: d.pin } : {}),
        ...(d.muteUntil !== undefined ? { muteUntil: d.muteUntil } : {}),
      });
      res.json({ ok: true });
    }),
  );
  router.post(
    "/chats/:chat/presence",
    wrap(async (req, res) => {
      const { presence } = z
        .object({
          presence: z.enum([
            "available",
            "unavailable",
            "composing",
            "recording",
            "paused",
          ]),
        })
        .parse(req.body);
      await wa
        .active(req.instance.id)
        .sendPresenceUpdate(presence, jid(req.params.chat));
      res.json({ ok: true });
    }),
  );
  router.post(
    "/chats/:chat/history",
    wrap(async (req, res) => {
      const chat = jid(req.params.chat),
        { oldestId, count } = z
          .object({
            oldestId: z.string(),
            count: z.number().int().min(1).max(100).default(50),
          })
          .parse(req.body);
      const m = await inbox.load(req.instance.id, oldestId);
      if (!m || m.key.remoteJid !== chat)
        fail(404, "Message not found in this chat");
      res.json({
        requestId: await wa
          .active(req.instance.id)
          .fetchMessageHistory(
            count,
            m.key,
            timestampSeconds(m.messageTimestamp),
          ),
      });
    }),
  );
  const message = async (req) => {
    const m = await inbox.load(req.instance.id, req.params.message);
    if (!m?.key?.remoteJid) fail(404, "Message not found");
    return m;
  };
  router.post(
    "/inbox/:message/read",
    wrap(async (req, res) => {
      const m = await message(req);
      await wa.active(req.instance.id).readMessages([m.key]);
      res.json({ ok: true });
    }),
  );
  router.post(
    "/inbox/:message/reaction",
    wrap(async (req, res) => {
      const { emoji } = z.object({ emoji: z.string().max(16) }).parse(req.body),
        m = await message(req);
      res.json({
        id: (
          await wa.active(req.instance.id).sendMessage(m.key.remoteJid, {
            react: { text: emoji, key: m.key },
          })
        )?.key?.id,
      });
    }),
  );
  router.put(
    "/inbox/:message/text",
    wrap(async (req, res) => {
      const { text } = z
          .object({ text: z.string().min(1).max(20000) })
          .parse(req.body),
        m = await message(req);
      if (!m.key.fromMe)
        fail(403, "You can only edit messages sent by this number");
      await wa
        .active(req.instance.id)
        .sendMessage(m.key.remoteJid, { text, edit: m.key });
      res.json({ ok: true });
    }),
  );
  router.post(
    "/inbox/:message/delete",
    wrap(async (req, res) => {
      const m = await message(req);
      const options = {};
      if (m.key.remoteJid === "status@broadcast") {
        const job = (
          await store.query("messages", {
            instanceId: req.instance.id,
            lookupKey: m.key.id,
            limit: 1,
          })
        )[0];
        if (!job)
          fail(409, "Only statuses published by this platform can be deleted");
        const d = JSON.parse(enc.open(job.payload));
        options.statusJidList = d.statusAudience;
        options.broadcast = true;
      }
      await wa
        .active(req.instance.id)
        .sendMessage(m.key.remoteJid, { delete: m.key }, options);
      res.json({ ok: true });
    }),
  );
  router.post(
    "/inbox/:message/star",
    wrap(async (req, res) => {
      const { star } = z.object({ star: z.boolean() }).parse(req.body),
        m = await message(req);
      await wa
        .active(req.instance.id)
        .star(
          m.key.remoteJid,
          [{ id: m.key.id, fromMe: !!m.key.fromMe }],
          star,
        );
      res.json({ ok: true });
    }),
  );
  router.get(
    "/inbox/:message/media",
    wrap(async (req, res) => {
      const m = await message(req),
        s = (() => { try { return wa.active(req.instance.id); } catch { return null; } })();
      const stream = await downloadMediaMessage(
        m,
        "stream",
        {},
        {
          logger: pino({ level: "silent" }),
          reuploadRequest: s ? s.updateMediaMessage.bind(s) : async () => { fail(409, "Reconnect WhatsApp to recover expired media"); },
        },
      );
      const info = describeMessage(m.message),
        extension =
          { image: ".jpg", video: ".mp4", audio: ".ogg", sticker: ".webp" }[
            info.type
          ] || "";
      res.set({
        "Content-Type": info.mimetype || "application/octet-stream",
        "Content-Disposition": `attachment; filename="${safeName(info.filename || "whatsapp-" + m.key.id + extension)}"`,
      });
      let bytes = 0;
      for await (const chunk of stream) {
        bytes += chunk.length;
        if (bytes > MAX_MEDIA_BYTES) {
          stream.destroy();
          fail(413, "Incoming media exceeds the configured download size");
        }
        if (res.destroyed) {
          stream.destroy();
          break;
        }
        if (!res.write(chunk))
          await Promise.race([once(res, "drain"), once(res, "close")]);
      }
      res.end();
    }),
  );
  router.get(
    "/polls/:message/votes",
    wrap(async (req, res) =>
      res.json(await inbox.votes(req.instance, req.params.message)),
    ),
  );
  router.get(
    "/contacts",
    wrap(async (req, res) => {
      const q = String(req.query.search || "").toLowerCase();
      res.json(
        (
          await store.query("contacts", {
            instanceId: req.instance.id,
            ...page(req.query),
          })
        ).filter(
          (c) =>
            !q ||
            JSON.stringify([c.name, c.notify, c.chatId, c.phone])
              .toLowerCase()
              .includes(q),
        ),
      );
    }),
  );
  const contactSchema = z.object({
    phone: z.string(),
    name: z.string().min(1).max(100),
    consent: z.boolean().default(false),
    optedOut: z.boolean().default(false),
    tags: z.array(z.string().max(40)).max(20).default([]),
  });
  async function saveContact(instance, input) {
    const d = contactSchema.parse(input),
      chatId = jid(d.phone),
      id = hash(instance.id + ":" + chatId);
    const previous = await store.get("contacts", id);
    const row = {
      ...previous,
      ...d,
      ...(previous?.optedOut ? { optedOut: true, consent: false } : {}),
      id,
      chatId,
      instanceId: instance.id,
      userId: instance.userId,
      lookupKey: chatId,
      createdAt: previous?.createdAt || new Date().toISOString(),
    };
    await store.set("contacts", id, row);
    return row;
  }
  router.post(
    "/contacts",
    wrap(async (req, res) =>
      res.status(201).json(await saveContact(req.instance, req.body)),
    ),
  );
  router.post(
    "/contacts/import",
    wrap(async (req, res) => {
      const { contacts } = z
        .object({ contacts: z.array(contactSchema).min(1).max(1000) })
        .parse(req.body);
      for (const c of contacts) jid(c.phone);
      let saved = 0;
      for (const c of contacts) {
        await saveContact(req.instance, c);
        saved++;
      }
      res.json({ saved });
    }),
  );
  router.post(
    "/contacts/:contact/opt-out",
    wrap(async (req, res) => {
      const c = await store.get("contacts", req.params.contact);
      if (!c || c.instanceId !== req.instance.id)
        fail(404, "Contact not found");
      await store.patch("contacts", c.id, { optedOut: true, consent: false });
      res.json({ ok: true });
    }),
  );
  router.get(
    "/blocklist",
    wrap(async (req, res) =>
      res.json(await wa.active(req.instance.id).fetchBlocklist()),
    ),
  );
  router.put(
    "/contacts/block",
    wrap(async (req, res) => {
      const { phone, blocked } = z
        .object({ phone: z.string(), blocked: z.boolean() })
        .parse(req.body);
      await wa
        .active(req.instance.id)
        .updateBlockStatus(jid(phone), blocked ? "block" : "unblock");
      res.json({ ok: true });
    }),
  );
  router.get(
    "/profile",
    wrap(async (req, res) => {
      const s = wa.active(req.instance.id);
      const [about, business] = await Promise.allSettled([
        s.fetchStatus(jidNormalizedUser(s.user.id)),
        s.getBusinessProfile(jidNormalizedUser(s.user.id)),
      ]);
      res.json({
        id: jidNormalizedUser(s.user.id),
        name: s.user.name || "",
        about: about.status === "fulfilled" ? about.value : null,
        business: business.status === "fulfilled" ? business.value : null,
      });
    }),
  );
  router.put(
    "/profile",
    wrap(async (req, res) => {
      const d = z
          .object({
            name: z.string().min(1).max(100).optional(),
            about: z.string().max(139).optional(),
            pictureMediaId: z.string().uuid().optional(),
          })
          .parse(req.body),
        s = wa.active(req.instance.id);
      if (d.name) await s.updateProfileName(d.name);
      if (d.about !== undefined) await s.updateProfileStatus(d.about);
      if (d.pictureMediaId)
        await s.updateProfilePicture(
          jidNormalizedUser(s.user.id),
          await media.buffer(req.instance, d.pictureMediaId),
        );
      res.json({ ok: true });
    }),
  );
  router.get(
    "/groups/:group",
    wrap(async (req, res) =>
      res.json(
        await wa
          .active(req.instance.id)
          .groupMetadata(groupId(req.params.group)),
      ),
    ),
  );
  router.put(
    "/groups/:group",
    wrap(async (req, res) => {
      const d = z
          .object({
            name: z.string().min(1).max(100).optional(),
            description: z.string().max(2048).optional(),
            announcement: z.boolean().optional(),
            locked: z.boolean().optional(),
            ephemeralSeconds: z
              .union([
                z.literal(0),
                z.literal(86400),
                z.literal(604800),
                z.literal(7776000),
              ])
              .optional(),
            pictureMediaId: z.string().uuid().optional(),
          })
          .parse(req.body),
        s = wa.active(req.instance.id),
        id = groupId(req.params.group);
      if (d.name) await s.groupUpdateSubject(id, d.name);
      if (d.description !== undefined)
        await s.groupUpdateDescription(id, d.description);
      if (d.announcement !== undefined)
        await s.groupSettingUpdate(
          id,
          d.announcement ? "announcement" : "not_announcement",
        );
      if (d.locked !== undefined)
        await s.groupSettingUpdate(id, d.locked ? "locked" : "unlocked");
      if (d.ephemeralSeconds !== undefined)
        await s.groupToggleEphemeral(id, d.ephemeralSeconds);
      if (d.pictureMediaId)
        await s.updateProfilePicture(
          id,
          await media.buffer(req.instance, d.pictureMediaId),
        );
      res.json({ ok: true });
    }),
  );
  router.get(
    "/groups/:group/invite",
    wrap(async (req, res) =>
      res.json({
        code: await wa
          .active(req.instance.id)
          .groupInviteCode(groupId(req.params.group)),
      }),
    ),
  );
  router.post(
    "/groups/:group/invite/revoke",
    wrap(async (req, res) =>
      res.json({
        code: await wa
          .active(req.instance.id)
          .groupRevokeInvite(groupId(req.params.group)),
      }),
    ),
  );
  router.post(
    "/groups/:group/leave",
    wrap(async (req, res) => {
      await wa.active(req.instance.id).groupLeave(groupId(req.params.group));
      res.json({ ok: true });
    }),
  );
  router.post(
    "/groups/join",
    wrap(async (req, res) => {
      const { code } = z
        .object({ code: z.string().regex(/^[A-Za-z0-9_-]{10,100}$/) })
        .parse(req.body);
      res.json({
        groupId: await wa.active(req.instance.id).groupAcceptInvite(code),
      });
    }),
  );
  router.get(
    "/statuses",
    wrap(async (req, res) =>
      res.json(
        (
          await store.query("inbox", {
            instanceId: req.instance.id,
            chatId: "status@broadcast",
            ...page(req.query),
          })
        ).map(inbox.dto),
      ),
    ),
  );
  router.post(
    "/statuses",
    wrap(async (req, res) => {
      const d = messageSchema.parse({ ...req.body, to: "status@broadcast" });
      if (!d.statusAudience?.length)
        fail(400, "Provide statusAudience with recipient numbers");
      await validateMessage(req.instance, d, media, inbox.load, {
        status: true,
      });
      const { httpStatus, ...result } = await enqueueMessage(
        store,
        enc,
        req.instance,
        d,
        req.headers["idempotency-key"],
        () => {},
      );
      res.status(httpStatus).json(result);
    }),
  );
  router.get(
    "/rules",
    wrap(async (req, res) =>
      res.json(
        await store.query("rules", {
          instanceId: req.instance.id,
          ...page(req.query),
        }),
      ),
    ),
  );
  router.post(
    "/rules",
    wrap(async (req, res) => {
      const d = z
        .object({
          name: z.string().min(1).max(60),
          match: z.enum(["any", "exact", "contains"]),
          keyword: z.string().max(200).default(""),
          reply: z.string().min(1).max(20000),
          cooldownSeconds: z.number().int().min(0).max(86400).default(60),
          enabled: z.boolean().default(true),
          stopAfterMatch: z.boolean().default(true),
        })
        .parse(req.body);
      if (d.match !== "any" && !d.keyword.trim())
        fail(400, "Keyword is required");
      const id = randomUUID();
      await store.set("rules", id, {
        ...d,
        id,
        instanceId: req.instance.id,
        userId: req.user.id,
        status: d.enabled ? "enabled" : "disabled",
        createdAt: new Date().toISOString(),
      });
      res.status(201).json({ id });
    }),
  );
  router.put(
    "/rules/:rule",
    wrap(async (req, res) => {
      const rule = await store.get("rules", req.params.rule);
      if (!rule || rule.instanceId !== req.instance.id)
        fail(404, "Rule not found");
      const d = z
        .object({
          enabled: z.boolean().optional(),
          reply: z.string().min(1).max(20000).optional(),
        })
        .parse(req.body);
      await store.patch("rules", rule.id, {
        ...d,
        ...(d.enabled !== undefined
          ? { status: d.enabled ? "enabled" : "disabled" }
          : {}),
      });
      res.json({ ok: true });
    }),
  );
  router.get(
    "/templates",
    wrap(async (req, res) =>
      res.json(
        await store.query("templates", {
          instanceId: req.instance.id,
          ...page(req.query),
        }),
      ),
    ),
  );
  router.post(
    "/templates",
    wrap(async (req, res) => {
      const d = z
          .object({
            name: z.string().min(1).max(60),
            text: z.string().min(1).max(20000),
          })
          .parse(req.body),
        id = randomUUID();
      await store.set("templates", id, {
        ...d,
        id,
        instanceId: req.instance.id,
        userId: req.user.id,
        createdAt: new Date().toISOString(),
      });
      res.status(201).json({ id });
    }),
  );
  router.get(
    "/campaigns",
    wrap(async (req, res) => {
      const result = [];
      for (const c of await store.query("campaigns", {
        instanceId: req.instance.id,
        ...page(req.query),
      })) {
        const jobs = await store.query("messages", {
          instanceId: req.instance.id,
          campaignId: c.id,
          limit: 1000,
        });
        const counts = {};
        for (const j of jobs) counts[j.status] = (counts[j.status] || 0) + 1;
        if (c.status === "running" && !counts.queued && !counts.sending) {
          c.status = "completed";
          await store.patch("campaigns", c.id, { status: "completed" });
        }
        result.push({ ...c, counts });
      }
      res.json(result);
    }),
  );
  router.post(
    "/campaigns",
    wrap(async (req, res) => {
      const input = z
        .object({
          name: z.string().min(1).max(60),
          recipients: z
            .array(
              z.union([
                z.string(),
                z.object({
                  to: z.string(),
                  name: z.string().max(100).default(""),
                }),
              ]),
            )
            .min(1)
            .max(1000),
          message: messageSchema.omit({ to: true }),
          intervalSeconds: z.number().min(1).max(3600).default(5),
          startAt: z.iso.datetime().optional(),
          consentConfirmed: z.literal(true),
        })
        .parse(req.body);
      const start = input.startAt ? Date.parse(input.startAt) : Date.now();
      if (start < Date.now() - 60000) fail(400, "Start time is in the past");
      const requestKey = req.headers["idempotency-key"];
      if (
        requestKey &&
        (typeof requestKey !== "string" ||
          requestKey.length < 8 ||
          requestKey.length > 200)
      )
        fail(400, "Idempotency-Key must be 8 to 200 characters");
      const id = requestKey
          ? "campaign_" + hash(req.instance.id + ":" + requestKey)
          : randomUUID(),
        fingerprint = hash(JSON.stringify(input));
      const existing = await store.get("campaigns", id);
      if (existing) {
        if (existing.fingerprint !== fingerprint)
          fail(409, "Idempotency key was used for different campaign content");
        if (existing.status === "building")
          fail(409, "Campaign is still compiling; retry later");
        return res.status(200).json(existing);
      }
      const recipients = new Map();
      for (const r of input.recipients) {
        const row = typeof r === "string" ? { to: r, name: "" } : r;
        recipients.set(jid(row.to), row.name);
      }
      const campaign = {
        id,
        fingerprint,
        name: input.name,
        instanceId: req.instance.id,
        userId: req.user.id,
        status: "building",
        total: recipients.size,
        skipped: 0,
        createdAt: new Date().toISOString(),
      };
      if (!(await store.insert("campaigns", id, campaign)))
        fail(409, "Campaign is already being created");
      let n = 0;
      try {
        for (const [to, name] of recipients) {
          const c = await store.get(
            "contacts",
            hash(req.instance.id + ":" + to),
          );
          if (c?.optedOut) {
            campaign.skipped++;
            continue;
          }
          const d = messageSchema.parse({
            ...input.message,
            to,
            sendAt: new Date(
              start + n * input.intervalSeconds * 1000,
            ).toISOString(),
            text: input.message.text
              ? renderTemplate(input.message.text, {
                  name: name || c?.name || "",
                  phone: to.split("@")[0],
                })
              : undefined,
          });
          await validateMessage(req.instance, d, media, inbox.load);
          await enqueueMessage(
            store,
            enc,
            req.instance,
            d,
            "campaign:" + hash(id + ":" + to),
            () => {},
            { campaignId: id },
          );
          n++;
        }
        campaign.status = "running";
        campaign.queued = n;
        await store.set("campaigns", id, campaign);
        res.status(201).json(campaign);
      } catch (e) {
        await store.patch("campaigns", id, {
          status: "failed",
          error: "Campaign compilation failed",
        });
        throw e;
      }
    }),
  );
  router.put(
    "/campaigns/:campaign",
    wrap(async (req, res) => {
      const { status } = z
          .object({ status: z.enum(["running", "paused", "cancelled"]) })
          .parse(req.body),
        c = await store.get("campaigns", req.params.campaign);
      if (!c || c.instanceId !== req.instance.id)
        fail(404, "Campaign not found");
      if (["building", "failed", "cancelled", "completed"].includes(c.status))
        fail(409, "This campaign cannot be resumed");
      await store.patch("campaigns", c.id, { status });
      for (const previous of status === "cancelled"
        ? ["queued", "paused"]
        : status === "paused"
          ? ["queued"]
          : ["paused"])
        for (const j of await store.query("messages", {
          instanceId: req.instance.id,
          campaignId: c.id,
          status: previous,
          limit: 1000,
        })) {
          j.status =
            status === "cancelled"
              ? "cancelled"
              : status === "paused"
                ? "paused"
                : "queued";
          await store.transition("messages", j.id, previous, j);
        }
      res.json({ ok: true });
    }),
  );
  router.post(
    "/webhooks/:delivery/retry",
    wrap(async (req, res) => {
      const h = await store.get("hooks", req.params.delivery);
      if (!h || h.instanceId !== req.instance.id)
        fail(404, "Webhook delivery not found");
      if (h.status === "delivered") fail(409, "Delivery already succeeded");
      await store.patch("hooks", h.id, {
        status: "pending",
        attempts: 0,
        nextAt: Date.now(),
      });
      res.json({ ok: true });
    }),
  );
  router.post(
    "/webhook/rotate",
    wrap(async (req, res) => {
      const secret = token();
      await store.patch("instances", req.instance.id, {
        webhookSecret: enc.seal(secret),
      });
      res.json({ secret });
    }),
  );
  router.delete(
    "/rules/:rule",
    wrap(async (req, res) => {
      const r = await store.get("rules", req.params.rule);
      if (!r || r.instanceId !== req.instance.id) fail(404, "Rule not found");
      await store.delete("rules", r.id);
      res.json({ ok: true });
    }),
  );
  router.put(
    "/templates/:template",
    wrap(async (req, res) => {
      const r = await store.get("templates", req.params.template);
      if (!r || r.instanceId !== req.instance.id)
        fail(404, "Template not found");
      const d = z
        .object({
          name: z.string().min(1).max(60),
          text: z.string().min(1).max(20000),
        })
        .parse(req.body);
      await store.patch("templates", r.id, d);
      res.json({ ok: true });
    }),
  );
  router.delete(
    "/templates/:template",
    wrap(async (req, res) => {
      const r = await store.get("templates", req.params.template);
      if (!r || r.instanceId !== req.instance.id)
        fail(404, "Template not found");
      await store.delete("templates", r.id);
      res.json({ ok: true });
    }),
  );
  router.delete(
    "/contacts/:contact",
    wrap(async (req, res) => {
      const c = await store.get("contacts", req.params.contact);
      if (!c || c.instanceId !== req.instance.id)
        fail(404, "Contact not found");
      if (c.optedOut)
        fail(
          409,
          "Keep the opt-out record to prevent future campaign delivery",
        );
      await store.delete("contacts", c.id);
      res.json({ ok: true });
    }),
  );
  router.get(
    "/messages/:job",
    wrap(async (req, res) => {
      const m = await store.get("messages", req.params.job);
      if (!m || m.instanceId !== req.instance.id)
        fail(404, "Message not found");
      const { payload, ...row } = m;
      res.json({ ...row, text: JSON.parse(enc.open(payload)).text || "" });
    }),
  );
  return router;
}
