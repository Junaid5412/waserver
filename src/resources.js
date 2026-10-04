import { readFileSync } from "node:fs";
import os from "node:os";
import v8 from "node:v8";

const read = (p) => {
  try { return readFileSync(p, "utf8").trim(); } catch { return null; }
};
const num = (v) => {
  const n = Number(v);
  return Number.isFinite(n) && n > 0 && n < 2 ** 52 ? n : null;
};

// os.totalmem(), os.freemem(), os.loadavg() and os.cpus() describe the whole physical
// server. On shared hosting that is hundreds of other sites, so we report this app's own
// limits (cgroup) and its own CPU use instead, and say when a number is unavailable.
function memory() {
  const rss = process.memoryUsage().rss;
  let used = null, limit = null, source = "process";
  const v2cur = num(read("/sys/fs/cgroup/memory.current")), v2max = read("/sys/fs/cgroup/memory.max");
  if (v2cur) {
    used = v2cur; source = "container";
    limit = v2max && v2max !== "max" ? num(v2max) : null;
  } else {
    const v1use = num(read("/sys/fs/cgroup/memory/memory.usage_in_bytes"));
    if (v1use) {
      used = v1use; source = "container";
      const lim = num(read("/sys/fs/cgroup/memory/memory.limit_in_bytes"));
      limit = lim && lim < os.totalmem() * 4 && lim < 2 ** 50 ? lim : null;
    }
  }
  return { used: used ?? rss, limit, source };
}

function cpuQuota() {
  const v2 = read("/sys/fs/cgroup/cpu.max");
  if (v2) {
    const [q, p] = v2.split(/\s+/);
    if (q !== "max" && num(q) && num(p)) return num(q) / num(p);
  }
  const q = Number(read("/sys/fs/cgroup/cpu/cpu.cfs_quota_us")), p = Number(read("/sys/fs/cgroup/cpu/cpu.cfs_period_us"));
  return q > 0 && p > 0 ? q / p : null;
}

let last = { at: Date.now(), cpu: process.cpuUsage() };
let lastPercent = null;
function cpuPercent() {
  const now = Date.now(), usage = process.cpuUsage();
  const wall = (now - last.at) * 1000;
  if (wall >= 2000000 || lastPercent === null) {
    const spent = usage.user - last.cpu.user + (usage.system - last.cpu.system);
    // percent of one core, averaged since the previous sample
    if (wall > 0) lastPercent = Math.max(0, Math.round((spent / wall) * 1000) / 10);
    last = { at: now, cpu: usage };
  }
  return lastPercent ?? 0;
}

export function resources() {
  const m = memory(), mem = process.memoryUsage();
  const quota = cpuQuota();
  let heapLimit = null;
  try { heapLimit = v8.getHeapStatistics()?.heap_size_limit || null; } catch {}
  return {
    memory: { used: m.used, limit: m.limit, source: m.source },
    process: { rss: mem.rss, heapUsed: mem.heapUsed, heapTotal: mem.heapTotal, heapLimit, external: mem.external },
    cpu: { processPercent: cpuPercent(), limitCores: quota ? Math.round(quota * 100) / 100 : null },
  };
}
