import { DatabaseSync } from "node:sqlite";
import {
  mkdirSync,
  realpathSync,
  openSync,
  closeSync,
  chmodSync,
} from "node:fs";
import path from "node:path";
import lockfile from "proper-lockfile";
import { storageConfig, assertPrivateDirectory } from "./storage-config.js";
const columns = {
  user_id: "VARCHAR(191) NOT NULL DEFAULT ''",
  instance_id: "VARCHAR(191) NOT NULL DEFAULT ''",
  record_status: "VARCHAR(32) NOT NULL DEFAULT ''",
  created_at: "BIGINT NOT NULL DEFAULT 0",
  due_at: "BIGINT NOT NULL DEFAULT 0",
  lookup_key: "VARCHAR(254) NOT NULL DEFAULT ''",
  chat_id: "VARCHAR(191) NOT NULL DEFAULT ''",
  campaign_id: "VARCHAR(191) NOT NULL DEFAULT ''",
  metadata_version: "INT NOT NULL DEFAULT 0",
};
const indexes = {
  zelon_owner: ["namespace", "user_id", "created_at", "record_key"],
  zelon_instance: ["namespace", "instance_id", "created_at", "record_key"],
  zelon_due: ["namespace", "record_status", "due_at"],
  zelon_instance_due: ["namespace", "instance_id", "record_status", "due_at"],
  zelon_chat: [
    "namespace",
    "instance_id",
    "chat_id",
    "created_at",
    "record_key",
  ],
  zelon_campaign: ["namespace", "instance_id", "campaign_id", "record_status"],
  zelon_lookup: ["namespace", "lookup_key"],
};
const metadata = (v) => [
  v.userId || "",
  v.instanceId || "",
  v.status || "",
  Date.parse(v.createdAt || "") || 0,
  v.sendAt ?? v.nextAt ?? v.expires ?? 0,
  v.lookupKey ?? v.email?.toLowerCase() ?? v.waId ?? "",
  v.chatId || "",
  v.campaignId || "",
  2,
];
export async function openStore() {
  const config = storageConfig();
  let releaseFileLock;
  let db,
    pool,
    lease,
    leaseLost = false;
  const execute = async (sql, args = []) =>
    pool ? (await pool.query(sql, args))[0] : db.prepare(sql).all(...args);
  const mutate = async (sql, args = []) =>
    pool ? (await pool.query(sql, args))[0] : db.prepare(sql).run(...args);
  try {
    if (config.driver === "mysql") {
      const mysql = await import("mysql2/promise");
      pool = mysql.createPool({
        host: process.env.MYSQL_HOST,
        port: Number(process.env.MYSQL_PORT || 3306),
        user: process.env.MYSQL_USER,
        password: process.env.MYSQL_PASSWORD,
        database: process.env.MYSQL_DATABASE,
        connectionLimit: 10,
        charset: "utf8mb4",
        ...(process.env.MYSQL_SSL === "true"
          ? { ssl: { rejectUnauthorized: true } }
          : {}),
      });
      lease = await pool.getConnection();
      lease.on("error", () => {
        leaseLost = true;
      });
      const [locks] = await lease.query(
        "SELECT GET_LOCK(CONCAT('zelon:',LEFT(SHA2(DATABASE(),256),56)), 0) AS acquired",
      );
      if (!locks[0].acquired)
        throw Error(
          "Another Zelon server is using this database; run one process",
        );
      await pool.query(
        "CREATE TABLE IF NOT EXISTS zelon_records(namespace VARCHAR(64) NOT NULL,record_key VARCHAR(191) NOT NULL,payload LONGTEXT NOT NULL,PRIMARY KEY(namespace,record_key))",
      );
    } else {
      if (config.filename !== ":memory:") {
        const directory = path.dirname(path.resolve(config.filename));
        mkdirSync(directory, { recursive: true, mode: 0o700 });
        if (config.directory) {
          assertPrivateDirectory(realpathSync(directory));
          chmodSync(directory, 0o700);
        }
        closeSync(openSync(config.filename, "a", 0o600));
        if (config.directory)
          assertPrivateDirectory(path.dirname(realpathSync(config.filename)));
        chmodSync(config.filename, 0o600);
        try {
          releaseFileLock = await lockfile.lock(config.filename, {
            stale: 30000,
            update: 10000,
            retries: 0,
            onCompromised: () => {
              leaseLost = true;
            },
          });
        } catch (error) {
          if (error.code === "ELOCKED")
            throw Error(
              "Another Zelon server is using this SQLite database; run one process",
            );
          throw error;
        }
      }
      db = new DatabaseSync(config.filename);
      db.exec(
        "PRAGMA busy_timeout=5000; PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA foreign_keys=ON; CREATE TABLE IF NOT EXISTS zelon_records(namespace TEXT NOT NULL,record_key TEXT NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(namespace,record_key))",
      );
      if (config.directory)
        console.log("Zelon SQLite data directory:", config.directory);
    }
    const existing = pool
      ? await execute(
          "SELECT COLUMN_NAME AS name FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='zelon_records'",
        )
      : db.prepare("PRAGMA table_info(zelon_records)").all();
    for (const [name, definition] of Object.entries(columns))
      if (!existing.some((c) => c.name === name))
        await mutate(
          `ALTER TABLE zelon_records ADD COLUMN ${name} ${pool ? definition : definition.replace(/VARCHAR\(\d+\)/, "TEXT")}`,
        );
    const existingIndexes = pool
      ? await execute(
          "SELECT DISTINCT INDEX_NAME AS name FROM information_schema.STATISTICS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='zelon_records'",
        )
      : db.prepare("PRAGMA index_list(zelon_records)").all();
    for (const [name, cols] of Object.entries(indexes))
      if (!existingIndexes.some((i) => i.name === name))
        await mutate(
          `CREATE INDEX ${name} ON zelon_records(${cols.join(",")})`,
        );
    let rows;
    do {
      rows = await execute(
        "SELECT namespace,record_key,payload FROM zelon_records WHERE metadata_version<2 LIMIT 500",
      );
      for (const row of rows)
        await mutate(
          `UPDATE zelon_records SET ${Object.keys(columns)
            .map((c) => c + "=?")
            .join(",")} WHERE namespace=? AND record_key=?`,
          [...metadata(JSON.parse(row.payload)), row.namespace, row.record_key],
        );
    } while (rows.length);
  } catch (error) {
    if (lease) lease.release();
    if (pool) await pool.end();
    if (db) db.close();
    if (releaseFileLock) await releaseFileLock().catch(() => {});
    throw error;
  }
  function healthy() {
    if (leaseLost)
      throw Error(
        "Database worker lease lost; restart the server before processing requests",
      );
  }
  const colnames = [
    "namespace",
    "record_key",
    "payload",
    ...Object.keys(columns),
  ];
  const store = {
    storage: {
      driver: config.driver,
      ...(config.directory ? { directory: config.directory } : {}),
    },
    async get(ns, key) {
      healthy();
      const rows = await execute(
        "SELECT payload FROM zelon_records WHERE namespace=? AND record_key=?",
        [ns, key],
      );
      return rows[0] ? JSON.parse(rows[0].payload) : null;
    },
    async query(
      ns,
      {
        userId,
        instanceId,
        status,
        email,
        lookupKey,
        chatId,
        campaignId,
        limit = 100,
        before,
        beforeKey = "",
        dueBefore,
        ascending = false,
      } = {},
    ) {
      healthy();
      if (!Number.isInteger(limit) || limit < 1 || limit > 1000)
        throw Error("Query limit must be between 1 and 1000");
      const clauses = ["namespace=?"],
        args = [ns];
      for (const [column, value] of [
        ["user_id", userId],
        ["instance_id", instanceId],
        ["record_status", status],
        ["lookup_key", lookupKey ?? email?.toLowerCase()],
        ["chat_id", chatId],
        ["campaign_id", campaignId],
      ])
        if (value !== undefined) {
          clauses.push(column + "=?");
          args.push(value);
        }
      if (dueBefore !== undefined) {
        clauses.push("due_at<=?");
        args.push(dueBefore);
      }
      if (before !== undefined) {
        clauses.push("(created_at<? OR (created_at=? AND record_key<?))");
        args.push(before, before, beforeKey);
      }
      const order = ascending ? "ASC" : "DESC";
      return (
        await execute(
          `SELECT payload FROM zelon_records WHERE ${clauses.join(" AND ")} ORDER BY created_at ${order},record_key ${order} LIMIT ${limit}`,
          args,
        )
      ).map((r) => JSON.parse(r.payload));
    },
    async stats(ns, { userId, instanceId } = {}) {
      healthy();
      const clauses = ["namespace=?"],
        args = [ns];
      if (userId !== undefined) {
        clauses.push("user_id=?");
        args.push(userId);
      }
      if (instanceId !== undefined) {
        clauses.push("instance_id=?");
        args.push(instanceId);
      }
      return Object.fromEntries(
        (
          await execute(
            `SELECT record_status AS status,COUNT(*) AS total FROM zelon_records WHERE ${clauses.join(" AND ")} GROUP BY record_status`,
            args,
          )
        ).map((r) => [r.status, Number(r.total)]),
      );
    },
    async all(ns) {
      healthy();
      return (
        await execute("SELECT payload FROM zelon_records WHERE namespace=?", [
          ns,
        ])
      ).map((r) => JSON.parse(r.payload));
    },
    async set(ns, key, v) {
      healthy();
      const args = [ns, key, JSON.stringify(v), ...metadata(v)];
      const update = colnames
        .slice(2)
        .map((c) => `${c}=${pool ? "VALUES(" + c + ")" : "excluded." + c}`)
        .join(",");
      await mutate(
        `INSERT INTO zelon_records(${colnames.join(",")}) VALUES(${colnames.map(() => "?").join(",")}) ${pool ? "ON DUPLICATE KEY UPDATE" : "ON CONFLICT(namespace,record_key) DO UPDATE SET"} ${update}`,
        args,
      );
    },
    async insert(ns, key, v) {
      healthy();
      const args = [ns, key, JSON.stringify(v), ...metadata(v)];
      const result = await mutate(
        `INSERT ${pool ? "IGNORE " : ""}INTO zelon_records(${colnames.join(",")}) VALUES(${colnames.map(() => "?").join(",")}) ${pool ? "" : "ON CONFLICT(namespace,record_key) DO NOTHING"}`,
        args,
      );
      return pool ? result.affectedRows === 1 : result.changes === 1;
    },
    async patch(ns, key, changes) {
      healthy();
      let connection;
      try {
        if (pool) {
          connection = await pool.getConnection();
          await connection.beginTransaction();
        } else db.exec("BEGIN IMMEDIATE");
        const rows = connection
          ? (
              await connection.query(
                "SELECT payload FROM zelon_records WHERE namespace=? AND record_key=? FOR UPDATE",
                [ns, key],
              )
            )[0]
          : db
              .prepare(
                "SELECT payload FROM zelon_records WHERE namespace=? AND record_key=?",
              )
              .all(ns, key);
        if (!rows.length) {
          if (connection) await connection.commit();
          else db.exec("COMMIT");
          return null;
        }
        const previous = JSON.parse(rows[0].payload);
        const value =
          typeof changes === "function"
            ? changes(previous)
            : { ...previous, ...changes };
        const fields = ["payload", ...Object.keys(columns)],
          args = [JSON.stringify(value), ...metadata(value), ns, key];
        const sql = `UPDATE zelon_records SET ${fields.map((c) => c + "=?").join(",")} WHERE namespace=? AND record_key=?`;
        if (connection) {
          await connection.query(sql, args);
          await connection.commit();
        } else {
          db.prepare(sql).run(...args);
          db.exec("COMMIT");
        }
        return value;
      } catch (e) {
        if (connection) await connection.rollback();
        else db.exec("ROLLBACK");
        throw e;
      } finally {
        connection?.release();
      }
    },
    async transition(ns, key, expected, v) {
      healthy();
      const fields = ["payload", ...Object.keys(columns)];
      const result = await mutate(
        `UPDATE zelon_records SET ${fields.map((c) => c + "=?").join(",")} WHERE namespace=? AND record_key=? AND record_status=?`,
        [JSON.stringify(v), ...metadata(v), ns, key, expected],
      );
      return pool ? result.affectedRows === 1 : result.changes === 1;
    },
    async clearNamespace(ns) {
      healthy();
      await mutate("DELETE FROM zelon_records WHERE namespace=?", [ns]);
    },
    async delete(ns, key) {
      healthy();
      await mutate(
        "DELETE FROM zelon_records WHERE namespace=? AND record_key=?",
        [ns, key],
      );
    },
    async health() {
      healthy();
      if (pool) {
        const [rows] = await lease.query(
          "SELECT IS_USED_LOCK(CONCAT('zelon:',LEFT(SHA2(DATABASE(),256),56)))=CONNECTION_ID() AS held",
        );
        if (!rows[0].held) {
          leaseLost = true;
          throw Error("Database lease is not held");
        }
      } else {
        if (releaseFileLock && !(await lockfile.check(config.filename))) {
          leaseLost = true;
          throw Error("SQLite worker lease is not held");
        }
        db.prepare("SELECT 1").get();
      }
    },
    async close() {
      if (pool) {
        try {
          await lease.query(
            "SELECT RELEASE_LOCK(CONCAT('zelon:',LEFT(SHA2(DATABASE(),256),56)))",
          );
        } catch {}
        lease.release();
        await pool.end();
      } else {
        db.close();
        if (releaseFileLock) await releaseFileLock().catch(() => {});
      }
    },
  };
  return store;
}
