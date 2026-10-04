window.ZelonChat = (() => {
  const S = (d, size = 20, sw = 1.9) =>
    `<svg viewBox="0 0 24 24" width="${size}" height="${size}" fill="none" stroke="currentColor" stroke-width="${sw}" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${d}</svg>`;
  const I = {
    search: S('<circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/>', 18),
    plus: S('<path d="M12 5v14M5 12h14"/>'),
    refresh: S('<path d="M21 12a9 9 0 0 0-15-6.7L3 8"/><path d="M3 3v5h5"/><path d="M3 12a9 9 0 0 0 15 6.7L21 16"/><path d="M21 21v-5h-5"/>', 18),
    expand: S('<path d="M8 3H5a2 2 0 0 0-2 2v3m18 0V5a2 2 0 0 0-2-2h-3m0 18h3a2 2 0 0 0 2-2v-3M3 16v3a2 2 0 0 0 2 2h3"/>', 18),
    back: S('<path d="m12 19-7-7 7-7"/><path d="M19 12H5"/>'),
    send: S('<path d="m22 2-7 20-4-9-9-4z"/><path d="M22 2 11 13"/>'),
    clip: S('<path d="m21.44 11.05-9.19 9.19a6 6 0 0 1-8.49-8.49l8.57-8.57A4 4 0 1 1 18 8.84l-8.59 8.57a2 2 0 0 1-2.83-2.83l8.49-8.48"/>'),
    smile: S('<circle cx="12" cy="12" r="9"/><path d="M8 14s1.5 2 4 2 4-2 4-2"/><path d="M9 9h.01M15 9h.01"/>'),
    more: S('<circle cx="12" cy="5" r="1.3"/><circle cx="12" cy="12" r="1.3"/><circle cx="12" cy="19" r="1.3"/>'),
    x: S('<path d="M18 6 6 18M6 6l12 12"/>', 18),
    chev: S('<path d="m6 9 6 6 6-6"/>', 16),
    reply: S('<path d="M9 14 4 9l5-5"/><path d="M20 20v-7a4 4 0 0 0-4-4H4"/>', 17),
    copy: S('<rect x="9" y="9" width="12" height="12" rx="2"/><path d="M5 15V5a2 2 0 0 1 2-2h10"/>', 17),
    star: S('<path d="m12 2 3.1 6.3 6.9 1-5 4.9 1.2 6.8L12 17.8 5.8 21l1.2-6.8-5-4.9 6.9-1z"/>', 17),
    edit: S('<path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z"/>', 17),
    trash: S('<path d="M3 6h18"/><path d="M8 6V4h8v2"/><path d="M19 6l-1 14H6L5 6"/>', 17),
    forward: S('<path d="m15 14 5-5-5-5"/><path d="M4 20v-7a4 4 0 0 1 4-4h12"/>', 17),
    info: S('<circle cx="12" cy="12" r="9"/><path d="M12 8h.01M11 12h1v4h1"/>', 17),
    download: S('<path d="M12 3v12"/><path d="m7 10 5 5 5-5"/><path d="M4 21h16"/>', 17),
    pin: S('<path d="M12 17v5"/><path d="M9 3h6l-1 7 3 3H7l3-3z"/>', 17),
    archive: S('<rect x="3" y="4" width="18" height="4" rx="1"/><path d="M5 8v11a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1V8"/><path d="M10 12h4"/>', 17),
    mute: S('<path d="M13.7 21a2 2 0 0 1-3.4 0"/><path d="M18 8a6 6 0 0 0-9.3-5M6.3 6.3A6 6 0 0 0 6 8c0 7-3 9-3 9h14"/><path d="m2 2 20 20"/>', 17),
    check: S('<path d="m5 12 5 5 9-10"/>', 17),
    block: S('<circle cx="12" cy="12" r="9"/><path d="m5.6 5.6 12.8 12.8"/>', 17),
    group: S('<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>', 22),
    file: S('<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/>', 26),
    pin2: S('<path d="M20 10c0 6-8 12-8 12S4 16 4 10a8 8 0 0 1 16 0z"/><circle cx="12" cy="10" r="3"/>', 22),
    user: S('<path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/>', 22),
    poll: S('<path d="M18 20V10M12 20V4M6 20v-6"/>', 20),
    ban: S('<circle cx="12" cy="12" r="9"/><path d="m5.6 5.6 12.8 12.8"/>', 15),
    image: S('<rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/><path d="m21 15-5-5L5 21"/>', 20),
  };
  const tickPaths = {
    one: '<path d="M11.1.7 4.6 7.1 1.9 4.5 1 5.4l3.6 3.5L12 1.6z"/>',
    two: '<path d="M11.1.7 4.6 7.1 1.9 4.5 1 5.4l3.6 3.5L12 1.6z"/><path d="M15.1.7 8.6 7.1 7.7 6.2 6.8 7.1l1.8 1.8L16 1.6z"/>',
  };
  const tick = (kind, cls) => `<svg class="tick ${cls}" viewBox="0 0 17 10" width="16" height="10" fill="currentColor" aria-hidden="true">${tickPaths[kind]}</svg>`;
  const clock = '<svg class="tick pending" viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></svg>';
  const statusIcon = (m) => {
    if (m.pending) return m.late ? '<span class="tick failed" title="Not delivered">!</span>' : clock;
    switch (m.status) {
      case "failed": return '<span class="tick failed" title="Failed">!</span>';
      case "delivered": return tick("two", "delivered");
      case "read":
      case "played": return tick("two", "read");
      default: return tick("one", "sent");
    }
  };
  const EMOJI = Array.from(
    "😀😃😄😁😆😅😂🤣😊😇🙂😉😍🥰😘😗😋😛😜🤪😎🤩🥳😏😒😞😔😟😕🙁😣😖😫😩🥺😢😭😤😠😡🤬🤯😳🥵🥶😱😨😰😥😓🤗🤔🤭🤫🤥😶😐😑😬🙄😯😦😧😮😲🥱😴🤤😪😵🤐🥴🤢🤮🤧😷🤒🤕👍👎👌✌️🤞🤟🤘👏🙌🙏🤝💪👋🤙👈👉👆👇☝️✋🖐️🖖❤️🧡💛💚💙💜🖤🤍💔❣️💕💞💓💗💖💘💝🔥✨⭐🌟💫🎉🎊🎁🏆💯✅❌⚠️❓❗💬👀🙈🙉🙊☕🍕🍔🍟🍎🎂🌹🌸🌞🌙⚡🌈",
  ).filter((e) => e.trim() && e !== "\ufe0f");
  const QUICK = ["👍", "❤️", "😂", "😮", "😢", "🙏"];

  const initialOf = (n) => (String(n || "?").replace(/^[^\p{L}\p{N}]+/u, "")[0] || "?").toUpperCase();
  const hueOf = (s) => {
    let h = 0;
    for (const c of String(s || "")) h = (h * 31 + c.codePointAt(0)) % 360;
    return h;
  };
  const norm = (j) => String(j || "").replace(/:\d+@/, "@");
  const hhmm = (iso) => {
    const d = new Date(iso);
    return isNaN(d) ? "" : d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
  };
  const listTime = (iso) => {
    const d = new Date(iso);
    if (!iso || isNaN(d)) return "";
    const now = new Date();
    if (d.toDateString() === now.toDateString()) return hhmm(iso);
    if (d.toDateString() === new Date(now - 864e5).toDateString()) return "Yesterday";
    if (now - d < 6 * 864e5) return d.toLocaleDateString([], { weekday: "long" });
    return d.toLocaleDateString([], { day: "2-digit", month: "2-digit", year: "2-digit" });
  };
  const dayLabel = (iso) => {
    const d = new Date(iso);
    if (isNaN(d)) return "";
    const now = new Date();
    if (d.toDateString() === now.toDateString()) return "Today";
    if (d.toDateString() === new Date(now - 864e5).toDateString()) return "Yesterday";
    return d.toLocaleDateString([], { weekday: "long", day: "numeric", month: "long", year: "numeric" });
  };
  const bytes = (n) => (n > 1048576 ? (n / 1048576).toFixed(1) + " MB" : Math.max(1, Math.round(n / 1024)) + " KB");

  async function render(ctx) {
    const { p, base, api, esc, toast, upload } = ctx;
    document.body.classList.remove("inbox-lock");
    document.body.classList.add("page-chats");
    const picUrl = (id) => `/api${base}/chats/${encodeURIComponent(id)}/picture`;
    const mediaUrl = (m, inline) => `/api${base}/inbox/${encodeURIComponent(m.waId)}/media${inline ? "?inline=1" : ""}`;
    const avatar = (c, size = "", own = false) => {
      const group = c?.kind === "group" || /@g\.us$/.test(c?.chatId || "");
      const id = own ? "me" : c?.chatId;
      return `<span class="wa-av ${size} ${group ? "group" : ""}" style="--h:${hueOf(c?.chatId || "me")}"><i>${group ? I.group : esc(initialOf(c?.name || c?.chatId))}</i>${id ? `<img class="pic" loading="lazy" alt="" src="${esc(picUrl(id))}">` : ""}</span>`;
    };
    const fmt = (t) => {
      let s = esc(t);
      s = s.replace(/(https?:\/\/[^\s<]+[^\s<.,;:!?)\]'"])/g, (u) => `<a href="${u}" target="_blank" rel="noopener noreferrer">${u}</a>`);
      s = s.replace(/(^|[\s(>])\*([^*\n]+)\*(?=$|[\s).,!?<:])/g, "$1<b>$2</b>");
      s = s.replace(/(^|[\s(>])_([^_\n]+)_(?=$|[\s).,!?<:])/g, "$1<i>$2</i>");
      s = s.replace(/(^|[\s(>])~([^~\n]+)~(?=$|[\s).,!?<:])/g, "$1<s>$2</s>");
      s = s.replace(/`([^`\n]+)`/g, "<code>$1</code>");
      return s.replace(/\n/g, "<br>");
    };
    const getChats = async (cursor) => {
      const q = "?limit=100" + (cursor ? "&before=" + encodeURIComponent(cursor.createdAt) + "&beforeId=" + encodeURIComponent(cursor.id) : "");
      const r = await fetch("/api" + base + "/chats" + q);
      const rows = await r.json();
      if (!r.ok) throw Error(rows.error || "Could not load conversations");
      const h = (k) => r.headers?.get?.(k);
      return {
        rows,
        more: h("X-Has-More") != null ? h("X-Has-More") === "true" : rows.length === 100,
        cursor: h("X-Cursor-Created") ? { createdAt: h("X-Cursor-Created"), id: h("X-Cursor-Id") } : rows.at(-1),
      };
    };
    const byRecent = (a, b) => (b.pinned ? 1 : 0) - (a.pinned ? 1 : 0) || Date.parse(b.createdAt || 0) - Date.parse(a.createdAt || 0);
    const mergeChats = (cur, inc) => {
      const m = new Map(cur.map((c) => [c.chatId, c]));
      for (const c of inc) m.set(c.chatId, c);
      return [...m.values()].sort(byRecent);
    };

    let state = { status: "connected" };
    try { state = await api(base + "/state"); } catch {}
    const first = await getChats();
    let chats = mergeChats([], first.rows),
      hasMore = first.more,
      cursor = first.cursor,
      filter = "all",
      query = "",
      current = null,
      msgs = [],
      pending = [],
      hasOlder = false,
      loadingOlder = false,
      replyTo = null,
      editing = null,
      infoOpen = false,
      searchOpen = false,
      attachment = null,
      es = null,
      refreshTimer = null,
      presence = null,
      presenceTimer = null,
      typingSent = 0,
      typingStop = null,
      listSig = "",
      msgSig = "",
      unseen = 0;
    const drafts = new Map();
    const mm = (q) => (window.matchMedia ? window.matchMedia(q) : { matches: q.includes("max-width") ? false : true, addEventListener() {} });
    const mobile = mm("(max-width: 760px)");
    const syncLock = () => document.body.classList.toggle("inbox-lock", !!document.querySelector("#wa")?.classList.contains("inbox-full") || (mobile.matches && !!document.querySelector("#wa")?.classList.contains("chat-open")));

    p.innerHTML = `<div class="wa inboxlayout" id="wa">
      <aside class="wa-side" id="waSide">
        <header class="wa-head">
          <button class="wa-me" id="waMe" title="Your profile" aria-label="Your profile">${avatar({ name: "Me" }, "sm", true)}</button>
          <h3>Chats</h3>
          <div class="wa-tools">
            <button class="wa-ib" id="newChatBtn" title="New chat" aria-label="New chat">${I.plus}</button>
            <button class="wa-ib" id="reloadInbox" title="Refresh" aria-label="Refresh conversations">${I.refresh}</button>
            <button class="wa-ib" id="fullInbox" title="Full screen" aria-label="Full screen">${I.expand}</button>
          </div>
        </header>
        <div class="wa-banner" id="waBanner" hidden>This number is not connected. Open the <b>Connect</b> tab to link it.</div>
        <div class="wa-searchbox">${I.search}<input id="chatSearch" aria-label="Search conversations" placeholder="Search or start a new chat" autocomplete="off"></div>
        <div class="wa-chips" role="tablist">
          <button class="chip active" data-filter="all">All</button><button class="chip" data-filter="unread">Unread</button><button class="chip" data-filter="groups">Groups</button><button class="chip" data-filter="archived">Archived</button>
        </div>
        <div class="wa-list" id="chatRows"></div>
        <button class="btn mini wa-more" id="moreChats" hidden>Load more conversations</button>
      </aside>
      <section class="wa-main conversation" id="conversation"></section>
      <aside class="wa-info" id="waInfo" hidden></aside>
      <div class="wa-layer" id="waLayer"></div>
    </div>`;
    const $ = (sel) => p.querySelector(sel);
    const root = $("#wa"),
      layer = $("#waLayer");

    /* ---------- chat list ---------- */
    const preview = (c) => (c.lastPreview ? esc(c.lastPreview) : '<span class="muted">No messages yet</span>');
    function drawList(force) {
      const q = query.trim().toLowerCase();
      let rows = chats.filter((c) => {
        const text = ((c.name || "") + " " + (c.chatId || "") + " " + (c.phone || "")).toLowerCase();
        if (q && !text.includes(q)) return false;
        if (filter === "archived") return !!c.archived;
        if (c.archived) return false;
        return filter === "all" || (filter === "unread" && c.unread > 0) || (filter === "groups" && c.kind === "group");
      });
      const digits = q.replace(/\D/g, "");
      const startRow = digits.length >= 7 && !rows.length
        ? `<button class="wa-chat" data-start="${esc(digits)}"><span class="wa-av" style="--h:150"><i>${I.plus}</i></span><div class="wa-ct"><div class="wa-r1"><strong>Chat with +${esc(digits)}</strong></div><div class="wa-r2"><span class="wa-pv">Start a new conversation</span></div></div></button>`
        : "";
      const html = rows.map((c) => `<button class="wa-chat ${current?.chatId === c.chatId ? "active" : ""}" data-chat="${esc(c.chatId)}">
        ${avatar(c)}
        <div class="wa-ct"><div class="wa-r1"><strong>${esc(c.name || c.chatId)}</strong><time class="${c.unread ? "unread" : ""}">${esc(listTime(c.createdAt))}</time></div>
        <div class="wa-r2"><span class="wa-pv">${preview(c)}</span>${c.muteUntil && Date.parse(c.muteUntil) > Date.now() ? `<span class="wa-ico">${I.mute}</span>` : ""}${c.pinned ? `<span class="wa-ico">${I.pin}</span>` : ""}${c.unread ? `<b class="wa-badge">${c.unread > 99 ? "99+" : c.unread}</b>` : ""}</div></div></button>`).join("");
      const sig = html + startRow;
      if (!force && sig === listSig) return;
      listSig = sig;
      const box = $("#chatRows"),
        top = box.scrollTop;
      box.innerHTML = sig || `<div class="wa-empty-list">${filter === "all" && !q ? "No conversations yet." : "No conversations match."}</div>`;
      box.scrollTop = top;
      $("#moreChats").hidden = !hasMore;
    }
    async function refreshList() {
      const next = await getChats();
      const ids = new Set(next.rows.map((c) => c.chatId));
      chats = mergeChats(chats.filter((c) => !ids.has(c.chatId) || true), next.rows);
      if (current) {
        const live = chats.find((c) => c.chatId === current.chatId);
        if (live) current = { ...current, ...live };
      }
      drawList();
    }

    /* ---------- messages ---------- */
    const sameChat = (id) => {
      if (!current || !id) return false;
      const n = norm(id);
      return current.chatId === n || (current.aliases || []).includes(n);
    };
    const sigOf = (list) => JSON.stringify(list.map((m) => [m.waId, m.status, m.text, m.edited, m.deleted, m.starred, m.reactions, m.pending, m.late]));
    const allMsgs = () => [...pending.map((m) => ({ ...m })), ...msgs].sort((a, b) => Date.parse(b.createdAt) - Date.parse(a.createdAt));
    const senderName = (m) => (m.fromMe ? "You" : m.name || m.participant || "Contact");
    function mediaHtml(m) {
      if (!m.hasMedia) return "";
      const url = esc(mediaUrl(m, true));
      if (m.type === "image") return `<div class="wa-media"><img src="${url}" loading="lazy" alt="Photo" data-zoom="${esc(m.waId)}"></div>`;
      if (m.type === "sticker") return `<div class="wa-media sticker"><img src="${url}" loading="lazy" alt="Sticker"></div>`;
      if (m.type === "video") return `<div class="wa-media"><video controls preload="metadata" src="${url}"></video></div>`;
      if (m.type === "audio") return `<div class="wa-audio"><audio controls preload="none" src="${url}"></audio></div>`;
      return `<a class="wa-doc" href="${esc(mediaUrl(m, false))}">${I.file}<span><b>${esc(m.filename || "Document")}</b><small>${esc((m.mimetype || "File").split("/").pop().toUpperCase())} · tap to download</small></span></a>`;
    }
    function bodyHtml(m) {
      if (m.deleted) return `<div class="wa-text deleted">${I.ban} <span>This message was deleted</span></div>`;
      let h = m.quotedText ? `<div class="wa-quote">${esc(m.quotedText)}</div>` : "";
      h += mediaHtml(m);
      if (m.location && Number.isFinite(m.location.latitude))
        h += `<a class="wa-loc" target="_blank" rel="noopener noreferrer" href="https://www.google.com/maps?q=${encodeURIComponent(m.location.latitude + "," + m.location.longitude)}">${I.pin2}<span><b>${esc(m.location.name || "Shared location")}</b><small>${esc(m.location.address || "Open in Maps")}</small></span></a>`;
      for (const c of m.contacts || []) h += `<div class="wa-contact">${I.user}<span><b>${esc(c.name)}</b><small>Contact card</small></span></div>`;
      if (m.pollOptions?.length)
        h += `<div class="wa-poll"><b>${I.poll} ${esc(m.text || "Poll")}</b>${m.pollOptions.map((o) => `<div>○ ${esc(o)}</div>`).join("")}</div>`;
      else if (m.text) h += `<div class="wa-text">${fmt(m.text)}</div>`;
      else if (!m.hasMedia && !m.location && !(m.contacts || []).length) h += `<div class="wa-text muted">[${esc(m.type || "message")}]</div>`;
      else if (m.hasMedia && m.text) h += "";
      return h;
    }
    function reactionsHtml(m) {
      const entries = Object.values(m.reactions || {});
      if (!entries.length) return "";
      const counts = {};
      for (const e of entries) counts[e] = (counts[e] || 0) + 1;
      return `<div class="wa-reacts">${Object.entries(counts).map(([e, n]) => `<span>${esc(e)}${n > 1 ? `<small>${n}</small>` : ""}</span>`).join("")}</div>`;
    }
    function drawMessages({ stick = true, older = false, prev = 0 } = {}) {
      const box = $("#waMsgs");
      if (!box) return;
      const isGroup = current.kind === "group" || /@g\.us$/.test(current.chatId);
      const list = allMsgs().reverse();
      let day = "",
        lastKey = "",
        lastAt = 0,
        html = "";
      list.forEach((m, i) => {
        const d = dayLabel(m.createdAt);
        if (d && d !== day) { html += `<div class="wa-day"><span>${esc(d)}</span></div>`; day = d; lastKey = ""; }
        const key = m.fromMe ? "me" : m.participant || "them",
          at = Date.parse(m.createdAt) || 0,
          head = key !== lastKey || at - lastAt > 300000,
          next = list[i + 1],
          lastOfRun = !next || (next.fromMe ? "me" : next.participant || "them") !== key || dayLabel(next.createdAt) !== d || (Date.parse(next.createdAt) || 0) - at > 300000;
        lastKey = key; lastAt = at;
        const who = !m.fromMe && isGroup && head ? `<div class="wa-who" style="--h:${hueOf(m.participant || m.name)}">${esc(senderName(m))}</div>` : "";
        const av = !m.fromMe && isGroup
          ? lastOfRun
            ? `<span class="wa-av xs" style="--h:${hueOf(m.participant)}"><i>${esc(initialOf(senderName(m)))}</i>${m.participant ? `<img class="pic" loading="lazy" alt="" src="${esc(picUrl(m.participant))}">` : ""}</span>`
            : '<span class="wa-av xs ghost"></span>'
          : "";
        const meta = `<span class="wa-meta">${m.starred ? `<span class="wa-star">${I.star}</span>` : ""}${m.edited && !m.deleted ? "<em>edited</em>" : ""}<time>${esc(hhmm(m.createdAt))}</time>${m.fromMe && !m.deleted ? statusIcon(m) : ""}</span>`;
        const media = m.hasMedia && ["image", "video", "sticker"].includes(m.type) && !m.text;
        html += `<div class="wa-row ${m.fromMe ? "out" : "in"} ${head ? "head" : ""} ${isGroup ? "grp" : ""} ${m.pending ? "is-pending" : ""}" data-id="${esc(m.waId)}">${av}<div class="wa-b ${head ? "tail" : ""} ${media ? "mediaonly" : ""} ${m.type === "sticker" ? "stk" : ""}"><button class="wa-chev" data-menu="${esc(m.waId)}" aria-label="Message options" title="Options">${I.chev}</button>${who}${bodyHtml(m)}${meta}${reactionsHtml(m)}</div></div>`;
      });
      const wasBottom = box.scrollHeight - box.scrollTop - box.clientHeight < 90;
      const keepOffset = box.scrollHeight - box.scrollTop;
      box.innerHTML = (hasOlder ? '<div class="wa-older" id="waOlder">Loading older messages…</div>' : "") + (html || '<div class="wa-nomsg">No messages in this conversation yet. Say hello 👋</div>');
      if (older) box.scrollTop = box.scrollHeight - prev;
      else if (stick || wasBottom) { box.scrollTop = box.scrollHeight; unseen = 0; }
      else box.scrollTop = box.scrollHeight - keepOffset;
      $("#waNew").hidden = unseen === 0;
      $("#waNew").textContent = "↓ " + unseen + " new message" + (unseen === 1 ? "" : "s");
      applySearch();
    }
    function applySearch() {
      const q = $("#waFind")?.value.trim().toLowerCase();
      for (const row of p.querySelectorAll(".wa-row")) {
        const hit = !q || row.textContent.toLowerCase().includes(q);
        row.classList.toggle("dim", !hit);
      }
    }
    async function fetchMessages(older) {
      const last = msgs.at(-1);
      const suffix = older && last ? "&before=" + encodeURIComponent(last.createdAt) + "&beforeId=" + encodeURIComponent(last.id) : "";
      return api(base + "/chats/" + encodeURIComponent(current.chatId) + "/messages?limit=50" + suffix);
    }
    function dropMatchedPending() {
      pending = pending.filter((pm) => {
        if (Date.now() - pm.sentAt > 180000) return false;
        return !msgs.some((m) => m.fromMe && Date.parse(m.createdAt) >= pm.sentAt - 15000 && (pm.text ? m.text === pm.text : m.type === pm.type));
      });
      for (const pm of pending) pm.late = Date.now() - pm.sentAt > 60000;
    }
    async function refreshCurrent() {
      if (!current) return;
      const id = current.chatId;
      const rows = await fetchMessages(false);
      if (!current || current.chatId !== id) return;
      const known = new Set(msgs.map((m) => m.waId));
      const fresh = rows.filter((m) => !known.has(m.waId));
      const incoming = fresh.filter((m) => !m.fromMe).length;
      const map = new Map(msgs.map((m) => [m.waId, m]));
      for (const m of rows) map.set(m.waId, m);
      msgs = [...map.values()].sort((a, b) => Date.parse(b.createdAt) - Date.parse(a.createdAt) || (a.id < b.id ? 1 : -1));
      dropMatchedPending();
      const sig = sigOf(allMsgs());
      if (sig === msgSig) return;
      msgSig = sig;
      const box = $("#waMsgs");
      const atBottom = !box || box.scrollHeight - box.scrollTop - box.clientHeight < 90;
      if (!atBottom) unseen += incoming;
      drawMessages({ stick: false });
      if (incoming && !document.hidden) markRead();
    }
    let readTimer;
    function markRead() {
      if (!current) return;
      clearTimeout(readTimer);
      readTimer = setTimeout(async () => {
        if (!current) return;
        const c = chats.find((x) => x.chatId === current.chatId);
        try {
          await api(base + "/chats/" + encodeURIComponent(current.chatId) + "/settings", "PUT", { read: true });
          if (c) { c.unread = 0; drawList(); }
        } catch { /* reading receipts are best effort */ }
      }, 400);
    }
    function scheduleRefresh(chatId) {
      clearTimeout(refreshTimer);
      refreshTimer = setTimeout(() => {
        refreshList().catch(() => {});
        if (!chatId || sameChat(chatId)) refreshCurrent().catch(() => {});
      }, 250);
    }

    /* ---------- conversation view ---------- */
    function headSub() {
      if (!current) return "";
      if (presence && presence.chatId === current.chatId && presence.until > Date.now()) {
        return `<span class="live">${presence.state === "recording" ? "recording audio…" : (presence.who ? presence.who + " is " : "") + "typing…"}</span>`;
      }
      if (current.kind === "group") return esc(current.participants ? current.participants + " participants" : "Group · click for group info");
      return esc(current.phone || "Click for contact info");
    }
    function drawConversation() {
      const c = $("#conversation");
      if (!current) {
        c.innerHTML = `<div class="wa-welcome"><div class="wa-wmark">${I.send}</div><h2>Zelon Web Chat</h2><p>Select a conversation to read and reply in real time.<br>Messages stay in sync with your phone.</p></div>`;
        root.classList.remove("chat-open");
        syncLock();
        return;
      }
      const draft = drafts.get(current.chatId) || "";
      c.innerHTML = `<header class="wa-chead">
          <button class="wa-ib wa-back" id="chatBack" aria-label="Back to conversations">${I.back}</button>
          <button class="wa-who-btn" id="waHeadInfo" title="Contact info">${avatar(current, "md")}<span class="wa-title"><strong>${esc(current.name || current.chatId)}</strong><small id="waSub">${headSub()}</small></span></button>
          <div class="wa-tools">
            <button class="wa-ib" id="waSearchBtn" title="Search in chat" aria-label="Search in chat">${I.search}</button>
            <button class="wa-ib" id="refreshChat" title="Refresh" aria-label="Refresh chat">${I.refresh}</button>
            <button class="wa-ib" id="fullInbox2" title="Full screen" aria-label="Full screen">${I.expand}</button>
            <button class="wa-ib" id="waMore" title="Menu" aria-label="Chat menu">${I.more}</button>
          </div>
        </header>
        <div class="wa-find" id="waFindBar" ${searchOpen ? "" : "hidden"}>${I.search}<input id="waFind" placeholder="Search in this conversation" autocomplete="off"><button class="wa-ib" id="waFindClose" aria-label="Close search">${I.x}</button></div>
        <div class="wa-msgs" id="waMsgs" aria-live="polite"></div>
        <button class="wa-newpill" id="waNew" hidden></button>
        <div class="wa-compose-wrap">
          <div class="wa-ctx" id="waCtx" hidden></div>
          <div class="wa-attach" id="waAttach" hidden></div>
          <form id="replyForm" class="wa-compose">
            <div class="wa-emoji" id="waEmoji" hidden>${EMOJI.map((e) => `<button type="button" data-emoji="${e}">${e}</button>`).join("")}</div>
            <button type="button" class="wa-ib" id="waEmojiBtn" title="Emoji" aria-label="Emoji">${I.smile}</button>
            <label class="wa-ib attach" title="Attach a file">${I.clip}<input id="replyAttachment" name="replyAttachment" type="file" aria-label="Attach an image, video, audio or document"></label>
            <textarea id="replyText" name="replyText" rows="1" maxlength="20000" placeholder="Type a message" aria-label="Message">${esc(draft)}</textarea>
            <button type="submit" class="wa-send send-btn" aria-label="Send">${I.send}</button>
          </form>
        </div>`;
      root.classList.add("chat-open");
      drawContext();
      bindComposer();
      $("#fullInbox2").onclick = toggleFull;
      $("#fullInbox2").classList.toggle("on", root.classList.contains("inbox-full"));
      syncLock();
    }
    function drawContext() {
      const box = $("#waCtx");
      if (!box) return;
      if (editing) {
        box.hidden = false;
        box.innerHTML = `<div class="wa-ctxcard edit"><div><b>Editing message</b><span>${esc((editing.text || "").slice(0, 120))}</span></div><button class="wa-ib" id="waCtxX" aria-label="Cancel edit">${I.x}</button></div>`;
      } else if (replyTo) {
        box.hidden = false;
        box.innerHTML = `<div class="wa-ctxcard"><div><b>${esc(senderName(replyTo))}</b><span>${esc((replyTo.text || "[" + (replyTo.type || "message") + "]").slice(0, 120))}</span></div><button class="wa-ib" id="waCtxX" aria-label="Cancel reply">${I.x}</button></div>`;
      } else { box.hidden = true; box.innerHTML = ""; }
      $("#waCtxX") && ($("#waCtxX").onclick = () => { replyTo = null; editing = null; $("#replyText").value = drafts.get(current.chatId) || ""; drawContext(); });
    }
    function drawAttachment() {
      const box = $("#waAttach");
      if (!attachment) { box.hidden = true; box.innerHTML = ""; return; }
      box.hidden = false;
      const isImg = attachment.type.startsWith("image/");
      box.innerHTML = `<div class="wa-attcard">${isImg ? `<img alt="" src="${esc(attachment.preview)}">` : I.file}<div><b>${esc(attachment.name)}</b><small>${bytes(attachment.size)} · add a caption below</small></div><button type="button" class="wa-ib" id="waAttX" aria-label="Remove attachment">${I.x}</button></div>`;
      $("#waAttX").onclick = () => { if (attachment.preview) URL.revokeObjectURL(attachment.preview); attachment = null; $("#replyAttachment").value = ""; drawAttachment(); };
    }
    function setAttachment(file) {
      if (!file) return;
      if (attachment?.preview) URL.revokeObjectURL(attachment.preview);
      attachment = { file, name: file.name || "pasted-image.png", size: file.size, type: file.type || "application/octet-stream", preview: file.type?.startsWith("image/") ? URL.createObjectURL(file) : "" };
      drawAttachment();
      $("#replyText").focus();
    }
    function sendPresence(kind) {
      if (!current) return;
      api(base + "/chats/" + encodeURIComponent(current.chatId) + "/presence", "POST", { presence: kind }).catch(() => {});
    }
    function bindComposer() {
      const ta = $("#replyText"),
        formEl = $("#replyForm");
      const grow = () => { ta.style.height = "auto"; ta.style.height = Math.min(ta.scrollHeight, 140) + "px"; };
      grow();
      ta.oninput = () => {
        grow();
        if (!editing) drafts.set(current.chatId, ta.value);
        if (Date.now() - typingSent > 4000 && ta.value.trim()) { typingSent = Date.now(); sendPresence("composing"); }
        clearTimeout(typingStop);
        typingStop = setTimeout(() => { typingSent = 0; sendPresence("paused"); }, 5000);
      };
      ta.onkeydown = (e) => {
        if (e.key === "Enter" && !e.shiftKey && !e.isComposing) { e.preventDefault(); formEl.requestSubmit(); }
        if (e.key === "Escape" && (replyTo || editing)) { replyTo = null; editing = null; ta.value = drafts.get(current.chatId) || ""; drawContext(); }
      };
      ta.onpaste = (e) => {
        const f = [...(e.clipboardData?.files || [])][0];
        if (f) { e.preventDefault(); setAttachment(f); }
      };
      $("#replyAttachment").onchange = (e) => setAttachment(e.target.files[0]);
      $("#waEmojiBtn").onclick = () => { $("#waEmoji").hidden = !$("#waEmoji").hidden; };
      $("#waEmoji").onclick = (e) => {
        const b = e.target.closest("[data-emoji]");
        if (!b) return;
        const s = ta.selectionStart ?? ta.value.length;
        ta.value = ta.value.slice(0, s) + b.dataset.emoji + ta.value.slice(ta.selectionEnd ?? s);
        ta.selectionStart = ta.selectionEnd = s + b.dataset.emoji.length;
        ta.focus(); ta.oninput();
      };
      const conv = $("#conversation");
      conv.ondragover = (e) => { if (e.dataTransfer?.types?.includes("Files")) { e.preventDefault(); conv.classList.add("drop"); } };
      conv.ondragleave = () => conv.classList.remove("drop");
      conv.ondrop = (e) => { e.preventDefault(); conv.classList.remove("drop"); setAttachment(e.dataTransfer.files[0]); };
      formEl.onsubmit = async (e) => {
        e.preventDefault();
        const text = ta.value.trim();
        if (editing) {
          if (!text) return toast("Write the new message text");
          const target = editing;
          try {
            await api(base + "/inbox/" + encodeURIComponent(target.waId) + "/text", "PUT", { text });
            const m = msgs.find((x) => x.waId === target.waId);
            if (m) { m.text = text; m.edited = true; }
            editing = null; ta.value = drafts.get(current.chatId) || ""; grow(); drawContext();
            msgSig = ""; drawMessages({ stick: false });
          } catch (err) { toast(err.message); }
          return;
        }
        if (!text && !attachment) return;
        const btn = formEl.querySelector("button[type=submit]");
        btn.disabled = true;
        const quotedId = replyTo?.waId,
          file = attachment?.file;
        const payload = { to: current.chatId, type: "text", text, quotedId };
        const tmp = { waId: "tmp-" + crypto.randomUUID(), fromMe: true, pending: true, sentAt: Date.now(), createdAt: new Date().toISOString(), status: "pending", text, type: "text", hasMedia: false, quotedText: replyTo ? (replyTo.text || "").slice(0, 200) : "", reactions: {} };
        try {
          if (file) {
            payload.type = file.type.startsWith("image/") ? "image" : file.type.startsWith("video/") ? "video" : file.type.startsWith("audio/") ? "audio" : "document";
            payload.mediaId = await upload(base, file, api, toast);
            if (!text) delete payload.text;
            tmp.type = payload.type;
            tmp.text = text;
            tmp.filename = file.name;
            tmp.hasMedia = false;
            tmp.text = text || "📎 " + file.name;
          }
          if (!formEl.dataset.key) formEl.dataset.key = crypto.randomUUID();
          await api(base + "/messages", "POST", payload, { "Idempotency-Key": formEl.dataset.key });
          formEl.dataset.key = "";
          pending.push(tmp);
          drafts.delete(current.chatId);
          ta.value = ""; grow();
          replyTo = null; drawContext();
          if (attachment?.preview) URL.revokeObjectURL(attachment.preview);
          attachment = null; $("#replyAttachment").value = ""; drawAttachment();
          sendPresence("paused");
          msgSig = "";
          drawMessages({ stick: true });
          setTimeout(() => refreshCurrent().catch(() => {}), 1500);
          setTimeout(() => refreshCurrent().catch(() => {}), 4000);
        } catch (err) { toast(err.message); }
        finally { btn.disabled = false; ta.focus(); }
      };
      $("#chatBack").onclick = () => { root.classList.remove("chat-open"); closeInfo(); syncLock(); };
      $("#refreshChat").onclick = () => open(current.chatId, { keep: true }).catch((e) => toast(e.message));
      $("#waHeadInfo").onclick = () => openInfo();
      $("#waSearchBtn").onclick = () => { searchOpen = !searchOpen; $("#waFindBar").hidden = !searchOpen; if (searchOpen) $("#waFind").focus(); else { $("#waFind").value = ""; applySearch(); } };
      $("#waFindClose").onclick = () => { searchOpen = false; $("#waFindBar").hidden = true; $("#waFind").value = ""; applySearch(); };
      $("#waFind").oninput = applySearch;
      $("#waMore").onclick = (e) => { e.stopPropagation(); chatMenu(e.currentTarget.getBoundingClientRect(), current); };
      $("#waNew").onclick = () => { const b = $("#waMsgs"); b.scrollTop = b.scrollHeight; unseen = 0; $("#waNew").hidden = true; };
      const box = $("#waMsgs");
      box.onscroll = async () => {
        if (box.scrollHeight - box.scrollTop - box.clientHeight < 60 && unseen) { unseen = 0; $("#waNew").hidden = true; }
        if (box.scrollTop < 50 && hasOlder && !loadingOlder) {
          loadingOlder = true;
          const prev = box.scrollHeight;
          try {
            const rows = await fetchMessages(true);
            const known = new Set(msgs.map((m) => m.waId));
            msgs = [...msgs, ...rows.filter((m) => !known.has(m.waId))];
            hasOlder = rows.length === 50;
            drawMessages({ older: true, prev });
          } catch (err) { toast(err.message); }
          finally { loadingOlder = false; }
        }
      };
    }

    async function open(id, { keep = false } = {}) {
      id = norm(id);
      const known = chats.find((x) => x.chatId === id || (x.aliases || []).includes(id));
      const stash = window.__zelonChatMeta?.id === id ? window.__zelonChatMeta : null;
      const meta = known || stash || { chatId: id, name: /@g\.us$/.test(id) ? "Group" : "+" + id.split("@")[0], kind: /@g\.us$/.test(id) ? "group" : "contact", phone: /@s\.whatsapp\.net$/.test(id) ? "+" + id.split("@")[0] : "" };
      const chatId = known?.chatId || meta.chatId || id;
      const switching = !current || current.chatId !== chatId;
      if (current) drafts.set(current.chatId, $("#replyText")?.value || drafts.get(current.chatId) || "");
      current = { ...meta, chatId };
      if (switching) { msgs = []; pending = []; replyTo = null; editing = null; attachment = null; searchOpen = false; unseen = 0; msgSig = ""; closeInfo(); presence = null; }
      drawConversation();
      drawList(true);
      const rows = await fetchMessages(false);
      if (!current || current.chatId !== chatId) return;
      msgs = rows;
      hasOlder = rows.length === 50;
      msgSig = sigOf(allMsgs());
      drawMessages({ stick: true });
      api(base + "/chats/" + encodeURIComponent(chatId) + "/subscribe", "POST", {}).catch(() => {});
      if (current.unread) markRead();
      if (mm("(min-width: 761px)").matches) $("#replyText")?.focus();
    }

    /* ---------- menus, modals ---------- */
    function closeMenus() { layer.querySelectorAll(".wa-menu").forEach((n) => n.remove()); }
    function modal(title, body, { wide = false } = {}) {
      const el = document.createElement("div");
      el.className = "wa-modal";
      el.innerHTML = `<div class="wa-dialog ${wide ? "wide" : ""}" role="dialog" aria-modal="true"><header><h3>${title}</h3><button class="wa-ib" data-close aria-label="Close">${I.x}</button></header><div class="wa-dbody">${body}</div></div>`;
      el.onclick = (e) => { if (e.target === el || e.target.closest("[data-close]")) el.remove(); };
      layer.appendChild(el);
      return el;
    }
    function placeMenu(menu, x, y) {
      layer.appendChild(menu);
      const r = root.getBoundingClientRect(),
        w = menu.offsetWidth,
        h = menu.offsetHeight;
      const left = Math.max(8, Math.min(x - r.left, r.width - w - 8)),
        top = Math.max(8, Math.min(y - r.top, r.height - h - 8));
      menu.style.left = left + "px";
      menu.style.top = top + "px";
    }
    function messageMenu(m, x, y) {
      closeMenus();
      if (m.pending) return;
      const menu = document.createElement("div");
      menu.className = "wa-menu";
      const items = [];
      if (!m.deleted) {
        items.push(["reply", I.reply, "Reply"]);
        if (m.text) items.push(["copy", I.copy, "Copy"]);
        items.push(["forward", I.forward, "Forward"]);
        items.push(["star", I.star, m.starred ? "Unstar" : "Star"]);
        if (m.fromMe && m.text && !m.hasMedia && m.type !== "poll") items.push(["edit", I.edit, "Edit"]);
        if (m.hasMedia) items.push(["download", I.download, "Download"]);
        if (m.pollOptions?.length) items.push(["votes", I.poll, "Poll results"]);
        items.push(["info", I.info, "Message info"]);
      }
      items.push(["delete", I.trash, "Delete", "danger"]);
      menu.innerHTML = (m.deleted ? "" : `<div class="wa-quick">${QUICK.map((e) => `<button data-react="${e}" class="${m.reactions?.me === e ? "on" : ""}">${e}</button>`).join("")}</div>`) +
        items.map(([k, ic, label, cls]) => `<button data-act="${k}" class="${cls || ""}">${ic}<span>${label}</span></button>`).join("");
      menu.onclick = async (e) => {
        const react = e.target.closest("[data-react]"),
          act = e.target.closest("[data-act]");
        if (react) { closeMenus(); return doReact(m, react.dataset.react); }
        if (!act) return;
        closeMenus();
        messageAction(act.dataset.act, m);
      };
      placeMenu(menu, x, y);
    }
    async function doReact(m, emoji) {
      const same = m.reactions?.me === emoji;
      try {
        await api(base + "/inbox/" + encodeURIComponent(m.waId) + "/reaction", "POST", { emoji: same ? "" : emoji });
        const live = msgs.find((x) => x.waId === m.waId);
        if (live) { live.reactions = { ...(live.reactions || {}) }; if (same) delete live.reactions.me; else live.reactions.me = emoji; }
        msgSig = ""; drawMessages({ stick: false });
      } catch (err) { toast(err.message); }
    }
    async function messageAction(act, m) {
      try {
        if (act === "reply") { replyTo = m; editing = null; drawContext(); $("#replyText").focus(); }
        else if (act === "copy") { await navigator.clipboard?.writeText(m.text || ""); toast("Copied"); }
        else if (act === "edit") { editing = m; replyTo = null; drawContext(); const ta = $("#replyText"); ta.value = m.text || ""; ta.focus(); ta.oninput?.(); }
        else if (act === "star") {
          await api(base + "/inbox/" + encodeURIComponent(m.waId) + "/star", "POST", { star: !m.starred });
          const live = msgs.find((x) => x.waId === m.waId);
          if (live) live.starred = !m.starred;
          msgSig = ""; drawMessages({ stick: false });
        }
        else if (act === "download") window.location.href = mediaUrl(m, false);
        else if (act === "forward") forwardDialog(m);
        else if (act === "delete") deleteDialog(m);
        else if (act === "info") infoDialog(m);
        else if (act === "votes") {
          const votes = await api(base + "/polls/" + encodeURIComponent(m.waId) + "/votes");
          const rows = Array.isArray(votes) ? votes : Object.entries(votes || {}).map(([name, voters]) => ({ name, voters }));
          modal("Poll results", rows.length ? rows.map((v) => `<div class="wa-line"><b>${esc(v.name)}</b><span>${(v.voters || []).length} vote${(v.voters || []).length === 1 ? "" : "s"}</span></div>`).join("") : '<p class="muted">No votes yet.</p>');
        }
      } catch (err) { toast(err.message); }
    }
    function deleteDialog(m) {
      const el = modal("Delete message?", `<p class="muted">${m.fromMe ? "You can delete this message for everyone, or only remove it from this dashboard." : "This removes the message from this dashboard only."}</p>
        <div class="wa-dactions">${m.fromMe ? '<button class="btn danger" data-del="everyone">Delete for everyone</button>' : ""}<button class="btn" data-del="me">Delete for me</button><button class="btn ghost" data-close>Cancel</button></div>`);
      el.onclick = async (e) => {
        if (e.target === el || e.target.closest("[data-close]")) return el.remove();
        const b = e.target.closest("[data-del]");
        if (!b) return;
        b.disabled = true;
        try {
          await api(base + "/inbox/" + encodeURIComponent(m.waId) + "/delete", "POST", { scope: b.dataset.del });
          if (b.dataset.del === "me") msgs = msgs.filter((x) => x.waId !== m.waId);
          else { const live = msgs.find((x) => x.waId === m.waId); if (live) { live.deleted = true; live.text = ""; live.hasMedia = false; } }
          el.remove(); msgSig = ""; drawMessages({ stick: false });
          toast(b.dataset.del === "me" ? "Deleted for you" : "Deleted for everyone");
        } catch (err) { toast(err.message); b.disabled = false; }
      };
    }
    function forwardDialog(m) {
      const selected = new Set();
      const el = modal("Forward message", `<div class="wa-searchbox">${I.search}<input id="fwSearch" placeholder="Search chats" autocomplete="off"></div><div class="wa-fwlist" id="fwList"></div><div class="wa-dactions"><button class="btn primary" id="fwSend" disabled>Send</button></div>`);
      const draw = () => {
        const q = el.querySelector("#fwSearch").value.toLowerCase();
        el.querySelector("#fwList").innerHTML = chats.filter((c) => !c.archived && ((c.name || "") + c.chatId).toLowerCase().includes(q)).slice(0, 80)
          .map((c) => `<label class="wa-fwrow">${avatar(c, "sm")}<span><b>${esc(c.name || c.chatId)}</b><small>${esc(c.kind === "group" ? "Group" : c.phone || "")}</small></span><input type="checkbox" data-fw="${esc(c.chatId)}" ${selected.has(c.chatId) ? "checked" : ""}></label>`).join("") || '<p class="muted">No chats found.</p>';
        const b = el.querySelector("#fwSend");
        b.disabled = !selected.size;
        b.textContent = selected.size ? "Send to " + selected.size : "Send";
      };
      draw();
      el.querySelector("#fwSearch").oninput = draw;
      el.addEventListener("change", (e) => {
        const c = e.target.closest("[data-fw]");
        if (!c) return;
        c.checked ? selected.add(c.dataset.fw) : selected.delete(c.dataset.fw);
        const b = el.querySelector("#fwSend");
        b.disabled = !selected.size;
        b.textContent = selected.size ? "Send to " + selected.size : "Send";
      });
      el.querySelector("#fwSend").onclick = async (e) => {
        e.currentTarget.disabled = true;
        let ok = 0;
        for (const to of selected) {
          try { await api(base + "/messages", "POST", { to, type: "forward", forwardId: m.waId }, { "Idempotency-Key": crypto.randomUUID() }); ok++; }
          catch (err) { toast(err.message); }
        }
        el.remove();
        if (ok) toast("Forwarded to " + ok + " chat" + (ok === 1 ? "" : "s"));
        setTimeout(() => scheduleRefresh(), 2500);
      };
    }
    function infoDialog(m) {
      const t = new Date(m.createdAt);
      modal("Message info", `<div class="wa-line"><b>Type</b><span>${esc(m.type || "text")}</span></div><div class="wa-line"><b>From</b><span>${esc(senderName(m))}</span></div><div class="wa-line"><b>Time</b><span>${esc(t.toLocaleString())}</span></div>${m.fromMe ? `<div class="wa-line"><b>Status</b><span class="wa-st ${esc(m.status)}">${esc(m.status)}</span></div>` : ""}<div class="wa-line"><b>Message ID</b><span class="mono">${esc(m.waId)}</span></div>`);
    }
    async function chatSetting(c, body, done) {
      try {
        await api(base + "/chats/" + encodeURIComponent(c.chatId) + "/settings", "PUT", body);
        const live = chats.find((x) => x.chatId === c.chatId);
        if (live) {
          if (body.pin !== undefined) live.pinned = body.pin;
          if (body.archive !== undefined) live.archived = body.archive;
          if (body.muteUntil !== undefined) live.muteUntil = body.muteUntil;
          if (body.read) live.unread = 0;
          chats.sort(byRecent);
        }
        if (current?.chatId === c.chatId && live) current = { ...current, ...live };
        drawList(true);
        toast(done);
      } catch (err) { toast(err.message); }
    }
    function chatMenu(rect, c) {
      closeMenus();
      const live = chats.find((x) => x.chatId === c.chatId) || c;
      const muted = live.muteUntil && Date.parse(live.muteUntil) > Date.now();
      const menu = document.createElement("div");
      menu.className = "wa-menu";
      const items = [
        ["open", I.user, "Open chat"],
        ["info", I.info, c.kind === "group" ? "Group info" : "Contact info"],
        ["read", I.check, "Mark as read"],
        ["pin", I.pin, live.pinned ? "Unpin chat" : "Pin chat"],
        ["mute", I.mute, muted ? "Unmute notifications" : "Mute for 8 hours"],
        ["archive", I.archive, live.archived ? "Unarchive chat" : "Archive chat"],
      ];
      menu.innerHTML = items.map(([k, ic, l]) => `<button data-act="${k}">${ic}<span>${l}</span></button>`).join("");
      menu.onclick = async (e) => {
        const b = e.target.closest("[data-act]");
        if (!b) return;
        closeMenus();
        const k = b.dataset.act;
        if (k === "open") open(c.chatId).catch((err) => toast(err.message));
        else if (k === "info") { if (current?.chatId !== c.chatId) await open(c.chatId).catch(() => {}); openInfo(); }
        else if (k === "read") chatSetting(c, { read: true }, "Marked as read");
        else if (k === "pin") chatSetting(c, { pin: !live.pinned }, live.pinned ? "Unpinned" : "Pinned");
        else if (k === "mute") chatSetting(c, { muteUntil: muted ? null : new Date(Date.now() + 8 * 3600000).toISOString() }, muted ? "Unmuted" : "Muted for 8 hours");
        else if (k === "archive") chatSetting(c, { archive: !live.archived }, live.archived ? "Unarchived" : "Archived");
      };
      placeMenu(menu, rect.left, rect.bottom + 4);
    }

    /* ---------- contact / group info panel ---------- */
    function closeInfo() { infoOpen = false; const a = $("#waInfo"); if (a) { a.hidden = true; a.innerHTML = ""; } root.classList.remove("info-open"); }
    async function openInfo(target = current) {
      if (!target) return;
      infoOpen = true;
      const a = $("#waInfo");
      a.hidden = false;
      root.classList.add("info-open");
      const live = chats.find((x) => x.chatId === target.chatId) || target;
      const muted = live.muteUntil && Date.parse(live.muteUntil) > Date.now();
      const shell = (inner) => `<header class="wa-ihead"><button class="wa-ib" id="waInfoX" aria-label="Close info">${I.x}</button><h3>${target.kind === "group" ? "Group info" : "Contact info"}</h3></header><div class="wa-ibody">
        <div class="wa-hero">${avatar(target, "xl")}<h2>${esc(target.name || target.chatId)}</h2><p>${esc(target.kind === "group" ? (target.participants ? target.participants + " participants" : "Group") : target.phone || "")}</p></div>${inner}</div>`;
      const bind = () => {
        $("#waInfoX").onclick = closeInfo;
        $("#waInfoAvatar") && 0;
        a.querySelectorAll("[data-iact]").forEach((b) => (b.onclick = async () => {
          const k = b.dataset.iact;
          if (k === "pin") chatSetting(target, { pin: !live.pinned }, live.pinned ? "Unpinned" : "Pinned").then(() => openInfo(target));
          if (k === "mute") chatSetting(target, { muteUntil: muted ? null : new Date(Date.now() + 8 * 3600000).toISOString() }, muted ? "Unmuted" : "Muted for 8 hours").then(() => openInfo(target));
          if (k === "archive") chatSetting(target, { archive: !live.archived }, live.archived ? "Unarchived" : "Archived").then(() => openInfo(target));
          if (k === "read") chatSetting(target, { read: true }, "Marked as read");
          if (k === "copy") { await navigator.clipboard?.writeText(target.phone || target.chatId); toast("Copied"); }
          if (k === "block" || k === "unblock") {
            try { await api(base + "/contacts/block", "PUT", { phone: target.phone, blocked: k === "block" }); toast(k === "block" ? "Contact blocked" : "Contact unblocked"); openInfo(target); }
            catch (err) { toast(err.message); }
          }
        }));
        a.querySelectorAll("[data-open]").forEach((b) => (b.onclick = () => { closeInfo(); open(b.dataset.open).catch((err) => toast(err.message)); }));
      };
      const actions = `<div class="wa-iactions"><button data-iact="pin">${I.pin}<span>${live.pinned ? "Unpin" : "Pin"}</span></button><button data-iact="mute">${I.mute}<span>${muted ? "Unmute" : "Mute"}</span></button><button data-iact="archive">${I.archive}<span>${live.archived ? "Unarchive" : "Archive"}</span></button><button data-iact="read">${I.check}<span>Mark read</span></button></div>`;
      a.innerHTML = shell(actions + '<div class="wa-card"><p class="muted">Loading details…</p></div>');
      bind();
      try {
        const d = await api(base + "/chats/" + encodeURIComponent(target.chatId) + "/info");
        if (!infoOpen || current?.chatId !== target.chatId) return;
        let extra = "";
        if (d.kind === "group") {
          extra = `${d.description ? `<div class="wa-card"><small>Description</small><p>${fmt(d.description)}</p></div>` : ""}
            <div class="wa-card"><div class="wa-line"><b>Created</b><span>${d.createdAt ? esc(new Date(d.createdAt).toLocaleDateString()) : "—"}</span></div><div class="wa-line"><b>Created by</b><span>${esc(d.owner || "—")}</span></div><div class="wa-line"><b>Messages</b><span>${d.announce ? "Only admins" : "All members"}</span></div></div>
            <div class="wa-card"><small>${d.participants.length} participants</small>${d.participants.map((x) => `<button class="wa-part" data-open="${esc(x.id)}"><span class="wa-av sm" style="--h:${hueOf(x.id)}"><i>${esc(initialOf(x.name || x.phone))}</i><img class="pic" loading="lazy" alt="" src="${esc(picUrl(x.id))}"></span><span><b>${esc(x.name || x.phone)}</b><small>${esc(x.name ? x.phone : "")}</small></span>${x.admin ? '<em class="wa-admin">Admin</em>' : ""}</button>`).join("")}</div>`;
        } else {
          const biz = d.business;
          extra = `<div class="wa-card"><small>About</small><p>${d.about ? fmt(d.about) : '<span class="muted">No status available</span>'}</p>${d.aboutSetAt ? `<small class="muted">Updated ${esc(new Date(d.aboutSetAt).toLocaleDateString())}</small>` : ""}</div>
            <div class="wa-card"><div class="wa-line"><b>Phone</b><span>${esc(d.phone || target.phone || "—")}</span></div>${d.name ? `<div class="wa-line"><b>Saved name</b><span>${esc(d.name)}</span></div>` : ""}</div>
            ${biz ? `<div class="wa-card"><small>Business</small>${biz.description ? `<p>${esc(biz.description)}</p>` : ""}${biz.address ? `<div class="wa-line"><b>Address</b><span>${esc(biz.address)}</span></div>` : ""}${biz.email ? `<div class="wa-line"><b>Email</b><span>${esc(biz.email)}</span></div>` : ""}</div>` : ""}
            <div class="wa-card danger-zone">${target.phone ? `<button data-iact="${d.blocked ? "unblock" : "block"}" class="wa-dangerbtn">${I.block}<span>${d.blocked ? "Unblock" : "Block"} ${esc(target.name || target.phone)}</span></button>` : ""}<button data-iact="copy" class="wa-plain">${I.copy}<span>Copy number</span></button></div>`;
        }
        a.innerHTML = shell(actions + extra);
        bind();
      } catch (err) {
        a.innerHTML = shell(actions + `<div class="wa-card"><p class="muted">Extra details are unavailable right now (${esc(err.message)}).</p></div>`);
        bind();
      }
    }

    /* ---------- events ---------- */
    p.addEventListener("error", (e) => { if (e.target?.classList?.contains("pic")) e.target.remove(); else if (e.target?.closest?.(".wa-media") && e.target.tagName === "IMG") { const w = e.target.closest(".wa-media"); w.innerHTML = '<div class="wa-gone">Media unavailable — expired or not downloaded.</div>'; } }, true);
    p.addEventListener("click", (e) => {
      const t = e.target;
      if (!t.closest(".wa-menu")) closeMenus();
      if (!t.closest(".wa-emoji") && !t.closest("#waEmojiBtn")) { const em = $("#waEmoji"); if (em) em.hidden = true; }
      const chev = t.closest("[data-menu]");
      if (chev) {
        e.stopPropagation();
        const m = allMsgs().find((x) => x.waId === chev.dataset.menu);
        const r = chev.getBoundingClientRect();
        if (m) messageMenu(m, r.left - 150, r.bottom + 4);
        return;
      }
      const zoom = t.closest("[data-zoom]");
      if (zoom) {
        const m = allMsgs().find((x) => x.waId === zoom.dataset.zoom);
        if (m) modal("Photo", `<img class="wa-zoom" src="${esc(mediaUrl(m, true))}" alt="Photo"><div class="wa-dactions"><a class="btn" href="${esc(mediaUrl(m, false))}">Download</a></div>`, { wide: true });
        return;
      }
      const row = t.closest("[data-chat]");
      if (row && row.closest("#chatRows")) return void open(row.dataset.chat).catch((err) => toast(err.message));
      const start = t.closest("[data-start]");
      if (start) { $("#chatSearch").value = ""; query = ""; return void open(start.dataset.start + "@s.whatsapp.net").catch((err) => toast(err.message)); }
      const chip = t.closest("[data-filter]");
      if (chip) { filter = chip.dataset.filter; p.querySelectorAll("[data-filter]").forEach((x) => x.classList.toggle("active", x === chip)); drawList(true); }
    });
    p.addEventListener("contextmenu", (e) => {
      const msgEl = e.target.closest(".wa-row[data-id]");
      if (msgEl) {
        e.preventDefault();
        const m = allMsgs().find((x) => x.waId === msgEl.dataset.id);
        if (m) messageMenu(m, e.clientX, e.clientY);
        return;
      }
      const chatEl = e.target.closest("#chatRows [data-chat]");
      if (chatEl) {
        e.preventDefault();
        const c = chats.find((x) => x.chatId === chatEl.dataset.chat);
        if (c) chatMenu({ left: e.clientX, bottom: e.clientY }, c);
      }
    });
    let hold;
    p.addEventListener("touchstart", (e) => {
      const el = e.target.closest(".wa-row[data-id], #chatRows [data-chat]");
      if (!el) return;
      const t = e.touches[0];
      hold = setTimeout(() => {
        if (el.dataset.id) { const m = allMsgs().find((x) => x.waId === el.dataset.id); if (m) messageMenu(m, t.clientX - 100, t.clientY); }
        else { const c = chats.find((x) => x.chatId === el.dataset.chat); if (c) chatMenu({ left: t.clientX - 100, bottom: t.clientY }, c); }
      }, 500);
    }, { passive: true });
    for (const ev of ["touchend", "touchmove", "touchcancel"]) p.addEventListener(ev, () => clearTimeout(hold), { passive: true });
    $("#chatSearch").oninput = (e) => { query = e.target.value; drawList(true); };
    $("#chatSearch").onkeydown = (e) => {
      if (e.key === "Enter") { const first = p.querySelector("#chatRows [data-chat], #chatRows [data-start]"); first?.click(); }
    };
    $("#newChatBtn").onclick = () => { $("#chatSearch").focus(); toast("Type a phone number with country code to start a chat"); };
    $("#reloadInbox").onclick = async () => { try { await refreshList(); if (current) await refreshCurrent(); toast("Conversations refreshed"); } catch (err) { toast(err.message); } };
    $("#waMe").onclick = () => { const me = { chatId: "me", name: "My profile", kind: "contact", phone: state.phone ? "+" + state.phone : "" }; modal("Your WhatsApp profile", `<div class="wa-hero">${avatar(me, "xl", true)}<h2>${esc(state.phone ? "+" + state.phone : "This number")}</h2><p class="muted">Edit your name, about and photo in <b>Messaging → Profile &amp; settings</b>.</p></div>`); };
    const more = $("#moreChats");
    more.onclick = async () => {
      more.disabled = true;
      try { const next = await getChats(cursor); chats = mergeChats(chats, next.rows); cursor = next.cursor || cursor; hasMore = next.more; drawList(true); }
      catch (err) { toast(err.message); }
      finally { more.disabled = false; }
    };
    const setFull = (on) => {
      root.classList.toggle("inbox-full", on);
      syncLock();
      for (const b of p.querySelectorAll("#fullInbox,#fullInbox2")) { b.title = on ? "Exit full screen" : "Full screen"; b.classList.toggle("on", on); }
      if (on) root.requestFullscreen?.().catch(() => {});
      else if (document.fullscreenElement) document.exitFullscreen?.().catch(() => {});
    };
    const toggleFull = () => setFull(!root.classList.contains("inbox-full"));
    $("#fullInbox").onclick = toggleFull;
    const onFs = () => {
      if (!root.isConnected) return document.removeEventListener("fullscreenchange", onFs);
      if (document.fullscreenElement) root.dataset.native = "1";
      else if (root.classList.contains("inbox-full") && root.dataset.native === "1") { root.dataset.native = ""; setFull(false); }
    };
    document.addEventListener("fullscreenchange", onFs);
    const onKey = (e) => {
      if (!root.isConnected) return document.removeEventListener("keydown", onKey);
      if (e.key !== "Escape") return;
      if (layer.querySelector(".wa-modal")) return layer.querySelector(".wa-modal:last-child").remove();
      if (layer.querySelector(".wa-menu")) return closeMenus();
      if (infoOpen) return closeInfo();
      if (root.classList.contains("inbox-full")) setFull(false);
    };
    document.addEventListener("keydown", onKey);

    /* ---------- realtime ---------- */
    const banner = () => { $("#waBanner").hidden = state.status === "connected"; };
    banner();
    let beat;
    const teardown = () => { es?.close(); es = null; clearInterval(beat); document.removeEventListener("visibilitychange", onVisible); };
    const onVisible = () => { if (!document.hidden && root.isConnected) scheduleRefresh(current?.chatId); };
    document.addEventListener("visibilitychange", onVisible);
    function onEvent(ev) {
      if (ev.type === "message" || ev.type === "update") scheduleRefresh(ev.chatId);
      else if (ev.type === "connection") { state.status = ev.data?.status || state.status; banner(); }
      else if (ev.type === "presence" && current && sameChat(ev.data?.id)) {
        const entries = Object.entries(ev.data?.presences || {});
        const hit = entries.find(([, v]) => ["composing", "recording"].includes(v?.lastKnownPresence)) || entries[0];
        if (!hit) return;
        const live = ["composing", "recording"].includes(hit[1]?.lastKnownPresence);
        const nameOf = (j) => { const c = chats.find((x) => x.aliases?.includes(norm(j))); return current.kind === "group" ? (c?.name || "+" + norm(j).split("@")[0]) : ""; };
        presence = live ? { chatId: current.chatId, state: hit[1].lastKnownPresence, who: nameOf(hit[0]), until: Date.now() + 7000 } : null;
        const sub = $("#waSub");
        if (sub) sub.innerHTML = presence ? headSub() : !live && hit[1]?.lastKnownPresence === "available" ? '<span class="live">online</span>' : headSub();
        clearTimeout(presenceTimer);
        if (presence) presenceTimer = setTimeout(() => { presence = null; const s2 = $("#waSub"); if (s2) s2.innerHTML = headSub(); }, 7500);
      }
    }
    if ("EventSource" in window) {
      es = new EventSource("/api" + base + "/stream");
      es.onmessage = (m) => {
        if (!root.isConnected) return teardown();
        try { onEvent(JSON.parse(m.data)); } catch { /* ignore malformed event */ }
      };
      beat = setInterval(() => { if (!root.isConnected) teardown(); }, 4000);
    }
    ctx.startPolling?.(async () => {
      if (!root.isConnected) return teardown();
      if (document.hidden) return;
      try { await refreshList(); if (current) await refreshCurrent(); } catch { /* keep the screen during outages */ }
    }, 8000);

    drawList(true);
    drawConversation();
    const pendingOpen = window.__zelonChatMeta;
    if (pendingOpen) {
      window.__zelonChatMeta = undefined;
      chats = chats.some((c) => c.chatId === pendingOpen.id) ? chats : chats;
      window.__zelonChatMeta = pendingOpen;
      open(pendingOpen.id).catch((e) => toast(e.message)).finally(() => { window.__zelonChatMeta = undefined; });
    }
  }
  return { render };
})();
