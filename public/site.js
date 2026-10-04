/* Zelon API - public website and sign-in page */
(function () {
  const S = (d) => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${d}</svg>`;
  const I = {
    chat: S('<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>'),
    qr: S('<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><path d="M14 14h3v3h-3zM20 14v3M14 20h3M20 20v1"/>'),
    hook: S('<path d="M18 16.98h-5.99c-1.1 0-1.95.94-2.48 1.9A4 4 0 0 1 2 17c.01-.7.2-1.4.57-2"/><path d="m6 17 3.13-5.78c.53-.97.1-2.18-.5-3.1a4 4 0 1 1 6.89-4.06"/><path d="m12 6 3.13 5.73C15.66 12.7 16.9 13 18 13a4 4 0 0 1 0 8"/>'),
    users: S('<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75"/>'),
    clock: S('<circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/>'),
    shield: S('<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/><path d="m9 12 2 2 4-4"/>'),
    bolt: S('<path d="M13 2 3 14h9l-1 8 10-12h-9z"/>'),
    inbox: S('<path d="M22 12h-6l-2 3h-4l-2-3H2"/><path d="M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"/>'),
    send: S('<path d="m22 2-7 20-4-9-9-4z"/><path d="M22 2 11 13"/>'),
    image: S('<rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/><path d="m21 15-5-5L5 21"/>'),
    chart: S('<path d="M3 3v18h18"/><path d="m19 9-5 5-4-4-3 3"/>'),
    key: S('<circle cx="7.5" cy="15.5" r="4.5"/><path d="m10.7 12.3 9.3-9.3M16 7l3 3M14 9l2 2"/>'),
    check: S('<path d="m20 6-11 11-5-5"/>'),
    eye: S('<path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/>'),
    menu: S('<path d="M3 6h18M3 12h18M3 18h18"/>'),
    server: S('<rect x="2" y="3" width="20" height="8" rx="2"/><rect x="2" y="13" width="20" height="8" rx="2"/><path d="M6 7h.01M6 17h.01"/>'),
    code: S('<path d="m16 18 6-6-6-6M8 6l-6 6 6 6"/>'),
  };
  const year = new Date().getFullYear();
  const brand = (href = "/") => `<a class="brandmark" href="${href}"><span class="mark">Z</span><span>Zelon<small>API</small></span></a>`;
  const esc = (v) => String(v ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

  const SNIP = {
    curl: () =>
      `<span class="tk-k">curl</span> -X POST <span class="tk-s">"https://YOUR-DOMAIN/api/instances/$ID/messages"</span> \\\n  -H <span class="tk-s">"Authorization: Bearer $API_KEY"</span> \\\n  -H <span class="tk-s">"Idempotency-Key: order-1042"</span> \\\n  -H <span class="tk-s">"Content-Type: application/json"</span> \\\n  -d <span class="tk-s">'{\n    "to": "+97450000000",\n    "type": "text",\n    "text": "Your order #1042 has shipped 🚚"\n  }'</span>`,
    node: () =>
      `<span class="tk-c">// npm i node-fetch (or use Node 18+ fetch)</span>\n<span class="tk-k">const</span> res = <span class="tk-k">await</span> fetch(<span class="tk-s">\`https://YOUR-DOMAIN/api/instances/\${ID}/messages\`</span>, {\n  method: <span class="tk-s">"POST"</span>,\n  headers: {\n    Authorization: <span class="tk-s">\`Bearer \${API_KEY}\`</span>,\n    <span class="tk-s">"Content-Type"</span>: <span class="tk-s">"application/json"</span>,\n    <span class="tk-s">"Idempotency-Key"</span>: <span class="tk-s">"order-1042"</span>,\n  },\n  body: JSON.stringify({\n    to: <span class="tk-s">"+97450000000"</span>,\n    type: <span class="tk-s">"text"</span>,\n    text: <span class="tk-s">"Your order #1042 has shipped 🚚"</span>,\n  }),\n});\n<span class="tk-k">console</span>.log(<span class="tk-k">await</span> res.json());`,
    python: () =>
      `<span class="tk-k">import</span> requests\n\nr = requests.post(\n    <span class="tk-s">f"https://YOUR-DOMAIN/api/instances/{ID}/messages"</span>,\n    headers={<span class="tk-s">"Authorization"</span>: <span class="tk-s">f"Bearer {API_KEY}"</span>,\n             <span class="tk-s">"Idempotency-Key"</span>: <span class="tk-s">"order-1042"</span>},\n    json={<span class="tk-s">"to"</span>: <span class="tk-s">"+97450000000"</span>,\n          <span class="tk-s">"type"</span>: <span class="tk-s">"text"</span>,\n          <span class="tk-s">"text"</span>: <span class="tk-s">"Your order #1042 has shipped 🚚"</span>},\n)\n<span class="tk-k">print</span>(r.json())`,
    php: () =>
      `&lt;?php\n$ch = curl_init(<span class="tk-s">"https://YOUR-DOMAIN/api/instances/$id/messages"</span>);\ncurl_setopt_array($ch, [\n  CURLOPT_POST =&gt; <span class="tk-n">true</span>,\n  CURLOPT_RETURNTRANSFER =&gt; <span class="tk-n">true</span>,\n  CURLOPT_HTTPHEADER =&gt; [\n    <span class="tk-s">"Authorization: Bearer $apiKey"</span>,\n    <span class="tk-s">"Content-Type: application/json"</span>,\n    <span class="tk-s">"Idempotency-Key: order-1042"</span>,\n  ],\n  CURLOPT_POSTFIELDS =&gt; json_encode([\n    <span class="tk-s">"to"</span> =&gt; <span class="tk-s">"+97450000000"</span>,\n    <span class="tk-s">"type"</span> =&gt; <span class="tk-s">"text"</span>,\n    <span class="tk-s">"text"</span> =&gt; <span class="tk-s">"Your order #1042 has shipped 🚚"</span>,\n  ]),\n]);\n<span class="tk-k">echo</span> curl_exec($ch);`,
  };

  const FEATURES = [
    ["chat", "Send anything", "Text, images, video, voice notes, documents, stickers, locations, contacts and polls from a single endpoint."],
    ["inbox", "Live shared inbox", "A WhatsApp-style web inbox with real-time messages, read receipts, reactions, replies, edit and delete."],
    ["qr", "Link in seconds", "Connect a number by scanning a QR code or entering a pairing code, with sessions that survive restarts."],
    ["hook", "Signed webhooks", "Receive messages, receipts and connection events on your server with HMAC signatures and automatic retries."],
    ["clock", "Scheduling & queues", "Queue messages for later, throttle sending, cancel before delivery and track every status change."],
    ["users", "Groups & contacts", "Create groups, manage members, import contacts with consent flags and check whether a number is on WhatsApp."],
    ["bolt", "Auto replies & campaigns", "Keyword rules, reusable templates and consent-based bulk campaigns with pacing built in."],
    ["chart", "Analytics & history", "Searchable message history, delivery statistics and incoming event logs for every connected number."],
    ["shield", "Private by design", "Encrypted session storage, scoped API keys, rotating secrets and audit logs of every sign-in."],
  ];
  const CASES = [
    ["Order & delivery updates", "Confirm purchases, send tracking links and let customers reply in the same thread."],
    ["Appointment reminders", "Schedule reminders before bookings and capture confirmations automatically."],
    ["Customer support", "Give your team one shared inbox with history, assignments and quick replies."],
    ["Alerts & notifications", "Push monitoring alerts, OTP-style notices and account updates to the channel people read."],
  ];
  const FAQ = [
    ["Do I need a WhatsApp number?", "Yes. Link a number you control from the Linked devices screen in WhatsApp, using either a QR code or a pairing code."],
    ["How is my data protected?", "Session credentials are encrypted at rest, API keys are scoped to a single number and shown once, and every sign-in is recorded in an audit log."],
    ["Can I use my own application or website?", "Yes. Zelon API is a plain HTTPS REST interface, so any language that can send an HTTP request works. Ready-made Node, Python and PHP clients are included."],
    ["What happens if my connection drops?", "Sessions are stored securely and restored automatically. A built-in keep-alive monitor checks the service on a schedule and reconnects linked numbers if needed."],
    ["Is this the official WhatsApp Business Platform?", "No. Zelon API links your own WhatsApp account as a companion device. It is an independent product and is not affiliated with or endorsed by WhatsApp or Meta. Use it responsibly and follow WhatsApp's terms."],
    ["Can several people use the same workspace?", "Administrators can create member accounts, reset passwords, sign users out of every device and disable access at any time."],
  ];

  function codeWindow() {
    const tabs = [["curl", "cURL"], ["node", "Node.js"], ["python", "Python"], ["php", "PHP"]];
    return `<div class="win" id="heroWin"><div class="win-bar"><i></i><i></i><i></i><div class="win-tabs">${tabs.map(([k, l], i) => `<button type="button" data-snip="${k}" class="${i ? "" : "on"}">${l}</button>`).join("")}</div></div><pre id="heroCode">${SNIP.curl()}</pre><div class="res"><b>202 Accepted</b> · 38 ms<br>{ <span class="tk-s">"id"</span>: <span class="tk-s">"9f1c…"</span>, <span class="tk-s">"status"</span>: <span class="tk-s">"queued"</span> }</div></div>`;
  }

  function phoneMock() {
    return `<div class="phone"><div class="screen"><div class="scr-head"><span class="av">A</span><div><strong>Amina Rahman</strong><small>online</small></div></div><div class="scr-body">
      <div class="bub">Hi! Is my order ready?<small>10:41</small></div>
      <div class="bub out">Hello Amina 👋 Order #1042 has shipped. Track it here: zelon.link/t/1042<small>10:41 <b>✓✓</b></small></div>
      <div class="bub">Amazing, thank you!<small>10:42</small></div>
      <div class="bub out card2"><b>Delivery window</b><span>Today · 4:00 – 6:00 PM</span><small>10:42 <b>✓✓</b></small></div>
      <div class="bub out">Anything else we can help with? 😊<small>10:43 <b>✓✓</b></small></div></div></div></div>`;
  }

  function landing(root) {
    root.className = "site";
    root.innerHTML = `
    <div class="snav"><div class="wrap">${brand()}<button class="burger" id="burger" aria-label="Menu">${I.menu}</button><nav id="snavMenu"><a href="#features">Features</a><a href="#how">How it works</a><a href="#developers">Developers</a><a href="#faq">FAQ</a><a href="/api-reference.html">API docs</a><a class="sbtn primary sm" href="/console">Sign in</a></nav></div></div>
    <section class="hero2"><div class="wrap">
      <div><span class="pill"><i></i>WhatsApp messaging, built for developers</span>
        <h1>Connect your apps to <em>WhatsApp</em> in minutes.</h1>
        <p class="lead">One clean REST API and a beautiful web console to send messages, receive replies in a live inbox, automate answers and run campaigns — on infrastructure you control.</p>
        <div class="cta"><a class="sbtn primary lg" href="/console">Open the console</a><a class="sbtn ghost lg" href="/api-reference.html">Read the API docs</a></div>
        <div class="trust"><span>${I.check}Link by QR or pairing code</span><span>${I.check}Real-time webhooks</span><span>${I.check}Encrypted sessions</span></div></div>
      <div>${codeWindow()}</div></div></section>
    <div class="stats2"><div class="wrap"><div><strong>30s</strong><span>from sign-in to first message</span></div><div><strong>10+</strong><span>message types supported</span></div><div><strong>3</strong><span>ready-made SDKs</span></div><div><strong>24/7</strong><span>sessions with auto-recovery</span></div></div></div>
    <section class="blk" id="features"><div class="wrap"><div class="head-c"><div class="kicker">Everything you need</div><h2>One connection. A whole messaging platform.</h2><p class="sub">From a single API call to a full customer-conversation workflow, every building block is already here.</p></div>
      <div class="fgrid">${FEATURES.map(([i, h, p]) => `<article class="fcard"><span class="fico">${I[i]}</span><h3>${esc(h)}</h3><p>${esc(p)}</p></article>`).join("")}</div></div></section>
    <section class="blk dark" id="how"><div class="wrap"><div class="head-c"><div class="kicker">How it works</div><h2>Go live in three steps.</h2><p class="sub">No approvals, no waiting lists. Create a connection, link your number and start sending.</p></div>
      <div class="steps2"><div class="step2"><h3>Create a connection</h3><p>Sign in to the console and add a WhatsApp instance. Give it a name your team will recognise.</p></div><div class="step2"><h3>Link your number</h3><p>Scan the QR code, or request a pairing code and enter it under Linked devices on your phone.</p></div><div class="step2"><h3>Send &amp; receive</h3><p>Generate a scoped API key, call the REST API and receive replies through webhooks or the live inbox.</p></div></div></div></section>
    <section class="blk"><div class="wrap split2">
      <div>${phoneMock()}</div>
      <div><div class="kicker">Live inbox</div><h2>A familiar inbox your whole team will love.</h2><p class="sub">Conversations update in real time, with profile photos, delivery ticks and every action you expect from WhatsApp.</p>
        <ul class="checklist"><li>${I.check}<span>Reply, forward, react, star, edit and delete messages</span></li><li>${I.check}<span>Photos, video, voice, documents, locations and contact cards inline</span></li><li>${I.check}<span>Group chats, contact info, search and full-screen mode</span></li><li>${I.check}<span>Fully responsive on desktop, tablet and phone</span></li></ul></div></div></section>
    <section class="blk alt"><div class="wrap"><div class="head-c"><div class="kicker">Built for real workflows</div><h2>Made for the messages that matter.</h2></div>
      <div class="ugrid">${CASES.map(([h, p]) => `<div class="ucase"><b>${esc(h)}</b><p>${esc(p)}</p></div>`).join("")}</div></div></section>
    <section class="blk dark" id="developers"><div class="wrap split2">
      <div><div class="kicker">For developers</div><h2>A clean API you can learn in five minutes.</h2><p class="sub">Predictable JSON, idempotent requests, cursor pagination and signed webhooks. The full reference includes copy-ready examples in cURL, Node.js, Python and PHP.</p>
        <ul class="checklist"><li>${I.check}<span>Idempotency keys prevent duplicate sends on retries</span></li><li>${I.check}<span>Per-number API keys with instant revoke and rotate</span></li><li>${I.check}<span>OpenAPI 3.1 specification for code generation</span></li></ul>
        <div class="cta"><a class="sbtn primary" href="/api-reference.html">Explore the docs</a><a class="sbtn ghost" href="/openapi.json">OpenAPI spec</a></div></div>
      <div><div class="win"><div class="win-bar"><i></i><i></i><i></i><span style="margin-left:12px;color:#7e93a6;font-size:12.5px">webhook payload</span></div><pre>{
  <span class="tk-s">"type"</span>: <span class="tk-s">"message"</span>,
  <span class="tk-s">"instanceId"</span>: <span class="tk-s">"a1b2…"</span>,
  <span class="tk-s">"data"</span>: {
    <span class="tk-s">"chatId"</span>: <span class="tk-s">"97450000000@s.whatsapp.net"</span>,
    <span class="tk-s">"fromMe"</span>: <span class="tk-n">false</span>,
    <span class="tk-s">"text"</span>: <span class="tk-s">"Is my order ready?"</span>
  }
}
<span class="tk-c">// X-Zelon-Signature: sha256=…</span></pre></div></div></div></section>
    <section class="blk"><div class="wrap"><div class="head-c"><div class="kicker">SDKs</div><h2>Use the language you already know.</h2></div>
      <div class="sdkgrid" style="--x:0"><div class="sdk" style="background:#fff;border-color:#e3e9ef"><b style="color:#0f172a">Node.js</b><p style="color:#5b6b7c">Zero-dependency ES module client.</p><a style="color:#0a8f62" href="/sdk/zelon.mjs">Download zelon.mjs →</a></div><div class="sdk" style="background:#fff;border-color:#e3e9ef"><b style="color:#0f172a">Python</b><p style="color:#5b6b7c">Single-file client built on requests.</p><a style="color:#0a8f62" href="/sdk/zelon.py">Download zelon.py →</a></div><div class="sdk" style="background:#fff;border-color:#e3e9ef"><b style="color:#0f172a">PHP</b><p style="color:#5b6b7c">Drop-in class using cURL.</p><a style="color:#0a8f62" href="/sdk/zelon.php">Download zelon.php →</a></div></div></div></section>
    <section class="blk alt" id="faq"><div class="wrap"><div class="head-c"><div class="kicker">FAQ</div><h2>Good questions, straight answers.</h2></div>
      <div class="faq">${FAQ.map(([q, a]) => `<details><summary>${esc(q)}</summary><p>${esc(a)}</p></details>`).join("")}</div></div></section>
    <section class="band"><div class="wrap"><h2>Ready to put WhatsApp to work?</h2><p>Open the console, link your number and send your first message today.</p><div class="cta"><a class="sbtn primary lg" href="/console">Get started</a><a class="sbtn ghost lg" href="/api-reference.html">View documentation</a></div></div></section>
    <div class="sfoot"><div class="wrap"><div class="fcols"><div>${brand()}<p>WhatsApp messaging infrastructure for developers and growing teams.</p></div>
      <div><h4>Product</h4><a href="#features">Features</a><a href="#how">How it works</a><a href="/console">Console</a></div>
      <div><h4>Developers</h4><a href="/api-reference.html">API documentation</a><a href="/openapi.json">OpenAPI spec</a><a href="/sdk/zelon.mjs">Node.js SDK</a><a href="/sdk/zelon.py">Python SDK</a></div>
      <div><h4>Company</h4><a href="#faq">FAQ</a><a href="/console">Sign in</a><a href="/health">Service status</a></div></div>
      <div class="fbot"><span>© ${year} Zelon API. All Rights Reserved.</span><span>Zelon API is an independent product and is not affiliated with WhatsApp or Meta.</span></div></div></div>`;
    const nav = root.querySelector("#snavMenu");
    root.querySelector("#burger").onclick = () => nav.classList.toggle("open");
    nav.addEventListener("click", (e) => e.target.closest("a") && nav.classList.remove("open"));
    const code = root.querySelector("#heroCode");
    root.querySelectorAll("[data-snip]").forEach((b) => (b.onclick = () => {
      root.querySelectorAll("[data-snip]").forEach((x) => x.classList.toggle("on", x === b));
      code.innerHTML = SNIP[b.dataset.snip]();
    }));
    document.title = "Zelon API — WhatsApp messaging infrastructure";
  }

  function login(root) {
    root.className = "site authpage";
    const bullets = [["chat", "Live inbox with real-time conversations"], ["key", "Scoped API keys, webhooks and automation"], ["shield", "Encrypted sessions and sign-in audit log"]];
    root.innerHTML = `
    <aside class="auth-l">${brand()}<div class="mid"><h2>Your WhatsApp,<br><em>connected</em> to everything.</h2><p class="lead">Manage numbers, chat with customers and build integrations from one secure workspace.</p>
      <ul>${bullets.map(([i, t]) => `<li><span>${I[i]}</span>${esc(t)}</li>`).join("")}</ul></div><div class="copy">© ${year} Zelon API. All Rights Reserved.</div></aside>
    <main class="auth-r"><a class="back" href="/">← Back to website</a>
      <section class="auth-card"><h1>Welcome back</h1><p class="hint">Sign in to your Zelon API console.</p>
        <form id="login" novalidate><label for="email">Email address</label><div class="field"><input id="email" name="email" type="email" autocomplete="username" placeholder="you@company.com" required></div>
          <label for="password">Password</label><div class="field"><input id="password" name="password" type="password" autocomplete="current-password" placeholder="Enter your password" required><button type="button" class="eye" id="eye" aria-label="Show password">${I.eye}</button></div>
          <div class="auth-err" id="loginErr" hidden></div>
          <button type="submit" class="sbtn primary">Sign in</button></form>
        <p class="auth-foot">Accounts are created by your workspace administrator.<br>Forgot your password? Ask an administrator to reset it.</p></section>
      <p class="copy2">© ${year} Zelon API. All Rights Reserved.</p></main>`;
    root.querySelector("#eye").onclick = () => {
      const p = root.querySelector("#password");
      p.type = p.type === "password" ? "text" : "password";
    };
    document.title = "Sign in — Zelon API";
  }

  window.ZelonSite = { landing, login, brand, esc };
})();
