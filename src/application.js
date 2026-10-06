import express from "express";
import { createServer } from "node:http";
import { Server as NetServer } from "node:net";
import { writeFileSync, chmodSync, rmSync } from "node:fs";
import { workerEndpoint } from "./follower.js";
import helmet from "helmet";
import rateLimit from "express-rate-limit";
import { requestKey } from "./request-key.js";
import cookieParser from "cookie-parser";
import { z } from "zod";
import { randomUUID } from "node:crypto";
import os from "node:os";
import { createBus } from "./realtime.js";
import { resources } from "./resources.js";
import { createKeepAlive } from "./keepalive.js";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { openStore } from "./store.js";
import {
  token,
  hash,
  passwordHash,
  passwordMatches,
  cipher,
  jid,
} from "./security.js";
import { gateway } from "./whatsapp.js";
import { webhookUrl } from "./webhooks.js";
import { createWorker } from "./worker.js";
import { enqueueMessage } from "./messages.js";
import { createMediaStore } from "./media.js";
import { createInbox } from "./inbox.js";
import { createAutomation } from "./automation.js";
import { createFeatures } from "./features.js";
import { messageSchema, validateMessage, buildContent } from "./content.js";
import { generateSmartReplies, SUPPORTED_GEMINI_MODELS, verifyGeminiKey } from "./ai.js";
const production = process.env.NODE_ENV === "production";
if (!process.env.APP_ORIGIN) throw Error("APP_ORIGIN is required");
const origin = new URL(process.env.APP_ORIGIN).origin;
if (production && !origin.startsWith("https://"))
  throw Error("Production APP_ORIGIN must use HTTPS");
const enc = cipher(process.env.ENCRYPTION_KEY),
  store = await openStore();
if (!(await store.query("users", { limit: 1 })).length) {
  if (
    !process.env.ADMIN_EMAIL ||
    !process.env.ADMIN_PASSWORD ||
    process.env.ADMIN_PASSWORD.length < 12
  )
    throw Error(
      "Set ADMIN_EMAIL and ADMIN_PASSWORD (minimum 12 characters) for initial setup",
    );
  const id = randomUUID();
  await store.set("users", id, {
    id,
    email: z.email().max(254).parse(process.env.ADMIN_EMAIL).toLowerCase(),
    password: passwordHash(process.env.ADMIN_PASSWORD),
    role: "admin",
  });
}
const app = express();
app.set("trust proxy", Number(process.env.TRUST_PROXY || 0));
app.disable("x-powered-by");
app.use(
  helmet({
    contentSecurityPolicy: {
      directives: {
        defaultSrc: ["'self'"],
        scriptSrc: ["'self'"],
        styleSrc: ["'self'"],
        imgSrc: ["'self'", "data:", "blob:"],
        mediaSrc: ["'self'", "blob:"],
        connectSrc: ["'self'"],
        fontSrc: ["'self'"],
        objectSrc: ["'none'"],
        styleSrcAttr: ["'unsafe-inline'"],
        frameSrc: ["'self'", "blob:"],
        frameAncestors: ["'self'"],
      },
    },
  }),
);
app.use(express.json({ limit: "1mb" }));
app.use(cookieParser());
app.use(
  "/api",
  rateLimit({
    keyGenerator: requestKey,
    windowMs: 60000,
    limit: (req) => (/\/media\/[^/]+\/chunks\/|\/picture$|\/inbox\/[^/]+\/media$/.test(req.path) ? 1500 : 240),
    standardHeaders: "draft-8",
    legacyHeaders: false,
  }),
);
app.use("/api", (req, res, next) => {
  res.set("Cache-Control", "no-store");
  if (
    !["GET", "HEAD"].includes(req.method) &&
    !/^Bearer [a-f0-9]{64}$/.test(req.headers.authorization || "")
  ) {
    if (req.headers.origin && req.headers.origin !== origin)
      return res.status(403).json({ error: "Request origin is not allowed" });
  }
  next();
});
const wrap = (fn) => (req, res, next) =>
  Promise.resolve(fn(req, res, next)).catch(next);
const fail = (status, message) => {
  throw Object.assign(Error(message), { status });
};
const startedAt = new Date().toISOString();
const bus = createBus(),
  streams = new Set();
