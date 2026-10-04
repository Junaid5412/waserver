window.ZelonAdmin = (() => {
  const ago = (iso) => {
    const t = Date.parse(iso);
    if (!t) return "never";
    const s = Math.max(0, Math.round((Date.now() - t) / 1000));
    if (s < 45) return "just now";
    if (s < 3600) return Math.round(s / 60) + " min ago";
    if (s < 86400) return Math.round(s / 3600) + " h ago";
    return Math.round(s / 86400) + " d ago";
  };
  const when = (iso) => (iso && !isNaN(Date.parse(iso)) ? new Date(iso).toLocaleString([], { dateStyle: "medium", timeStyle: "short" }) : "—");
  const dhms = (sec) => {
    sec = Math.max(0, Math.floor(Number(sec) || 0));
    const d = Math.floor(sec / 86400), h = Math.floor((sec % 86400) / 3600), m = Math.floor((sec % 3600) / 60), s = sec % 60;
    return (d ? d + "d " : "") + (d || h ? h + "h " : "") + m + "m " + String(s).padStart(2, "0") + "s";
  };
  const mb = (n) => (n >= 1073741824 ? (n / 1073741824).toFixed(1) + " GB" : Math.round(n / 1048576) + " MB");
  const device = (ua) => {
    ua = String(ua || "");
    const browser = /Edg\//.test(ua) ? "Edge" : /OPR\//.test(ua) ? "Opera" : /Firefox\//.test(ua) ? "Firefox" : /Chrome\//.test(ua) ? "Chrome" : /Safari\//.test(ua) ? "Safari" : /node|curl|python/i.test(ua) ? "API client" : "Browser";
    const os = /Windows/.test(ua) ? "Windows" : /Android/.test(ua) ? "Android" : /iPhone|iPad/.test(ua) ? "iOS" : /Mac OS/.test(ua) ? "macOS" : /Linux/.test(ua) ? "Linux" : "Unknown OS";
    const mobile = /Android|iPhone|iPad|Mobile/.test(ua);
    return { label: browser + " on " + os, mobile };
  };
  const copy = async (text, toast, msg = "Copied") => {
    try { await navigator.clipboard.writeText(text); toast(msg); } catch { toast("Copy failed — select and copy manually"); }
  };
  const bar = (pct, tone = "") => `<div class="meter ${tone}" role="progressbar" aria-valuenow="${Math.round(pct)}" aria-valuemin="0" aria-valuemax="100"><i style="width:${Math.max(2, Math.min(100, pct))}%"></i></div>`;
  const toneFor = (pct) => (pct > 85 ? "bad" : pct > 65 ? "warn" : "");

  /* ============================== SYSTEM HEALTH ============================== */
  async function system(c) {
    const { api, esc, ico, toast, on, getView, startPolling } = c;
    const w = document.querySelector("#workspace");
    w.innerHTML = '<div class="loading">Checking system…</div>';
    let d;
    try { d = await api("/admin/system"); } catch (e) { w.textContent = e.message; return; }
    if (getView() !== "system") return;
    let tick;
    const draw = () => {
      const ka = d.keepAlive,
        mem = d.memory,
        heapPct = (mem.heapUsed / Math.max(1, mem.heapTotal)) * 100,
        sysPct = ((mem.systemTotal - mem.systemFree) / Math.max(1, mem.systemTotal)) * 100,
        sockets = d.instances.sockets,
        total = d.instances.total,
        healthy = d.database === "healthy" && (ka.lastOk !== false);
      const stat = (label, value, hint, icon, tone = "") => `<div class="card sh-card"><span class="ico-box ${tone}">${ico(icon)}</span><div><div class="sh-value">${value}</div><div class="hint">${label}</div>${hint ? `<div class="sh-sub">${hint}</div>` : ""}</div></div>`;
      const hist = ka.history || [];
      const maxMs = Math.max(200, ...hist.map((h) => h.ms || 0));
      const bars = hist.length
        ? hist.map((h) => `<i class="${h.ok ? "ok" : "bad"}" style="height:${Math.max(14, Math.round(((h.ms || 0) / maxMs) * 100))}%" title="${esc(when(h.at))} · ${h.ok ? "OK" : "Failed"} · ${h.ms} ms"></i>`).join("")
        : '<span class="hint">No checks recorded yet. The first one runs shortly after the server starts.</span>';
      const counts = Object.entries(d.counts || {}).map(([k, v]) => {
        const total2 = Object.values(v || {}).reduce((a, b) => a + b, 0);
        const parts = Object.entries(v || {}).map(([s, n]) => `<span class="chip-s">${esc(s || "—")} <b>${n}</b></span>`).join("");
        return `<div class="rec"><div><strong>${esc(k)}</strong><span class="hint">${total2} total</span></div><div class="chips-s">${parts || '<span class="hint">empty</span>'}</div></div>`;
      }).join("");
      w.innerHTML = `
      <div class="top"><div><div class="eyebrow">Administration</div><h1>System health</h1><p>Live status of the server, database, WhatsApp connections and the keep-alive cron.</p></div>
        <div class="actions" style="margin:0"><span class="status ${healthy ? "connected" : "failed"}" id="shBadge">${healthy ? "All systems operational" : "Attention needed"}</span><button class="btn" id="shRefresh">${ico("activity", 16)}Refresh</button></div></div>
      <div class="sh-grid">
        ${stat("Uptime", `<span id="shUptime">${esc(dhms(d.uptimeSeconds))}</span>`, "Since " + esc(when(d.startedAt)), "activity", "ok")}
        ${stat("Database", esc(d.databaseMs) + " ms", esc(d.storage?.driver || "sqlite") + " · healthy", "check", "ok")}
        ${stat("WhatsApp sessions", sockets + " / " + total, Object.entries(d.instances.byStatus).map(([s, n]) => n + " " + esc(s.replaceAll("_", " "))).join(" · ") || "No instances yet", "phone", sockets === total ? "ok" : "warn")}
        ${stat("Live chat streams", d.liveStreams, "Open real-time inbox connections", "chat")}
      </div>
      <section class="card sh-cron"><div class="row card-title"><div><h3>Keep-alive cron</h3><p class="hint" style="margin:2px 0 0">Pings this site on a schedule so free hosts don't put it to sleep, and reconnects any WhatsApp session that dropped.</p></div>
        <label class="switch" title="Turn the keep-alive on or off"><input type="checkbox" id="kaToggle" ${ka.enabled ? "checked" : ""}><span></span><b>${ka.enabled ? "Active" : "Paused"}</b></label></div>
        <div class="seg ka-seg" role="tablist" aria-label="Ping interval">${ka.options.map((m) => `<button type="button" class="segbtn ${ka.intervalMinutes === m ? "active" : ""}" data-ka="${m}">Every ${m} min</button>`).join("")}</div>
        <div class="ka-stats">
          <div><span class="hint">Last check</span><strong class="${ka.lastOk === false ? "bad" : ka.lastOk ? "good" : ""}">${ka.lastAt ? (ka.lastOk ? "OK" : "Failed") + " · " + ago(ka.lastAt) : "Waiting"}</strong><small>${ka.lastMs != null ? ka.lastMs + " ms" : ""}${ka.lastError ? " · " + esc(ka.lastError) : ""}</small></div>
          <div><span class="hint">Next check</span><strong id="kaNext">${ka.enabled && ka.nextAt ? "in " + Math.max(0, Math.round((ka.nextAt - Date.now()) / 1000)) + " s" : "—"}</strong><small>${ka.enabled ? "Automatic" : "Paused"}</small></div>
          <div><span class="hint">Success rate</span><strong>${ka.uptimePercent == null ? "—" : ka.uptimePercent + "%"}</strong><small>${ka.ok} ok · ${ka.fail} failed</small></div>
          <div><span class="hint">Sessions revived</span><strong>${ka.lastWatchdog}</strong><small>on last check</small></div>
        </div>
        <div class="ka-bars" aria-label="Recent check results">${bars}</div>
        <div class="ka-url"><code id="kaUrl">${esc(ka.url)}</code><button class="btn mini" id="kaCopy">Copy URL</button><button class="btn primary" id="kaRun">Run check now</button></div>
        <p class="hint ka-note">Tip: for extra safety, also add the URL above to a free external monitor (cron-job.org or UptimeRobot) every 5 minutes. It works even if this server restarts.</p></section>
      <div class="sh-two">
        <section class="card"><h3>Resources</h3>
          <div class="res"><div class="row"><span>Node heap</span><b>${mb(mem.heapUsed)} / ${mb(mem.heapTotal)}</b></div>${bar(heapPct, toneFor(heapPct))}</div>
          <div class="res"><div class="row"><span>Server memory</span><b>${mb(mem.systemTotal - mem.systemFree)} / ${mb(mem.systemTotal)}</b></div>${bar(sysPct, toneFor(sysPct))}</div>
          <div class="res"><div class="row"><span>Process (RSS)</span><b>${mb(mem.rss)}</b></div></div>
          <div class="res"><div class="row"><span>CPU load (1/5/15 min)</span><b>${d.loadAverage.join(" · ")}</b></div><p class="hint" style="margin:2px 0 0">${d.cpus} CPU core${d.cpus === 1 ? "" : "s"}</p></div></section>
        <section class="card"><h3>Server</h3><dl class="kv one">
          <div><dt>Environment</dt><dd>${esc(d.environment)}</dd></div><div><dt>Node.js</dt><dd>${esc(d.nodeVersion)}</dd></div><div><dt>Platform</dt><dd>${esc(d.platform)}</dd></div><div><dt>Process ID</dt><dd>${esc(d.pid)}</dd></div><div><dt>Public URL</dt><dd>${esc(d.origin)}</dd></div><div><dt>Storage</dt><dd>${esc(d.storage?.driver || "sqlite")}${d.storage?.directory ? " · local files" : ""}</dd></div></dl></section>
      </div>
      <section class="card"><h3>Records</h3><div class="recs">${counts}</div></section>
      <section class="card"><h3>Start-up history</h3><p class="hint">Every time the server starts is recorded. Frequent entries mean the host is restarting or putting the app to sleep.</p>
        <ol class="timeline">${(d.restarts || []).map((r) => `<li><span class="dot"></span><div><strong>Server started</strong><small>${esc(when(r.at))} · ${ago(r.at)} · Node ${esc(r.node || "")}</small></div></li>`).join("") || '<li><span class="dot"></span><div><strong>No history yet</strong></div></li>'}</ol></section>`;
      bind();
    };
    const refresh = async () => {
      try { d = await api("/admin/system"); if (getView() === "system") draw(); } catch (e) { toast(e.message); }
    };
    function bind() {
      on("shRefresh", async () => { await refresh(); toast("Refreshed"); });
      const t = document.querySelector("#kaToggle");
      if (t) t.onchange = async () => {
        try { d.keepAlive = await api("/admin/keepalive", "PUT", { enabled: t.checked }); toast(t.checked ? "Keep-alive enabled" : "Keep-alive paused"); draw(); }
        catch (e) { toast(e.message); t.checked = !t.checked; }
      };
      document.querySelectorAll("[data-ka]").forEach((b) => (b.onclick = async () => {
        try { d.keepAlive = await api("/admin/keepalive", "PUT", { intervalMinutes: Number(b.dataset.ka), enabled: true }); toast("Checking every " + b.dataset.ka + " minutes"); draw(); }
        catch (e) { toast(e.message); }
      }));
      on("kaRun", async () => { d.keepAlive = await api("/admin/keepalive/run", "POST", {}); toast(d.keepAlive.lastOk ? "Check passed" : "Check failed: " + (d.keepAlive.lastError || "unknown")); await refresh(); });
      on("kaCopy", () => copy(d.keepAlive.url, toast, "URL copied"));
    }
    draw();
    startPolling(refresh, 20000);
    clearInterval(tick);
    tick = setInterval(() => {
      const el = document.querySelector("#shUptime");
      if (!el) return clearInterval(tick);
      el.textContent = dhms((Date.now() - Date.parse(d.startedAt)) / 1000);
      const n = document.querySelector("#kaNext");
      if (n && d.keepAlive.enabled && d.keepAlive.nextAt) n.textContent = "in " + Math.max(0, Math.round((d.keepAlive.nextAt - Date.now()) / 1000)) + " s";
    }, 1000);
  }

  /* ============================== USER ACCOUNTS ============================== */
  async function users(c) {
    const { api, esc, ico, toast, on, form, modal, getView, getUser } = c;
    const w = document.querySelector("#workspace");
    w.innerHTML = '<div class="loading">Loading accounts…</div>';
    let list, q = "", filter = "all";
    try { list = await api("/admin/users"); } catch (e) { w.textContent = e.message; return; }
    if (getView() !== "users") return;
    const me = getUser();
    const draw = () => {
      const rows = list.filter((u) => {
        const text = (u.email + " " + (u.name || "")).toLowerCase();
        if (q && !text.includes(q)) return false;
        return filter === "all" || (filter === "admin" && u.role === "admin") || (filter === "user" && u.role !== "admin") || (filter === "disabled" && u.disabled);
      });
      const stats = { total: list.length, admins: list.filter((u) => u.role === "admin").length, active: list.filter((u) => !u.disabled).length, disabled: list.filter((u) => u.disabled).length };
      const body = rows.map((u) => {
        const self = u.id === me.id;
        return `<article class="ua-row ${u.disabled ? "off" : ""}" data-row="${esc(u.id)}">
          <span class="avatar ua-av">${esc((u.name || u.email)[0].toUpperCase())}</span>
          <div class="ua-id"><strong>${esc(u.name || u.email.split("@")[0])}${self ? ' <em class="you">You</em>' : ""}</strong><span class="hint">${esc(u.email)}</span></div>
          <div class="ua-tags"><span class="role ${u.role === "admin" ? "admin" : ""}">${u.role === "admin" ? "Administrator" : "User"}</span><span class="status ${u.disabled ? "failed" : "connected"}">${u.disabled ? "Disabled" : "Active"}</span></div>
          <div class="ua-meta"><span>${u.instances} number${u.instances === 1 ? "" : "s"}</span><span class="hint">Last sign-in: ${u.lastLoginAt ? ago(u.lastLoginAt) : "never"}</span></div>
          <div class="ua-actions">${self ? '<span class="hint">Manage yours in Account &amp; security</span>' : `<button class="btn mini" data-edit="${esc(u.id)}">${ico("edit", 14)}Edit</button><button class="btn mini" data-reset-user="${esc(u.id)}">${ico("key", 14)}Reset password</button><button class="btn mini" data-signout="${esc(u.id)}">Sign out</button><button class="btn mini" data-user="${esc(u.id)}" data-disabled="${!u.disabled}">${u.disabled ? "Enable" : "Disable"}</button><button class="btn mini danger" data-delete="${esc(u.id)}">${ico("archive", 14)}Delete</button>`}</div>
        </article>`;
      }).join("");
      w.innerHTML = `<div class="top"><div><div class="eyebrow">Administration</div><h1>User accounts</h1><p>Create accounts, set roles and control who can sign in to the console.</p></div><button class="btn primary" id="addUser" aria-label="Add user">${ico("plus", 18)}Add user</button></div>
        <div class="ua-stats"><div class="card"><strong>${stats.total}</strong><span class="hint">Accounts</span></div><div class="card"><strong>${stats.admins}</strong><span class="hint">Administrators</span></div><div class="card"><strong>${stats.active}</strong><span class="hint">Active</span></div><div class="card"><strong>${stats.disabled}</strong><span class="hint">Disabled</span></div></div>
        <section class="card ua-card"><div class="ua-tools"><input id="uaSearch" class="inline-search" placeholder="Search name or email" value="${esc(q)}" aria-label="Search accounts"><div class="chips" style="margin:0">${[["all", "All"], ["admin", "Administrators"], ["user", "Users"], ["disabled", "Disabled"]].map(([k, l]) => `<button class="chip ${filter === k ? "active" : ""}" data-f="${k}">${l}</button>`).join("")}</div></div>
        <div class="ua-list">${body || '<p class="hint" style="padding:20px">No accounts match.</p>'}</div></section>`;
      bind();
    };
    const reload = async () => { list = await api("/admin/users"); if (getView() === "users") draw(); };
    const secret = (title, line, pwd, done) => {
      const m = modal(`<h2>${title}</h2><p>${line}</p><p class="hint">Save this password securely. It is shown only once.</p><div class="key" id="pwdBox">${esc(pwd)}</div><div class="actions"><button class="btn" id="copyPwd">Copy password</button><button class="btn primary" id="doneUser">Done</button></div>`);
      on("copyPwd", () => copy(pwd, toast, "Password copied"));
      on("doneUser", () => { m.close(); done?.(); });
    };
    function bind() {
      const s = document.querySelector("#uaSearch");
      if (s) s.oninput = () => { q = s.value.trim().toLowerCase(); const pos = s.selectionStart; draw(); const n = document.querySelector("#uaSearch"); n.focus(); n.setSelectionRange(pos, pos); };
      document.querySelectorAll("[data-f]").forEach((b) => (b.onclick = () => { filter = b.dataset.f; draw(); }));
      on("addUser", () => {
        const m = modal(`<h2>Add user</h2><form id="addUserForm"><label for="userName">Full name (optional)</label><input id="userName" name="name" maxlength="80" autocomplete="off"><label for="userEmail">Email address</label><input id="userEmail" name="email" type="email" maxlength="254" required><label for="userRole">Access role</label><select id="userRole" name="role"><option value="user">User — own numbers and messaging only</option><option value="admin">Administrator — manage accounts and system</option></select><p class="hint">A secure initial password will be generated and shown once.</p><div class="actions"><button type="submit" class="btn primary">Create account</button><button type="button" class="btn" id="closeUser">Cancel</button></div></form>`);
        on("closeUser", m.close);
        form("addUserForm", async (d) => {
          if (!d.name) delete d.name;
          const r = await api("/admin/users", "POST", d);
          m.close();
          secret("Account created", esc(r.email), r.password, reload);
        });
      });
      document.querySelectorAll("[data-edit]").forEach((b) => (b.onclick = () => {
        const u = list.find((x) => x.id === b.dataset.edit);
        const m = modal(`<h2>Edit account</h2><form id="editUserForm"><label for="euName">Full name</label><input id="euName" name="name" value="${esc(u.name || "")}" maxlength="80"><label for="euEmail">Email address</label><input id="euEmail" name="email" type="email" value="${esc(u.email)}" required><label for="euRole">Access role</label><select id="euRole" name="role"><option value="user" ${u.role !== "admin" ? "selected" : ""}>User</option><option value="admin" ${u.role === "admin" ? "selected" : ""}>Administrator</option></select><div class="actions"><button type="submit" class="btn primary">Save changes</button><button type="button" class="btn" id="closeEdit">Cancel</button></div></form>`);
        on("closeEdit", m.close);
        form("editUserForm", async (d) => { await api("/admin/users/" + u.id, "PUT", d); m.close(); toast("Account updated"); await reload(); });
      }));
      document.querySelectorAll("[data-reset-user]").forEach((b) => (b.onclick = () => {
        const u = list.find((x) => x.id === b.dataset.resetUser);
        const m = modal(`<h2>Reset password?</h2><p>${esc(u.email)} will receive a new initial password and will be signed out everywhere.</p><div class="actions"><button class="btn primary" id="confirmReset">Reset password</button><button class="btn" id="cancelReset">Cancel</button></div>`);
        on("cancelReset", m.close);
        on("confirmReset", async () => {
          const r = await api("/admin/users/" + u.id + "/reset-password", "POST", {});
          m.close();
          secret("New password", esc(u.email), r.password);
        });
      }));
      document.querySelectorAll("[data-signout]").forEach((b) => (b.onclick = async () => {
        try { await api("/admin/users/" + b.dataset.signout + "/sign-out", "POST", {}); toast("Signed out of all devices"); } catch (e) { toast(e.message); }
      }));
      document.querySelectorAll("[data-user]").forEach((b) => (b.onclick = async () => {
        try { await api("/admin/users/" + b.dataset.user, "PUT", { disabled: b.dataset.disabled === "true" }); toast(b.dataset.disabled === "true" ? "Account disabled" : "Account enabled"); await reload(); } catch (e) { toast(e.message); }
      }));
      document.querySelectorAll("[data-delete]").forEach((b) => (b.onclick = () => {
        const u = list.find((x) => x.id === b.dataset.delete);
        const m = modal(`<h2>Delete this account?</h2><p><b>${esc(u.email)}</b> will be removed, signed out everywhere, and their ${u.instances} WhatsApp number${u.instances === 1 ? "" : "s"} will be disconnected and archived. This cannot be undone.</p><div class="actions"><button class="btn danger" id="confirmDelete">Delete account</button><button class="btn" id="cancelDelete">Cancel</button></div>`);
        on("cancelDelete", m.close);
        on("confirmDelete", async () => { await api("/admin/users/" + u.id, "DELETE"); m.close(); toast("Account deleted"); await reload(); });
      }));
    }
    draw();
  }

  /* ============================== ACCOUNT & SECURITY ============================== */
  const ACTIONS = {
    login: ["Signed in", "ok"], login_failed: ["Failed sign-in attempt", "bad"], password_changed: ["Password changed", "warn"],
    password_reset: ["Password reset by an administrator", "warn"], email_changed: ["Email address changed", "warn"], profile_updated: ["Profile updated", ""],
    session_revoked: ["Device signed out", ""], sessions_revoked: ["Other devices signed out", ""], forced_sign_out: ["Signed out by an administrator", "warn"],
    account_created: ["Account created", "ok"], account_updated: ["Account updated by an administrator", ""], keepalive_changed: ["Keep-alive settings changed", ""],
    account_deleted: ["Account deleted", "bad"],
  };
  const strength = (p) => {
    let s = 0;
    if (p.length >= 12) s++;
    if (p.length >= 16) s++;
    if (/[a-z]/.test(p) && /[A-Z]/.test(p)) s++;
    if (/\d/.test(p)) s++;
    if (/[^A-Za-z0-9]/.test(p)) s++;
    return Math.min(4, Math.max(p ? 1 : 0, s - 1));
  };
  const SLABEL = ["Enter a password", "Weak", "Fair", "Good", "Strong"];
  const generate = () => {
    const sets = "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#$%^&*-_";
    const bytes = crypto.getRandomValues(new Uint32Array(20));
    return Array.from(bytes, (n) => sets[n % sets.length]).join("");
  };
  async function account(c) {
    const { api, esc, ico, toast, on, form, modal, getUser, reloadUser, signedOut, getView } = c;
    const w = document.querySelector("#workspace");
    w.innerHTML = '<div class="loading">Loading your account…</div>';
    let a, activity = [];
    try { [a, activity] = await Promise.all([api("/account"), api("/account/activity").catch(() => [])]); } catch (e) {
      try { a = { ...(getUser()), instances: [], sessions: [] }; activity = []; } catch { w.textContent = e.message; return; }
    }
    if (getView() !== "account") return;
    a.email ||= getUser().email;
    a.role ||= getUser().role;
    a.sessions ||= [];
    a.instances ||= [];
    activity = Array.isArray(activity) ? activity : [];
    const checks = [
      { ok: !!a.passwordChangedAt, label: "Password updated by you", hint: a.passwordChangedAt ? "Changed " + ago(a.passwordChangedAt) : "Still using the initial password — change it now." },
      { ok: (a.sessions || []).length <= 3, label: "Few active sessions", hint: (a.sessions || []).length + " device" + ((a.sessions || []).length === 1 ? "" : "s") + " signed in" },
      { ok: !(a.instances || []).some((x) => x.hasKey && x.status !== "connected"), label: "No unused API keys", hint: (a.instances || []).filter((x) => x.hasKey).length + " active key(s); keys on disconnected numbers should be rotated or removed" },
      { ok: !activity.slice(0, 15).some((x) => x.action === "login_failed"), label: "No recent failed sign-ins", hint: activity.some((x) => x.action === "login_failed") ? "Review the activity log below" : "All clear" },
    ];
    const score = Math.round((checks.filter((x) => x.ok).length / checks.length) * 100);
    const initial = ((a.name || a.email || "?")[0] || "?").toUpperCase();
    w.innerHTML = `
    <div class="top"><div><div class="eyebrow">Account</div><h1>Account &amp; security</h1><p>Manage your profile, password, devices and recent security activity.</p></div></div>
    <section class="card ac-hero"><span class="avatar ac-av">${esc(initial)}</span><div class="ac-who"><h2>${esc(a.name || a.email.split("@")[0])}</h2><p class="hint">${esc(a.email)}</p><div class="ac-tags"><span class="role ${a.role === "admin" ? "admin" : ""}">${a.role === "admin" ? "Administrator" : "Workspace member"}</span><span class="hint">Member since ${esc(when(a.createdAt))}</span><span class="hint">Last sign-in ${esc(a.lastLoginAt ? ago(a.lastLoginAt) : "—")}</span></div></div>
      <div class="ac-score"><div class="ring" style="--p:${score}"><b>${score}%</b></div><span class="hint">Security score</span></div></section>
    <div class="ac-grid">
      <div class="ac-col">
        <section class="card"><h3>Profile</h3><form id="profileForm"><label for="profName">Display name</label><input id="profName" name="name" value="${esc(a.name || "")}" maxlength="80" placeholder="Your name"><div class="actions"><button class="btn primary" type="submit">Save profile</button></div></form>
          <hr class="sep"><h4>Email address</h4><form id="emailForm"><label for="newEmail">New email</label><input id="newEmail" name="email" type="email" value="${esc(a.email)}" maxlength="254" required><label for="emailPass">Confirm with your password</label><input id="emailPass" name="password" type="password" autocomplete="current-password" required><div class="actions"><button class="btn" type="submit">Update email</button></div></form></section>
        <section class="card"><h3>Change password</h3><p class="hint">Changing your password signs you out on every device.</p>
          <form id="passwordForm"><label for="currentPassword">Current password</label><input id="currentPassword" name="currentPassword" type="password" autocomplete="current-password" required>
            <label for="newPassword">New password</label><div class="pwrow"><input id="newPassword" name="newPassword" type="password" autocomplete="new-password" minlength="12" maxlength="200" required><button type="button" class="btn mini" id="pwShow">Show</button><button type="button" class="btn mini" id="pwGen">Generate</button></div>
            <div class="pwmeter" id="pwMeter"><i></i><i></i><i></i><i></i></div><p class="hint" id="pwLabel">Enter a password</p>
            <ul class="rules" id="pwRules"><li data-r="len">At least 12 characters</li><li data-r="case">Upper and lower case letters</li><li data-r="num">A number</li><li data-r="sym">A symbol</li></ul>
            <div class="actions"><button class="btn primary" type="submit">Change password</button></div></form></section>
      </div>
      <div class="ac-col">
        <section class="card"><div class="row card-title"><h3>Security checklist</h3></div><ul class="checks">${checks.map((x) => `<li class="${x.ok ? "ok" : "warn"}"><span>${ico(x.ok ? "check" : "alert", 18)}</span><div><strong>${esc(x.label)}</strong><small>${esc(x.hint)}</small></div></li>`).join("")}</ul></section>
        <section class="card"><div class="row card-title"><h3>Active sessions</h3>${(a.sessions || []).length > 1 ? '<button class="btn mini danger" id="revokeOthers">Sign out other devices</button>' : ""}</div>
          <div class="sessions">${(a.sessions || []).map((s) => { const dv = device(s.ua); return `<div class="sess"><span class="ico-box ${s.current ? "ok" : ""}">${ico(dv.mobile ? "phone" : "home", 18)}</span><div><strong>${esc(dv.label)}${s.current ? ' <em class="you">This device</em>' : ""}</strong><small>${esc(s.ip || "Unknown IP")} · signed in ${esc(ago(s.createdAt))}</small></div>${s.current ? "" : `<button class="btn mini" data-revoke="${esc(s.id)}">Sign out</button>`}</div>`; }).join("") || '<p class="hint">No session details available.</p>'}</div></section>
        <section class="card"><h3>API access</h3><p class="hint">API keys are created per WhatsApp number. Manage them under each number’s Connect tab.</p>
          <div class="keys">${(a.instances || []).map((x) => `<div class="keyrow"><div><strong>${esc(x.name)}</strong><small>${esc(x.phone ? "+" + x.phone : "Not linked")}</small></div><span class="status ${x.status === "connected" ? "connected" : ""}">${esc(x.status.replaceAll("_", " "))}</span><span class="chip-s">${x.hasKey ? "Key active" : "No key"}</span>${x.hasWebhook ? '<span class="chip-s">Webhook</span>' : ""}</div>`).join("") || '<p class="hint">No numbers yet.</p>'}</div></section>
        <section class="card"><h3>Recent security activity</h3><ol class="timeline">${activity.slice(0, 12).map((x) => { const [label, tone] = ACTIONS[x.action] || [x.action, ""]; const dv = device(x.ua); return `<li class="${tone}"><span class="dot"></span><div><strong>${esc(label)}</strong><small>${esc(when(x.createdAt))} · ${esc(x.ip || "")}${x.ua ? " · " + esc(dv.label) : ""}${x.detail && !/^Signed in$/.test(x.detail) ? " · " + esc(x.detail) : ""}</small></div></li>`; }).join("") || '<li><span class="dot"></span><div><strong>No activity recorded yet</strong></div></li>'}</ol></section>
      </div>
    </div>`;
    const pw = document.querySelector("#newPassword");
    const paint = () => {
      const v = pw.value, st = strength(v);
      document.querySelectorAll("#pwMeter i").forEach((el, i) => el.className = i < st ? "on s" + st : "");
      document.querySelector("#pwLabel").textContent = SLABEL[st];
      const rules = { len: v.length >= 12, case: /[a-z]/.test(v) && /[A-Z]/.test(v), num: /\d/.test(v), sym: /[^A-Za-z0-9]/.test(v) };
      document.querySelectorAll("#pwRules li").forEach((li) => li.classList.toggle("ok", !!rules[li.dataset.r]));
    };
    pw.oninput = paint;
    on("pwShow", () => { pw.type = pw.type === "password" ? "text" : "password"; document.querySelector("#pwShow").textContent = pw.type === "password" ? "Show" : "Hide"; });
    on("pwGen", () => { pw.value = generate(); pw.type = "text"; document.querySelector("#pwShow").textContent = "Hide"; paint(); copy(pw.value, toast, "Strong password generated and copied"); });
    form("profileForm", async (d) => { await api("/account/profile", "PUT", d); toast("Profile saved"); await reloadUser(); });
    form("emailForm", async (d) => { await api("/account/email", "PUT", d); toast("Email updated"); await reloadUser(); });
    form("passwordForm", async (d) => {
      await api("/account/password", "PUT", d);
      toast("Password changed. Sign in with your new password.");
      signedOut();
    });
    document.querySelectorAll("[data-revoke]").forEach((b) => (b.onclick = async () => {
      try { await api("/account/sessions/" + b.dataset.revoke, "DELETE"); toast("Device signed out"); account(c); } catch (e) { toast(e.message); }
    }));
    on("revokeOthers", async () => {
      const r = await api("/account/sessions/revoke-others", "POST", {});
      toast(r.revoked + " device" + (r.revoked === 1 ? "" : "s") + " signed out");
      account(c);
    });
    void modal;
  }
  return { system, users, account };
})();
