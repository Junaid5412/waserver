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
  root.innerHTML = `<header>${brand}<nav><a href="#features">Features</a><a href="#developers">Developers</a><a href="#faq">FAQ</a><a class="btn bright" href="/console">Open console</a></nav></header><main><section class="hero"><div><div class="eyebrow">Messaging infrastructure, yours to own</div><h1>Your applications.<br>Your WhatsApp.<br><em>Connected.</em></h1><p>Build conversations into your workflow. Connect a number, create an API key, and send messages from your own applications.</p><div class="actions"><a class="btn bright" href="/console">Open your console</a><a class="btn" href="#developers">Explore the API</a></div><div class="hint">Self-hosted · Persistent sessions · No Zelon subscription tiers</div></div><div class="codepanel"><div class="codehead"><span>POST /api/instances/:id/messages</span><span>REST API</span></div><pre>curl -X POST "$ZELON_URL/api/instances/$ID/messages" \\\n  -H "Authorization: Bearer $API_KEY" \\\n  -H "Content-Type: application/json" \\\n  -d '{\n    "to": "+97450000000",\n    "type": "text",\n    "text": "Your booking is confirmed."\n  }'</pre><div class="response">Example response · 202 Accepted<br>{ "id": "…", "status": "queued" }</div></div></section><section class="section stats"><div><strong>QR</strong><span>Link in seconds</span></div><div><strong>REST</strong><span>Simple JSON API</span></div><div><strong>3 SDKs</strong><span>Node, Python, PHP</span></div><div><strong>Own</strong><span>Self-hosted data</span></div></section><section id="features" class="section"><div class="eyebrow">One connection. More possibilities.</div><h2>The building blocks of better conversations.</h2><div class="featuregrid">${[
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
  root.onkeydown = null;
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
const ICONS = {
  home: '<path d="m3 10 9-7 9 7v10a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><path d="M9 22V12h6v10"/>',
  phone: '<rect x="5" y="2" width="14" height="20" rx="2"/><path d="M12 18h.01"/>',
  book: '<path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/>',
  users: '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>',
  activity: '<path d="M22 12h-4l-3 9L9 3l-3 9H2"/>',
  shield: '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>',
  logout: '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><path d="m16 17 5-5-5-5"/><path d="M21 12H9"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  check: '<path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><path d="m9 11 3 3L22 4"/>',
  alert: '<path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3z"/><path d="M12 9v4"/><path d="M12 17h.01"/>',
  arrowLeft: '<path d="m12 19-7-7 7-7"/><path d="M19 12H5"/>',
  chevron: '<path d="m9 18 6-6-6-6"/>',
  edit: '<path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z"/>',
  archive: '<rect x="2" y="3" width="20" height="5" rx="1"/><path d="M4 8v11a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8"/><path d="M10 12h4"/>',
  link: '<path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/>',
  chat: '<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>',
  bolt: '<path d="M13 2 3 14h9l-1 8 10-12h-9z"/>',
  qr: '<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><path d="M14 14h3v3h-3zM20 14v3M14 20h3M20 20v1"/>',
  key: '<circle cx="7.5" cy="15.5" r="4.5"/><path d="m10.7 12.3 9.3-9.3M16 7l3 3M14 9l2 2"/>',
  plug: '<path d="M12 22v-5"/><path d="M9 8V2"/><path d="M15 8V2"/><path d="M18 8v5a6 6 0 0 1-12 0V8z"/>',
};
const ico = (n, s = 20) => `<svg viewBox="0 0 24 24" width="${s}" height="${s}" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICONS[n] || ""}</svg>`;
function shell() {
  clearInterval(timer);
  const items = [
    ["Main", [["overview", "Overview", "home"], ["instances", "WhatsApp instances", "phone"], ["docs", "API docs", "book"]]],
    ...(user.role === "admin" ? [["Admin", [["users", "User accounts", "users"], ["system", "System health", "activity"]]]] : []),
    ["Account", [["account", "Account & security", "shield"]]],
  ];
  const navButton = ([id, title, icon]) => `<button class="nav-item ${view === id ? "active" : ""}" data-view="${id}" title="${title}">${ico(icon)}<span class="nav-text">${title}</span></button>`;
  const short = { overview: "Home", instances: "Numbers", docs: "Docs", users: "Users", system: "Health", account: "Account" };
  const bottom = items.flatMap(([, list]) => list).map(([id, , icon]) => `<button class="bn-item ${view === id ? "active" : ""}" data-view="${id}">${ico(icon, 22)}<span>${short[id]}</span></button>`).join("");
  root.innerHTML = `<div class="shell"><aside class="sidebar" id="consoleSidebar">${brand}<nav aria-label="Console navigation">${items.map(([label, list]) => `<div class="nav-group"><div class="nav-label">${label}</div>${list.map(navButton).join("")}</div>`).join("")}</nav><button class="nav-item signout" id="logout" title="Sign out">${ico("logout")}<span class="nav-text">Sign out</span></button></aside><div class="main-col"><header class="topbar">${brand}<div class="topbar-title">Developer console</div><div class="topbar-user"><span class="avatar">${esc(user.email[0].toUpperCase())}</span><div class="who"><strong>${esc(user.role === "admin" ? "Administrator" : "Workspace member")}</strong><small>${esc(user.email)}</small></div><button class="icon-btn" id="logout2" aria-label="Sign out" title="Sign out">${ico("logout", 18)}</button></div></header><main class="workspace" id="workspace"></main></div><nav class="bottomnav" aria-label="Console navigation">${bottom}</nav></div>`;
  root.onkeydown = null;
  document.querySelectorAll("[data-view]").forEach(
    (b) =>
      (b.onclick = () => {
        view = b.dataset.view;
        selected = null;
        render();
        document
          .querySelectorAll("[data-view]")
          .forEach((x) => x.classList.toggle("active", x.dataset.view === view));
        window.scrollTo({ top: 0 });
      }),
  );
  const out = async () => {
    await api("/logout", "POST");
    login();
  };
  on("logout", out);
  on("logout2", out);
  render();
}
function summarize(data) {
  if (!data || typeof data !== "object") return "";
  return Object.entries(data)
    .filter(([k, v]) => v != null && v !== "" && k !== "message")
    .map(([k, v]) => {
      const label = k.replace(/([A-Z])/g, " $1").replace(/^./, (c) => c.toUpperCase());
      const val = typeof v === "object" ? (Array.isArray(v) ? v.length + " items" : Object.keys(v).length + " fields") : String(v);
      return label + ": " + (val.length > 80 ? val.slice(0, 77) + "…" : val);
    })
    .join(" · ");
}
const uptime = (s) => {
  s = Number(s) || 0;
  const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60);
  return d ? d + "d " + h + "h" : h ? h + "h " + m + "m" : m + "m";
};
const flat = (v) => (v && typeof v === "object" ? Object.entries(v).map(([k, n]) => k + ": " + n).join(", ") : String(v));
function cards(limit) {
  const list = limit ? instances.slice(0, limit) : instances;
  return list.length
    ? `<div class="inst-list">${list.map((x) => `<article class="inst-row"><span class="inst-avatar">${ico("phone", 20)}</span><div class="inst-info"><strong>${esc(x.name)}</strong><span class="hint">${esc(x.phone || "No number linked yet")}</span></div><span class="status ${esc(x.status)}">${esc(x.status.replaceAll("_", " "))}</span><button class="btn" data-instance="${x.id}">Manage${ico("chevron", 16)}</button></article>`).join("")}</div>`
    : `<div class="empty"><span class="ico-box big">${ico("phone", 28)}</span><h2>Your first connection starts here.</h2><p>Create an instance, then link your WhatsApp number.</p><button id="first" class="btn primary">${ico("plus", 18)}Create instance</button></div>`;
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
        w.innerHTML = `<div class="top"><div><div class="eyebrow">Administration</div><h1>System health</h1><p>Live status of the server and database.</p></div></div><div class="metrics"><div class="card metric"><span class="ico-box ok">${ico("check")}</span><div><div class="value">${esc(d.database)}</div><div class="hint">Database</div></div></div><div class="card metric"><span class="ico-box">${ico("activity")}</span><div><div class="value">${uptime(d.uptimeSeconds)}</div><div class="hint">Uptime</div></div></div><div class="card metric"><span class="ico-box warn">${ico("home")}</span><div><div class="value">${esc(d.nodeVersion)}</div><div class="hint">Node.js</div></div></div></div><section class="card"><h3>Records</h3><div class="tablewrap"><table><thead><tr><th>Type</th><th>Count</th></tr></thead><tbody>${Object.entries(d.counts || {}).map(([k, v]) => `<tr><td>${esc(k)}</td><td>${esc(flat(v))}</td></tr>`).join("")}</tbody></table></div></section>`;
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
  const connected = instances.filter((x) => x.status === "connected").length;
  const name = user.email.split("@")[0];
  w.innerHTML = view === "overview" ? `<section class="welcome"><div><div class="eyebrow">Overview</div><h1>Welcome back, ${esc(name)}</h1><p>Connect numbers, send messages and manage everything from one place.</p></div><button id="new" class="btn bright">${ico("plus", 18)}New instance</button></section>
  <div class="metrics"><div class="card metric"><span class="ico-box">${ico("phone")}</span><div><div class="value">${instances.length}</div><div class="hint">Instances</div></div></div><div class="card metric"><span class="ico-box ok">${ico("check")}</span><div><div class="value">${connected}</div><div class="hint">Connected</div></div></div><div class="card metric"><span class="ico-box warn">${ico("alert")}</span><div><div class="value">${instances.length - connected}</div><div class="hint">Needs setup</div></div></div></div>
  <div class="dash-grid"><section class="card"><div class="row card-title"><h3>Your instances</h3><button class="btn mini" data-view-link="instances">View all</button></div>${cards(5)}</section><section class="card"><h3>Quick start</h3><ol class="steps"><li><span>1</span><div><strong>Create an instance</strong><p>Give your WhatsApp connection a name.</p></div></li><li><span>2</span><div><strong>Scan the QR code</strong><p>WhatsApp → Linked devices → Link a device.</p></div></li><li><span>3</span><div><strong>Generate an API key</strong><p>Start sending from your application.</p></div></li></ol><button class="btn" data-view-link="docs">${ico("book", 16)}Read API docs</button></section></div>` : `<div class="top"><div><div class="eyebrow">Workspace</div><h1>WhatsApp instances</h1><p>Connect and manage your numbers.</p></div><button id="new" class="btn primary">${ico("plus", 18)}New instance</button></div><section class="card">${cards()}</section>`;
  document.querySelectorAll("[data-view-link]").forEach((b) => (b.onclick = () => document.querySelector('.sidebar [data-view="' + b.dataset.viewLink + '"]').click()));
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
  const groups = [
    ["Connect", "link", [["connection", "Connection"], ["tools", "Profile & settings"]]],
    ["Messaging", "chat", [["inbox", "Chats"], ["send", "Compose message"], ["history", "Message history"], ["contacts", "Contacts"], ["media", "Media library"], ["statuses", "Statuses"]]],
    ["Automation", "bolt", [["campaigns", "Campaigns"], ["automation", "Auto replies"], ["analytics", "Analytics"]]],
    ["Integration", "plug", [["webhooks", "Webhooks"], ["events", "Incoming events"]]],
    ["Groups", "users", [["groups", "Groups & numbers"], ["group-tools", "Group settings"]]],
  ];
  const activeGroup = groups.find(([, , items]) => items.some(([id]) => id === tab)) || groups[0];
  w.innerHTML = `<nav class="crumbs" aria-label="Breadcrumb"><button class="crumb" id="back">${ico("arrowLeft", 16)}Instances</button><span>/</span><strong>${esc(x.name)}</strong></nav>
  <section class="card inst-head"><div class="inst-id"><span class="inst-avatar">${ico("phone", 24)}</span><div><h1>${esc(x.name)}</h1><div class="inst-meta"><span class="status ${esc(x.status)}">${esc(x.status.replaceAll("_", " "))}</span>${x.phone ? "<span>" + esc(x.phone) + "</span>" : ""}</div></div></div><div class="inst-actions"><button class="btn" id="rename">${ico("edit", 16)}Rename</button><button class="btn danger" id="archiveInstance">${ico("archive", 16)}Archive</button></div></section>
  <nav class="gtabs" aria-label="Instance sections">${groups.map(([title, icon, items]) => `<button class="gtab ${title === activeGroup[0] ? "active" : ""}" data-tab="${items[0][0]}">${ico(icon, 18)}<span>${title}</span></button>`).join("")}</nav>
  <nav class="ptabs" aria-label="Instance tools">${activeGroup[2].map(([id, label]) => `<button class="ptab ${tab === id ? "active" : ""}" data-tab="${id}" ${tab === id ? 'aria-current="page"' : ""}>${label}</button>`).join("")}</nav>
  <section id="panel" class="panel"></section>`;
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
      startPolling: (fn, ms) => { clearInterval(timer); timer = setInterval(fn, ms); },
    }).catch((e) => {
      p.textContent = e.message;
    });
    return;
  }
  if (tab === "connection") {
    const connected = x.status === "connected";
    const method0 = localStorage.getItem("zelonLinkMethod") === "pair" ? "pair" : "qr";
    const linkCard = connected
      ? `<div class="state-ok"><span class="ico-box ok big">${ico("check", 28)}</span><h3>WhatsApp is connected</h3><p class="hint">${x.phone ? "Linked number <strong>+" + esc(x.phone) + "</strong> is" : "Your number is"} online and ready to send and receive messages.</p><div class="actions center"><button id="restart" class="btn">Restart connection</button><button id="disconnect" class="btn danger">Log out number</button></div></div>`
      : `<h3>Link your WhatsApp number</h3><p class="hint">Choose how you want to link this number. You only need one method.</p><div class="alert" id="linkAlert" hidden></div><div class="seg" role="tablist"><button type="button" class="segbtn ${method0 === "qr" ? "active" : ""}" data-method="qr">${ico("qr", 18)}Scan QR code</button><button type="button" class="segbtn ${method0 === "pair" ? "active" : ""}" data-method="pair">${ico("key", 18)}Pairing code</button></div><div id="methodQr" ${method0 === "qr" ? "" : "hidden"}><ol class="how"><li>Open WhatsApp on your phone</li><li>Go to <b>Linked devices → Link a device</b></li><li>Scan the QR code shown below</li></ol><div id="qrbox" class="qrbox"></div><div class="actions center"><button id="connect" class="btn primary">Generate QR code</button></div></div><div id="methodPair" ${method0 === "pair" ? "" : "hidden"}><ol class="how"><li>Enter the number you want to link</li><li>Open WhatsApp → <b>Linked devices → Link a device</b></li><li>Choose <b>Link with phone number instead</b> and type the code</li></ol><form id="pairForm"><label for="pairPhone">WhatsApp number (with country code)</label><input id="pairPhone" name="pairPhone" type="tel" placeholder="+97450000000" required><div class="actions"><button type="submit" class="btn primary">Get pairing code</button></div></form><div id="pairResult"></div></div>`;
    p.innerHTML = `<div class="split"><section class="card link-card">${linkCard}</section><section class="card"><h3>API access</h3><p class="hint">Generate an API key scoped to this instance. It is shown once. Generating a new key revokes the previous one.</p><div class="actions"><button id="key" class="btn">${ico("key", 16)}Generate API key</button></div><div id="keybox"></div><p class="hint">Instance ID</p><div class="key">${esc(x.id)}</div></section></div>`;
    const swap = (m) => {
      localStorage.setItem("zelonLinkMethod", m);
      document.querySelectorAll("[data-method]").forEach((b) => b.classList.toggle("active", b.dataset.method === m));
      document.querySelector("#methodQr")?.toggleAttribute("hidden", m !== "qr");
      document.querySelector("#methodPair")?.toggleAttribute("hidden", m !== "pair");
    };
    document.querySelectorAll("[data-method]").forEach((b) => (b.onclick = () => swap(b.dataset.method)));
    on("connect", async () => {
      await api(base + "/connect", "POST", {});
      toast("Connection started. Waiting for QR code.");
      await poll();
    });
    form("pairForm", async (d) => {
      const r = await api(base + "/pairing-code", "POST", { phone: d.pairPhone });
      const code = String(r.code || "").replace(/(.{4})(?=.)/, "$1-");
      document.querySelector("#pairResult").innerHTML = `<div class="paircode"><span>Your pairing code</span><strong>${esc(code)}</strong><button type="button" class="btn mini" id="copyCode">Copy code</button><p class="hint">Enter it in WhatsApp within about a minute.</p></div>`;
      on("copyCode", async () => {
        await navigator.clipboard?.writeText(String(r.code));
        toast("Code copied");
      });
    });
    on("restart", async () => {
      await api(base + "/restart", "POST", {});
      toast("Connection restarting");
      setTimeout(load, 2500);
    });
    on("disconnect", () => {
      const m = modal(
        '<h2>Log out this number?</h2><p>The WhatsApp session will be removed from this server. You will need to link the number again to send or receive messages.</p><div class="actions"><button class="btn danger" id="confirmLogout">Log out number</button><button class="btn" id="cancelLogout">Cancel</button></div>',
      );
      on("cancelLogout", m.close);
      on("confirmLogout", async () => {
        m.close();
        let failure;
        try { await api(base + "/disconnect", "POST", {}); } catch (e) { failure = e; }
        await load(); // WhatsApp can drop the socket mid-logout; trust the real state.
        if (selected?.status === "connected") toast(failure?.message || "Could not log out. Try again.");
        else toast("Number logged out");
      });
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
        const wasConnected = x.status === "connected";
        if (d.status !== x.status) {
          instances = await api("/instances");
          selected = instances.find((i) => i.id === x.id) || selected;
          x.status = d.status;
          if ((d.status === "connected") !== wasConnected) {
            render();
            return;
          }
        }
        const box = document.querySelector("#qrbox");
        if (box)
          box.innerHTML = d.qr
            ? `<img class="qr" src="${esc(d.qr)}" alt="WhatsApp linking QR code">`
            : `<p class="hint center">${["connecting", "reconnecting", "awaiting_qr"].includes(d.status) ? "Connecting to WhatsApp… the QR code will appear here." : "Select Generate QR code to start linking."}</p>`;
        const alert = document.querySelector("#linkAlert");
        if (alert) {
          alert.hidden = !d.error;
          alert.textContent = d.error || "";
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
      p.innerHTML = `<div class="card"><div class="row"><h3>${currentTab === "history" ? "Outgoing messages" : "Incoming events"}</h3><button id="refresh" class="btn">Refresh</button></div><p class="hint">Newest records first.</p>${records.length ? `<div class="tablewrap"><table><thead><tr><th>Time</th><th>${currentTab === "history" ? "Recipient" : "Event"}</th><th>Details</th><th>Status</th><th>Action</th></tr></thead><tbody>${records.map((r) => `<tr><td>${esc(new Date(r.createdAt).toLocaleString())}</td><td>${esc(r.to || r.type)}</td><td>${esc(r.text || summarize(r.data))}</td><td><span class="status ${esc(r.status || "")}">${esc(r.status || "received")}</span></td><td>${r.status === "queued" ? `<button class="btn" data-cancel="${esc(r.id)}">Cancel</button>` : ""}</td></tr>`).join("")}</tbody></table></div>` : '<p class="hint">No records yet.</p>'}${rows.length === 25 ? '<div class="actions"><button class="btn" id="older">Load older records</button></div>' : ""}</div>`;
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
    p.innerHTML = `<section class="card"><div class="row card-title"><h3>Your groups</h3><div class="row"><input id="groupSearch" class="inline-search" placeholder="Search groups" aria-label="Search groups"><button id="groups" class="btn mini">Refresh</button></div></div><div id="groupList"><p class="hint">Loading groups…</p></div></section><div class="split spaced"><section class="card"><h3>Check a WhatsApp number</h3><form id="check"><label for="phone">Phone number</label><input name="phone" id="phone" placeholder="+97450000000" required><div class="actions"><button type="submit" class="btn primary">Check number</button></div></form><div id="result"></div></section><section class="card"><h3>Create a group</h3><form id="groupCreate"><label for="groupName">Group name</label><input id="groupName" name="name" required><label for="participants">Participants (one phone number per line)</label><textarea name="participants" id="participants" required></textarea><div class="actions"><button type="submit" class="btn primary">Create group</button></div></form></section></div><section class="card"><h3>Manage group members</h3><form id="members"><label for="groupId">Group</label><input id="groupId" name="groupId" list="groupChoices" placeholder="Pick a group or paste 123456789@g.us" autocomplete="off" required><datalist id="groupChoices"></datalist><label for="memberPhones">Participants (one phone per line)</label><textarea id="memberPhones" name="participants" required></textarea><label for="memberAction">Action</label><select id="memberAction" name="action"><option value="add">Add</option><option value="remove">Remove</option><option value="promote">Promote to admin</option><option value="demote">Remove admin role</option></select><div class="actions"><button class="btn primary" type="submit">Update members</button></div></form></section>`;
    p.classList.add("stack");
    let groupRows = [];
    const drawGroups = () => {
      const q = document.querySelector("#groupSearch").value.toLowerCase();
      const rows = groupRows.filter((g) => (g.subject || "").toLowerCase().includes(q));
      document.querySelector("#groupList").innerHTML = rows.length
        ? `<div class="inst-list">${rows.map((g) => `<article class="group-row"><span class="avatar group">${ico("users", 20)}</span><div class="inst-info"><strong>${esc(g.subject || "Unnamed group")}</strong><span class="hint">${g.participants?.length || 0} participants${g.desc ? " · " + esc(String(g.desc).slice(0, 60)) : ""}</span></div><button class="btn mini primary" data-open-group="${esc(g.id)}">Open chat</button><button class="btn mini" data-group-info="${esc(g.id)}">Details</button></article>`).join("")}</div>`
        : `<p class="hint">${groupRows.length ? "No groups match your search." : "No groups found for this number."}</p>`;
      document.querySelectorAll("[data-open-group]").forEach((b) => (b.onclick = () => {
        const g = groupRows.find((r) => r.id === b.dataset.openGroup);
        window.__zelonChatMeta = { id: g.id, chatId: g.id, name: g.subject, kind: "group", participants: g.participants?.length || 0 };
        tab = "inbox";
        render();
      }));
      document.querySelectorAll("[data-group-info]").forEach((b) => (b.onclick = async () => {
        try {
          const g = await api(base + "/groups/" + encodeURIComponent(b.dataset.groupInfo) + "/overview");
          const m = modal(`<h2>${esc(g.subject)}</h2><p class="hint">${g.createdAt ? "Created " + esc(new Date(g.createdAt).toLocaleDateString()) : ""}${g.owner ? " · Owner " + esc(g.owner) : ""}</p>${g.description ? `<p>${esc(g.description)}</p>` : ""}<div class="chips"><span class="status ${g.announce ? "queued" : "connected"}">${g.announce ? "Only admins can send" : "Everyone can send"}</span><span class="status ${g.restrict ? "queued" : "connected"}">${g.restrict ? "Only admins edit info" : "Everyone can edit info"}</span></div><h3>${g.participants.length} participants</h3><div class="members">${g.participants.map((u) => `<div class="record row"><div><strong>${esc(u.name || u.phone)}</strong>${u.name ? `<div class="hint">${esc(u.phone)}</div>` : ""}</div>${u.admin ? `<span class="status connected">${u.admin === "superadmin" ? "Owner" : "Admin"}</span>` : ""}</div>`).join("")}</div><div class="actions"><button class="btn" id="closeGroup">Close</button></div>`);
          on("closeGroup", m.close);
        } catch (e) { toast(e.message); }
      }));
    };
    const loadGroups = async () => {
      try {
        const r = await api(base + "/groups");
        groupRows = Object.values(r).sort((a, b) => (a.subject || "").localeCompare(b.subject || ""));
        document.querySelector("#groupChoices").innerHTML = groupRows.map((g) => `<option value="${esc(g.id)}">${esc(g.subject)}</option>`).join("");
        drawGroups();
      } catch (e) {
        document.querySelector("#groupList").innerHTML = `<p class="hint">${esc(e.message)}. Connect your number to load groups.</p>`;
      }
    };
    document.querySelector("#groupSearch").oninput = drawGroups;
    on("groups", loadGroups);
    loadGroups();
    form("members", async (d) => {
      const group = d.groupId;
      delete d.groupId;
      d.participants = d.participants.split("\n").map((s) => s.trim()).filter(Boolean);
      await api(base + "/groups/" + encodeURIComponent(group) + "/participants", "PUT", d);
      toast("Group members updated");
    });
    form("check", async (d) => {
      const r = await api(base + "/check-number", "POST", d);
      const ok = r[0]?.exists;
      document.querySelector("#result").innerHTML = `<p class="resultline ${ok ? "ok" : "no"}">${ok ? "This number is on WhatsApp." : "No WhatsApp account found."}</p>`;
    });
    form("groupCreate", async (d) => {
      d.participants = d.participants.split("\n").map((s) => s.trim()).filter(Boolean);
      const r = await api(base + "/groups", "POST", d);
      toast("Group created: " + (r.subject || r.id));
      await loadGroups();
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
      )}</table></div><h3>Webhooks</h3><p>Configure your public HTTPS endpoint in the Webhooks tab. Verify the raw body signature using the displayed secret. Delivery is at least once; deduplicate by event ID. Event types: connection, message, receipt.</p><h3>Failure handling</h3><p>400: invalid input. 401: invalid credentials. 404: inaccessible instance. 409: conflicting state or idempotency key. 429: request rate exceeded. Messages interrupted during a send are marked unknown; check delivery before retrying to prevent duplicates.</p><h3>Deployment contract</h3><p>One worker owns the database and WhatsApp sessions; additional local HTTP processes forward to it. Message and event history use indexed database queries and cursor pagination. Your configured SQLite/MySQL database stores records and encrypted WhatsApp credentials. Preserve ENCRYPTION_KEY across deployments. Shared inbox, status publishing, contacts, auto replies, consent-based campaigns, encrypted large media and SDK examples are included. Read the complete API reference and deployment guide in GitHub.</p></div>`;
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
