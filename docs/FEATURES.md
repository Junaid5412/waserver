# Feature coverage

This release implements Zelon's core WhatsApp integration workflows. External WhatsApp behavior remains subject to real-number acceptance testing.

| Area             | Included                                                                                                               | Console / API                                |
| ---------------- | ---------------------------------------------------------------------------------------------------------------------- | -------------------------------------------- |
| Public website   | Responsive home, feature sections, FAQs, developer entry                                                               | Website                                      |
| Accounts         | Admin creation, generated initial password, disable/enable, password reset/change                                      | Both                                         |
| Connections      | Multiple owned instances, QR, phone pairing, restart/reconnect, archive/restore                                        | Both; lifecycle uses console session         |
| Security         | Scoped hashed keys, origin checks, secure cookies, encrypted sessions/bodies/media, HTTPS webhook validation           | Backend                                      |
| Messages         | Text/image/video/audio/voice/document/sticker/location/contact/poll                                                    | Both; advanced fields via API                |
| Message controls | Quote, mention, forward, react, edit, delete, read, star, media download, poll votes                                   | Both except star via API                     |
| Queue            | Scheduled/offline queue, atomic cancellation/claim, idempotency, pacing, explicit unknown/failed outcomes              | Both                                         |
| Inbox            | Deduplicated sync, stored chat history, unread, search within loaded records, replies, receipts                        | Both                                         |
| Chat controls    | Read/archive/pin/mute/presence, request older WhatsApp history                                                         | Both; mute/presence/history requests via API |
| Media            | Chunk upload, size/digest validation, encrypted durable library, download/transport streaming                          | Both                                         |
| Contacts         | Sync, create/import, tags, consent, durable opt-outs, block/unblock                                                    | Both                                         |
| Groups           | Create/members/roles, metadata, subject/description, permissions, disappearing messages, invite/revoke/join/leave      | Both; group image via API                    |
| Profile          | Name/about, business details, image updates                                                                            | Both; image via API                          |
| Statuses         | Text/image/video/audio publishing with selected audience, persistent status journal                                    | Both                                         |
| Campaigns        | Up to 1,000 unique recipients/request, templates/personalization/schedule/interval, skip opt-outs, pause/resume/cancel | Both; campaign media via API                 |
| Automation       | Direct incoming text rules, exact/contains/any match, cooldown, personalized auto replies                              | Both                                         |
| Templates        | Create/list/edit/delete reusable text                                                                                  | Both; editing via API                        |
| Webhooks         | HMAC signing, event filtering, eight-attempt retry, manual replay, secret rotation                                     | Both                                         |
| Monitoring       | Per-instance message/webhook/inbox/campaign counts, admin database health/uptime                                       | Both                                         |
| Developers       | OpenAPI 3.1, detailed reference, Node/Python/PHP clients                                                               | Docs + SDK                                   |
| Persistence      | MySQL production, SQLite development, indexed pagination and exclusive worker lease                                    | Backend                                      |

## Transport and runtime limits

- No live WhatsApp account has been linked here; linking, media codecs, statuses, message controls and group permissions need real-number acceptance checks.
- History is the history WhatsApp provides to the linked device. It is not an exhaustive copy of the phone's entire history. Console lists start with the latest records; the API supports cursor pagination.
- Expired/removed media may no longer be available from WhatsApp. Status content is retained as journal records even after WhatsApp expires it.
- WhatsApp edit/delete windows, group roles, recipient privacy and rate limits still apply. A queued job is not proof of delivery.
- Paused/cancelled campaigns cannot undo a send already submitted to WhatsApp. Failed/unknown sends require investigation; there is no automatic message retry.
- Storage is not infinite. Monitor encrypted-media growth and define retention/backups for your deployment.
- The app runs as one long-lived process per database. Horizontal scaling and automatic retention/key rotation are not provided.

## Separate products not included

This project does not implement GREEN-API's separate AI/Telegram products, a payment/subscription system, voice/video call handling, or Meta's official WABA templates. There is no claim of complete parity with every GREEN-API service.
