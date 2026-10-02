import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, rm, stat, mkdir, symlink } from "node:fs/promises";
import { tmpdir } from "node:os";
import { spawnSync } from "node:child_process";
import {
  storageConfig,
  assertPrivateDirectory,
} from "../src/storage-config.js";
import { openStore } from "../src/store.js";
const storeUrl = new URL("../src/store.js", import.meta.url).href;
test("Production SQLite detects Hostinger domain data folder and rejects managed deployment paths", () => {
  const appRoot = "/home/u123/domains/api.example/hbuilds/versions/42/nodejs";
  assert.equal(
    storageConfig(
      { NODE_ENV: "production", DATABASE_DRIVER: "sqlite" },
      { appRoot },
    ).filename,
    "/home/u123/domains/api.example/zelon-data/zelon.sqlite",
  );
  assert.equal(
    storageConfig(
      {
        NODE_ENV: "production",
        DATABASE_DRIVER: "sqlite",
        MYSQL_HOST: "unused",
        DATA_DIR: "/srv/zelon-data",
      },
      { appRoot },
    ).driver,
    "sqlite",
  );
  for (const directory of [
    "/home/u123/domains/api.example/hbuilds/data",
    "/home/u123/domains/api.example/public_html/data",
    appRoot + "/data",
    "/srv/public/data",
  ])
    assert.throws(() => assertPrivateDirectory(directory, { appRoot }));
  assert.throws(
    () => storageConfig({ NODE_ENV: "production" }, { appRoot: "/app/zelon" }),
    /Set DATA_DIR/,
  );
  assert.throws(
    () =>
      storageConfig(
        { NODE_ENV: "production", DATA_DIR: "../data" },
        { appRoot },
      ),
    /absolute/,
  );
  assert.throws(
    () => storageConfig({ DATABASE_DRIVER: "bad" }),
    /DATABASE_DRIVER/,
  );
});
test("Production SQLite preserves records across processes/build working directories and rejects a second worker", async (t) => {
  const root = await mkdtemp(tmpdir() + "/zelon-persistent-"),
    data = root + "/private-data",
    buildA = root + "/release-a",
    buildB = root + "/release-b";
  await mkdir(buildA);
  await mkdir(buildB);
  t.after(() => rm(root, { recursive: true, force: true }));
  const env = {
    ...process.env,
    NODE_ENV: "production",
    DATABASE_DRIVER: "sqlite",
    DATA_DIR: data,
  };
  delete env.SQLITE_PATH;
  const first = spawnSync(
    process.execPath,
    [
      "--input-type=module",
      "-e",
      `import {openStore} from ${JSON.stringify(storeUrl)};const s=await openStore();await s.set('auth:example','creds',{data:'encrypted-session'});await s.set('media','upload',{id:'upload',status:'ready'});await s.close();`,
    ],
    { env, cwd: buildA, encoding: "utf8" },
  );
  assert.equal(first.status, 0, first.stderr);
  const second = spawnSync(
    process.execPath,
    [
      "--input-type=module",
      "-e",
      `import assert from 'node:assert/strict';import {openStore} from ${JSON.stringify(storeUrl)};const s=await openStore();assert.equal((await s.get('auth:example','creds')).data,'encrypted-session');assert.equal((await s.get('media','upload')).status,'ready');await assert.rejects(openStore(),/Another Zelon server/);await s.health();await s.close();`,
    ],
    { env, cwd: buildB, encoding: "utf8" },
  );
  assert.equal(second.status, 0, second.stderr);
  assert.equal((await stat(data)).mode & 0o777, 0o700);
  assert.equal((await stat(data + "/zelon.sqlite")).mode & 0o777, 0o600);
});
test("Production SQLite rejects a private path symlinked into publicly served storage", async (t) => {
  const root = await mkdtemp(tmpdir() + "/zelon-symlink-");
  t.after(() => rm(root, { recursive: true, force: true }));
  await mkdir(root + "/public");
  await symlink(root + "/public", root + "/private-link");
  const env = {
    ...process.env,
    NODE_ENV: "production",
    DATABASE_DRIVER: "sqlite",
    DATA_DIR: root + "/private-link",
  };
  const child = spawnSync(
    process.execPath,
    [
      "--input-type=module",
      "-e",
      `import {openStore} from ${JSON.stringify(storeUrl)};await openStore();`,
    ],
    { env, encoding: "utf8" },
  );
  assert.notEqual(child.status, 0);
  assert.match(child.stderr, /DATA_DIR cannot be inside/);
});