app.get(
  "/health",
  wrap(async (req, res) => {
    const t = Date.now();
    await store.health();
    res.set("Cache-Control", "no-store").json({
      status: "ok",
      uptimeSeconds: Math.floor(process.uptime()),
      startedAt,
      databaseMs: Date.now() - t,
    });
  }),
);
app.get("/ping", (req, res) => res.set("Cache-Control", "no-store").type("text").send("pong"));
const audit = (req, userId, action, detail = "") => {
  const id = randomUUID();
  return store
    .set("audit", id, {
      id,
      userId,
      action,
      detail: String(detail).slice(0, 300),
      actor: req.user?.email || "",
      ip: String(req.ip || "").slice(0, 60),
      ua: String(req.headers["user-agent"] || "").slice(0, 200),
      createdAt: new Date().toISOString(),
    })
    .catch(() => {});
};
app.post(
  "/api/login",
  rateLimit({
    keyGenerator: requestKey,
    windowMs: 15 * 60000,
    limit: 15,
    standardHeaders: "draft-8",
    legacyHeaders: false,
  }),
  wrap(async (req, res) => {
    const data = z
      .object({ email: z.email(), password: z.string().min(1).max(200) })
      .parse(req.body);
    const user = (
      await store.query("users", { email: data.email, limit: 1 })
    )[0];
    if (
      !user ||
      !passwordMatches(data.password, user.password) ||
      user.disabled
    ) {
      if (user) await audit(req, user.id, "login_failed", user.disabled ? "Account disabled" : "Wrong password");
      fail(401, "Incorrect email or password");
    }
    const t = token();
    await store.set("sessions", hash(t), {
      id: hash(t),
      userId: user.id,
      version: user.sessionVersion || 0,
      expires: Date.now() + 86400000,
      createdAt: new Date().toISOString(),
      ip: String(req.ip || "").slice(0, 60),
      ua: String(req.headers["user-agent"] || "").slice(0, 200),
    });
    await store.patch("users", user.id, { lastLoginAt: new Date().toISOString() });
    await audit(req, user.id, "login", "Signed in");
    res.cookie("zelon_session", t, {
      httpOnly: true,
      secure: production,
      sameSite: "strict",
      maxAge: 86400000,
      path: "/",
    });
    res.json({
      ok: true,
      token: t,
      user: {
        id: user.id,
        email: user.email,
        role: user.role,
        name: user.name || "",
        permissions: user.permissions || {},
      },
    });
  }),
);
const auth = wrap(async (req, res, next) => {
  const bearer = req.headers.authorization?.match(
    /^Bearer ([a-f0-9]{64})$/,
  )?.[1];
  if (bearer) {
    const key = await store.get("keys", hash(bearer));
    if (key) {
      const instance = await store.get("instances", key.instanceId);
      if (
        instance &&
        !instance.archived &&
        (!instance.activeKeyId || instance.activeKeyId === key.id)
      ) {
        req.user = await store.get("users", key.userId);
        req.apiInstance = key.instanceId;
      }
    } else {
      const s = await store.get("sessions", hash(bearer));
      if (s && s.expires > Date.now()) {
        const u = await store.get("users", s.userId);
        if (u && (u.sessionVersion || 0) === (s.version || 0)) {
          req.user = u;
          req.sessionId = s.id;
        }
      }
    }
  } else if (req.cookies.zelon_session || req.headers["x-session-token"]) {
    const tokenVal = req.cookies.zelon_session || req.headers["x-session-token"];
    const s = await store.get("sessions", hash(tokenVal));
    if (s && s.expires > Date.now()) {
      const u = await store.get("users", s.userId);
      if (u && (u.sessionVersion || 0) === (s.version || 0)) {
        req.user = u;
        req.sessionId = s.id;
      }
    }
  }
  if (!req.user || req.user.disabled) fail(401, "Sign in to continue");
  next();
});
app.use("/api", auth);
const consoleOnly = (req, res, next) =>
  req.apiInstance
    ? res
        .status(403)
        .json({ error: "Use the dashboard session for this operation" })
    : next();
app.get("/api/me", (req, res) =>
  res.json({
    id: req.user.id,
    email: req.user.email,
    role: req.user.role,
    name: req.user.name || "",
    permissions: req.user.permissions || {},
  }),
);
const sessionDto = (x, current) => ({
  id: x.id.slice(0, 16),
  full: x.id,
  createdAt: x.createdAt || null,
  expires: x.expires,
  ip: x.ip || "",
  ua: x.ua || "",
  current: x.id === current,
});
app.get(
  "/api/account",
  consoleOnly,
  wrap(async (req, res) => {
    const mine = (await store.query("instances", { userId: req.user.id, limit: 1000 })).filter((x) => !x.archived);
    const sessions = (await store.query("sessions", { userId: req.user.id, limit: 200 })).filter((x) => x.expires > Date.now());
    res.json({
      id: req.user.id,
      email: req.user.email,
      name: req.user.name || "",
      role: req.user.role,
      createdAt: req.user.createdAt || null,
      lastLoginAt: req.user.lastLoginAt || null,
      passwordChangedAt: req.user.passwordChangedAt || null,
      instances: mine.map((x) => ({
        id: x.id,
        name: x.name,
        status: x.status,
        phone: x.phone || null,
        hasKey: !!x.activeKeyId && x.activeKeyId !== "revoked",
        hasWebhook: !!x.webhookUrl,
      })),
      sessions: sessions
        .sort((a, b) => (Date.parse(b.createdAt || 0) || 0) - (Date.parse(a.createdAt || 0) || 0))
        .map((x) => ({ ...sessionDto(x, req.sessionId), full: undefined })),
    });
  }),
);
app.put(
  "/api/account/profile",
  consoleOnly,
  wrap(async (req, res) => {
    const d = z.object({ name: z.string().trim().max(80) }).parse(req.body);
    await store.patch("users", req.user.id, { name: d.name });
    await audit(req, req.user.id, "profile_updated", "Display name changed");
    res.json({ ok: true });
  }),
);
app.put(
  "/api/account/email",
  consoleOnly,
  wrap(async (req, res) => {
    const d = z.object({ email: z.email().max(254), password: z.string().min(1).max(200) }).parse(req.body);
    if (!passwordMatches(d.password, req.user.password)) fail(403, "Password is incorrect");
    const email = d.email.toLowerCase();
    const taken = (await store.query("users", { email, limit: 1 }))[0];
    if (taken && taken.id !== req.user.id) fail(409, "An account with this email already exists");
    await store.patch("users", req.user.id, { email });
    await audit(req, req.user.id, "email_changed", req.user.email + " → " + email);
    res.json({ ok: true, email });
  }),
);
app.delete(
  "/api/account/sessions/:sid",
  consoleOnly,
  wrap(async (req, res) => {
    const rows = await store.query("sessions", { userId: req.user.id, limit: 200 });
    const target = rows.find((x) => x.id.startsWith(req.params.sid) && req.params.sid.length >= 8);
    if (!target) fail(404, "Session not found");
    await store.delete("sessions", target.id);
    await audit(req, req.user.id, "session_revoked", "Signed out a device");
    res.json({ ok: true, current: target.id === req.sessionId });
  }),
);
app.post(
  "/api/account/sessions/revoke-others",
  consoleOnly,
  wrap(async (req, res) => {
    let n = 0;
    for (const x of await store.query("sessions", { userId: req.user.id, limit: 500 }))
      if (x.id !== req.sessionId) {
        await store.delete("sessions", x.id);
        n++;
      }
    await audit(req, req.user.id, "sessions_revoked", n + " other device(s) signed out");
    res.json({ ok: true, revoked: n });
  }),
);
app.get(
  "/api/account/activity",
  consoleOnly,
  wrap(async (req, res) =>
    res.json(
      (await store.query("audit", { userId: req.user.id, limit: 40 })).map(({ id, action, detail, actor, ip, ua, createdAt }) => ({
        id, action, detail, actor, ip, ua, createdAt,
      })),
    ),
  ),
);
app.put(
  "/api/account/password",
  consoleOnly,
  wrap(async (req, res) => {
    const d = z
      .object({
        currentPassword: z.string().min(1).max(200),
        newPassword: z.string().min(12).max(200),
      })
      .parse(req.body);
    if (!passwordMatches(d.currentPassword, req.user.password))
      fail(403, "Current password is incorrect");
    req.user.password = passwordHash(d.newPassword);
    req.user.sessionVersion = token();
    req.user.passwordChangedAt = new Date().toISOString();
    await store.set("users", req.user.id, req.user);
    await audit(req, req.user.id, "password_changed", "Password updated; all devices signed out");
    for (const session of await store.query("sessions", {
      userId: req.user.id,
      limit: 1000,
    }))
      await store.delete("sessions", session.id);
    res.clearCookie("zelon_session", { path: "/" }).json({ ok: true });
  }),
);
app.post(
  "/api/logout",
  consoleOnly,
  wrap(async (req, res) => {
    if (req.cookies.zelon_session)
      await store.delete("sessions", hash(req.cookies.zelon_session));
    res.clearCookie("zelon_session", { path: "/" }).json({ ok: true });
  }),
);
const adminOnly = (req, res, next) =>
  req.user.role !== "admin" || req.apiInstance
    ? res.status(403).json({ error: "Administrator access required" })
    : next();
