import express from "express";
import helmet from "helmet";
import rateLimit from "express-rate-limit";
import cookieParser from "cookie-parser";
import { z } from "zod";
import { randomUUID } from "node:crypto";
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
        imgSrc: ["'self'", "data:"],
        connectSrc: ["'self'"],
        fontSrc: ["'self'"],
        objectSrc: ["'none'"],
        frameAncestors: ["'none'"],
      },
    },
  }),
);
app.use(express.json({ limit: "1mb" }));
app.use(cookieParser());
app.use(
  "/api",
  rateLimit({
    windowMs: 60000,
    limit: (req) => (/\/media\/[^/]+\/chunks\//.test(req.path) ? 1500 : 180),
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
    if (req.headers.origin !== origin)
      return res.status(403).json({ error: "Request origin is not allowed" });
  }
  next();
});
const wrap = (fn) => (req, res, next) =>
  Promise.resolve(fn(req, res, next)).catch(next);
const fail = (status, message) => {
  throw Object.assign(Error(message), { status });
};
app.get(
  "/health",
  wrap(async (req, res) => {
    await store.health();
    res.json({ status: "ok" });
  }),
);
app.post(
  "/api/login",
  rateLimit({
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
    )
      fail(401, "Incorrect email or password");
    const t = token();
    await store.set("sessions", hash(t), {
      id: hash(t),
      userId: user.id,
      version: user.sessionVersion || 0,
      expires: Date.now() + 86400000,
    });
    res.cookie("zelon_session", t, {
      httpOnly: true,
      secure: production,
      sameSite: "strict",
      maxAge: 86400000,
      path: "/",
    });
    res.json({ ok: true });
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
    }
  } else if (req.cookies.zelon_session) {
    const s = await store.get("sessions", hash(req.cookies.zelon_session));
    if (s && s.expires > Date.now()) {
      const u = await store.get("users", s.userId);
      if (u && (u.sessionVersion || 0) === (s.version || 0)) req.user = u;
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
  res.json({ id: req.user.id, email: req.user.email, role: req.user.role }),
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
    await store.set("users", req.user.id, req.user);
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
  wrap(async (req, res) =>
    res.json(
      (await store.query("users", { limit: 1000 })).map(
        ({ password, ...u }) => u,
      ),
    ),
  ),
);
let creatingUser = false;
app.get(
  "/api/admin/system",
  adminOnly,
  wrap(async (req, res) => {
    await store.health();
    const counts = {};
    for (const ns of ["users", "instances", "messages", "hooks", "media"])
      counts[ns] = await store.stats(ns);
    res.json({
      database: "healthy",
      storage: store.storage,
      uptimeSeconds: Math.floor(process.uptime()),
      nodeVersion: process.version,
      counts,
    });
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
        })
        .parse(req.body);
      if ((await store.query("users", { email: data.email, limit: 1 })).length)
        fail(409, "An account with this email already exists");
      const id = randomUUID(),
        password = token().slice(0, 24);
      await store.set("users", id, {
        id,
        email: data.email.toLowerCase(),
        role: data.role,
        password: passwordHash(password),
        createdAt: new Date().toISOString(),
      });
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
    if (req.params.userId === req.user.id)
      fail(400, "You cannot disable your own administrator account");
    const data = z.object({ disabled: z.boolean() }).parse(req.body);
    const u = await store.get("users", req.params.userId);
    if (!u) fail(404, "Account not found");
    u.disabled = data.disabled;
    await store.set("users", u.id, u);
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
    });
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
  inbox = createInbox(store, enc),
  automation = createAutomation(store, enc);
const wa = gateway(
  store,
  enc,
  async (instance, type, data) => {
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
app.post(
  "/api/instances/:id/connect",
  consoleOnly,
  wrap(async (req, res) => {
    await wa.connect(req.instance);
    res.json({ ok: true });
  }),
);
app.get("/api/instances/:id/qr", consoleOnly, (req, res) =>
  res.json({ qr: wa.qr(req.instance.id) || null, status: req.instance.status }),
);
app.post(
  "/api/instances/:id/disconnect",
  consoleOnly,
  wrap(async (req, res) => {
    await wa.disconnect(req.instance, true);
    res.json({ ok: true });
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
  if (!x.archived && ["connected", "reconnecting"].includes(x.status))
    await wa.connect(x);
const timer = setInterval(
  () => work().catch((e) => console.error("Worker failed:", e.message)),
  2000,
);
timer.unref();
const server = app.listen(Number(process.env.PORT || 3000), "0.0.0.0", () =>
  console.log("Zelon API listening"),
);
let stopping = false;
async function shutdown() {
  if (stopping) return;
  stopping = true;
  clearInterval(timer);
  setTimeout(() => process.exit(1), 15000).unref();
  try {
    await new Promise((resolve) => server.close(resolve));
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
