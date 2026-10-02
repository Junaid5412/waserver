# Zelon API guide

Browse `/api-reference.html` and import `/openapi.json` into an OpenAPI-compatible API client. The generated specification lists the application's routes; this guide explains payloads for advanced actions.

All instance paths below are relative to `/api/instances/INSTANCE_ID`. Authenticate with `Authorization: Bearer YOUR_INSTANCE_KEY`. Console/session operations also need the exact APP_ORIGIN header on writes. Admin actions require an administrator session. See the OpenAPI operation security declarations.

## Responses and pagination

A send returns 202 `{id,status:"queued"}`. Repeat the same stable Idempotency-Key and identical body to retrieve the original job (200). A different body with the same key returns 409. GET `/messages/JOB_ID` retrieves its current status.

400 is validation, 401 invalid credentials, 403 insufficient privileges, 404 inaccessible record, 409 connection/state conflict, 413 request/media too large, 429 rate limiting. Unexpected errors use a generic 500 response; inspect server logs without exposing secrets.

List endpoints default to 100 newest records; `limit` accepts 1–100. For older records, pass `before=LAST_CREATED_AT&beforeId=LAST_RECORD_ID`. URL-encode values. Chat messages and outgoing jobs have different IDs: inbox operations use `waId`, queue operations use job `id`.

## Message payloads

| Type                               | Fields                                                                         |
| ---------------------------------- | ------------------------------------------------------------------------------ |
| text                               | to, type, text                                                                 |
| image/video/audio/document/sticker | to, type, mediaId; optional caption text, filename, mimetype; ptt for audio    |
| location                           | to, type, latitude, longitude; optional name                                   |
| contact                            | to, type, name, phone                                                          |
| poll                               | to, type, text (question), options (2–12 strings), selectableCount (default 1) |
| forward                            | to, type, forwardId (existing WhatsApp message ID in this instance)            |

Additional fields: `quotedId`, `mentions` (phone/JID array), `sendAt` (ISO UTC). Phone numbers use international format. Groups use their `@g.us` JID; existing linked-device contacts may use `@lid`. Inline base64 `data` is supported only for small legacy requests; use encrypted media uploads for larger files. Voice-note codec requirements are imposed by WhatsApp; Zelon does not transcode audio.

## Uploads

1. POST `/media` with `{filename,mimetype,size}`.
2. Read returned `id`, `chunkSize`, `totalChunks`.
3. PUT `/media/ID/chunks/INDEX` with `Content-Type: application/octet-stream`, exact raw bytes. Indices start at 0. Final chunk is the remaining bytes. Same-content retries succeed; different content at the same index returns 409.
4. POST `/media/ID/complete` with `{}`. Missing chunks return 409. Response includes SHA-256 `digest` and ready status.
5. Use `mediaId` when queuing a message. GET `/media/ID/download` to download from persistent storage.

Incomplete uploads remain in storage so chunks can be retried. Media IDs are scoped to the owner/instance. Default cap 100 MiB, configured by MAX_MEDIA_MB, 1–256. Provider limits may be lower.

## Inbox and chat actions

| Action                         | Request                                                                                             |
| ------------------------------ | --------------------------------------------------------------------------------------------------- |
| Chat list                      | GET `/chats`                                                                                        |
| Chat messages                  | GET `/chats/CHAT_JID/messages`                                                                      |
| Mark/read/archive/pin/mute     | PUT `/chats/CHAT_JID/settings` with optional read, archive, pin booleans; muteUntil ISO UTC or null |
| Presence                       | POST `/chats/CHAT_JID/presence` with presence: available/unavailable/composing/recording/paused     |
| Ask WhatsApp for older history | POST `/chats/CHAT_JID/history` with oldestId (existing waId) and count (1–100)                      |
| Read message                   | POST `/inbox/WA_ID/read` with `{}`                                                                  |
| React/remove reaction          | POST `/inbox/WA_ID/reaction` with emoji string (empty removes reaction)                             |
| Edit outgoing text             | PUT `/inbox/WA_ID/text` with text                                                                   |
| Delete                         | POST `/inbox/WA_ID/delete` with `{}`; WhatsApp permissions/time windows apply                       |
| Star/unstar                    | POST `/inbox/WA_ID/star` with star boolean                                                          |
| Download media                 | GET `/inbox/WA_ID/media` while media is available                                                   |
| Poll votes                     | GET `/polls/WA_ID/votes`                                                                            |

## Contacts and campaigns

