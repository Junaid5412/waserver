# Zelon API

Private, self-hosted WhatsApp integration platform, with its own Zelon branding, responsive marketing website and multi-user developer console. Uses Baileys WhatsApp Web integration, not the official Meta Business Platform.

## Included in 0.3.0

- Persistent MySQL production database; encrypted WhatsApp sessions, message bodies, inbox, media chunks, events and signing secrets. SQLite for local development.
- Admin-provisioned accounts, password changes, admin password resets, account disablement, instance ownership and scoped API keys.
- QR and phone-code linking, reconnect handling, connection restart, recoverable instance archiving and key revocation.
- Text, images, video, audio/voice, documents, stickers, locations, contacts and polls. Scheduled sends, mentions, quotes, forwarding, reactions, editing, deleting, stars and media download.
- Persistent shared inbox, WhatsApp history synchronization, contact synchronization, unread counts, read markers, archive/pin/mute/presence APIs and delivery/read receipts.
- Encrypted chunk uploads, configurable 100 MB default maximum, integrity checks and persistent media library.
- Address book, CSV/JSON import, tags, consent records, opt-outs, blocking and blocklist.
- Personalized consent-based campaigns with scheduling, deduplication, pause/resume/cancel and delivery counts. Direct-message auto replies with keyword matching, templates and per-contact cooldown.
- WhatsApp statuses with explicit audiences, group creation/membership/roles, metadata, subject/description, disappearing messages, invite management and profile settings.
- Signed HTTPS webhooks, event filtering, bounded retries, manual replay and secret rotation.
- Instance analytics, administrator system health, OpenAPI 3.1 reference and Node/Python/PHP clients.

This is the main WhatsApp integration product. AI products, Telegram integration, paid SaaS billing and official WABA template messaging are outside the application. See [feature details](docs/FEATURES.md).

## Run locally

Requires Node.js 22.13+; Node 24 recommended.

```sh
npm ci
cp .env.example .env
```

In `.env`, set `NODE_ENV=development`, `APP_ORIGIN=http://localhost:3000`, `TRUST_PROXY=0`, your admin email/password, and a generated encryption key. Remove `MYSQL_HOST` for SQLite development. Generate the key with:

```sh
node -e "console.log(require('crypto').randomBytes(32).toString('base64'))"
npm test
npm run build
node --env-file=.env src/server.js
```

Open `/console`. Account creation is administrator-controlled. `npm start` expects environment variables already set by your hosting platform. `/health` checks database access and worker lease.

## Deploy yourself

Follow [Hostinger deployment](docs/DEPLOYMENT.md). The application is an Express server with no `dist` directory. Use `npm run build` and `npm start`, root directory `/`, entry `src/server.js`. Production refuses to start without persistent MySQL, HTTPS APP_ORIGIN and a valid encryption key.

An optional Dockerfile and Compose definition are included for local MySQL acceptance testing or a VPS. Do not run multiple application processes against the same database. Keep the same database and **ENCRYPTION_KEY** when redeploying. Back them up separately and test restores; losing the encryption key makes encrypted data unrecoverable.

## API and clients

Open `/api-reference.html` and `/openapi.json`, or read [API guide](docs/API.md). SDKs are in [sdk](sdk). Every client supports arbitrary scoped endpoints through `request`.

```js
import { Zelon } from "./sdk/zelon.mjs";
const client = new Zelon({
  url: process.env.ZELON_URL,
  instanceId: process.env.ZELON_INSTANCE_ID,
  apiKey: process.env.ZELON_API_KEY,
});
const result = await client.send(
  {
    to: "+97450000000",
    type: "text",
    text: "Hello from Zelon",
  },
  { key: "your-unique-business-operation-id" },
);
console.log(await client.getMessage(result.id));
```

Keys are shown once and stored hashed. Console operations require a secure session and matching Origin. Use a stable Idempotency-Key when retrying message, status and campaign requests. A replay returns the existing job; a changed payload returns 409. SDKs never automatically retry sends. Retain your chosen key when retrying a timed-out operation.

## Delivery and operational behavior

202 means **queued**, not delivered. Jobs wait while disconnected. A send interrupted during shutdown/restart becomes `unknown`; inspect WhatsApp delivery before manually retrying. Failed sends are not automatically retried. Read receipts depend on privacy settings and what WhatsApp reports; group user receipts represent reported participant activity, not a guarantee every participant read the message.

Campaigns accept up to 1,000 recipients per request, skip known opt-outs and require consent confirmation. STOP/unsubscribe/cancel subscription text creates durable opt-outs. Imports preserve opt-outs. Pausing/cancelling affects waiting jobs; already submitted sends can finish. Auto replies only trigger for fresh incoming direct messages, not history, groups or outgoing messages.

History contains only what WhatsApp synchronizes. Expired media may no longer be retrievable. Your number/group permissions, WhatsApp codec and size limits still apply. There are no Zelon subscription tiers, but infrastructure and WhatsApp usage limits still exist.

Media is uploaded in 512 KiB chunks and streamed to the WhatsApp transport. Encrypted/base64 database storage uses approximately 1.8 times the original media size, before database/backups overhead. Data is retained indefinitely; arrange an appropriate retention policy and monitor database size. Contact metadata and routing IDs are indexed in plaintext; message bodies, media and credentials are encrypted.

Webhook receivers must verify HMAC SHA-256 against **raw request bytes** and deduplicate event IDs. URLs must use public HTTPS on port 443; redirects and private/reserved IPv4 destinations are blocked. Delivery retries up to eight attempts. Secret rotation takes effect for subsequent attempts.

## Verification status

24 local tests passed, with 0 failures and 1 MySQL test skipped. See [verification record](docs/VERIFICATION.md). Local automated checks cover authentication, CSRF/origin protection, account isolation, key revocation, queue/idempotency, persistence, upload integrity, inbox deduplication, receipts, campaign controls, opt-outs, UI DOM workflows and the Node SDK. `npm audit --omit=dev` reported no known vulnerabilities during this update.

**Not live-deployed or tested with a linked WhatsApp account.** Real MySQL tests are configured but skipped locally because no MySQL server is available. GitHub Actions has been blocked by the account billing lock, so no successful CI/MySQL run is claimed. Browser preview was inaccessible; responsive CSS and DOM workflows were checked, but visual mobile/browser QA still requires deployment. The PHP client is supplied as source and has not been executed in a PHP runtime here. Complete the [deployment acceptance checks](docs/DEPLOYMENT.md#acceptance-checks) before production use.