app.get(
  "/api/admin/users",
  adminOnly,
  wrap(async (req, res) => {
    const owned = {};
    for (const x of await store.all("instances"))
      if (!x.archived) owned[x.userId] = (owned[x.userId] || 0) + 1;
    res.json(
      (await store.query("users", { limit: 1000 })).map(({ password, sessionVersion, ...u }) => ({
        ...u,
        instances: owned[u.id] || 0,
      })),
    );
  }),
);
let creatingUser = false;
app.get(
  "/api/admin/system",
  adminOnly,
  wrap(async (req, res) => {
    const t = Date.now();
    const ns = ["users", "instances", "messages", "hooks", "media"];
    const [, databaseMs, ...rest] = [
      0,
      await store.health().then(() => Date.now() - t),
      ...(await Promise.all([...ns.map((n) => store.stats(n)), store.all("instances"), keepAlive.boots()])),
    ];
    const counts = {};
    ns.forEach((n, i) => (counts[n] = rest[i]));
    const all = rest[ns.length].filter((x) => !x.archived),
      restarts = rest[ns.length + 1],
      byStatus = {};
    for (const x of all) byStatus[x.status || "disconnected"] = (byStatus[x.status || "disconnected"] || 0) + 1;
    const mem = process.memoryUsage();
    const rs = resources();
    res.json({
      database: "healthy",
      databaseMs,
      storage: store.storage,
      uptimeSeconds: Math.floor(process.uptime()),
      startedAt,
      now: new Date().toISOString(),
      nodeVersion: process.version,
      platform: os.platform() + " " + os.arch(),
      pid: process.pid,
      environment: production ? "production" : "development",
      resources: rs,
      memory: {
        rss: mem.rss,
        heapUsed: mem.heapUsed,
        heapTotal: mem.heapTotal,
        heapLimit: rs.process?.heapLimit || null,
      },
      instances: { total: all.length, byStatus, sockets: all.filter((x) => wa.has(x.id)).length },
      liveStreams: bus.size(),
      counts,
      keepAlive: keepAlive.status(),
      restarts,
      origin,
    });
  }),
);
app.get("/api/admin/keepalive", adminOnly, (req, res) => res.json(keepAlive.status()));
app.put(
  "/api/admin/keepalive",
  adminOnly,
  wrap(async (req, res) => {
    const d = z.object({ enabled: z.boolean().optional(), intervalMinutes: z.number().int().optional() }).parse(req.body);
    if (d.intervalMinutes !== undefined && !keepAlive.status().options.includes(d.intervalMinutes))
      fail(400, "Choose an interval of 1, 2, 5, 10 or 15 minutes");
    const s = await keepAlive.configure(d);
    await audit(req, req.user.id, "keepalive_changed", (s.enabled ? "On, every " + s.intervalMinutes + " min" : "Off"));
    res.json(s);
  }),
);
app.post(
  "/api/admin/keepalive/run",
  adminOnly,
  wrap(async (req, res) => res.json(await keepAlive.tick("manual"))),
);

app.get(
  "/api/admin/gemini",
  adminOnly,
  wrap(async (req, res) => {
    const config = await store.get("settings", "gemini");
    res.json({
      keys: config?.keys || [],
      model: config?.model || "gemini-2.5-flash",
      supportedModels: SUPPORTED_GEMINI_MODELS,
    });
  }),
);

app.post(
  "/api/admin/gemini",
  adminOnly,
  wrap(async (req, res) => {
    const { key, model } = z
      .object({
        key: z.string().trim().min(1).optional(),
        model: z.string().trim().min(1).optional(),
      })
      .parse(req.body);
    const config = (await store.get("settings", "gemini")) || { id: "gemini", keys: [] };
    if (key && !config.keys.includes(key)) {
      config.keys.push(key);
      await audit(req, req.user.id, "gemini_key_added", "Added Gemini API Key");
    }
    if (model) {
      config.model = model;
      await audit(req, req.user.id, "gemini_model_updated", "Updated default Gemini Model to " + model);
    }
    await store.set("settings", "gemini", config);
    res.json({ ok: true, keys: config.keys, model: config.model || "gemini-2.5-flash" });
  }),
);

