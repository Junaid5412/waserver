# Zelon API – Fix Guide

Known problems, their root causes and the permanent fixes.

---

## 1. Recipients see "Waiting for this message… This may take a while"

**Symptom:** Messages sent from the server show correctly on WhatsApp Web / the sender's
console, but on the recipient's phone (Android and iPhone) they show
"Waiting for this message".

**Root cause:** The old library `@whiskeysockets/baileys` 6.7.x does not support WhatsApp's
LID addressing. It encrypts for the wrong address, so the recipient's phone cannot decrypt.

**Fix (applied, commit `deb2e1e`):**
1. `npm install @whiskeysockets/baileys@7.0.0-rc14 --save-exact`
2. Deploy and restart the server.
3. In the console: open the instance → **Delete** → create it again → scan the QR code
   (fresh encryption sessions).
4. Send a test message.

**Supporting changes already in place:** `makeCacheableSignalKeyStore`, `getMessage` fallbacks
(wa-message / inbox / messages), `requestPlaceholderResend`, and storing sent messages via
`recordSent`.

**Rollback:** `git revert deb2e1e` then `npm install`.

**If it returns:** check server logs for decrypt/retry errors, confirm the installed version with
`node -e "console.log(require('@whiskeysockets/baileys/package.json').version)"`, then re-link.

---

## 2. "Generate QR code" shows no QR after a logout/disconnect

**Root cause:** On code 401 (logged out) the stored credentials kept `registered: true`, so the
library tried to resume a dead session instead of showing a new QR.

**Fix (commit `1478861`):**
- `src/whatsapp.js`: on loggedOut/badSession, clear `auth:<instanceId>` and the phone number.
- `reset(instance, forceClean)` wipes credentials when `forceClean` is true.
- `POST /api/instances/:id/connect` and `pairingCode` call `reset(instance, true)`.

**Why instances disconnect:** logged out from phone (Linked devices), phone offline for a long
time, or the device token being replaced. A 401 is permanent – re-link is required.

**Manual workaround:** use the **Delete** button on the instance (also under Archived instances),
then create it again.

---

## 3. Node heap bar shows red

Not a problem. Heap used / heap total is normally 75–95 %. The console now compares heap used with
the real V8 limit (`v8.getHeapStatistics().heap_size_limit`, ~4 GB). Worry only if memory climbs
continuously and never drops, CPU stays near 100 %, or logs show
`JavaScript heap out of memory`.

---

## 4. Git push hangs on Windows

Cause: Windows Credential Manager prompt. Fix: set the remote URL with the username:

```
git remote set-url zelon https://Junaid-Bharwana@github.com/Junaid-Bharwana/zelon-api.git
git push zelon zelon-main:main
```

Note: `origin` (Junaid5412/waserver) has a separate history – do not push `zelon-main` there.

---

## 5. Tests

`npm test` – 4 tests fail on Windows only (path/symlink/startup byte-size checks); they pass on
Linux hosting. All others must pass.
