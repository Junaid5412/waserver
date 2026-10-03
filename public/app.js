const root = document.querySelector("#root");
let user = null,
  instances = [],
  selected = null,
  view = "overview",
  tab = "connection",
  timer;
const esc = (v) =>
  String(v ?? "").replace(
    /[&<>"']/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        c
      ],
  );
const brand =
  '<a class="brand" href="/"><span class="mark">Z</span>Zelon<span>API</span></a>';
async function api(url, method = "GET", body, headers = {}) {
  const r = await fetch("/api" + url, {
    method,
    headers: {
      ...(body ? { "Content-Type": "application/json" } : {}),
      ...headers,
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await r.json();
  if (!r.ok) throw Error(data.error || "Request failed");
  return data;
}
function toast(s) {
  const el = document.querySelector("#toast");
  el.textContent = s;
  el.style.display = "block";
  setTimeout(() => (el.style.display = "none"), 5000);
}
function on(id, fn) {
  document.getElementById(id)?.addEventListener("click", async (e) => {
    const b = e.currentTarget;
    b.disabled = true;
    try {
      await fn(e);
    } catch (err) {
      toast(err.message);
    } finally {
      b.disabled = false;
    }
  });
}
function form(id, fn) {
  document.getElementById(id)?.addEventListener("submit", async (e) => {
    e.preventDefault();
    const b = e.target.querySelector("button[type=submit]");
    if (b) b.disabled = true;
    try {
      await fn(Object.fromEntries(new FormData(e.target)), e);
    } catch (err) {
      toast(err.message);
    } finally {
      if (b) b.disabled = false;
    }
  });
}
function landing() {
  root.innerHTML = `<header>${brand}<nav><a href="#features">Features</a><a href="#developers">Developers</a><a href="#faq">FAQ</a><a class="btn bright" href="/console">Open console</a></nav></header><main><section class="hero"><div><div class="eyebrow">Messaging infrastructure, yours to own</div><h1>Your applications.<br>Your WhatsApp.<br><em>Connected.</em></h1><p>Build conversations into your workflow. Connect a number, create an API key, and send messages from your own applications.</p><div class="actions"><a class="btn bright" href="/console">Open your console</a><a class="btn" href="#developers">Explore the API</a></div><div class="hint">Self-hosted · Persistent sessions · No Zelon subscription tiers</div></div><div class="codepanel"><div class="codehead"><span>POST /api/instances/:id/messages</span><span>REST API</span></div><pre>curl -X POST "$ZELON_URL/api/instances/$ID/messages" \\\n  -H "Authorization: Bearer $API_KEY" \\\n  -H "Content-Type: application/json" \\\n  -d '{\n    "to": "+97450000000",\n    "type": "text",\n    "text": "Your booking is confirmed."\n  }'</pre><div class="response">Example response · 202 Accepted<br>{ "id": "…", "status": "queued" }</div></div></section><section id="features" class="section"><div class="eyebrow">One connection. More possibilities.</div><h2>The building blocks of better conversations.</h2><div class="featuregrid">${[
    [
      "01",
      "Messages & media",
      "Send text, images, video, audio and documents through a single API.",
    ],
    [
      "02",
      "Instance management",
      "Link WhatsApp with a QR code and manage connections from your console.",
    ],
    [
      "03",
      "Signed webhooks",
      "Receive incoming messages, connection events and receipts with retry handling.",
    ],
    [
      "04",
      "Groups & contacts",
      "Create groups, manage participants and check WhatsApp number availability.",
    ],
    [
      "05",
      "Scheduling & history",
      "Queue messages for later and inspect persistent send and event records.",
    ],
    [
      "06",
      "Keys & session security",
      "Use scoped API keys and encrypted WhatsApp credentials stored in your database.",
    ],
  ]
    .map(
      ([n, h, p]) =>
        `<article class="card"><div class="number">${n}</div><h3>${h}</h3><p>${p}</p></article>`,
    )
    .join(
      "",
    )}</div></section><section id="developers" class="section"><div class="strip"><div><h3>From your first request to your daily workflow.</h3><p>Use any language that speaks HTTP. API examples are available inside your console.</p></div><a href="/console" class="btn primary">Go to developer console</a></div></section><section id="faq" class="section"><h2>A few things to know.</h2><details><summary>Do I need a WhatsApp number?</summary><p>Yes. Connect your number using WhatsApp’s Linked devices screen and the QR code in your console.</p></details><details><summary>Is Zelon API free?</summary><p>This self-hosted application has no subscription tiers. Hosting, database and any external services have their own costs. WhatsApp still applies its own limits.</p></details><details><summary>Is this the official WhatsApp Business API?</summary><p>No. This connection uses the open-source Baileys WhatsApp Web integration. It is independent of Meta and GREEN-API. Connect numbers you control and follow WhatsApp’s terms.</p></details><details><summary>Does my data survive redeployment?</summary><p>Production data and encrypted connection credentials are stored in your configured private SQLite directory or MySQL database. Keep your database and encryption key when redeploying.</p></details></section></main><footer><span>© ${new Date().getFullYear()} Zelon API</span><span>Independent WhatsApp integration platform</span></footer>`;
}
function login() {
  root.innerHTML = `<header>${brand}<nav><a href="/">Back to website</a></nav></header><main class="auth"><section class="card"><div class="eyebrow">Developer console</div><h1>Welcome back.</h1><p class="hint">Sign in to manage your WhatsApp connections.</p><form id="login"><label for="email">Email address</label><input id="email" name="email" type="email" autocomplete="username" required><label for="password">Password</label><input id="password" name="password" type="password" autocomplete="current-password" required><div class="actions"><button type="submit" class="btn primary">Sign in</button></div><p class="hint">Access is provisioned by your platform administrator.</p></form></section></main>`;
  form("login", async (d) => {
    await api("/login", "POST", d);
    await load();
  });
}
async function load() {
  user = await api("/me");
  instances = await api("/instances");
  if (selected) selected = instances.find((x) => x.id === selected.id) || null;
  shell();
}
function shell() {
  clearInterval(timer);
  root.innerHTML = `<div class="shell"><aside class="sidebar">${brand}<nav>${[
    ["overview", "Overview"],
    ["instances", "Instances"],
    ["docs", "API documentation"],
    ["account", "Account"],
    ...(user.role === "admin"
      ? [
          ["users", "User accounts"],
          ["system", "System health"],
        ]
      : []),
  ]
    .map(
      ([id, title]) =>
        `<button data-view="${id}" class="${view === id ? "active" : ""}">${title}</button>`,
    )
    .join(
      "",
    )}<button id="logout">Sign out</button></nav><div class="account">${esc(user.email)}</div></aside><main class="workspace" id="workspace"></main></div>`;
  document.querySelectorAll("[data-view]").forEach(
    (b) =>
      (b.onclick = () => {
        view = b.dataset.view;
        selected = null;
        render();
        document
          .querySelectorAll("[data-view]")
          .forEach((x) => x.classList.toggle("active", x === b));
      }),
  );
  on("logout", async () => {
    await api("/logout", "POST");
    login();
  });
  render();
}
function cards() {
  return instances.length
    ? `<div class="instancegrid">${instances.map((x) => `<article class="card"><div class="row"><h3>${esc(x.name)}</h3><span class="status ${esc(x.status)}">${esc(x.status.replaceAll("_", " "))}</span></div><p class="hint">${esc(x.phone || "No number linked yet")}</p><p class="hint">${esc(x.id)}</p><button class="btn" data-instance="${x.id}">Manage instance</button></article>`).join("")}</div>`
    : `<div class="empty"><h2>Your first connection starts here.</h2><p>Create an instance, then link your WhatsApp number.</p><button id="first" class="btn primary">Create instance</button></div>`;
}
function render() {
  clearInterval(timer);
  const w = document.querySelector("#workspace");
  if (selected) {
    instancePage();
    return;
  }
  if (view === "docs") {
    docs();
    return;
  }
  if (view === "system") {
    w.innerHTML = '<div class="loading">Checking system…</div>';
    api("/admin/system")
      .then((d) => {
        w.innerHTML =
          '<h1>System health</h1><div class="card"><p>Database: ' +
          esc(d.database) +
          "</p><p>Uptime: " +
          d.uptimeSeconds +
          " seconds · Node " +
          esc(d.nodeVersion) +
          '</p><pre class="doccode">' +
          esc(JSON.stringify(d.counts, null, 2)) +
          "</pre></div>";
      })
      .catch((e) => (w.textContent = e.message));
    return;
  }
  if (view === "users") {
    usersPage();
    return;
  }
  if (view === "account") {
    accountPage();
    return;
  }
  w.innerHTML = `<div class="top"><div><div class="eyebrow">Your messaging workspace</div><h1>${view === "overview" ? "Overview" : "WhatsApp instances"}</h1><p>Connect and manage your numbers.</p></div><button id="new" class="btn primary">+ New instance</button></div>${view === "overview" ? `<div class="metrics"><div class="card metric"><div class="hint">Instances</div><div class="value">${instances.length}</div></div><div class="card metric"><div class="hint">Connected</div><div class="value">${instances.filter((x) => x.status === "connected").length}</div></div><div class="card metric"><div class="hint">Needs setup</div><div class="value">${instances.filter((x) => x.status !== "connected").length}</div></div></div>` : ""}${cards()}`;
  w.insertAdjacentHTML(
    "beforeend",
    '<div class="actions"><button class="btn" id="showArchived">Archived instances</button></div><div id="archivedRows"></div>',
  );
  on("showArchived", async () => {
    const rows = await api("/archived-instances");
    document.querySelector("#archivedRows").innerHTML =
      rows
        .map(
          (x) =>
            `<div class="record row"><strong>${esc(x.name)}</strong><button class="btn" data-restore="${x.id}">Restore</button></div>`,
        )
        .join("") || "<p>No archived instances.</p>";
    document.querySelectorAll("[data-restore]").forEach(
      (b) =>
        (b.onclick = async () => {
          try {
            await api(
              "/instances/" + b.dataset.restore + "/restore",
              "POST",
              {},
            );
            await load();
          } catch (e) {
            toast(e.message);
          }
        }),
    );
  });
  on("new", newInstance);
  on("first", newInstance);
  document.querySelectorAll("[data-instance]").forEach(
    (b) =>
      (b.onclick = () => {
        selected = instances.find((x) => x.id === b.dataset.instance);
        tab = "connection";
        render();
      }),
  );
}
function newInstance() {
  const modal = document.createElement("div");
  modal.className = "modal";
  modal.setAttribute("role", "dialog");
  modal.setAttribute("aria-modal", "true");
  modal.setAttribute("aria-label", "Create WhatsApp instance");
  modal.innerHTML = `<section class="card"><h2>Create an instance</h2><form id="create"><label for="name">Instance name</label><input id="name" name="name" maxlength="60" placeholder="Customer support" required><div class="actions"><button class="btn primary" type="submit">Create instance</button><button class="btn" type="button" id="cancel">Cancel</button></div></form></section>`;
  root.append(modal);
  document.querySelector("#name").focus();
  on("cancel", () => modal.remove());
  form("create", async (d) => {
    await api("/instances", "POST", d);
    modal.remove();
    await load();
  });
}
function instancePage() {
  const x = selected,
    base = "/instances/" + x.id,
    w = document.querySelector("#workspace");
  w.innerHTML = `<div class="top"><div><button class="btn" id="back">All instances</button><h1>${esc(x.name)}</h1><button class="btn" id="rename">Rename</button><button class="btn danger" id="archiveInstance">Archive</button><p><span class="status ${esc(x.status)}">${esc(x.status.replaceAll("_", " "))}</span> ${esc(x.phone || "")}</p></div></div><div class="tabs">${[
    ["connection", "Connection"],
    ["send", "Send message"],
    ["history", "Message history"],
    ["events", "Incoming events"],
    ["webhooks", "Webhooks"],
    ["groups", "Groups & numbers"],
    ...(window.ZelonFeatures?.tabs || []),
  ]
    .map(
      ([id, title]) =>
        `<button class="btn ${tab === id ? "active" : ""}" data-tab="${id}">${title}</button>`,
    )
    .join("")}</div><section id="panel" class="panel"></section>`;
  on("back", () => {
    selected = null;
    render();
  });
  on("rename", () => renameInstance(base, x));
  on("archiveInstance", () => {
    const m = modal(
      '<h2>Archive instance?</h2><p>This stops its connection and revokes API access. Your records remain available after restoring the instance.</p><div class="actions"><button class="btn danger" id="confirmArchive">Archive instance</button><button class="btn" id="cancelArchive">Cancel</button></div>',
    );
    on("cancelArchive", m.close);
    on("confirmArchive", async () => {
      await api(base + "/archive", "POST", {});
      selected = null;
      m.close();
      await load();
    });
  });
  document.querySelectorAll("[data-tab]").forEach(
    (b) =>
      (b.onclick = () => {
        tab = b.dataset.tab;
        render();
      }),
  );
  const p = document.querySelector("#panel");
  if (window.ZelonFeatures?.tabs.some(([id]) => id === tab)) {
    window.ZelonFeatures.render({
      tab,
      base,
      p,
      api,
      esc,
      form,
      on,
      toast,
    }).catch((e) => {
      p.textContent = e.message;
    });
    return;
  }
  if (tab === "connection") {
    p.innerHTML = `<div class="split"><div class="card"><h3>Link your WhatsApp number</h3><p class="hint">Open WhatsApp → Linked devices → Link a device. Scan the QR code displayed here.</p><div id="qrbox"></div><div class="actions"><button id="connect" class="btn primary">Connect number</button><button id="disconnect" class="btn danger">Log out number</button></div></div><div class="card"><h3>API access</h3><p class="hint">Generate an API key scoped to this instance. It is shown once. Generating a new key revokes the previous one.</p><button id="key" class="btn">Generate API key</button><div id="keybox"></div><p class="hint">Instance ID</p><div class="key">${esc(x.id)}</div></div></div>`;
    on("connect", async () => {
      await api(base + "/connect", "POST", {});
      toast("Connection started. Waiting for QR code.");
      await poll();
    });
    on("disconnect", async () => {
      await api(base + "/disconnect", "POST", {});
      await load();
    });
    on("key", async () => {
      const d = await api(base + "/key", "POST", {});
      document.querySelector("#keybox").innerHTML =
        `<p class="hint">Save this key securely. It will not be shown again.</p><div class="key">${esc(d.key)}</div>`;
    });
    async function poll() {
      try {
        const d = await api(base + "/qr");
        if (selected?.id !== x.id || tab !== "connection") return;
        const box = document.querySelector("#qrbox");
        box.innerHTML = d.qr
          ? `<img class="qr" src="${esc(d.qr)}" alt="WhatsApp linking QR code">`
          : `<p class="hint">${esc(d.error || (d.status === "connected" ? "Your number is connected." : ["connecting", "reconnecting"].includes(d.status) ? "Connecting to WhatsApp. Waiting for QR code…" : "Select Connect number to generate a QR code."))}</p>`;
        if (d.status !== x.status) {
          instances = await api("/instances");
          selected = instances.find((i) => i.id === x.id);
          if (d.status === "connected") render();
        }
      } catch (e) {
        toast(e.message);
      }
    }
    poll();
    timer = setInterval(poll, 3000);
  }
  if (tab === "send") {
    p.innerHTML = `<div class="card"><h3>Compose a message</h3><form id="send"><label for="to">Recipient</label><input id="to" name="to" placeholder="+97450000000 or group JID" required><label for="type">Message type</label><select id="type" name="type"><option value="text">Text</option><option value="image">Image</option><option value="video">Video</option><option value="audio">Audio</option><option value="document">Document</option><option value="sticker">Sticker (WebP)</option><option value="location">Location</option><option value="contact">Contact</option><option value="poll">Poll</option></select><div id="fields"></div><label for="sendAt">Schedule (optional, local time)</label><input id="sendAt" name="sendAt" type="datetime-local"><div class="actions"><button type="submit" class="btn primary">Queue message</button></div><p class="hint">Queued messages send when the linked number is connected. Media files use encrypted chunk uploads; default maximum 100 MB.</p></form></div>`;
    function fields() {
      const t = document.querySelector("#type").value;
      document.querySelector("#fields").innerHTML =
        `${["text", "image", "video", "document", "poll"].includes(t) ? `<label for="text">${t === "poll" ? "Question" : "Message or caption"}</label><textarea id="text" name="text" ${["text", "poll"].includes(t) ? "required" : ""}></textarea>` : ""}${["image", "video", "audio", "document", "sticker"].includes(t) ? '<label for="file">Media file (default maximum 100 MB)</label><input id="file" type="file" required>' : ""}${t === "location" ? '<label for="latitude">Latitude</label><input name="latitude" id="latitude" type="number" step="any" min="-90" max="90" required><label for="longitude">Longitude</label><input name="longitude" id="longitude" type="number" step="any" min="-180" max="180" required>' : ""}${t === "contact" ? '<label for="name">Contact name</label><input id="name" name="name" required><label for="phone">Contact phone</label><input id="phone" name="phone" required>' : ""}${t === "poll" ? '<label for="options">Options (one per line)</label><textarea id="options" name="options" required></textarea>' : ""}`;
    }
    fields();
    const sendForm = document.querySelector("#send");
    sendForm.dataset.requestKey = crypto.randomUUID();
    sendForm.addEventListener("input", () => {
      sendForm.dataset.requestKey = crypto.randomUUID();
    });
    document.querySelector("#type").onchange = fields;
    form("send", async (d) => {
      if (d.sendAt) d.sendAt = new Date(d.sendAt).toISOString();
      else delete d.sendAt;
      if (d.latitude) d.latitude = Number(d.latitude);
      if (d.longitude) d.longitude = Number(d.longitude);
      if (d.options)
        d.options = d.options
          .split("\n")
          .map((s) => s.trim())
          .filter(Boolean);
      const f = document.querySelector("#file")?.files[0];
      if (f) {
        d.mediaId = await window.ZelonFeatures.upload(base, f, api, toast);
      }
      const result = await api(base + "/messages", "POST", d, {
        "Idempotency-Key": sendForm.dataset.requestKey,
      });
      toast("Message " + result.status);
      tab = "history";
      render();
    });
  }
  if (["history", "events"].includes(tab)) {
    const currentTab = tab;
    let records = [];
    const endpoint = base + (tab === "history" ? "/messages" : "/events");
    async function fetchRecords(older = false) {
      const last = records.at(-1);
      const query =
        older && last
          ? "?limit=25&before=" +
            encodeURIComponent(last.createdAt) +
            "&beforeId=" +
            encodeURIComponent(last.id)
          : "?limit=25";
      const rows = await api(endpoint + query);
      if (selected?.id !== x.id || tab !== currentTab) return;
      records = older ? [...records, ...rows] : rows;
      p.innerHTML = `<div class="card"><div class="row"><h3>${currentTab === "history" ? "Outgoing messages" : "Incoming events"}</h3><button id="refresh" class="btn">Refresh</button></div><p class="hint">Newest records first.</p>${records.length ? `<div class="tablewrap"><table><thead><tr><th>Time</th><th>${currentTab === "history" ? "Recipient" : "Event"}</th><th>Details</th><th>Status</th><th>Action</th></tr></thead><tbody>${records.map((r) => `<tr><td>${esc(new Date(r.createdAt).toLocaleString())}</td><td>${esc(r.to || r.type)}</td><td>${esc(r.text || JSON.stringify(r.data || {}))}</td><td><span class="status ${esc(r.status || "")}">${esc(r.status || "received")}</span></td><td>${r.status === "queued" ? `<button class="btn" data-cancel="${esc(r.id)}">Cancel</button>` : ""}</td></tr>`).join("")}</tbody></table></div>` : '<p class="hint">No records yet.</p>'}${rows.length === 25 ? '<div class="actions"><button class="btn" id="older">Load older records</button></div>' : ""}</div>`;
      on("refresh", () => fetchRecords());
      on("older", () => fetchRecords(true));
      document.querySelectorAll("[data-cancel]").forEach(
        (b) =>
          (b.onclick = async () => {
            try {
              await api(
                base + "/messages/" + b.dataset.cancel + "/cancel",
                "POST",
                {},
              );
              toast("Queued message cancelled");
              await fetchRecords();
            } catch (e) {
              toast(e.message);
            }
          }),
      );
    }
    p.innerHTML = '<div class="loading">Loading records…</div>';
    fetchRecords().catch((e) => {
      p.textContent = e.message;
    });
  }

  if (tab === "webhooks") {
    p.innerHTML = `<div class="card"><h3>Receive events in your application</h3><p class="hint">Zelon sends HTTPS POST requests. Verify X-Zelon-Signature with HMAC SHA-256 over the raw request body. Deduplicate using the event ID.</p><form id="webhook"><label for="url">Webhook URL</label><input type="url" id="url" name="url" value="${esc(x.webhookUrl)}" placeholder="https://your-app.example/webhooks/zelon"><div class="actions"><button class="btn primary" type="submit">Save webhook</button></div></form><div id="secret"></div><p class="hint">Leave the URL empty to disable delivery. Failed requests retry up to eight times.</p><button class="btn" id="rotateHook">Rotate signing secret</button><div id="deliveries"></div></div>`;
    form("webhook", async (d) => {
      const r = await api(base + "/webhook", "PUT", d);
      selected.webhookUrl = r.url;
      document.querySelector("#secret").innerHTML =
        `<p class="hint">Webhook signing secret</p><div class="key">${esc(r.secret)}</div>`;
      toast("Webhook saved");
    });
    on("rotateHook", async () => {
      const r = await api(base + "/webhook/rotate", "POST", {});
      document.querySelector("#secret").textContent = r.secret;
      toast("Signing secret rotated. Update your receiver.");
    });
    api(base + "/webhooks")
      .then((rows) => {
        document.querySelector("#deliveries").innerHTML =
          "<h3>Delivery log</h3>" +
          rows
            .map(
              (r) =>
                `<p><span class="status ${esc(r.status)}">${esc(r.status)}</span> ${r.attempts} retries · ${esc(r.error || r.id)} ${r.status === "failed" ? `<button class="btn" data-hook="${r.id}">Retry</button>` : ""}</p>`,
            )
            .join("");
        document.querySelectorAll("[data-hook]").forEach(
          (b) =>
            (b.onclick = async () => {
              try {
                await api(
                  base + "/webhooks/" + b.dataset.hook + "/retry",
                  "POST",
                  {},
                );
                toast("Webhook requeued");
              } catch (e) {
                toast(e.message);
              }
            }),
        );
      })
      .catch((e) => toast(e.message));
  }
  if (tab === "groups") {
    p.innerHTML = `<div class="split"><div class="card"><h3>Check a WhatsApp number</h3><form id="check"><label for="phone">Phone number</label><input name="phone" id="phone" placeholder="+97450000000" required><div class="actions"><button type="submit" class="btn primary">Check number</button></div></form><div id="result"></div></div><div class="card"><h3>Your groups</h3><button id="groups" class="btn">Load groups</button><div id="groupList"></div></div></div><div class="card"><h3>Create a group</h3><form id="groupCreate"><label for="groupName">Group name</label><input id="groupName" name="name" required><label for="participants">Participants (one phone number per line)</label><textarea name="participants" id="participants" required></textarea><div class="actions"><button type="submit" class="btn primary">Create group</button></div></form></div><div class="card"><h3>Manage group members</h3><form id="members"><label for="groupId">Group JID</label><input id="groupId" name="groupId" placeholder="123456789@g.us" required><label for="memberPhones">Participants (one phone per line)</label><textarea id="memberPhones" name="participants" required></textarea><label for="memberAction">Action</label><select id="memberAction" name="action"><option value="add">Add</option><option value="remove">Remove</option><option value="promote">Promote to admin</option><option value="demote">Remove admin role</option></select><div class="actions"><button class="btn primary" type="submit">Update members</button></div></form></div>`;
    form("members", async (d) => {
      const group = d.groupId;
      delete d.groupId;
      d.participants = d.participants
        .split("\n")
        .map((s) => s.trim())
        .filter(Boolean);
      await api(
        base + "/groups/" + encodeURIComponent(group) + "/participants",
        "PUT",
        d,
      );
      toast("Group members updated");
    });
    form("check", async (d) => {
      const r = await api(base + "/check-number", "POST", d);
      document.querySelector("#result").textContent = r[0]?.exists
        ? "This number is on WhatsApp."
        : "No WhatsApp account found.";
    });
    on("groups", async () => {
      const r = await api(base + "/groups");
      document.querySelector("#groupList").innerHTML =
        Object.values(r)
          .map(
            (g) =>
              `<p><strong>${esc(g.subject)}</strong><br><span class="hint">${esc(g.id)} · ${g.participants.length} participants</span></p>`,
          )
          .join("") || "<p>No groups found.</p>";
    });
    form("groupCreate", async (d) => {
      d.participants = d.participants
        .split("\n")
        .map((s) => s.trim())
        .filter(Boolean);
      const r = await api(base + "/groups", "POST", d);
      toast("Group created: " + r.id);
    });
  }
}
function docs() {
  document.querySelector("#workspace").innerHTML =
    `<div class="top"><div><div class="eyebrow">Developer resources</div><h1>API documentation</h1><p>Connect your applications with scoped Bearer authentication.</p></div></div><div class="panel card"><h3>Authentication</h3><p>Generate a key in your instance’s Connection tab. Include it in the Authorization header. Keys work only for their assigned instance. Send a unique Idempotency-Key header when queuing each message; retries with that same key reuse the existing job, preventing duplicate queue entries.</p><pre class="doccode">Authorization: Bearer YOUR_API_KEY</pre><h3>Send a message</h3><pre class="doccode">POST /api/instances/INSTANCE_ID/messages\nContent-Type: application/json\n\n{\n  "to": "+97450000000",\n  "type": "text",\n  "text": "Hello from Zelon API"\n}</pre><p class="hint">Response: 202 with a message ID and queued status. Scheduling uses sendAt in ISO 8601 UTC. Media uses base64 data, mimetype and filename. Use mediaId from a finalized chunk upload (100 MB default).</p><p><a class="btn" href="/api-reference.html" target="_blank" rel="noopener">Complete API reference & SDKs</a></p><h3>Available operations</h3><div class="tablewrap"><table><tr><th>Method</th><th>Instance endpoint</th><th>Purpose</th></tr>${[
      ["POST", "/messages", "Queue text, media, contacts, location or polls"],
      ["GET", "/messages", "Read outgoing history"],
      ["GET", "/events", "Read incoming messages and receipts"],
      ["POST", "/check-number", 'Check a phone number: { "phone": "+974…" }'],
      ["GET", "/groups", "List groups"],
      [
        "POST",
        "/groups",
        'Create: { "name": "Team", "participants": ["+974…"] }',
      ],
      [
        "PUT",
        "/groups/:group/participants",
        "Update members; action: add, remove, promote, demote",
      ],
      ["GET", "/avatar?phone=+974…", "Fetch a profile picture URL"],
    ]
      .map((r) => `<tr>${r.map((c) => `<td>${esc(c)}</td>`).join("")}</tr>`)
      .join(
        "",
      )}</table></div><h3>Webhooks</h3><p>Configure your public HTTPS endpoint in the Webhooks tab. Verify the raw body signature using the displayed secret. Delivery is at least once; deduplicate by event ID. Event types: connection, message, receipt.</p><h3>Failure handling</h3><p>400: invalid input. 401: invalid credentials. 404: inaccessible instance. 409: conflicting state or idempotency key. 429: request rate exceeded. Messages interrupted during a send are marked unknown; check delivery before retrying to prevent duplicates.</p><h3>Deployment contract</h3><p>Run one server process per database. Message and event history use indexed database queries and cursor pagination. Your configured SQLite/MySQL database stores records and encrypted WhatsApp credentials. Preserve ENCRYPTION_KEY across deployments. Shared inbox, status publishing, contacts, auto replies, consent-based campaigns, encrypted large media and SDK examples are included. Read the complete API reference and deployment guide in GitHub.</p></div>`;
}
async function boot() {
  if (location.pathname === "/") {
    landing();
    return;
  }
  root.innerHTML = '<div class="loading">Opening your workspace…</div>';
  try {
    await load();
  } catch (e) {
    login();
  }
}
boot();

function modal(content) {
  const overlay = document.createElement("div");
  overlay.className = "modal";
  overlay.setAttribute("role", "dialog");
  overlay.setAttribute("aria-modal", "true");
  overlay.innerHTML = '<section class="card">' + content + "</section>";
  root.append(overlay);
  const close = () => overlay.remove();
  overlay.addEventListener("keydown", (e) => {
    if (e.key === "Escape") close();
    if (e.key === "Tab") {
      const focusable = [
        ...overlay.querySelectorAll("button,input,select,textarea,a"),
      ];
      const first = focusable[0],
        last = focusable.at(-1);
      if (e.shiftKey && document.activeElement === first) {
        e.preventDefault();
        last.focus();
      } else if (!e.shiftKey && document.activeElement === last) {
        e.preventDefault();
        first.focus();
      }
    }
  });
  overlay.querySelector("input,button")?.focus();
  return { overlay, close };
}
function renameInstance(base, x) {
  const m = modal(
    `<h2>Rename instance</h2><form id="renameForm"><label for="newName">Instance name</label><input id="newName" name="name" value="${esc(x.name)}" maxlength="60" required><div class="actions"><button class="btn primary" type="submit">Save name</button><button class="btn" id="closeRename" type="button">Cancel</button></div></form>`,
  );
  on("closeRename", m.close);
  form("renameForm", async (d) => {
    await api(base + "/name", "PUT", d);
    m.close();
    await load();
  });
}
async function usersPage() {
  const w = document.querySelector("#workspace");
  w.innerHTML = '<div class="loading">Loading accounts…</div>';
  try {
    const users = await api("/admin/users");
    if (view !== "users") return;
    w.innerHTML = `<div class="top"><div><div class="eyebrow">Administration</div><h1>User accounts</h1><p>Provision access to each user’s own messaging workspace.</p></div><button class="btn primary" id="addUser" aria-label="Add user">+ Add user</button></div><div class="instancegrid">${users.map((u) => `<article class="card"><div class="row"><h3>${esc(u.email)}</h3><span class="status ${u.disabled ? "failed" : "connected"}">${u.disabled ? "Disabled" : "Active"}</span></div><p class="hint">${esc(u.role)}${u.id === user.id ? " · Your account" : ""}</p>${u.id !== user.id ? `<button class="btn" data-user="${u.id}" data-disabled="${!u.disabled}">${u.disabled ? "Enable account" : "Disable account"}</button><button class="btn" data-reset-user="${u.id}">Reset password</button>` : ""}</article>`).join("")}</div>`;
    document.querySelectorAll("[data-reset-user]").forEach(
      (b) =>
        (b.onclick = () => {
          const m = modal(
            '<h2>Reset user password?</h2><p>The account will receive a new initial password and existing sessions will be revoked.</p><div class="actions"><button class="btn primary" id="confirmReset">Reset password</button><button class="btn" id="cancelReset">Cancel</button></div>',
          );
          on("cancelReset", m.close);
          on("confirmReset", async () => {
            const r = await api(
              "/admin/users/" + b.dataset.resetUser + "/reset-password",
              "POST",
              {},
            );
            m.overlay.innerHTML =
              '<section class="card"><h2>New password</h2><p>Save this securely. Shown once.</p><div class="key">' +
              esc(r.password) +
              '</div><button class="btn" id="closeReset">Done</button></section>';
            on("closeReset", m.close);
          });
        }),
    );
    on("addUser", () => {
      const m = modal(
        '<h2>Add user</h2><form id="addUserForm"><label for="userEmail">Email address</label><input id="userEmail" name="email" type="email" maxlength="254" required><label for="userRole">Access role</label><select id="userRole" name="role"><option value="user">User</option><option value="admin">Administrator</option></select><p class="hint">A secure initial password will be generated and shown once.</p><div class="actions"><button type="submit" class="btn primary">Create account</button><button type="button" class="btn" id="closeUser">Cancel</button></div></form>',
      );
      on("closeUser", m.close);
      form("addUserForm", async (d) => {
        const r = await api("/admin/users", "POST", d);
        m.overlay.innerHTML = `<section class="card"><h2>Account created</h2><p>${esc(r.email)}</p><p class="hint">Save this initial password securely. It is shown once.</p><div class="key">${esc(r.password)}</div><div class="actions"><button class="btn primary" id="doneUser">Done</button></div></section>`;
        on("doneUser", () => {
          m.close();
          usersPage();
        });
      });
    });
    document.querySelectorAll("[data-user]").forEach(
      (b) =>
        (b.onclick = async () => {
          try {
            await api("/admin/users/" + b.dataset.user, "PUT", {
              disabled: b.dataset.disabled === "true",
            });
            await usersPage();
          } catch (e) {
            toast(e.message);
          }
        }),
    );
  } catch (e) {
    w.textContent = e.message;
  }
}

function accountPage() {
  document.querySelector("#workspace").innerHTML =
    `<div class="top"><div><h1>Your account</h1><p>${esc(user.email)}</p></div></div><div class="panel card"><h3>Change password</h3><p class="hint">Changing your password signs you out on every device.</p><form id="passwordForm"><label for="currentPassword">Current password</label><input id="currentPassword" name="currentPassword" type="password" autocomplete="current-password" required><label for="newPassword">New password</label><input id="newPassword" name="newPassword" type="password" autocomplete="new-password" minlength="12" maxlength="200" required><div class="actions"><button class="btn primary" type="submit">Change password</button></div></form></div>`;
  form("passwordForm", async (d) => {
    await api("/account/password", "PUT", d);
    toast("Password changed. Sign in with your new password.");
    login();
  });
}
