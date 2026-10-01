# Zelon API

A private, self-hosted WhatsApp integration application. Responsive marketing website and authenticated developer console, with persistent MySQL storage, encrypted WhatsApp authentication, instance-scoped API keys, message queue, scheduling, media messages, polls, contacts, locations, groups, events and signed webhook delivery.

## Status

Implementation release 0.2.0. **Not yet deployed or verified against a live WhatsApp account.** Automated checks cover authentication, instance authorization, API-key scoping, origin protection, encryption, unsafe webhook targets and local database persistence. Real WhatsApp linking, messaging, Hostinger runtime support and visual mobile/browser QA must be verified before production use. A dedicated CI job is configured to exercise MySQL integration; it has not run yet. Local tests include interface DOM flows, but the cloud browser could not reach the internal preview. This is not a full GREEN-API clone. Status publishing, AI products, large media uploads, SDK packages, bulk campaigns, chat synchronization and billing are not implemented.

Uses Baileys, an unofficial WhatsApp Web integration, not Meta's official WhatsApp Business Platform. No guarantee of unlimited usage or uninterrupted WhatsApp connectivity. No Zelon plan limits; infrastructural and WhatsApp limits still apply.

## Hostinger deployment

1. In Hostinger Websites, add a Node.js Web App and select this private repository, branch `main`.
2. Select Node.js 22.13+ (24 recommended), package manager npm, root `/`, build command `npm run build`, start command `npm start`, entry file `src/server.js`. This is an Express server; there is no `dist` output folder.
3. Create a dedicated persistent MySQL database and user. The app creates its own table. Configure `MYSQL_HOST`, `MYSQL_PORT`, `MYSQL_DATABASE`, `MYSQL_USER`, `MYSQL_PASSWORD` using Hostinger environment variables.
4. Set `NODE_ENV=production`, `APP_ORIGIN` to the exact HTTPS application origin, and `ENCRYPTION_KEY` to a stable base64-encoded 32-byte random key. Generate locally with `node -e "console.log(require('crypto').randomBytes(32).toString('base64'))"`.
5. Set `ADMIN_EMAIL` and a strong `ADMIN_PASSWORD` (12+ characters). These bootstrap the first account only. Never commit secrets. Remove the bootstrap password from deployment configuration after the account is created.
6. Set `TRUST_PROXY=1` only if one trusted reverse proxy fronts the app. Restrict direct access appropriately; incorrect proxy trust can weaken rate limiting.
7. Deploy, open `/health`, then `/console`. Create an instance and scan its QR code from your own WhatsApp phone. Verify actual sending, incoming events and webhook signatures.

The deployment requires persistent outbound WhatsApp WebSocket connectivity and a long-lived server process. If the Web App plan suspends the process or blocks this connection, a VPS worker is needed; this has not been verified on the user's account.

## Persistence and operations

Production refuses to start without MySQL and an encryption key. SQLite is strictly a development fallback. Keep the **same database and ENCRYPTION_KEY** across redeploys. Back up the database and encryption key separately; losing the key makes encrypted messages and WhatsApp credentials unrecoverable.

Run **one process per database**. If the connection holding the worker lease is lost, processing stops rather than silently allowing two workers. A dedicated MySQL advisory lock prevents a second process from starting concurrently. There is no horizontal scaling design in this release. MySQL must use a trusted/private network, or set `MYSQL_SSL=true` for a public TLS-enabled database using a trusted certificate authority.

Messages interrupted while sending become `unknown` on restart instead of being automatically resent. Investigate before manually retrying. Scheduled messages wait while disconnected. Media is capped at 500 KB; requests are capped at 1 MB. Webhook delivery retries up to eight times, does not follow redirects, and resolves/pins public IPv4 destinations to reduce SSRF exposure. Verify HMAC SHA-256 signatures against the raw request bytes and deduplicate event IDs.

Data is retained indefinitely in this release; arrange periodic archival/retention for production. The record table includes indexed user, instance, status, due-time and creation-time columns. Message/event reads use cursor pagination instead of loading entire histories. Worker scans select bounded due-job batches. Existing records are backfilled during schema migration.

## Local development

Copy `.env.example` values into your shell or use `node --env-file=.env src/server.js`. Set `NODE_ENV=development`, `APP_ORIGIN=http://localhost:3000`, ADMIN_EMAIL, ADMIN_PASSWORD and ENCRYPTION_KEY. Omit MYSQL_HOST for local SQLite. Run `npm ci`, `npm test`, `npm run build`, `npm start`.

## Accounts and reliability

Administrators create user accounts from the console using the + button and a popup. Initial passwords are generated and shown once. Each user sees only their own instances. Disable an account to revoke both session and API access. Users can change their own passwords; that revokes their existing sessions.

Send an `Idempotency-Key` header (8–200 characters) on every message creation request. Replaying the same key and content returns the original job; reusing a key for different content returns 409. Keys are scoped to an instance. Without this header, each POST creates a new message. Queue claim and cancellation transitions are atomic.

`POST /api/instances/:id/messages/:messageId/cancel` cancels a queued message; messages already sending cannot be cancelled. History endpoints accept `limit` (1–100), and `before` (ISO creation time) together with `beforeId` (last record ID) to retrieve the next page.

GitHub CI has separate application and real MySQL 8.4 tests, covering database persistence, indexes, worker exclusivity, atomic state transitions and pagination. A skipped local MySQL test is not a successful MySQL verification.

## API

All API key requests use `Authorization: Bearer KEY`. Each key is tied to one instance. Console-only operations require a secure session cookie and matching request origin. Keys are stored hashed and only shown once. WhatsApp authentication state, message payloads, events and webhook secrets are encrypted with AES-256-GCM.

| Method | Endpoint                                      | Purpose                           |
| ------ | --------------------------------------------- | --------------------------------- |
| POST   | /api/instances/:id/messages                   | Queue a message                   |
| GET    | /api/instances/:id/messages                   | Latest 100 outgoing records       |
| GET    | /api/instances/:id/events                     | Latest 100 events                 |
| POST   | /api/instances/:id/check-number               | Check `{ "phone": "+974…" }`      |
| GET    | /api/instances/:id/groups                     | List groups                       |
| POST   | /api/instances/:id/groups                     | Create a group                    |
| PUT    | /api/instances/:id/groups/:group/participants | Add/remove/promote/demote members |
| GET    | /api/instances/:id/avatar?phone=NUMBER        | Profile image URL                 |

Text request: `{ "to": "+97450000000", "type": "text", "text": "Hello" }`. Optional `sendAt` is ISO 8601 UTC. Media types use `data` (base64), `mimetype`, `filename`, optional `text` caption. Location uses `latitude`/`longitude`. Contact uses `name`/`phone`. Poll uses `text` and `options` array.

See the authenticated console documentation for examples. Use phone numbers you control and permitted recipients. No external messages have been sent during implementation.