app.post(
  "/api/admin/gemini/delete",
  adminOnly,
  wrap(async (req, res) => {
    const { key } = z.object({ key: z.string().trim().min(1) }).parse(req.body);
    const config = (await store.get("settings", "gemini")) || { id: "gemini", keys: [] };
    config.keys = config.keys.filter((k) => k !== key);
    await store.set("settings", "gemini", config);
    await audit(req, req.user.id, "gemini_key_removed", "Removed Gemini API Key");
    res.json({ ok: true, keys: config.keys, model: config.model || "gemini-2.5-flash" });
  }),
);

app.post(
  "/api/admin/gemini/test",
  adminOnly,
  wrap(async (req, res) => {
    const { key, model } = z
      .object({
        key: z.string().trim().min(1),
        model: z.string().trim().optional(),
      })
      .parse(req.body);
    const result = await verifyGeminiKey(key, model);
    res.json(result);
  }),
);

// --- Broadcasts & Urgent Announcements ---
app.get(
  "/api/admin/broadcasts",
  adminOnly,
  wrap(async (req, res) => {
    const list = (await store.all("broadcasts")) || [];
    list.sort((a, b) => (b.createdAt || 0) - (a.createdAt || 0));
    const allUsers = (await store.all("users")) || [];
    const totalUsers = allUsers.length;

    const results = list.map((b) => {
      const rec = b.recipients || {};
      const seenCount = Object.values(rec).filter((r) => r.seenAt).length;
      const ackCount = Object.values(rec).filter((r) => r.acknowledgedAt).length;
      const replyCount = Object.values(rec).filter((r) => r.reply).length;
      return {
        ...b,
        totalUsers,
        seenCount,
        ackCount,
        pendingCount: Math.max(0, totalUsers - ackCount),
        replyCount,
      };
    });
    res.json(results);
  }),
);

app.post(
  "/api/admin/broadcasts",
  adminOnly,
  wrap(async (req, res) => {
    const data = z
      .object({
        title: z.string().trim().min(1).max(200),
        body: z.string().trim().min(1).max(4000),
        requireAck: z.boolean().default(true),
        allowReply: z.boolean().default(true),
        urgency: z.enum(["normal", "urgent"]).default("normal"),
      })
      .parse(req.body);

    const id = `bcast_${Date.now()}_${Math.random().toString(36).substring(2, 8)}`;
    const broadcast = {
      id,
      title: data.title,
      body: data.body,
      requireAck: data.requireAck,
      allowReply: data.allowReply,
      urgency: data.urgency,
      senderId: req.user.id,
      senderName: req.user.name || "Administrator",
      createdAt: Date.now(),
      createdAtIso: new Date().toISOString(),
      recipients: {},
    };

    await store.set("broadcasts", id, broadcast);
    await audit(req, req.user.id, "broadcast_sent", `Sent broadcast: ${data.title}`);

    // Push notification to all active SSE streams
    const eventPayload = {
      type: "admin_broadcast",
      data: {
        id: broadcast.id,
        title: broadcast.title,
        body: broadcast.body,
        requireAck: broadcast.requireAck,
        allowReply: broadcast.allowReply,
        urgency: broadcast.urgency,
        senderName: broadcast.senderName,
        createdAt: broadcast.createdAt,
        createdAtIso: broadcast.createdAtIso,
      },
    };
    for (const s of streams) {
      try {
        s.write("data: " + JSON.stringify(eventPayload) + "\n\n");
      } catch (_) {}
    }

    res.json({ ok: true, broadcast });
  }),
);

app.get(
  "/api/admin/broadcasts/:id/audit",
  adminOnly,
  wrap(async (req, res) => {
    const broadcast = await store.get("broadcasts", req.params.id);
    if (!broadcast) fail(404, "Broadcast not found");
    const allUsers = (await store.all("users")) || [];
    const rec = broadcast.recipients || {};

    const auditList = allUsers.map((u) => {
      const r = rec[u.id] || {};
      return {
        userId: u.id,
        name: u.name || "User",
        email: u.email,
        role: u.role,
        seen: !!r.seenAt,
        seenAt: r.seenAt || null,
        acknowledged: !!r.acknowledgedAt,
        acknowledgedAt: r.acknowledgedAt || null,
        reply: r.reply || null,
        repliedAt: r.repliedAt || null,
      };
    });

    res.json({
      broadcast: {
        id: broadcast.id,
        title: broadcast.title,
        body: broadcast.body,
        requireAck: broadcast.requireAck,
        allowReply: broadcast.allowReply,
        urgency: broadcast.urgency,
        createdAt: broadcast.createdAt,
      },
      audit: auditList,
    });
  }),
);

app.get(
  "/api/user/broadcasts",
  consoleOnly,
  wrap(async (req, res) => {
    const list = (await store.all("broadcasts")) || [];
    list.sort((a, b) => (b.createdAt || 0) - (a.createdAt || 0));
    const userId = req.user.id;

    const userBroadcasts = list.map((b) => {
      const userState = (b.recipients && b.recipients[userId]) || {};
      return {
        id: b.id,
        title: b.title,
        body: b.body,
        requireAck: b.requireAck,
        allowReply: b.allowReply,
        urgency: b.urgency,
        senderName: b.senderName,
        createdAt: b.createdAt,
        createdAtIso: b.createdAtIso,
        seen: !!userState.seenAt,
        seenAt: userState.seenAt || null,
        acknowledged: !!userState.acknowledgedAt,
        acknowledgedAt: userState.acknowledgedAt || null,
        reply: userState.reply || null,
        repliedAt: userState.repliedAt || null,
      };
    });
    res.json(userBroadcasts);
  }),
);

app.post(
  "/api/user/broadcasts/:id/seen",
  consoleOnly,
  wrap(async (req, res) => {
    const broadcast = await store.get("broadcasts", req.params.id);
    if (!broadcast) fail(404, "Broadcast not found");
    broadcast.recipients = broadcast.recipients || {};
    broadcast.recipients[req.user.id] = broadcast.recipients[req.user.id] || {};
    if (!broadcast.recipients[req.user.id].seenAt) {
      broadcast.recipients[req.user.id].seenAt = new Date().toISOString();
      await store.set("broadcasts", broadcast.id, broadcast);
    }
    res.json({ ok: true });
  }),
);

