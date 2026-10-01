import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { randomBytes } from "node:crypto";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { setTimeout as delay } from "node:timers/promises";
test("API authentication, origin protection, instance persistence and scoped keys", async () => {
  const dir = await mkdtemp(tmpdir() + "/zelon-api-");
  const origin = "http://localhost:3139";
  const env = {
    ...process.env,
    NODE_ENV: "test",
    PORT: "3139",
    APP_ORIGIN: origin,
    ADMIN_EMAIL: "admin@example.com",
    ADMIN_PASSWORD: "test password 12345",
    ENCRYPTION_KEY: randomBytes(32).toString("base64"),
    SQLITE_PATH: dir + "/test.sqlite",
  };
  let logs = "";
  const child = spawn(process.execPath, ["src/server.js"], { env });
  child.stderr.on("data", (d) => (logs += d));
  child.stdout.on("data", (d) => (logs += d));
  try {
    let ready = false;
    for (let i = 0; i < 60; i++) {
      try {
        if ((await fetch(origin + "/health")).ok) {
          ready = true;
          break;
        }
      } catch {}
      if (child.exitCode !== null) break;
      await delay(100);
    }
    assert(ready, logs);
    let cookie = "";
    async function call(url, method = "GET", body, headers = {}) {
      return fetch(origin + url, {
        method,
        headers: {
          Origin: origin,
          "Content-Type": "application/json",
          Cookie: cookie,
          ...headers,
        },
        body: body ? JSON.stringify(body) : undefined,
      });
    }
    assert.equal((await call("/api/instances")).status, 401);
    assert.equal(
      (
        await call("/api/login", "POST", {
          email: "admin@example.com",
          password: "bad",
        })
      ).status,
      401,
    );
    assert.equal(
      (
        await call(
          "/api/login",
          "POST",
          { email: "admin@example.com", password: "test password 12345" },
          { Origin: "https://evil.example" },
        )
      ).status,
      403,
    );
    const login = await call("/api/login", "POST", {
      email: "admin@example.com",
      password: "test password 12345",
    });
    assert.equal(login.status, 200);
    cookie = login.headers.get("set-cookie").split(";")[0];
    const create = await call("/api/instances", "POST", { name: "Operations" });
    assert.equal(create.status, 201);
    const { id } = await create.json();
    const key = await (
      await call("/api/instances/" + id + "/key", "POST", {})
    ).json();
    assert.equal(
      (
        await call("/api/instances/" + id + "/messages", "GET", undefined, {
          Authorization: "Bearer " + key.key,
        })
      ).status,
      200,
    );
    assert.equal(
      (
        await call("/api/instances", "GET", undefined, {
          Authorization: "Bearer " + key.key,
        })
      ).status,
      403,
    );
    assert.equal(
      (
        await call("/api/instances/not-owned/events", "GET", undefined, {
          Authorization: "Bearer " + key.key,
        })
      ).status,
      404,
    );
    assert.equal(
      (
        await call("/api/instances/" + id + "/messages", "POST", {
          to: "+97450014037",
          text: "Hello",
        })
      ).status,
      409,
    );
    assert.equal(
      (
        await call("/api/instances/" + id + "/messages", "POST", {
          to: "bad",
          text: "Hello",
        })
      ).status,
      400,
    );
    const rows = await (await call("/api/instances")).json();
    assert.equal(rows[0].name, "Operations");
    assert.equal(rows[0].webhookSecret, undefined);
    assert.equal(
      (
        await call(
          "/api/instances",
          "POST",
          { name: "Bad origin" },
          { Origin: "https://evil.example", Authorization: "invalid" },
        )
      ).status,
      403,
    );
    assert.equal(
      (await call("/api/instances/" + id + "/messages?limit=1000")).status,
      400,
    );
    const oldKey = key.key;
    await call("/api/instances/" + id + "/key", "POST", {});
    assert.equal(
      (
        await call("/api/instances/" + id + "/messages", "GET", undefined, {
          Authorization: "Bearer " + oldKey,
        })
      ).status,
      401,
    );
    const createdUser = await call("/api/admin/users", "POST", {
      email: "member@example.com",
      role: "user",
    });
    assert.equal(createdUser.status, 201);
    const account = await createdUser.json();
    const duplicateUser = await call("/api/admin/users", "POST", {
      email: "MEMBER@example.com",
      role: "user",
    });
    assert.equal(duplicateUser.status, 409);
    const adminCookie = cookie;
    const memberLogin = await call("/api/login", "POST", {
      email: account.email,
      password: account.password,
    });
    assert.equal(memberLogin.status, 200);
    cookie = memberLogin.headers.get("set-cookie").split(";")[0];
    assert.equal((await call("/api/admin/users")).status, 403);
    assert.equal((await call("/api/instances/" + id + "/events")).status, 404);
    assert.deepEqual(await (await call("/api/instances")).json(), []);
    const memberCreate = await call("/api/instances", "POST", {
      name: "Member number",
    });
    assert.equal(memberCreate.status, 201);
    const memberCookie = cookie;
    cookie = adminCookie;
    await call("/api/admin/users/" + account.id, "PUT", { disabled: true });
    cookie = memberCookie;
    assert.equal((await call("/api/me")).status, 401);
    assert.equal(
      (
        await call("/api/login", "POST", {
          email: account.email,
          password: account.password,
        })
      ).status,
      401,
    );
    cookie = adminCookie;
    assert.equal(
      (
        await call("/api/account/password", "PUT", {
          currentPassword: "wrong",
          newPassword: "a strong new password",
        })
      ).status,
      403,
    );
    assert.equal(
      (
        await call("/api/account/password", "PUT", {
          currentPassword: "test password 12345",
          newPassword: "a strong new password",
        })
      ).status,
      200,
    );
    assert.equal((await call("/api/me")).status, 401);
    const relogin = await call("/api/login", "POST", {
      email: "admin@example.com",
      password: "a strong new password",
    });
    assert.equal(relogin.status, 200);
    cookie = relogin.headers.get("set-cookie").split(";")[0];
    await call("/api/logout", "POST", {});
    assert.equal((await call("/api/me")).status, 401);
  } finally {
    child.kill("SIGTERM");
    await new Promise((resolve) => child.once("exit", resolve));
    await rm(dir, { recursive: true, force: true });
  }
});
