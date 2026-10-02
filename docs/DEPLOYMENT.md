# Deploy Zelon API on Hostinger

The user will deploy this project. No Hostinger deployment was performed during this update.

## Requirements

Use a Node.js Web App plan that supports a long-lived server and outbound WhatsApp WebSocket connections. The default SQLite mode does not require creating an external database. Configure private storage as described below. MySQL remains optional. Baileys also needs external HTTPS/DNS access. Ordinary static/PHP hosting alone cannot run this app.

Hostinger's Node.js onboarding supports connecting a GitHub repository and configuring build/start settings and environment variables. Give its GitHub integration access to the private `Junaid-Bharwana/zelon-api` repository. Official references:

- [Add a Node.js web app](https://www.hostinger.com/support/how-to-deploy-a-nodejs-website-in-hostinger/)
- [Environment variables](https://www.hostinger.com/support/how-to-add-environment-variables-during-node-js-application-deployment/)
- [Redeploy an application](https://www.hostinger.com/support/how-to-redeploy-a-node-js-application/)

## Local file storage (recommended for this setup)

Set `DATABASE_DRIVER=sqlite`. On the documented Hostinger paths `/home/USERNAME/domains/DOMAIN/hbuilds/.../nodejs` or `/home/USERNAME/domains/DOMAIN/nodejs`, the app automatically creates `/home/USERNAME/domains/DOMAIN/zelon-data/zelon.sqlite`. This folder is a sibling of `hbuilds` and `public_html`, not part of a deployment.

If the runtime uses a different path, set `DATA_DIR` to your actual absolute private persistent directory. Do not enter the example username/domain literally. Use File Manager to confirm the full path and runtime logs to check the selected directory. The server rejects production data inside the app, `public_html`, `hbuilds`, `public`, `build` or `dist`. Existing MYSQL\_\* variables are ignored when DATABASE_DRIVER=sqlite.

Keep APP_ORIGIN, ENCRYPTION_KEY, ADMIN_EMAIL and ADMIN_PASSWORD. Importing a file with blank DATA_DIR into an existing configuration may leave an older value in some panels; remove any stale DATA_DIR value or replace it with the actual desired path.

Hostinger documents deployment folders as overwritten. Its public guide does not establish a persistence guarantee for every custom folder or confirm your runtime can write there. After the first successful start, create a test instance, redeploy, and verify it survives. If the private folder is inaccessible or resets, set DATA_DIR to a supported persistent mount or use MySQL. See [storage operations](STORAGE.md).

## Build settings

| Setting          | Value                                 |
| ---------------- | ------------------------------------- |
| Repository       | `Junaid-Bharwana/zelon-api` (private) |
| Branch           | `main`                                |
| Framework        | Express / Node.js                     |
| Root             | `/`                                   |
| Node             | 22.13+; use 24 if available           |
| Package manager  | npm                                   |
| Build            | `npm run build`                       |
| Start            | `npm start`                           |
| Entry            | `src/server.js`                       |
| Output directory | None; Express serves `public` itself  |

Hostinger field names can vary. Do not configure this as a static Vite build. Let the platform supply PORT if it does; the server binds 0.0.0.0. SQLite supports multiple LiteSpeed HTTP processes on the same machine: one owns the database and WhatsApp worker lease, and the others stream requests to its authenticated loopback endpoint. MySQL still requires exactly one process/replica.

## Environment

| Variable                                     | Required value                                                                                    |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| NODE_ENV                                     | `production`                                                                                      |
| APP_ORIGIN                                   | Exact final HTTPS origin, e.g. `https://api.your-domain.com`, with no path                        |
| ENCRYPTION_KEY                               | Stable random 32-byte key in base64                                                               |
| DATABASE_DRIVER                              | `sqlite` for file storage; `mysql` for optional external database                                 |
| DATA_DIR                                     | Optional on recognized Hostinger layout; otherwise the real absolute private persistent directory |
| MYSQL_HOST / MYSQL_PORT                      | Optional MySQL mode only: your database hostname and port, usually 3306                           |
| MYSQL_DATABASE / MYSQL_USER / MYSQL_PASSWORD | Optional MySQL mode only: dedicated database and user credentials                                 |
| MYSQL_SSL                                    | `true` for public TLS-enabled MySQL with a trusted CA; `false` on a trusted private network       |
| ADMIN_EMAIL                                  | First administrator's email                                                                       |
| ADMIN_PASSWORD                               | Strong 12+ character initial password                                                             |
| TRUST_PROXY                                  | Correct trusted reverse-proxy hop count; 1 only for one trusted proxy                             |
| MAX_MEDIA_MB                                 | Optional; default 100, maximum 256                                                                |

Generate ENCRYPTION_KEY locally with `node -e "console.log(require('crypto').randomBytes(32).toString('base64'))"`. Never place real secrets in `.env.example` or GitHub. Admin bootstrap happens only when the users table is empty. Remove ADMIN_PASSWORD from hosting configuration after successful bootstrap; changing it later will not reset an existing account.

For optional MySQL mode, use a MySQL user with access to this dedicated database, including CREATE/ALTER/INDEX for startup migrations. Existing records are migrated automatically. Take a backup before updates. The largest upload database record is approximately 1 MB; ensure `max_allowed_packet` is at least 4 MiB. Provide appropriate disk capacity for encrypted media and backups.

Configure the custom domain and HTTPS before setting the final APP_ORIGIN. If the temporary domain differs, login requests from it will fail origin validation until APP_ORIGIN is updated and the app redeployed. Domain changes require a new login.

## First run

1. Deploy. Inspect build and runtime logs for `Zelon API listening`.
2. Open `/health`; expect `{ "status": "ok" }`.
3. Open `/console` and sign in with the bootstrap administrator.
4. Create an instance, click Connect number, scan the QR from WhatsApp → Linked devices. Alternatively request a pairing code in Profile & settings.
5. Generate and securely save the instance API key. Test your own/consenting recipient using the console or SDK.
6. Configure a public HTTPS webhook and verify signatures in your receiver before accepting events.

The Web App plan's support for persistent WhatsApp connections has not been verified on this account. If it suspends the process or blocks outbound WebSockets, use a Node-capable VPS. Connecting a real number is an explicit deployment acceptance step; implementation tests do not emulate the WhatsApp network.

## Acceptance checks

- Login, create a regular user, verify they cannot see administrator instances; disable the user and verify existing access is rejected.
- Link your WhatsApp number; send text and supported image/audio/document formats to consenting recipients. Confirm sent/delivered/read when available.
- Receive a reply and check inbox, unread count, quote reply and signed webhook. Verify a duplicate incoming sync does not duplicate inbox entries.
- Upload a file larger than 512 KiB; download it and compare its SHA-256. Check uploads after redeploy.
- Create a small campaign with an opted-out contact; verify skip, pause/resume and cancellation. Test STOP and an auto reply cooldown using your own test recipients.
- Test group settings only in a group where you have administrator permission; test statuses with a selected audience.
- Redeploy once; verify account data, connection credentials and inbox history persist with the same database/key.
- Check desktop and narrow/mobile layouts and keyboard navigation in your browser.
- Run the real MySQL integration test against a **separate empty test database**; it must not use the live application's database.

## MySQL test / optional Docker workflow

```sh
# From a configured shell with MYSQL_* set for a dedicated test database:
node --test test/mysql.test.js
```

Optional Docker Compose supplies MySQL 8.4 and the application. Set DATABASE_DRIVER=mysql for this Compose workflow. It is included for VPS/local use and has not been run in this environment. Set `.env` with a dedicated MYSQL_DATABASE, MYSQL_USER, MYSQL_PASSWORD, MYSQL_ROOT_PASSWORD, ENCRYPTION_KEY and admin credentials first. For local testing only, set NODE_ENV=development, APP_ORIGIN=http://localhost:3000 and TRUST_PROXY=0. For production, use HTTPS at a trusted reverse proxy and NODE_ENV=production.

```sh
docker compose up -d --build
# Stop only the application to release its MySQL worker lease:
docker compose stop app
docker compose run --rm --no-deps app node --test test/mysql.test.js
docker compose up -d app
```

Compose stores MySQL in a named volume. `docker compose down -v` destroys that data. Do not use it on production data. The MySQL test uses isolated record namespaces, but still use a dedicated test database and never share it with an active server.

## Operations and troubleshooting

- **Set DATA_DIR:** runtime path was not recognized; provide an absolute private persistent storage path. For mysql mode, MYSQL_HOST is required.
- **Another Zelon server is using this database:** MySQL requires one worker. SQLite entries automatically share the active worker. When upgrading from the older exclusive-process build, stop the Web App completely before redeploy/start so the old worker cannot keep its lease. Allow 30 seconds after a forced stop for the heartbeat lock to expire; do not delete database or lock files while a worker is alive.
- **Incorrect email/password after env change:** bootstrap variables don't reset existing users; another administrator can reset a user password in the console.
- **Request origin is not allowed:** correct APP_ORIGIN and redeploy; use the final domain consistently.
- **Connect this WhatsApp instance first:** link/reconnect the number. The offline queue remains persistent.
- **QR disappears or number logs out:** inspect WhatsApp Linked devices and connection logs. Provider-side session revocations require relinking.
- **Webhook failure:** verify public HTTPS, certificate, port 443 and receiver response. Private network destinations/redirects are intentionally blocked.
- **Unknown send:** delivery may already have occurred; investigate before sending again with a new idempotency key.

Back up your SQLite/MySQL database and the encryption key separately, test restores, monitor system health/database size and apply an explicit data-retention policy. Do not rotate ENCRYPTION_KEY without an encrypted-data migration. Zelon has no horizontal scaling or background billing service.

### LiteSpeed startup compatibility

Keep the entry file set to `src/server.js`. This synchronous bootstrap loads
`src/application.js` through dynamic import, allowing LiteSpeed's CommonJS
`require()` loader to start the ESM application with asynchronous initialization.
Do not set the entry to `src/application.js`. No environment change is needed
for `ERR_REQUIRE_ASYNC_MODULE`; redeploy the updated code.