app.post(
  "/api/user/broadcasts/:id/ack",
  consoleOnly,
  wrap(async (req, res) => {
    const broadcast = await store.get("broadcasts", req.params.id);
    if (!broadcast) fail(404, "Broadcast not found");
    broadcast.recipients = broadcast.recipients || {};
    broadcast.recipients[req.user.id] = broadcast.recipients[req.user.id] || {};
    broadcast.recipients[req.user.id].seenAt = broadcast.recipients[req.user.id].seenAt || new Date().toISOString();
    broadcast.recipients[req.user.id].acknowledgedAt = new Date().toISOString();
    await store.set("broadcasts", broadcast.id, broadcast);
    res.json({ ok: true, acknowledgedAt: broadcast.recipients[req.user.id].acknowledgedAt });
  }),
);

app.post(
  "/api/user/broadcasts/:id/reply",
  consoleOnly,
  wrap(async (req, res) => {
    const { reply } = z.object({ reply: z.string().trim().min(1).max(1000) }).parse(req.body);
    const broadcast = await store.get("broadcasts", req.params.id);
    if (!broadcast) fail(404, "Broadcast not found");
    broadcast.recipients = broadcast.recipients || {};
    broadcast.recipients[req.user.id] = broadcast.recipients[req.user.id] || {};
    broadcast.recipients[req.user.id].seenAt = broadcast.recipients[req.user.id].seenAt || new Date().toISOString();
    broadcast.recipients[req.user.id].reply = reply;
    broadcast.recipients[req.user.id].repliedAt = new Date().toISOString();
    await store.set("broadcasts", broadcast.id, broadcast);
    res.json({ ok: true, reply, repliedAt: broadcast.recipients[req.user.id].repliedAt });
  }),
);

app.post(
  "/api/admin/users",
  adminOnly,
  wrap(async (req, res) => {
    if (creatingUser) fail(409, "Another account is being created; try again");
    creatingUser = true;
    try {
      const data = z
        .object({
          email: z.email().max(254),
          role: z.enum(["admin", "user"]).default("user"),
          name: z.string().trim().max(80).optional(),
          permissions: z.record(z.boolean()).optional(),
        })
        .parse(req.body);
      if ((await store.query("users", { email: data.email, limit: 1 })).length)
        fail(409, "An account with this email already exists");
      const id = randomUUID(),
        password = token().slice(0, 24);
      await store.set("users", id, {
        id,
        email: data.email.toLowerCase(),
        name: data.name || "",
        role: data.role,
        permissions: data.permissions || {},
        password: passwordHash(password),
        createdAt: new Date().toISOString(),
      });
      await audit(req, id, "account_created", "Created by " + req.user.email);
      res.status(201).json({ id, email: data.email, password });
    } finally {
      creatingUser = false;
    }
  }),
);
app.put(
  "/api/admin/users/:userId",
  adminOnly,
  wrap(async (req, res) => {
    const data = z
      .object({
        disabled: z.boolean().optional(),
        role: z.enum(["admin", "user"]).optional(),
        name: z.string().trim().max(80).optional(),
        email: z.email().max(254).optional(),
        permissions: z.record(z.boolean()).optional(),
      })
      .parse(req.body);
    const own = req.params.userId === req.user.id;
    if (own && (data.disabled !== undefined || data.role !== undefined))
      fail(400, "You cannot change your own role or disable your own administrator account");
    const u = await store.get("users", req.params.userId);
    if (!u) fail(404, "Account not found");
    if (data.email) {
      const taken = (await store.query("users", { email: data.email.toLowerCase(), limit: 1 }))[0];
      if (taken && taken.id !== u.id) fail(409, "An account with this email already exists");
      u.email = data.email.toLowerCase();
    }
    if (data.name !== undefined) u.name = data.name;
    if (data.role !== undefined) u.role = data.role;
    if (data.permissions !== undefined) u.permissions = data.permissions;
    if (data.disabled !== undefined) {
      u.disabled = data.disabled;
      if (data.disabled) u.sessionVersion = token();
    }
    await store.set("users", u.id, u);
    if (data.disabled) for (const x of await store.query("sessions", { userId: u.id, limit: 500 })) await store.delete("sessions", x.id);
    await audit(req, u.id, "account_updated", Object.keys(data).join(", ") + " changed by " + req.user.email);
    res.json({ ok: true });
  }),
);
app.post(
  "/api/admin/users/:userId/sign-out",
  adminOnly,
  wrap(async (req, res) => {
    const u = await store.get("users", req.params.userId);
    if (!u) fail(404, "Account not found");
    if (u.id === req.user.id) fail(400, "Use the sign out option in your account");
    await store.patch("users", u.id, { sessionVersion: token() });
    for (const x of await store.query("sessions", { userId: u.id, limit: 500 })) await store.delete("sessions", x.id);
    await audit(req, u.id, "forced_sign_out", "All devices signed out by " + req.user.email);
    res.json({ ok: true });
  }),
);
app.delete(
  "/api/admin/users/:userId",
  adminOnly,
  wrap(async (req, res) => {
    const u = await store.get("users", req.params.userId);
    if (!u) fail(404, "Account not found");
    if (u.id === req.user.id) fail(400, "You cannot delete your own account");
    for (const x of await store.query("instances", { userId: u.id, limit: 1000 })) {
      try { await wa.disconnect(x, false); } catch {}
      await store.patch("instances", x.id, { archived: true, activeKeyId: "revoked" });
    }
    for (const x of await store.query("sessions", { userId: u.id, limit: 500 })) await store.delete("sessions", x.id);
    await store.delete("users", u.id);
    await audit(req, req.user.id, "account_deleted", u.email + " deleted");
    res.json({ ok: true });
  }),
);
app.post(
  "/api/admin/users/:userId/reset-password",
  adminOnly,
  wrap(async (req, res) => {
    const u = await store.get("users", req.params.userId);
    if (!u) fail(404, "Account not found");
    if (u.id === req.user.id) fail(400, "Use your account password form");
    const password = token().slice(0, 24);
    await store.patch("users", u.id, {
      password: passwordHash(password),
      sessionVersion: token(),
      passwordChangedAt: new Date().toISOString(),
    });
    for (const x of await store.query("sessions", { userId: u.id, limit: 500 })) await store.delete("sessions", x.id);
    await audit(req, u.id, "password_reset", "Reset by " + req.user.email);
    res.json({ password });
  }),
);
app.post(
  "/api/instances/:id/restore",
  consoleOnly,
  wrap(async (req, res) => {
    const x = await store.get("instances", req.params.id);
    if (!x || x.userId !== req.user.id) fail(404, "Instance not found");
    await store.patch("instances", x.id, {
      archived: false,
      status: "disconnected",
    });
    res.json({ ok: true });
  }),
);
app.post(
  "/api/instances/:id/delete",
  consoleOnly,
  wrap(async (req, res) => {
    const x = await store.get("instances", req.params.id);
    if (!x || x.userId !== req.user.id) fail(404, "Instance not found");
    try { await wa.disconnect(x, true); } catch {}
    try { await wa.reset(x, true); } catch {}
    await store.clearInstance(x.id);
    await store.delete("instances", x.id);
    res.json({ ok: true });
  }),
);
app.delete(
  "/api/instances/:id",
  consoleOnly,
  wrap(async (req, res) => {
    const x = await store.get("instances", req.params.id);
    if (!x || x.userId !== req.user.id) fail(404, "Instance not found");
    try { await wa.disconnect(x, true); } catch {}
    try { await wa.reset(x, true); } catch {}
    await store.clearInstance(x.id);
    await store.delete("instances", x.id);
    res.json({ ok: true });
  }),
);
app.get(
  "/api/archived-instances",
  consoleOnly,
  wrap(async (req, res) =>
    res.json(
      (await store.query("instances", { userId: req.user.id, limit: 1000 }))
        .filter((x) => x.archived)
        .map(({ webhookSecret, activeKeyId, ...x }) => x),
    ),
  ),
);
app.put(
  "/api/instances/:id/name",
  consoleOnly,
  wrap(async (req, res) => {
    const { name } = z
      .object({ name: z.string().trim().min(1).max(60) })
      .parse(req.body);
    const x = await store.get("instances", req.params.id);
    if (!x || x.userId !== req.user.id) fail(404, "Instance not found");
    await store.patch("instances", x.id, { name });
    res.json({ ok: true });
  }),
);
app.get(
  "/api/instances",
  consoleOnly,
  wrap(async (req, res) =>
    res.json(
      (await store.query("instances", { userId: req.user.id, limit: 1000 }))
        .filter((x) => !x.archived)
        .map(({ webhookSecret, activeKeyId, ...x }) => x),
    ),
  ),
);
app.post(
  "/api/instances",
  consoleOnly,
  wrap(async (req, res) => {
    const { name } = z
      .object({ name: z.string().trim().min(1).max(60) })
      .parse(req.body);
    const x = {
      id: randomUUID(),
      userId: req.user.id,
      name,
      status: "disconnected",
      createdAt: new Date().toISOString(),
      webhookUrl: "",
      webhookSecret: enc.seal(token()),
    };
    await store.set("instances", x.id, x);
    res.status(201).json({ id: x.id });
  }),
);
app.use(
  "/api/instances/:id",
  wrap(async (req, res, next) => {
    const x = await store.get("instances", req.params.id);
    if (
      !x ||
      x.archived ||
      x.userId !== req.user.id ||
      (req.apiInstance && req.apiInstance !== x.id)
    )
      fail(404, "Instance not found");
    req.instance = x;
    next();
  }),
);
const media = createMediaStore(store, enc),
  inbox = createInbox(store, enc, (instance, event) => bus.publish(instance.id, event)),
  automation = createAutomation(store, enc);
