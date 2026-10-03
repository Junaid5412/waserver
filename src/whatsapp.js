import makeWASocket, {
  initAuthCreds,
  BufferJSON,
  proto,
  DisconnectReason,
  fetchLatestWaWebVersion,
} from "@whiskeysockets/baileys";
import pino from "pino";
import QRCode from "qrcode";
export function gateway(store, encryption, emit, {
  inbox, automation, socketFactory = makeWASocket,
  versionFetcher = fetchLatestWaWebVersion,
} = {}) {
  const sockets = new Map(),
    qrs = new Map(),
    reconnects = new Map(),
    connecting = new Set(),
    stopped = new Set();
  const logger = pino({ level: "error" });
  let shuttingDown = false;
  let protocol, protocolFetchedAt = 0;
  const reconnectTimers = new Map();
  async function connect(instance) {
    if (
      instance.archived ||
      sockets.has(instance.id) ||
      connecting.has(instance.id)
    )
      return;
    connecting.add(instance.id);
    stopped.delete(instance.id);
    try {
      const read = async (k) => {
        const r = await store.get("auth:" + instance.id, k);
        return r
          ? JSON.parse(encryption.open(r.data), BufferJSON.reviver)
          : null;
      };
      const write = async (k, v) =>
        store.set("auth:" + instance.id, k, {
          data: encryption.seal(JSON.stringify(v, BufferJSON.replacer)),
        });
      const creds = (await read("creds")) || initAuthCreds();
      await write("creds", creds);
      instance.status = "connecting";
      instance.connectionError = null;
      await store.patch("instances", instance.id, {
        status: instance.status,
        phone: instance.phone,
        connectionError: null,
      });
      if (!protocol || Date.now() - protocolFetchedAt > 600000) {
        const latest = await versionFetcher({ timeout: 15000 });
        if (!latest.isLatest || !Array.isArray(latest.version) ||
            latest.version.length !== 3 || !latest.version.every(Number.isInteger))
          throw Object.assign(Error("Cannot fetch the current WhatsApp Web version. Check hosting outbound HTTPS access and retry."), { status: 502 });
        protocol = latest.version;
        protocolFetchedAt = Date.now();
      }
      const socket = socketFactory({
        version: protocol,
        connectTimeoutMs: 30000,
        logger,
        auth: {
          creds,
          keys: {
            async get(type, ids) {
              const result = {};
              for (const id of ids) {
                let v = await read(type + "-" + id);
                if (type === "app-state-sync-key" && v)
                  v = proto.Message.AppStateSyncKeyData.fromObject(v);
                result[id] = v;
              }
              return result;
            },
            async set(data) {
              for (const type in data)
                for (const id in data[type]) {
                  const key = type + "-" + id;
                  if (data[type][id]) await write(key, data[type][id]);
                  else await store.delete("auth:" + instance.id, key);
                }
            },
          },
        },
        getMessage: async (key) => {
          const row = await store.get("wa-message:" + instance.id, key.id);
          if (!row) return undefined;
          const parsed = JSON.parse(
            encryption.open(row.data),
            BufferJSON.reviver,
          );
          return parsed.key ? parsed.message : parsed;
        },
        markOnlineOnConnect: false,
        syncFullHistory: false,
        shouldSyncHistoryMessage: () => true,
      });
      sockets.set(instance.id, socket);
      socket.ev.on("creds.update", () =>
        (sockets.get(instance.id) === socket && !stopped.has(instance.id)
          ? write("creds", creds)
          : Promise.resolve()
        ).catch(() =>
          emit(instance, "error", { message: "Session persistence failed" }),
        ),
      );
      socket.ev.on("connection.update", async (update) => {
        try {
          if (shuttingDown || sockets.get(instance.id) !== socket) return;
          if (update.qr) {
            qrs.set(instance.id, await QRCode.toDataURL(update.qr));
            instance.status = "awaiting_qr";
            instance.connectionError = null;
          }
          if (update.connection === "open") {
            instance.status = "connected";
            instance.connectionError = null;
            instance.phone = socket.user?.id?.split(":")[0];
            qrs.delete(instance.id);
            reconnects.set(instance.id, 0);
          }
          if (update.connection === "close") {
            sockets.delete(instance.id);
            qrs.delete(instance.id);
            const code = update.lastDisconnect?.error?.output?.statusCode;
            if (code === 405) protocol = undefined;
            instance.connectionError = "WhatsApp connection closed" + (code ? " (code " + code + ")" : "") + ". Retry the connection; if it persists, check server outbound WebSocket access.";
            logger.error({ instanceId: instance.id, disconnectCode: code }, "WhatsApp connection closed");
            const terminal = [
              DisconnectReason.loggedOut,
              DisconnectReason.badSession,
              DisconnectReason.connectionReplaced,
              DisconnectReason.forbidden,
            ].includes(code);
            instance.status =
              terminal || stopped.has(instance.id)
                ? "disconnected"
                : "reconnecting";
            if (!terminal && !stopped.has(instance.id)) {
              const n = (reconnects.get(instance.id) || 0) + 1;
              reconnects.set(instance.id, n);
              if (n <= 8) {
                const t = setTimeout(
                  () => {
                    reconnectTimers.delete(instance.id);
                    if (!stopped.has(instance.id) && !shuttingDown)
                      connect(instance).catch(() => {});
                  },
                  Math.min(30000, 1000 * 2 ** n),
                );
                t.unref();
                reconnectTimers.set(instance.id, t);
              } else instance.status = "disconnected";
            }
          }
          const current = await store.get("instances", instance.id);
          if (current) {
            instance = {
              ...current,
              status: instance.status,
              phone: instance.phone,
              connectionError: instance.connectionError,
            };
            await store.patch("instances", instance.id, {
              status: instance.status,
              phone: instance.phone,
              connectionError: instance.connectionError,
            });
          }
          await emit(instance, "connection", { status: instance.status });
        } catch {
          logger.error("Connection persistence failed");
        }
      });
      socket.ev.on("messages.upsert", async ({ messages, type }) => {
        for (const m of messages) {
          if (!m.message || !m.key.id) continue;
          try {
            const fresh = inbox
              ? await inbox.persist(instance, m, { notify: type === "notify" })
              : true;
            if (inbox && fresh && automation)
              await automation(instance, m, { notify: type === "notify" });
            if (!fresh) continue;
            await emit(instance, "message", {
              id: m.key.id,
              chatId: m.key.remoteJid,
              fromMe: m.key.fromMe,
              type,
              text:
                m.message.conversation ||
                m.message.extendedTextMessage?.text ||
                "",
              message: m.message,
            });
          } catch {
            logger.error("Message persistence failed");
          }
        }
      });
      socket.ev.on("messages.update", async (updates) => {
        try {
          if (inbox) await inbox.receipt(instance, updates);
          await emit(instance, "receipt", { updates });
        } catch {}
      });
      socket.ev.on("message-receipt.update", async (updates) => {
        try {
          if (inbox)
            await inbox.receipt(
              instance,
              updates.map(({ key, receipt }) => ({
                key,
                update: {
                  status: receipt.playedTimestamp
                    ? 5
                    : receipt.readTimestamp
                      ? 4
                      : 3,
                },
              })),
            );
          await emit(instance, "receipt", { userReceipts: updates });
        } catch (e) {
          logger.error({ err: e }, "Receipt persistence failed");
        }
      });
      if (inbox) {
        for (const event of ["chats.upsert", "chats.update"])
          socket.ev.on(event, async (rows) => {
            try { for (const row of rows) await inbox.chat(instance, row); }
            catch (error) { logger.error({ err: error }, "Chat persistence failed"); }
          });
        socket.ev.on(
          "messaging-history.set",
          async ({ messages, contacts, chats }) => {
            try {
              for (const c of chats || []) await inbox.chat(instance, c);
              for (const c of contacts || []) await inbox.contact(instance, c);
              for (const m of messages || []) await inbox.persist(instance, m);
              await emit(instance, "history", {
                messages: messages?.length || 0,
                contacts: contacts?.length || 0,
                chats: chats?.length || 0,
              });
            } catch (e) {
              logger.error({ err: e }, "History persistence failed");
            }
          },
        );
        for (const event of ["contacts.upsert", "contacts.update"])
          socket.ev.on(event, async (contacts) => {
            try {
              for (const c of contacts)
                if (c.id) await inbox.contact(instance, c);
            } catch (e) {
              logger.error({ err: e }, "Contact persistence failed");
            }
          });
      }
      socket.ev.on("presence.update", async (data) => {
        try {
          await emit(instance, "presence", data);
        } catch {}
      });
      socket.ev.on("groups.update", async (data) => {
        try {
          await emit(instance, "group", data);
        } catch {}
      });
      socket.ev.on("group-participants.update", async (data) => {
        try {
          await emit(instance, "group-participants", data);
        } catch {}
      });
      socket.ev.on("call", async (data) => {
        try {
          await emit(instance, "call", data);
        } catch {}
      });
    } catch (error) {
      if (!sockets.has(instance.id)) {
        instance.status = "disconnected";
        await store.patch("instances", instance.id, {
          status: instance.status,
          connectionError: error.status === 502 ? error.message : "WhatsApp startup failed. Check server logs and retry.",
        });
      }
      logger.error({ instanceId: instance.id, code: error.code }, "WhatsApp startup failed");
      throw error;
    } finally {
      connecting.delete(instance.id);
    }
  }
  const active = (id) => {
    const s = sockets.get(id);
    if (!s?.user)
      throw Object.assign(Error("Connect this WhatsApp instance first"), {
        status: 409,
      });
    return s;
  };
  return {
    connect,
    async pairingCode(instance, phone) {
      await connect(instance);
      const s = sockets.get(instance.id);
      if (!s)
        throw Object.assign(Error("Connection is not ready"), { status: 409 });
      if (s.authState.creds.registered)
        throw Object.assign(Error("This instance is already linked"), {
          status: 409,
        });
      await s.waitForSocketOpen();
      return s.requestPairingCode(phone.replace("+", ""));
    },
    async recordSent(instance, message) {
      if (inbox && message?.message) await inbox.persist(instance, message);
    },
    qr: (id) => qrs.get(id),
    active,
    async disconnect(instance, logout = false) {
      stopped.add(instance.id);
      clearTimeout(reconnectTimers.get(instance.id));
      reconnectTimers.delete(instance.id);
      const s = sockets.get(instance.id);
      if (s) {
        if (logout) await s.logout();
        else s.end(undefined);
      }
      sockets.delete(instance.id);
      qrs.delete(instance.id);
      if (logout) await store.clearNamespace("auth:" + instance.id);
      instance.status = "disconnected";
      await store.patch("instances", instance.id, {
        status: instance.status,
        phone: instance.phone,
      });
    },
    async shutdown() {
      shuttingDown = true;
      for (const t of reconnectTimers.values()) clearTimeout(t);
      reconnectTimers.clear();
      for (const id of sockets.keys()) stopped.add(id);
      for (const s of sockets.values()) s.end(undefined);
      sockets.clear();
    },
  };
}
