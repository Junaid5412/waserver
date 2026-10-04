import { randomUUID } from "node:crypto";
// Keeps hosted deployments awake (many hosts sleep an idle app after 15-30 minutes)
// and revives WhatsApp sessions whose socket silently disappeared.
const ALLOWED = [1, 2, 5, 10, 15];
export function createKeepAlive({ store, origin, wa, fetcher = globalThis.fetch, enabled = true, minutes = 4 }) {
  const history = [],
    state = {
      enabled,
      intervalMinutes: ALLOWED.includes(minutes) ? minutes : 5,
      lastAt: null,
      lastOk: null,
      lastMs: null,
      lastError: null,
      lastWatchdog: 0,
      ok: 0,
      fail: 0,
      nextAt: null,
    };
  let timer,
    running = false,
    stopped = false,
    loaded = false;
  const url = origin.replace(/\/$/, "") + "/health";
  async function restore() {
    if (loaded) return;
    loaded = true;
    try {
      const saved = await store.get("settings", "keepalive");
      if (saved) {
        if (typeof saved.enabled === "boolean") state.enabled = saved.enabled;
        if (ALLOWED.includes(saved.intervalMinutes)) state.intervalMinutes = saved.intervalMinutes;
      }
    } catch {}
  }
  async function watchdog() {
    let revived = 0;
    for (const status of ["connected", "reconnecting", "disconnected"])
      for (const x of await store.query("instances", { status, limit: 1000 })) {
        if (x.archived || wa.has(x.id)) continue;
        // Disconnected instances are only revived when still linked and not replaced by another session.
        if (status === "disconnected" && (!wa.canResume || /code 440/.test(x.connectionError || "") || !(await wa.canResume(x)))) continue;
        try {
          await wa.connect(x);
          revived++;
        } catch {}
      }
    state.lastWatchdog = revived;
  }
  function schedule() {
    clearTimeout(timer);
    state.nextAt = null;
    if (stopped || !state.enabled) return;
    const ms = state.intervalMinutes * 60000;
    state.nextAt = Date.now() + ms;
    timer = setTimeout(() => tick("schedule"), ms);
    timer.unref?.();
  }
  async function tick(reason = "schedule") {
    if (running) return status();
    running = true;
    const started = Date.now();
    let ok = false,
      error = null;
    try {
      const r = await fetcher(url, {
        headers: { "user-agent": "zelon-keepalive/1" },
        signal: AbortSignal.timeout(15000),
      });
      ok = r.ok;
      if (!ok) error = "HTTP " + r.status;
      await r.arrayBuffer().catch(() => {});
    } catch (e) {
      error = e.name === "TimeoutError" ? "Timed out after 15s" : e.message || "Request failed";
    }
    try { await watchdog(); } catch {}
    state.lastAt = new Date().toISOString();
    state.lastOk = ok;
    state.lastMs = Date.now() - started;
    state.lastError = error;
    state[ok ? "ok" : "fail"]++;
    history.push({ at: state.lastAt, ok, ms: state.lastMs, reason });
    if (history.length > 120) history.shift();
    running = false;
    schedule();
    return status();
  }
  function status() {
    const recent = history.slice(-60);
    return {
      ...state,
      running,
      url,
      options: ALLOWED,
      uptimePercent: recent.length ? Math.round((recent.filter((h) => h.ok).length / recent.length) * 1000) / 10 : null,
      history: recent,
    };
  }
  return {
    status,
    tick,
    async start() {
      await restore();
      try {
        await store.set("sys-boots", randomUUID(), {
          id: randomUUID(),
          createdAt: new Date().toISOString(),
          pid: process.pid,
          node: process.version,
        });
      } catch {}
      stopped = false;
      clearTimeout(timer);
      if (state.enabled) {
        state.nextAt = Date.now() + 20000;
        timer = setTimeout(() => tick("startup"), 20000);
        timer.unref?.();
      }
    },
    async configure({ enabled: on, intervalMinutes }) {
      await restore();
      if (typeof on === "boolean") state.enabled = on;
      if (ALLOWED.includes(intervalMinutes)) state.intervalMinutes = intervalMinutes;
      await store.set("settings", "keepalive", {
        id: "keepalive",
        enabled: state.enabled,
        intervalMinutes: state.intervalMinutes,
        createdAt: new Date().toISOString(),
      });
      schedule();
      return status();
    },
    async boots() {
      return (await store.query("sys-boots", { limit: 12 })).map((b) => ({ at: b.createdAt, pid: b.pid, node: b.node }));
    },
    stop() {
      stopped = true;
      clearTimeout(timer);
    },
  };
}