const wa = gateway(
  store,
  enc,
  async (instance, type, data) => {
    if (["presence", "connection", "message", "receipt", "group", "group-participants", "history"].includes(type))
      bus.publish(instance.id, { type, data });
    const current = await store.get("instances", instance.id);
    if (!current) return;
    instance = { ...instance, webhookUrl: current.webhookUrl };
    const event = {
      id: randomUUID(),
      instanceId: instance.id,
      userId: instance.userId,
      type,
      data,
      createdAt: new Date().toISOString(),
    };
    await store.set("events", event.id, {
      ...event,
      data: enc.seal(JSON.stringify(data)),
    });
    if (
      instance.webhookUrl &&
      (!current.webhookEvents?.length || current.webhookEvents.includes(type))
    )
      await store.set("hooks", event.id, {
        id: event.id,
        instanceId: instance.id,
        event: enc.seal(JSON.stringify(event)),
        createdAt: event.createdAt,
        attempts: 0,
        nextAt: Date.now(),
        status: "pending",
      });
  },
  { inbox, automation },
);
app.get("/api/instances/:id/stream", (req, res) => {
  res.set({
    "Content-Type": "text/event-stream",
    "Cache-Control": "no-cache, no-transform",
    Connection: "keep-alive",
    "X-Accel-Buffering": "no",
  });
  res.flushHeaders?.();
  streams.add(res);
  const send = (e) => res.write("data: " + JSON.stringify(e) + "\n\n"),
    off = bus.subscribe(req.instance.id, send),
    beat = setInterval(() => res.write(": ping\n\n"), 20000);
  res.write("retry: 3000\n\n");
  send({ type: "ready", status: req.instance.status });
  req.on("close", () => {
    clearInterval(beat);
    off();
    streams.delete(res);
  });
});
app.post(
  "/api/instances/:id/connect",
  consoleOnly,
  wrap(async (req, res) => {
    if (req.instance.status !== "connected") await wa.reset(req.instance, true);
    await wa.connect(req.instance);
    res.json({ ok: true });
  }),
);
app.get("/api/instances/:id/qr", consoleOnly, (req, res) => {
  const i = req.instance;
  if (["connecting", "awaiting_qr", "reconnecting"].includes(i.status) && !wa.has(i.id)) wa.connect(i).catch(() => {});
  res.json({ qr: wa.qr(req.instance.id) || null, status: req.instance.status, error: req.instance.connectionError || null });
});
app.post(
  "/api/instances/:id/disconnect",
  consoleOnly,
  wrap(async (req, res) => {
    await wa.disconnect(req.instance, true);
    res.json({ ok: true, status: "disconnected" });
  }),
);
app.post(
  "/api/instances/:id/key",
  consoleOnly,
  wrap(async (req, res) => {
    for (const k of await store.query("keys", {
      instanceId: req.instance.id,
      limit: 1000,
    }))
      await store.delete("keys", k.id);
    const t = token();
    await store.set("keys", hash(t), {
      id: hash(t),
      instanceId: req.instance.id,
      userId: req.user.id,
      createdAt: new Date().toISOString(),
    });
    await store.patch("instances", req.instance.id, { activeKeyId: hash(t) });
    res.json({ key: t });
  }),
);

