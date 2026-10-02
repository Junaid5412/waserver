# Private local storage

Zelon supports SQLite in production without an external database. It uses a structured SQLite database, not an unprotected JSON file. All existing accounts, sessions, messages, media chunks and encrypted WhatsApp credentials use this same database.

## Hostinger setup

1. Set `DATABASE_DRIVER=sqlite` in the Web App environment variables. This explicitly overrides leftover MYSQL\_\* values.
2. Keep the existing APP_ORIGIN, ENCRYPTION_KEY and administrator settings. Do not generate a replacement encryption key when you already have stored encrypted records.
3. On Hostinger's documented domain filesystem layout, the app automatically selects:

   `/home/YOUR_USERNAME/domains/YOUR_DOMAIN/zelon-data/zelon.sqlite`

   It creates the private folder automatically when filesystem permissions allow. The app logs the selected directory at startup; administrator System health also shows the storage driver/path.

4. If auto detection is unavailable, set `DATA_DIR` to the real absolute private persistent directory. For example `/srv/zelon-data` on a VPS with a persistent disk. Example paths are not literal values for your hosting account.
5. Redeploy, confirm `/health`, create a test instance, then redeploy once more and confirm the same instance remains. Also verify the database appears in the intended private directory in File Manager.

`zelon-data` must sit outside `public_html` and the whole `hbuilds` directory. Putting it just outside `public` inside a build is insufficient. Production also rejects paths inside the application root or `public`, `build`, `dist`, `node_modules`. Symlinks into these paths are rejected.

Hostinger says managed deployment folders are overwritten. A sibling data directory is an implementation choice based on its documented layout, not a verified promise that this account's runtime has permanent local storage. If Hostinger cannot expose that directory to Node or clears it, code cannot make an ephemeral disk persistent; use a supported persistent volume or an external database.

## SQLite behavior

- Private directories use mode 0700; the database file uses 0600. Deployment code does not include user data.
- WAL mode, full synchronous commits and a 5-second busy timeout are enabled.
- One database/WhatsApp worker per database. Additional LiteSpeed HTTP processes forward streamed requests to the lease owner through an authenticated loopback endpoint. Endpoint credentials stay in private `worker.json` (0600). The atomic heartbeat file lock still prevents duplicate messaging workers. A lost/compromised lock stops database operations.
- A crashed process's lock can remain briefly; allow about 30 seconds before restarting. Do not delete a lock directory while another process is alive.
- SQLite requires local filesystem locking; do not place this database on an incompatible network filesystem.
- An inaccessible directory, missing persistent path or permission failure prevents startup and is reported in runtime logs. The app does not silently fall back to a disposable database.

## Backups and switching databases

Preserve the database and ENCRYPTION_KEY separately. For a manual file backup, stop the app cleanly and copy `zelon.sqlite`; if the app is still running, copying only that file can miss committed WAL data. Use SQLite's online backup facility for live backups. Copying the main file and WAL separately during writes is also not a consistent backup.

Switching DATABASE_DRIVER from MySQL to SQLite selects a different database; it does not migrate existing data. An empty database bootstraps a fresh administrator using ADMIN_EMAIL/ADMIN_PASSWORD. Keep the old database intact until any migration has been separately completed and verified. Changing DATA_DIR similarly selects a different SQLite file; do not treat an empty console as evidence records were safely moved.

On a VPS/Docker deployment, mount the private data directory as a persistent host volume and set DATA_DIR to the mounted container path. The included MySQL Compose definition remains a MySQL alternative. Hostinger-managed runtime access/persistence must be checked on the actual account.
