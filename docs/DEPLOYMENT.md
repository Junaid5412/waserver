# Deploy Zelon API on Hostinger

The user will deploy this project. No Hostinger deployment was performed during this update.

## Requirements

Use a Node.js Web App plan that supports a long-lived server and outbound WhatsApp WebSocket connections. Create a dedicated persistent MySQL database/user and keep its credentials separate from GitHub. Baileys also needs external HTTPS/DNS access. Ordinary static/PHP hosting alone cannot run this app.

Hostinger's Node.js onboarding supports connecting a GitHub repository and configuring build/start settings and environment variables. Give its GitHub integration access to the private `Junaid-Bharwana/zelon-api` repository. Official references:

- [Add a Node.js web app](https://www.hostinger.com/support/how-to-deploy-a-nodejs-website-in-hostinger/)
- [Environment variables](https://www.hostinger.com/support/how-to-add-environment-variables-during-node-js-application-deployment/)
- [Redeploy an application](https://www.hostinger.com/support/how-to-redeploy-a-node-js-application/)

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

Hostinger field names can vary. Do not configure this as a static Vite build. Let the platform supply PORT if it does; the server binds 0.0.0.0. Run exactly one process/replica per database, with no overlapping old/new workers. The MySQL worker lease intentionally rejects a second process.

## Environment

| Variable                                     | Required value                                                                              |
| -------------------------------------------- | ------------------------------------------------------------------------------------------- |
| NODE_ENV                                     | `production`                                                                                |
| APP_ORIGIN                                   | Exact final HTTPS origin, e.g. `https://api.your-domain.com`, with no path                  |
| ENCRYPTION_KEY                               | Stable random 32-byte key in base64                                                         |
| MYSQL_HOST / MYSQL_PORT                      | Your database hostname and port, usually 3306                                               |
| MYSQL_DATABASE / MYSQL_USER / MYSQL_PASSWORD | Dedicated database and user credentials                                                     |
| MYSQL_SSL                                    | `true` for public TLS-enabled MySQL with a trusted CA; `false` on a trusted private network |
| ADMIN_EMAIL                                  | First administrator's email                                                                 |
| ADMIN_PASSWORD                               | Strong 12+ character initial password                                                       |
| TRUST_PROXY                                  | Correct trusted reverse-proxy hop count; 1 only for one trusted proxy                       |
| MAX_MEDIA_MB                                 | Optional; default 100, maximum 256                                                          |

Generate ENCRYPTION_KEY locally with `node -e "console.log(require('crypto').randomBytes(32).toString('base64'))"`. Never place real secrets in `.env.example` or GitHub. Admin bootstrap happens only when the users table is empty. Remove ADMIN_PASSWORD from hosting configuration after successful bootstrap; changing it later will not reset an existing account.

Use a MySQL user with access to this dedicated database, including CREATE/ALTER/INDEX for startup migrations. Existing records are migrated automatically. Take a backup before updates. The largest upload database record is approximately 1 MB; ensure `max_allowed_packet` is at least 4 MiB. Provide appropriate disk capacity for encrypted media and backups.

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

Optional Docker Compose supplies MySQL 8.4 and the application. It is included for VPS/local use and has not been run in this environment. Set `.env` with a dedicated MYSQL_DATABASE, MYSQL_USER, MYSQL_PASSWORD, MYSQL_ROOT_PASSWORD, ENCRYPTION_KEY and admin credentials first. For local testing only, set NODE_ENV=development, APP_ORIGIN=http://localhost:3000 and TRUST_PROXY=0. For production, use HTTPS at a trusted reverse proxy and NODE_ENV=production.

```sh
docker compose up -d --build
# Stop only the application to release its MySQL worker lease:
docker compose stop app
docker compose run --rm --no-deps app node --test test/mysql.test.js
docker compose up -d app
```

Compose stores MySQL in a named volume. `docker compose down -v` destroys that data. Do not use it on production data. The MySQL test uses isolated record namespaces, but still use a dedicated test database and never share it with an active server.

## Operations and troubleshooting

- **Production requires MYSQL_HOST:** provide MySQL runtime environment variables; SQLite is not allowed for production.
- **Another Zelon server is using this database:** stop the previous process/replica before starting the replacement.
- **Incorrect email/password after env change:** bootstrap variables don't reset existing users; another administrator can reset a user password in the console.
- **Request origin is not allowed:** correct APP_ORIGIN and redeploy; use the final domain consistently.
- **Connect this WhatsApp instance first:** link/reconnect the number. The offline queue remains persistent.
- **QR disappears or number logs out:** inspect WhatsApp Linked devices and connection logs. Provider-side session revocations require relinking.
- **Webhook failure:** verify public HTTPS, certificate, port 443 and receiver response. Private network destinations/redirects are intentionally blocked.
- **Unknown send:** delivery may already have occurred; investigate before sending again with a new idempotency key.

Back up MySQL and the encryption key separately, test restores, monitor system health/database size and apply an explicit data-retention policy. Do not rotate ENCRYPTION_KEY without an encrypted-data migration. Zelon has no horizontal scaling or background billing service.