app.post(
  "/api/instances/:id/ai/suggest-reply",
  consoleOnly,
  wrap(async (req, res) => {
    const { chatJid, messages, prompt, model, keys: clientKeys } = z.object({
      chatJid: z.string().trim().min(1),
      messages: z.array(
        z.object({
          text: z.string().optional().nullable(),
          fromMe: z.boolean(),
          type: z.string().optional().nullable(),
        })
      ),
      prompt: z.string().optional().nullable(),
      model: z.string().optional().nullable(),
      keys: z.array(z.string()).optional(),
    }).parse(req.body);

    if (req.user.permissions && req.user.permissions.canUseAi === false) {
      fail(403, "You do not have permission to use AI features");
    }

    const config = (await store.get("settings", "gemini")) || { id: "gemini", keys: [] };
    let keys = (config?.keys && config.keys.length > 0) ? config.keys : (clientKeys || []);

    // Auto-sync client keys to server settings if server had no keys
    if (clientKeys && clientKeys.length > 0 && (!config.keys || config.keys.length === 0)) {
      config.keys = clientKeys;
      await store.set("settings", "gemini", config);
    }

    if (!keys.length) fail(400, "No Gemini API keys configured. Please add an API key in Admin Control Center -> Gemini AI.");

    const chat = await store.get("chats", chatJid);
    const targetModel = model || config?.model || "gemini-2.0-flash";
    const result = await generateSmartReplies(keys, targetModel, {
      contactName: chat?.name || "Contact",
      messages,
      userPrompt: prompt,
    });

    res.json(result);
  }),
);

app.put(
  "/api/instances/:id/webhook",
  consoleOnly,
  wrap(async (req, res) => {
    const { url } = z.object({ url: z.string().max(1000) }).parse(req.body);
    if (url) webhookUrl(url);
    await store.patch("instances", req.instance.id, { webhookUrl: url });
    res.json({ url, secret: enc.open(req.instance.webhookSecret) });
  }),
);
const content = buildContent(media, inbox.load);
app.post(
  "/api/instances/:id/messages",
  wrap(async (req, res) => {
    const d = messageSchema.parse(req.body);
    await validateMessage(req.instance, d, media, inbox.load);
    const { httpStatus, ...result } = await enqueueMessage(
      store,
      enc,
      req.instance,
      d,
      req.headers["idempotency-key"],
      () => {},
    );
    work().catch(() => {});
    res.status(httpStatus).json(result);
  }),
);
function page(q) {
  const limit = q.limit === undefined ? 100 : Number(q.limit);
  if (!Number.isInteger(limit) || limit < 1 || limit > 100)
    fail(400, "Limit must be 1 to 100");
  if (q.before) {
    const before = Date.parse(String(q.before));
    if (!Number.isFinite(before) || !q.beforeId)
      fail(400, "Use before (ISO time) with beforeId to paginate");
    return { limit, before, beforeKey: String(q.beforeId) };
  }
  return { limit };
}
app.get(
  "/api/instances/:id/messages",
  wrap(async (req, res) =>
    res.json(
      (
        await store.query("messages", {
          instanceId: req.instance.id,
          ...page(req.query),
        })
      ).map(({ payload, ...x }) => ({
        ...x,
        text: JSON.parse(enc.open(payload)).text || "",
      })),
    ),
  ),
);
app.post(
  "/api/instances/:id/messages/:messageId/cancel",
  wrap(async (req, res) => {
    const m = await store.get("messages", req.params.messageId);
    if (!m || m.instanceId !== req.instance.id) fail(404, "Message not found");
    if (m.status !== "queued")
      fail(409, "Only queued messages can be cancelled");
    m.status = "cancelled";
    if (!(await store.transition("messages", m.id, "queued", m)))
      fail(409, "Message already started sending");
    res.json({ ok: true });
  }),
);
app.get(
  "/api/instances/:id/events",
  wrap(async (req, res) =>
    res.json(
      (
        await store.query("events", {
          instanceId: req.instance.id,
          ...page(req.query),
        })
      ).map((x) => ({ ...x, data: JSON.parse(enc.open(x.data)) })),
    ),
  ),
);
app.get(
  "/api/instances/:id/webhooks",
  consoleOnly,
  wrap(async (req, res) =>
    res.json(
      (
        await store.query("hooks", {
          instanceId: req.instance.id,
          ...page(req.query),
        })
      ).map(({ event, ...x }) => x),
    ),
  ),
);
app.post(
  "/api/instances/:id/check-number",
  wrap(async (req, res) => {
    const { phone } = z.object({ phone: z.string() }).parse(req.body);
    const results = await wa.active(req.instance.id).onWhatsApp(jid(phone));
    res.json(results || []);
  }),
);
app.get(
  "/api/instances/:id/groups",
  wrap(async (req, res) =>
    res.json(await wa.active(req.instance.id).groupFetchAllParticipating()),
  ),
);
app.post(
  "/api/instances/:id/groups",
  wrap(async (req, res) => {
    const d = z
      .object({
        name: z.string().min(1).max(100),
        participants: z.array(z.string()).min(1).max(100),
      })
      .parse(req.body);
    res.json(
      await wa
        .active(req.instance.id)
        .groupCreate(d.name, d.participants.map(jid)),
    );
  }),
);
app.put(
  "/api/instances/:id/groups/:group/participants",
  wrap(async (req, res) => {
    const d = z
      .object({
        participants: z.array(z.string()).min(1).max(100),
        action: z.enum(["add", "remove", "promote", "demote"]),
      })
      .parse(req.body);
    const group = jid(req.params.group);
    if (!group.endsWith("@g.us")) fail(400, "Group JID required");
    res.json(
      await wa
        .active(req.instance.id)
        .groupParticipantsUpdate(group, d.participants.map(jid), d.action),
    );
  }),
);
app.get(
  "/api/instances/:id/avatar",
  wrap(async (req, res) =>
    res.json({
      url: await wa
        .active(req.instance.id)
        .profilePictureUrl(jid(String(req.query.phone || "")), "image"),
    }),
  ),
);
app.use(
  "/api/instances/:id",
  createFeatures({ store, enc, wa, inbox, media, wrap, page }),
);
app.use("/api", (req, res) =>
  res.status(404).json({ error: "API endpoint not found" }),
);
app.get("/sdk/:file", (req, res, next) => {
  if (!["zelon.mjs", "zelon.py", "zelon.php"].includes(req.params.file))
    return res.status(404).end();
  res.download(
    path.join(
      path.dirname(fileURLToPath(import.meta.url)),
      "../sdk",
      req.params.file,
    ),
  );
});
app.use(
  express.static(
    path.join(path.dirname(fileURLToPath(import.meta.url)), "../public"),
  ),
);
app.get("/{*path}", (req, res) =>
  res.sendFile(
    path.join(
      path.dirname(fileURLToPath(import.meta.url)),
      "../public/index.html",
    ),
  ),
);
app.use((err, req, res, next) => {
  if (res.headersSent) {
    res.destroy(err);
    return;
  }
  if (
    err.message === "Use an international phone number or a group JID" ||
    err.message === "A recipient is required" ||
    err.message === "Use a public HTTPS webhook URL on port 443"
  )
    return res.status(400).json({ error: err.message });
  if (err instanceof z.ZodError)
    return res.status(400).json({
      error: err.issues
        .map((x) => `${x.path.join(".")}: ${x.message}`)
        .join("; "),
    });
  res.status(err.status || 500).json({
    error: err.status
      ? err.message
      : "Operation failed. Check the connection and server logs.",
  });
  if (!err.status) console.error(err.message);
});
const work = createWorker(store, enc, wa, content);
// A send interrupted after submission may already be delivered; never resend automatically.
while (true) {
  const interrupted = await store.query("messages", {
    status: "sending",
    limit: 500,
  });
  if (!interrupted.length) break;
  for (const m of interrupted) {
    m.status = "unknown";
    await store.set("messages", m.id, m);
  }
}
for (const x of await store.all("instances"))
  if (!x.archived && (["connected", "reconnecting"].includes(x.status) || (x.status === "disconnected" && !/code 440/.test(x.connectionError || "") && (await wa.canResume(x)))))
    await wa.connect(x);