POST `/contacts` accepts phone/name, tags array, consent and optedOut booleans. POST `/contacts/import` accepts `{contacts:[...]}` (maximum 1,000). A known opt-out cannot be cleared by an import/update. POST `/contacts/CONTACT_ID/opt-out` stores suppression. PUT `/contacts/block` accepts phone and blocked boolean; GET `/blocklist` retrieves WhatsApp blocklist. DELETE `/contacts/CONTACT_ID` is disallowed for opted-out contacts to preserve campaign suppression.

POST `/campaigns`:

```json
{
  "name": "Welcome",
  "recipients": [{ "to": "+97450000000", "name": "Sam" }],
  "message": { "type": "text", "text": "Hello {{name}}" },
  "intervalSeconds": 5,
  "consentConfirmed": true
}
```

Optional startAt is ISO UTC. Up to 1,000 unique recipients are accepted; known opt-outs are skipped. Message fields are shared across recipients; mediaId is supported. `{{name}}` and `{{phone}}` personalize text. Reuse a stable Idempotency-Key on campaign retries. Compilation failure prevents partially queued jobs from sending. PUT `/campaigns/ID` uses status running/paused/cancelled; cancelled or completed campaigns cannot be resumed. GET `/campaigns` includes per-status job counts and marks finished campaigns completed when read.

POST `/rules`: `{name,match,keyword,reply,cooldownSeconds,enabled,stopAfterMatch}`. Match is any/exact/contains. Use `{{name}}`, `{{phone}}`, `{{message}}`. PUT `/rules/ID` changes enabled/reply; DELETE removes. Only fresh direct incoming messages trigger rules. STOP suppression precedes rule evaluation. POST `/templates` accepts name/text; PUT replaces these fields; DELETE removes.

## Groups, profiles and statuses

GET/POST `/groups` lists/creates groups; creation uses name and participants phone/JID array. PUT `/groups/GROUP/participants` uses participants and action add/remove/promote/demote. GET `/groups/GROUP` reads metadata. PUT updates optional name, description, announcement, locked, ephemeralSeconds (0/86400/604800/7776000), pictureMediaId. GET `/groups/GROUP/invite`; POST `/groups/GROUP/invite/revoke`; POST `/groups/join` with code; POST `/groups/GROUP/leave`.

GET `/profile` returns available name/about/business details; PUT accepts name/about/pictureMediaId. POST `/check-number` accepts phone; GET `/avatar?phone=NUMBER` returns a profile URL when available. Names, permissions and privacy remain controlled by WhatsApp.

POST `/statuses` accepts type text/image/video/audio, text/caption, optional mediaId/backgroundColor, and **required statusAudience** phone/JID array. GET `/statuses` exposes persisted incoming/outgoing status journal. Use the idempotency header as with messages. Only this platform's own published status can be deleted using its recorded audience.

## Settings and webhook configuration

GET/PUT `/settings` reads/updates sendIntervalMs (0–60000), webhookEvents (empty means all). Supported event names: message, receipt, connection, group, group-participants, presence, call, history, error. GET `/analytics` returns indexed status counts.

Console session operations: POST `/connect`, GET `/qr`, POST `/pairing-code` with phone, POST `/disconnect`, POST `/restart`, POST `/archive`, POST `/key` for scoped key rotation, PUT `/webhook` with url, POST `/webhook/rotate`. GET `/webhooks` is console-only. POST `/webhooks/DELIVERY_ID/retry` requeues a failed delivery. Archived instances use GET `/api/archived-instances` and POST `/api/instances/ID/restore` (console session). Restoring does not restore the revoked key; generate a new key.

Webhook headers include X-Zelon-Signature (`sha256=HEX`) and X-Zelon-Event-ID. Validate raw body bytes with HMAC SHA-256. Receivers should acknowledge quickly and deduplicate event IDs. Rotating secrets affects later retry attempts. URLs must be public HTTPS on port 443; no redirects/private network destinations.

## SDKs

Clients are source files in `sdk/`; they are also downloadable through the application API reference page. Node needs Node 22+; Python uses the standard library; PHP needs PHP 8+ and curl. No SDK sends automatically on import. Every send accepts your stable idempotency key; automatic transport retries are disabled. Node uploads read the file into memory, while the Python/PHP examples read chunks. For very large Node client files, call request on the chunk endpoints using your own file stream.

## Local storage configuration

DATABASE_DRIVER=sqlite uses a private SQLite file and does not require a database provider. DATA_DIR chooses an absolute persistent directory outside the deployment. The Hostinger domain layout is detected when available. DATABASE_DRIVER=mysql keeps the external database option. Preserve your existing ENCRYPTION_KEY. No automatic MySQL-to-SQLite data migration occurs. See STORAGE.md before switching an existing database.
