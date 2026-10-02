import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { randomBytes } from "node:crypto";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { setTimeout as delay } from "node:timers/promises";

test("LiteSpeed CommonJS require starts the production ESM application", async () => {
  const dir = await mkdtemp(tmpdir() + "/zelon-loader-");
  let logs = "";
  const child = spawn(process.execPath, ["--input-type=commonjs", "-e",
    'require("./src/server.js"); console.log("REQUIRE_RETURNED");'], {
    env: { ...process.env, NODE_ENV: "production", PORT: "3141",
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
    child.kill("SIGTERM");
    const [code] = await closed;
    assert.equal(code, 0, logs);
  } finally {
    if (child.exitCode === null) { child.kill("SIGKILL"); await closed; }
    await rm(dir, { recursive: true, force: true });
  }
});