const keepAlive = createKeepAlive({
  store,
  origin,
  wa,
  enabled: process.env.KEEPALIVE !== "off",
  minutes: Number(process.env.KEEPALIVE_MINUTES || 5),
});
await keepAlive.start();
const timer = setInterval(
  () => work().catch((e) => console.error("Worker failed:", e.message)),
  2000,
);
timer.unref();
// Only the process holding the SQLite lease publishes this authenticated loopback endpoint.
// Other LiteSpeed processes forward here instead of opening WhatsApp sessions.
let internalServer;
if (store.storage.driver === "sqlite" && store.storage.directory) {
  const secret = randomUUID() + randomUUID();
  internalServer = createServer((req, res) => {
    if (req.headers["x-zelon-worker-token"] !== secret) {
      res.writeHead(403); res.end(); return;
    }
    delete req.headers["x-zelon-worker-token"];
    app(req, res);
  });
  const tcp = process.env.WORKER_TRANSPORT === "tcp";
  const socketPath = path.join(store.storage.directory, "worker.sock");
  // The database lease is already held, so an abandoned socket is safe to unlink.
  if (!tcp) rmSync(socketPath, { force: true });
  await new Promise((resolve, reject) => {
    internalServer.once("error", reject);
    // Bypass LiteSpeed's HTTP listen override for this private listener.
    if (tcp)
      NetServer.prototype.listen.call(internalServer, 0, "127.0.0.1", resolve);
    else NetServer.prototype.listen.call(internalServer, socketPath, resolve);
  });
  if (!tcp) chmodSync(socketPath, 0o600);
  const endpoint = tcp
    ? { port: NetServer.prototype.address.call(internalServer).port }
    : { socketPath };
  writeFileSync(workerEndpoint(), JSON.stringify({
    ...endpoint, secret, pid: process.pid,
  }), { mode: 0o600 });
  console.log("Zelon private worker listening:", JSON.stringify({ pid: process.pid, ...endpoint }));
}
const server = app.listen(Number(process.env.PORT || 3000), "0.0.0.0", () =>
  console.log("Zelon API listening"),
);
let stopping = false;
async function shutdown() {
  if (stopping) return;
  stopping = true;
  clearInterval(timer);
  keepAlive.stop();
  for (const r of streams) r.end();
  setTimeout(() => process.exit(1), 15000).unref();
  try {
    await Promise.all([
      new Promise((resolve) => server.close(resolve)),
      internalServer && new Promise((resolve) => internalServer.close(resolve)),
    ]);
    await work.stop();
    await wa.shutdown();
    await store.close();
    process.exit(0);
  } catch (e) {
    console.error("Shutdown failed:", e.message);
    process.exit(1);
  }
}
process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);
