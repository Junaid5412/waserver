# Verification record — 0.3.1

Implementation checks completed on 2026-10-02 with Node 24.19.0.

| Check                         | Result                                                            |
| ----------------------------- | ----------------------------------------------------------------- |
| JavaScript build/syntax check | Passed for src, public, scripts and Node SDK                      |
| Automated tests               | 27 passed, 0 failed; 1 MySQL test skipped                         |
| Production dependency audit   | 0 reported vulnerabilities                                        |
| Lockfile/version consistency  | Passed                                                            |
| OpenAPI route inventory       | 69 paths verified                                                 |
| Python client syntax          | Passed                                                            |
| Real linked WhatsApp behavior | Not tested; requires a linked real number                         |
| Real MySQL integration        | Not run locally; separate test and CI configured                  |
| GitHub Actions                | Previously blocked by account billing lock; no CI success claimed |
| Browser/mobile visual QA      | Not completed; preview browser could not access local app         |
| PHP client execution          | Not run; no PHP runtime available                                 |
| Docker Compose                | Provided but not run                                              |
| Hostinger Web App deployment  | Not performed; user will deploy                                   |

Tests exercise the running Express application for login, origin protection, scoped keys, account isolation/password lifecycle and encrypted media HTTP upload/download. Persistent-store tests cover atomic idempotency/claim/cancellation, indexed history pagination and record survival. Feature tests cover chunk integrity, ownership, inbox deduplication, receipts that do not regress, concurrent auto-reply cooldown, durable STOP opt-outs, campaign deduplication/pause/resume/cancel and worker opt-out checks. DOM tests cover account creation, escaping, inbox quote reply, campaign submission and CSV parsing. The Node SDK is tested against an HTTP server.

Provider methods are wired to the installed Baileys APIs, but local mocks do not establish WhatsApp compatibility. Follow the deployment acceptance checklist before relying on this application for production messaging.

SQLite update: production-mode child processes reopened the same private database from different release working directories, rejected a second worker, validated 0700/0600 filesystem permissions, and rejected public-directory symlinks. Production Express startup and /health were checked with DATABASE_DRIVER=sqlite and an unused legacy MYSQL_HOST value. Hostinger persistence itself remains unverified; run the create-instance/redeploy check on the live account.

LiteSpeed startup fix: `npm run build` passed; `npm test` passed 28 tests
with one optional MySQL test skipped. A CommonJS child process required
`src/server.js` with production SQLite settings, returned synchronously,
served `/health` and `/`, and shut down cleanly. This reproduces the loader
mechanism from the supplied Hostinger error; live redeployment remains pending.
