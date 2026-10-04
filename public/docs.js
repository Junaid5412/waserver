/* Zelon API - interactive documentation (used by /api-reference.html and the console) */
(function () {
  const esc = (v) => String(v ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
  const ORIGIN = () => location.origin;
  const BASE = "/api/instances/INSTANCE_ID";
  const J = (o) => JSON.stringify(o, null, 2);
  const P = (name, type, req, desc) => ({ name, type, req, desc });

  /* ------------------------------------------------------------ catalogue */
  const SECTIONS = [
    {
      id: "messages", title: "Messages", intro: "Everything is sent through one endpoint. Messages are queued instantly, delivered by the worker and tracked through status updates. Every message type shares the same envelope.",
      eps: [
        { m: "POST", p: "/messages", d: "Queue a message of any type", params: [
          P("to", "string", true, "Recipient phone with country code (+97450000000), a group id (…@g.us) or a chat id."),
          P("type", "string", false, "text (default), image, video, audio, document, sticker, location, contact, poll or forward."),
          P("text", "string", false, "Message body, or the caption for media. Up to 20,000 characters. Required for text."),
          P("mediaId", "uuid", false, "Id of an uploaded file (see Media). Use for large files."),
          P("data", "string", false, "Base64 media for small files (up to about 500 KB). Combine with mimetype and filename."),
          P("mimetype / filename", "string", false, "Metadata for media. Defaults come from the uploaded file."),
          P("ptt", "boolean", false, "With type audio, send as a voice note."),
          P("latitude / longitude / name", "number / string", false, "Location coordinates and optional label."),
          P("name / phone", "string", false, "Contact card details (type contact)."),
          P("options / selectableCount", "string[] / number", false, "Poll options (2–12) and how many may be chosen."),
          P("quotedId", "string", false, "WhatsApp message id to reply to (shows a quoted reply)."),
          P("forwardId", "string", false, "WhatsApp message id to forward (type forward)."),
          P("mentions", "string[]", false, "Phone numbers to @mention in a group message."),
          P("sendAt", "ISO 8601", false, "Schedule for later, in UTC. Up to 60 seconds in the past is tolerated."),
        ], headers: [["Idempotency-Key", "Optional, 8–200 chars. Retrying with the same key returns the original job instead of sending twice."]],
          body: { to: "+97450000000", type: "text", text: "Your order #1042 has shipped 🚚" }, status: 202, res: { id: "9f1c3d2e-6c0a-4b53-b0c9-2a0d1c7b9e11", status: "queued" } },
        { m: "GET", p: "/messages/:job", d: "Check one message's status", params: [P("job", "string", true, "Id returned when the message was queued.")], res: { id: "9f1c…", status: "sent", to: "+97450000000", type: "text", createdAt: "2026-10-04T09:21:00.000Z" } },
        { m: "GET", p: "/messages", d: "List outgoing messages (newest first)", params: [P("limit", "number", false, "1–100, default 100."), P("before + beforeId", "ISO date + id", false, "Cursor from the previous page (X-Cursor-Created and X-Cursor-Id headers). Both are required together.")], res: [{ id: "9f1c…", status: "sent", to: "+97450000000", type: "text" }] },
        { m: "POST", p: "/messages/:messageId/cancel", d: "Cancel a queued or scheduled message", params: [P("messageId", "string", true, "Message id. Only messages that are still queued can be cancelled.")], res: { ok: true } },
      ],
      examples: [
        ["Image with caption", { to: "+97450000000", type: "image", mediaId: "UPLOADED_MEDIA_ID", text: "Your invoice" }],
        ["Voice note", { to: "+97450000000", type: "audio", mediaId: "UPLOADED_MEDIA_ID", ptt: true }],
        ["Document", { to: "+97450000000", type: "document", mediaId: "UPLOADED_MEDIA_ID", filename: "invoice.pdf", text: "Invoice #1042" }],
        ["Location", { to: "+97450000000", type: "location", latitude: 25.2854, longitude: 51.531, name: "Our store" }],
        ["Contact card", { to: "+97450000000", type: "contact", name: "Support Team", phone: "+97455555555" }],
        ["Poll", { to: "+97450000000", type: "poll", text: "Pick a delivery slot", options: ["Morning", "Afternoon", "Evening"], selectableCount: 1 }],
        ["Reply to a message", { to: "+97450000000", type: "text", text: "On its way!", quotedId: "3EB0A1B2C3D4E5F6" }],
        ["Scheduled message", { to: "+97450000000", type: "text", text: "Appointment tomorrow at 10:00", sendAt: "2026-10-05T06:00:00.000Z" }],
        ["Forward a message", { to: "+97450000000", type: "forward", forwardId: "3EB0A1B2C3D4E5F6" }],
      ],
    },
    {
      id: "media", title: "Media uploads", intro: "Upload a file once, then reuse its mediaId in any number of messages. Files up to 100 MB are uploaded in 512 KB chunks, encrypted at rest and streamed back when needed.",
      eps: [
        { m: "POST", p: "/media", d: "Start an upload", params: [P("filename", "string", true, "File name."), P("mimetype", "string", false, "MIME type, for example application/pdf."), P("size", "number", true, "Total size in bytes (up to 100 MB).")], body: { filename: "invoice.pdf", mimetype: "application/pdf", size: 482113 }, status: 201, res: { id: "0c4e…", chunkSize: 524288, totalChunks: 1 } },
        { m: "PUT", p: "/media/:mediaId/chunks/:index", d: "Upload one chunk (raw bytes)", params: [P("Content-Type", "header", true, "application/octet-stream"), P("index", "number", true, "Zero-based chunk number.")], res: { ok: true } },
        { m: "POST", p: "/media/:mediaId/complete", d: "Finish the upload", res: { id: "0c4e…", status: "ready" } },
        { m: "GET", p: "/media", d: "List uploaded files", res: [{ id: "0c4e…", filename: "invoice.pdf", size: 482113 }] },
        { m: "GET", p: "/media/:mediaId/download", d: "Download an uploaded file", res: "(binary file)" },
      ],
    },
    {
      id: "inbox", title: "Chats & inbox", intro: "Read conversations that your number sends and receives, and act on messages the way you would inside WhatsApp.",
      eps: [
        { m: "GET", p: "/chats", d: "List conversations", params: [P("limit", "number", false, "1�100."), P("search", "string", false, "Filter by name or number.")], res: [{ chatId: "97450000000@s.whatsapp.net", name: "Amina Rahman", lastPreview: "Thanks!", unread: 2, lastAt: "2026-10-04T09:30:00Z", pinned: false }] },
        { m: "GET", p: "/chats/:chat/messages", d: "Read a conversation", params: [P("chat", "string", true, "Chat id or phone number."), P("limit", "number", false, "1�100."), P("before + beforeId", "ISO date + id", false, "Cursor for older messages.")], res: [{ id: "row1", waId: "3EB0…", fromMe: false, type: "text", text: "Hello", status: "received", createdAt: "2026-10-04T09:30:00Z" }] },
        { m: "PUT", p: "/chats/:chat/settings", d: "Pin, archive, mute or mark read", body: { pin: true, archive: false, muteUntil: null, read: true }, res: { ok: true } },
        { m: "POST", p: "/chats/:chat/presence", d: "Show typing, recording or online", params: [P("presence", "string", true, "composing, recording, paused, available or unavailable.")], body: { presence: "composing" }, res: { ok: true } },
        { m: "POST", p: "/chats/:chat/history", d: "Request older history from your phone", body: { oldestId: "3EB0A1B2C3D4E5F6", count: 50 }, res: { ok: true } },
        { m: "GET", p: "/chats/:chat/picture", d: "Profile photo (image bytes)", res: "(image/jpeg)" },
        { m: "GET", p: "/chats/:chat/info", d: "Contact or group details (about, business profile, participants)", res: { kind: "contact", name: "Amina Rahman", phone: "97450000000", about: "Busy" } },
        { m: "POST", p: "/inbox/:message/read", d: "Send a read receipt", res: { ok: true } },
        { m: "POST", p: "/inbox/:message/reaction", d: "React with an emoji (empty string removes it)", body: { emoji: "👍" }, res: { ok: true } },
        { m: "PUT", p: "/inbox/:message/text", d: "Edit a message you sent", body: { text: "Corrected text" }, res: { ok: true } },
        { m: "POST", p: "/inbox/:message/delete", d: "Delete a message", params: [P("scope", "string", false, "everyone (default) or me.")], body: { scope: "everyone" }, res: { ok: true } },
        { m: "POST", p: "/inbox/:message/star", d: "Star or unstar", body: { star: true }, res: { ok: true } },
        { m: "GET", p: "/inbox/:message/media", d: "Download media from a received message", params: [P("inline", "1", false, "Display in the browser instead of downloading.")], res: "(binary file)" },
        { m: "GET", p: "/polls/:message/votes", d: "Poll results", res: [{ option: "Morning", voters: ["97450000000"] }] },
      ],
    },
    {
      id: "contacts", title: "Contacts", intro: "Keep an address book with consent flags so campaigns only reach people who agreed to hear from you.",
      eps: [
        { m: "GET", p: "/contacts", d: "List contacts", res: [{ id: "c1", phone: "+97450000000", name: "Amina", consent: true, tags: ["vip"] }] },
        { m: "POST", p: "/contacts", d: "Create or update a contact", params: [P("phone", "string", true, "With country code."), P("name", "string", true, "1–100 characters."), P("consent", "boolean", false, "Marketing consent. Default false."), P("tags", "string[]", false, "Up to 20 tags.")], body: { phone: "+97450000000", name: "Amina", consent: true, tags: ["vip"] }, res: { id: "c1", ok: true } },
        { m: "POST", p: "/contacts/import", d: "Import up to 1,000 contacts", body: { contacts: [{ phone: "+97450000000", name: "Amina", consent: true }] }, res: { imported: 1 } },
        { m: "POST", p: "/contacts/:contact/opt-out", d: "Mark a contact as opted out", res: { ok: true } },
        { m: "DELETE", p: "/contacts/:contact", d: "Delete a contact", res: { ok: true } },
        { m: "POST", p: "/check-number", d: "Check whether a number is on WhatsApp", body: { phone: "+97450000000" }, res: [{ exists: true, jid: "97450000000@s.whatsapp.net" }] },
        { m: "GET", p: "/avatar", d: "Profile picture URL", params: [P("phone", "string", true, "Phone with country code.")], res: { url: "https://…" } },
        { m: "GET", p: "/blocklist", d: "Blocked numbers", res: ["97450000000"] },
        { m: "PUT", p: "/contacts/block", d: "Block or unblock", body: { phone: "+97450000000", blocked: true }, res: { ok: true } },
      ],
    },
    {
      id: "groups", title: "Groups", intro: "Create and manage WhatsApp groups. Your linked number must be an admin for membership and settings changes.",
      eps: [
        { m: "GET", p: "/groups", d: "List your groups", res: [{ id: "1203630…@g.us", subject: "Team", size: 12 }] },
        { m: "POST", p: "/groups", d: "Create a group", body: { name: "Team", participants: ["+97450000000"] }, res: { id: "1203630…@g.us", subject: "Team" } },
        { m: "GET", p: "/groups/:group", d: "Group metadata", res: { id: "…@g.us", subject: "Team", participants: [] } },
        { m: "PUT", p: "/groups/:group", d: "Rename, set description or restrictions", body: { name: "Team Alpha", description: "Weekly updates", announcement: false, locked: false }, res: { ok: true } },
        { m: "PUT", p: "/groups/:group/participants", d: "Add, remove, promote or demote", params: [P("action", "string", true, "add, remove, promote or demote."), P("participants", "string[]", true, "Phone numbers.")], body: { action: "add", participants: ["+97450000001"] }, res: { ok: true } },
        { m: "GET", p: "/groups/:group/invite", d: "Get the invite link", res: { code: "AbCdEf123456", url: "https://chat.whatsapp.com/AbCdEf123456" } },
        { m: "POST", p: "/groups/:group/invite/revoke", d: "Reset the invite link", res: { code: "NewCode123456" } },
        { m: "POST", p: "/groups/join", d: "Join with an invite code", body: { code: "AbCdEf123456" }, res: { id: "…@g.us" } },
        { m: "POST", p: "/groups/:group/leave", d: "Leave a group", res: { ok: true } },
      ],
    },
    {
      id: "automation", title: "Automation", intro: "Reply automatically, reuse message templates and reach consenting contacts with paced campaigns.",
      eps: [
        { m: "GET", p: "/rules", d: "List auto-reply rules", res: [{ id: "r1", name: "Greeting", match: "contains", keyword: "hello", reply: "Hi! 👋", enabled: true }] },
        { m: "POST", p: "/rules", d: "Create a rule", params: [P("match", "string", true, "any, exact or contains."), P("keyword", "string", false, "Text to look for."), P("reply", "string", true, "Auto-reply text."), P("cooldownSeconds", "number", false, "Minimum seconds between replies to the same chat."), P("stopAfterMatch", "boolean", false, "Stop evaluating later rules.")], body: { name: "Greeting", match: "contains", keyword: "hello", reply: "Hi! How can we help?", cooldownSeconds: 60, enabled: true }, status: 201, res: { id: "r1" } },
        { m: "PUT", p: "/rules/:rule", d: "Enable, disable or edit", body: { enabled: false }, res: { ok: true } },
        { m: "DELETE", p: "/rules/:rule", d: "Delete a rule", res: { ok: true } },
        { m: "GET", p: "/templates", d: "List templates", res: [{ id: "t1", name: "Shipped", text: "Hi {{name}}, your order shipped." }] },
        { m: "POST", p: "/templates", d: "Create a template", body: { name: "Shipped", text: "Hi {{name}}, your order shipped." }, status: 201, res: { id: "t1" } },
        { m: "GET", p: "/campaigns", d: "List campaigns", res: [{ id: "cm1", name: "Launch", status: "running", sent: 12, total: 40 }] },
        { m: "POST", p: "/campaigns", d: "Start a campaign", params: [P("recipients", "array", true, "Phone strings or { to, name } objects."), P("consentConfirmed", "boolean", true, "You confirm every recipient agreed to receive messages."), P("intervalSeconds", "number", false, "Delay between messages (1–3600, default 5)."), P("startAt", "ISO 8601", false, "Start later.")], body: { name: "Launch", text: "Hi {{name}}, we just launched!", recipients: [{ to: "+97450000000", name: "Amina" }], consentConfirmed: true, intervalSeconds: 5 }, status: 201, res: { id: "cm1", status: "running" } },
        { m: "PUT", p: "/campaigns/:campaign", d: "Pause, resume or cancel", body: { status: "paused" }, res: { ok: true } },
        { m: "GET", p: "/statuses", d: "List status updates", res: [] },
        { m: "POST", p: "/statuses", d: "Publish a status", body: { type: "text", text: "We are open until 9 PM", statusAudience: ["+97450000000"] }, res: { id: "s1", status: "queued" } },
      ],
    },
    {
      id: "instance", title: "Instance & profile", intro: "Inspect the connected number, tune sending behaviour and manage the profile shown to your contacts. Linking, QR codes, API keys and logout are done from the console.",
      eps: [
        { m: "GET", p: "/state", d: "Connection state and phone", res: { status: "connected", phone: "97450000000" } },
        { m: "GET", p: "/settings", d: "Read settings", res: { sendIntervalMs: 1000, webhookEvents: [], maxMediaBytes: 104857600 } },
        { m: "PUT", p: "/settings", d: "Update settings", params: [P("sendIntervalMs", "number", false, "Delay between outgoing messages (0–60000)."), P("webhookEvents", "string[]", false, "Limit webhook deliveries to these event types.")], body: { sendIntervalMs: 1500 }, res: { ok: true } },
        { m: "GET", p: "/profile", d: "Profile name, about and picture", res: { name: "Support", about: "We reply fast" } },
        { m: "PUT", p: "/profile", d: "Update profile", body: { name: "Support", about: "We reply within minutes" }, res: { ok: true } },
        { m: "GET", p: "/analytics", d: "Message and delivery statistics", res: { sent: 120, received: 98, failed: 1 } },
        { m: "GET", p: "/events", d: "Incoming messages, receipts and connection events", params: [P("limit", "number", false, "1–100."), P("before + beforeId", "ISO date + id", false, "Cursor for older events.")], res: [{ id: "e1", type: "message", createdAt: "2026-10-04T09:30:00Z" }] },
      ],
    },
  ];

  /* ------------------------------------------------------- code generators */
  const fullUrl = (p) => ORIGIN() + BASE + p;
  const hasBody = (e) => e.body !== undefined && e.m !== "GET";
  function gen(lang, e, body) {
    const url = fullUrl(e.p), m = e.m, b = body ?? e.body, withBody = b !== undefined && m !== "GET";
    const idem = e.p === "/messages" && m === "POST";
    if (lang === "curl")
      return `curl -X ${m} "${url}" \\\n  -H "Authorization: Bearer YOUR_API_KEY"` + (idem ? ` \\\n  -H "Idempotency-Key: unique-id-123"` : "") + (withBody ? ` \\\n  -H "Content-Type: application/json" \\\n  -d '${J(b)}'` : "");
    if (lang === "node")
      return `const res = await fetch("${url}", {\n  method: "${m}",\n  headers: {\n    Authorization: "Bearer " + process.env.ZELON_KEY,` + (withBody ? `\n    "Content-Type": "application/json",` : "") + (idem ? `\n    "Idempotency-Key": "unique-id-123",` : "") + `\n  },` + (withBody ? `\n  body: JSON.stringify(${J(b).replace(/\n/g, "\n  ")}),` : "") + `\n});\nconsole.log(await res.json());`;
    if (lang === "python") {
      const pyBody = withBody ? J(b).replace(/\btrue\b/g, "True").replace(/\bfalse\b/g, "False").replace(/\bnull\b/g, "None").replace(/\n/g, "\n    ") : "";
      return `import os, requests\n\nr = requests.request(\n    "${m}", "${url}",\n    headers={"Authorization": "Bearer " + os.environ["ZELON_KEY"]` + (idem ? `, "Idempotency-Key": "unique-id-123"` : "") + `},` + (withBody ? `\n    json=${pyBody},` : "") + `\n)\nprint(r.json())`;
    }
    const phpArr = (o, ind = "  ") => Array.isArray(o) ? "[" + o.map((x) => (typeof x === "object" && x ? phpArr(x, ind + "  ") : JSON.stringify(x))).join(", ") + "]" : typeof o === "object" && o ? "[\n" + Object.entries(o).map(([k, v]) => `${ind}  ${JSON.stringify(k)} => ${typeof v === "object" && v ? phpArr(v, ind + "  ") : v === null ? "null" : JSON.stringify(v)}`).join(",\n") + "\n" + ind + "]" : JSON.stringify(o);
    return `<?php\n$ch = curl_init("${url}");\ncurl_setopt_array($ch, [\n  CURLOPT_CUSTOMREQUEST => "${m}",\n  CURLOPT_RETURNTRANSFER => true,\n  CURLOPT_HTTPHEADER => [\n    "Authorization: Bearer " . getenv("ZELON_KEY"),` + (withBody ? `\n    "Content-Type: application/json",` : "") + (idem ? `\n    "Idempotency-Key: unique-id-123",` : "") + `\n  ],` + (withBody ? `\n  CURLOPT_POSTFIELDS => json_encode(${phpArr(b)}),` : "") + `\n]);\necho curl_exec($ch);`;
  }
  const LANGS = [["curl", "cURL"], ["node", "Node.js"], ["python", "Python"], ["php", "PHP"]];
  let uid = 0;
  const codeTabs = (e, body) => {
    const id = "ct" + ++uid;
    return `<div data-ct="${id}"><div class="tabs2">${LANGS.map(([k, l], i) => `<button type="button" data-lang="${k}" class="${i ? "" : "on"}">${l}</button>`).join("")}</div><div class="code"><button class="copy" type="button" data-copy>Copy</button><pre>${esc(gen("curl", e, body))}</pre></div></div>`;
  };
  const jsonBlock = (v) => `<div class="code solo"><button class="copy" type="button" data-copy>Copy</button><pre>${esc(typeof v === "string" ? v : J(v))}</pre></div>`;

  function endpoint(e, sid, i) {
    const params = e.params?.length ? `<h4>Parameters</h4><div style="overflow:auto"><table class="dtable"><tr><th>Name</th><th>Type</th><th>Description</th></tr>${e.params.map((x) => `<tr><td><code>${esc(x.name)}</code>${x.req ? ' <span class="req">required</span>' : ""}</td><td>${esc(x.type)}</td><td>${esc(x.desc)}</td></tr>`).join("")}</table></div>` : "";
    const headers = e.headers?.length ? `<h4>Headers</h4><table class="dtable">${e.headers.map(([k, v]) => `<tr><td><code>${esc(k)}</code></td><td>${esc(v)}</td></tr>`).join("")}</table>` : "";
    const status = e.status || 200;
    return `<div class="ep" id="${sid}-${i}" data-text="${esc((e.m + " " + e.p + " " + e.d).toLowerCase())}"><div class="ep-h" data-toggle><span class="verb ${e.m}">${e.m}</span><span class="path">${esc(e.p)}</span><span class="desc">${esc(e.d)}</span></div><div class="ep-b">${headers}${params}<h4>Example request</h4>${codeTabs(e)}<h4>Example response</h4><div class="resp"><span class="st">${status}</span>${status === 202 ? "Accepted" : status === 201 ? "Created" : "OK"}</div>${jsonBlock(e.res)}</div></div>`;
  }

  function section(s) {
    const extra = s.examples ? `<h3>Message type recipes</h3><p>Send these as the JSON body of <code>POST /messages</code>.</p>${s.examples.map(([t, b]) => `<details class="ep" style="margin-top:10px"><summary class="ep-h" style="list-style:none"><span class="verb POST">POST</span><span class="path">${esc(t)}</span></summary><div class="ep-b" style="display:block">${codeTabs({ m: "POST", p: "/messages", body: b })}</div></details>`).join("")}` : "";
    return `<section class="dsec" id="${s.id}"><h2>${esc(s.title)}</h2><p>${esc(s.intro)}</p>${s.eps.map((e, i) => endpoint(e, s.id, i)).join("")}${extra}</section>`;
  }

  /* ----------------------------------------------------------- prose parts */
  const GETTING = () => `
  <section class="dsec" id="intro"><h2>Introduction</h2><p>The Zelon API is a JSON-over-HTTPS interface for sending and receiving WhatsApp messages from your own software. Every endpoint belongs to one connected number (an <em>instance</em>), so a single API key can only act on its own number.</p>
    <div class="dgrid"><div class="dcard"><b>Base URL</b><p><code>${esc(ORIGIN())}${BASE}</code></p></div><div class="dcard"><b>Format</b><p>Requests and responses use <code>application/json</code> and UTF-8. Timestamps are ISO 8601 in UTC.</p></div><div class="dcard"><b>Authentication</b><p>Send <code>Authorization: Bearer YOUR_API_KEY</code> on every request.</p></div><div class="dcard"><b>Idempotency</b><p>Add an <code>Idempotency-Key</code> header when sending to make retries safe.</p></div></div></section>
  <section class="dsec" id="quickstart"><h2>Quick start</h2><ol><li>Sign in to the <a href="/console"><b>console</b></a> and create an instance.</li><li>Open <b>Connection</b>, then link your number with a QR code or a pairing code (WhatsApp → Linked devices).</li><li>Click <b>Generate API key</b> and store it securely — it is shown only once.</li><li>Send your first message:</li></ol>${codeTabs({ m: "POST", p: "/messages", body: { to: "+97450000000", type: "text", text: "Hello from Zelon API 👋" } })}<div class="note">Replace <code>INSTANCE_ID</code> with the id shown at the bottom of the Connection tab. Keep keys on your server — never in browser or mobile app code.</div></section>
  <section class="dsec" id="auth"><h2>Authentication</h2><p>Create a key under <b>Instance → Connection → API access</b>. A key works only for its instance. Generating a new key immediately revokes the previous one, which also makes rotation easy.</p>${jsonBlock("Authorization: Bearer zk_live_xxxxxxxxxxxxxxxxxxxxxxxx")}<div class="note warn">Treat API keys like passwords. If one leaks, generate a new key right away.</div></section>
  <section class="dsec" id="lifecycle"><h2>Message lifecycle</h2><p>Sending is asynchronous. <code>POST /messages</code> returns immediately with <code>queued</code>; the worker then delivers it and updates the status.</p><table class="dtable"><tr><th>Status</th><th>Meaning</th></tr><tr><td><code>queued</code></td><td>Accepted and waiting for its send time.</td></tr><tr><td><code>sent</code></td><td>Handed to WhatsApp (one grey tick).</td></tr><tr><td><code>delivered</code></td><td>Reached the recipient's device (two grey ticks).</td></tr><tr><td><code>read</code></td><td>Opened by the recipient (two blue ticks).</td></tr><tr><td><code>failed</code></td><td>Could not be sent. See <code>error</code> in the job.</td></tr><tr><td><code>cancelled</code></td><td>Cancelled before sending.</td></tr><tr><td><code>unknown</code></td><td>Interrupted mid-send. Check delivery before retrying to avoid duplicates.</td></tr></table></section>
  <section class="dsec" id="limits"><h2>Errors, limits &amp; pagination</h2><table class="dtable"><tr><th>Code</th><th>Meaning</th></tr><tr><td><code>400</code></td><td>Invalid input. The error message explains which field.</td></tr><tr><td><code>401</code></td><td>Missing or invalid API key.</td></tr><tr><td><code>404</code></td><td>Instance or resource not found.</td></tr><tr><td><code>409</code></td><td>Number not connected, or idempotency key reused with different content.</td></tr><tr><td><code>429</code></td><td>Rate limit exceeded. Wait a moment and retry.</td></tr></table>${jsonBlock({ error: "Connect this WhatsApp instance first" })}<h3>Rate limits</h3><p>Requests are limited per client (240 per minute by default). Sending speed to WhatsApp is separately paced by the instance's send interval to protect your number.</p><h3>Cursor pagination</h3><p>List endpoints return newest-first. When more rows exist, the response carries <code>X-Has-More: true</code> with <code>X-Cursor-Created</code> and <code>X-Cursor-Id</code>; pass them back as <code>before</code> and <code>beforeId</code> to read the next page.</p></section>`;

  const WEBHOOKS = () => `
  <section class="dsec" id="webhooks"><h2>Webhooks</h2><p>Add a public HTTPS URL under <b>Instance → Webhooks</b> and Zelon will POST every event to it. Delivery is at least once, with automatic retries and exponential back-off, so de-duplicate using the event <code>id</code>.</p>
    <h3>Event types</h3><table class="dtable"><tr><th>Type</th><th>When</th></tr><tr><td><code>message</code></td><td>A message arrives or is sent from your phone.</td></tr><tr><td><code>receipt</code></td><td>A delivery or read receipt changes.</td></tr><tr><td><code>connection</code></td><td>The number connects, disconnects or needs relinking.</td></tr><tr><td><code>presence</code></td><td>A contact starts or stops typing.</td></tr><tr><td><code>group</code> / <code>group-participants</code></td><td>Group settings or membership change.</td></tr><tr><td><code>call</code></td><td>An incoming call is detected.</td></tr></table>
    <h3>Payload</h3>${jsonBlock({ id: "7d8e…", instanceId: "a1b2…", userId: "…", type: "message", createdAt: "2026-10-04T09:30:00.000Z", data: { id: "3EB0A1B2C3D4E5F6", chatId: "97450000000@s.whatsapp.net", fromMe: false, text: "Is my order ready?" } })}
    <h3>Headers</h3><table class="dtable"><tr><td><code>X-Zelon-Signature</code></td><td><code>sha256=&lt;hex HMAC of the raw body&gt;</code></td></tr><tr><td><code>X-Zelon-Event-ID</code></td><td>Unique event id, for de-duplication.</td></tr></table>
    <h3>Verify the signature</h3><p>Compute an HMAC-SHA256 of the <b>raw</b> request body with your webhook secret and compare it in constant time.</p>
    <div data-ct="vv"><div class="tabs2"><button type="button" data-lang="node" class="on">Node.js</button><button type="button" data-lang="python">Python</button><button type="button" data-lang="php">PHP</button></div><div class="code"><button class="copy" type="button" data-copy>Copy</button><pre data-vsrc="node">${esc(`import crypto from "node:crypto";\n\napp.post("/zelon", express.raw({ type: "*/*" }), (req, res) => {\n  const expected = "sha256=" + crypto\n    .createHmac("sha256", process.env.ZELON_WEBHOOK_SECRET)\n    .update(req.body)\n    .digest("hex");\n  const sig = req.get("X-Zelon-Signature") || "";\n  const ok = sig.length === expected.length &&\n    crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(expected));\n  if (!ok) return res.sendStatus(401);\n  const event = JSON.parse(req.body);\n  // handle event.type …\n  res.sendStatus(200);\n});`)}</pre></div></div>
    <div class="note">Respond with any <code>2xx</code> status within 10 seconds. Failed deliveries are retried and can be re-sent manually from the Webhooks tab.</div></section>`;

  const SDKS = () => `<section class="dsec" id="practices"><h2>Best practices</h2><ul><li>Always send an <code>Idempotency-Key</code> from background jobs and retries.</li><li>Use webhooks instead of polling for incoming messages and receipts.</li><li>Only message people who have agreed to hear from you, and respect opt-outs.</li><li>Pace bulk sends. Sudden high volume can get a WhatsApp number restricted.</li></ul></section>`;

  /* ------------------------------------------------------------ render */
  function render(el, { standalone = false } = {}) {
    const nav = [
      ["Getting started", [["intro", "Introduction"], ["quickstart", "Quick start"], ["auth", "Authentication"], ["lifecycle", "Message lifecycle"], ["limits", "Errors & limits"]]],
      ["API reference", SECTIONS.map((s) => [s.id, s.title])],
      ["Integrations", [["webhooks", "Webhooks"], ["practices", "Best practices"]]],
    ];
    el.innerHTML = `<div class="dlayout"><aside class="dside"><input type="search" id="docSearch" placeholder="Search endpoints…" aria-label="Search the documentation">${nav.map(([h, items]) => `<h5>${h}</h5>${items.map(([id, t]) => `<a data-nav="${id}">${esc(t)}</a>`).join("")}`).join("")}</aside><div class="dmain" id="docMain">${GETTING()}${SECTIONS.map(section).join("")}${WEBHOOKS()}${SDKS()}<div class="dsec" id="docEmpty" hidden><h2>No matches</h2><p>Nothing matches your search. Try a different word such as “group”, “webhook” or “media”.</p></div></div></div>`;

    el.addEventListener("click", async (ev) => {
      const t = ev.target;
      const nv = t.closest("[data-nav]");
      if (nv) {
        el.querySelector("#" + nv.dataset.nav)?.scrollIntoView({ behavior: "smooth", block: "start" });
        return;
      }
      const tg = t.closest("[data-toggle]");
      if (tg) { tg.parentElement.classList.toggle("open"); return; }
      const cp = t.closest("[data-copy]");
      if (cp) {
        const text = cp.parentElement.querySelector("pre")?.textContent || "";
        try { await navigator.clipboard.writeText(text); cp.textContent = "Copied"; } catch { cp.textContent = "Press Ctrl+C"; }
        setTimeout(() => (cp.textContent = "Copy"), 1500);
        return;
      }
      const lg = t.closest("[data-lang]");
      if (lg) {
        const wrap = lg.closest("[data-ct]");
        wrap.querySelectorAll("[data-lang]").forEach((b) => b.classList.toggle("on", b === lg));
        const pre = wrap.querySelector("pre");
        if (wrap.dataset.ct === "vv") pre.textContent = VERIFY[lg.dataset.lang];
        else {
          const epEl = wrap.closest(".ep");
          const found = findEp(epEl);
          pre.textContent = gen(lg.dataset.lang, found.e, found.body);
        }
      }
    });
    const search = el.querySelector("#docSearch");
    search.addEventListener("input", () => {
      const q = search.value.trim().toLowerCase();
      let any = false;
      el.querySelectorAll(".dsec[id]").forEach((sec) => {
        if (!sec.querySelector(".ep")) { sec.hidden = !!q; if (!q) any = true; return; }
        let hit = false;
        sec.querySelectorAll(".ep").forEach((ep) => {
          const text = ep.dataset.text || ep.textContent.toLowerCase().slice(0, 200);
          const m = !q || text.includes(q);
          ep.hidden = !m;
          if (m) hit = true;
          if (q && m) ep.classList.add("open");
        });
        sec.hidden = !hit;
        if (hit) any = true;
      });
      el.querySelector("#docEmpty").hidden = any || !q;
    });
    const spy = () => {
      let cur = "intro";
      el.querySelectorAll(".dsec[id]").forEach((s) => { if (!s.hidden && s.getBoundingClientRect().top < 140) cur = s.id; });
      el.querySelectorAll("[data-nav]").forEach((a) => a.classList.toggle("on", a.dataset.nav === cur));
    };
    window.addEventListener("scroll", spy, { passive: true });
    spy();
    if (location.hash.length > 1 && standalone) setTimeout(() => el.querySelector(location.hash.replace(/[^#\w-]/g, ""))?.scrollIntoView(), 50);
  }

  const VERIFY = {
    node: `import crypto from "node:crypto";\n\napp.post("/zelon", express.raw({ type: "*/*" }), (req, res) => {\n  const expected = "sha256=" + crypto\n    .createHmac("sha256", process.env.ZELON_WEBHOOK_SECRET)\n    .update(req.body)\n    .digest("hex");\n  const sig = req.get("X-Zelon-Signature") || "";\n  const ok = sig.length === expected.length &&\n    crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(expected));\n  if (!ok) return res.sendStatus(401);\n  const event = JSON.parse(req.body);\n  // handle event.type …\n  res.sendStatus(200);\n});`,
    python: `import hmac, hashlib, os\nfrom flask import Flask, request, abort\n\napp = Flask(__name__)\n\n@app.post("/zelon")\ndef zelon():\n    raw = request.get_data()\n    expected = "sha256=" + hmac.new(\n        os.environ["ZELON_WEBHOOK_SECRET"].encode(), raw, hashlib.sha256\n    ).hexdigest()\n    if not hmac.compare_digest(request.headers.get("X-Zelon-Signature", ""), expected):\n        abort(401)\n    event = request.get_json()\n    # handle event["type"] …\n    return "", 200`,
    php: `<?php\n$raw = file_get_contents("php://input");\n$expected = "sha256=" . hash_hmac("sha256", $raw, getenv("ZELON_WEBHOOK_SECRET"));\n$sig = $_SERVER["HTTP_X_ZELON_SIGNATURE"] ?? "";\nif (!hash_equals($expected, $sig)) {\n  http_response_code(401);\n  exit;\n}\n$event = json_decode($raw, true);\n// handle $event["type"] …\nhttp_response_code(200);`,
  };

  const registry = new Map();
  SECTIONS.forEach((s) => s.eps.forEach((e, i) => registry.set(s.id + "-" + i, { e })));
  function findEp(epEl) {
    if (epEl?.id && registry.has(epEl.id)) return { e: registry.get(epEl.id).e };
    // recipe blocks: rebuild from the visible title
    const title = epEl?.querySelector(".path")?.textContent;
    const rec = SECTIONS[0].examples.find(([t]) => t === title);
    return { e: { m: "POST", p: "/messages", body: rec?.[1] }, body: rec?.[1] };
  }

  window.ZelonDocs = { render };
})();
