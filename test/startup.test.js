import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { randomBytes } from "node:crypto";
import { mkdtemp, rm, readFile, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import { setTimeout as delay } from "node:timers/promises";

test("LiteSpeed CommonJS require starts the production ESM application", async () => {
  const dir = await mkdtemp(tmpdir() + "/zelon-loader-");
  let logs = "";
  let follower, followerClosed;
  const child = spawn(process.execPath, ["--input-type=commonjs", "-e",
    'const http = require("node:http"); const originalListen = http.Server.prototype.listen; let calls = 0; http.Server.prototype.listen = function(...args) { if (++calls > 1) throw Error("LiteSpeed listener called twice"); return originalListen.apply(this, args); }; http.Server.prototype.address = () => null; require("./src/server.js"); console.log("REQUIRE_RETURNED");'], {
    env: { ...process.env, WORKER_TRANSPORT: "tcp", NODE_ENV: "production", PORT: "3141",
      APP_ORIGIN: "https://wa.example.com", DATABASE_DRIVER: "sqlite",
      DATA_DIR: dir, ADMIN_EMAIL: "admin@example.com",
      ADMIN_PASSWORD: "loader test password 12345",
      ENCRYPTION_KEY: randomBytes(32).toString("base64") },
  });
  const closed = once(child, "close");
  child.stdout.on("data", (data) => { logs += data; });
  child.stderr.on("data", (data) => { logs += data; });
  try {
    let ready = false;
    for (let i = 0; i < 100; i++) {
      if (child.exitCode !== null) break;
      try { ready = (await fetch("http://127.0.0.1:3141/health")).ok; } catch {}
      if (ready) break;
      await delay(100);
    }
    assert(ready, logs);
    assert.match(logs, /REQUIRE_RETURNED/);
    assert.doesNotMatch(logs, /ERR_REQUIRE_ASYNC_MODULE/);
    assert.equal((await fetch("http://127.0.0.1:3141/")).status, 200);
    follower = spawn(process.execPath, ["--input-type=commonjs", "-e",
      'require("./src/server.js")'], { env: { ...process.env,
        WORKER_TRANSPORT: "tcp", NODE_ENV: "production", PORT: "3142", APP_ORIGIN: "https://wa.example.com",
        DATABASE_DRIVER: "sqlite", DATA_DIR: dir, ADMIN_EMAIL: "admin@example.com",
        ADMIN_PASSWORD: "loader test password 12345",
        ENCRYPTION_KEY: randomBytes(32).toString("base64") } });
    followerClosed = once(follower, "close");
    let followerLogs = "";
    follower.stdout.on("data", d => { followerLogs += d; });
    follower.stderr.on("data", d => { followerLogs += d; });
    let followerReady = false;
    for (let i = 0; i < 100; i++) {
      try { followerReady = (await fetch("http://127.0.0.1:3142/health")).ok; } catch {}
      if (followerReady || follower.exitCode !== null) break;
      await delay(100);
    }
    assert(followerReady, followerLogs);
    assert.match(followerLogs, /shared SQLite worker/);
    const endpoint = JSON.parse(await readFile(dir + "/worker.json", "utf8"));
    assert.equal((await stat(dir + "/worker.json")).mode & 0o777, 0o600);
    assert.equal((await fetch("http://127.0.0.1:" + endpoint.port + "/health")).status, 403);
    const parallel = await Promise.all(Array.from({ length: 20 }, () =>
      fetch("http://127.0.0.1:3142/health")));
    assert(parallel.every(response => response.status === 200));
    const login = await fetch("http://127.0.0.1:3142/api/login", {
      method: "POST", headers: { Origin: "https://wa.example.com", "Content-Type": "application/json" },
      body: JSON.stringify({ email: "admin@example.com", password: "loader test password 12345" }),
    });
    assert.equal(login.status, 200);
    const cookie = login.headers.get("set-cookie").split(";")[0];
    const created = await fetch("http://127.0.0.1:3142/api/instances", {
      method: "POST", headers: { Origin: "https://wa.example.com", Cookie: cookie, "Content-Type": "application/json" },
      body: JSON.stringify({ name: "Shared worker test" }),
    });
    assert.equal(created.status, 201);
    const instance = await created.json();
    const list = await fetch("http://127.0.0.1:3141/api/instances", { headers: { Cookie: cookie } });
    assert.match(await list.text(), new RegExp(instance.id));
    follower.kill("SIGTERM");
    assert.equal((await followerClosed)[0], 0, followerLogs);
    child.kill("SIGTERM");
    const [code] = await closed;
    assert.equal(code, 0, logs);
  } finally {
    if (follower && follower.exitCode === null) { follower.kill("SIGKILL"); await followerClosed; }
    if (child.exitCode === null) { child.kill("SIGKILL"); await closed; }
    await rm(dir, { recursive: true, force: true });
  }
});
