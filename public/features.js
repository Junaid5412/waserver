window.ZelonFeatures = (() => {
  const tabs = [
    ["inbox", "Shared inbox"],
    ["contacts", "Contacts"],
    ["media", "Media library"],
    ["campaigns", "Campaigns"],
    ["automation", "Auto replies"],
    ["statuses", "Statuses"],
    ["group-tools", "Group settings"],
    ["analytics", "Analytics"],
    ["tools", "Profile & settings"],
  ];
  async function upload(base, file, api, toast) {
    if (!file) throw Error("Select a file");
    const settings = await api(base + "/settings");
    if (file.size > settings.maxMediaBytes)
      throw Error(
        "File exceeds " + Math.round(settings.maxMediaBytes / 1048576) + " MB",
      );
    const item = await api(base + "/media", "POST", {
      filename: file.name,
      mimetype: file.type || "application/octet-stream",
      size: file.size,
    });
    for (let index = 0; index < item.totalChunks; index++) {
      const r = await fetch(
        "/api" + base + "/media/" + item.id + "/chunks/" + index,
        {
          method: "PUT",
          headers: { "Content-Type": "application/octet-stream" },
          body: file.slice(
            index * item.chunkSize,
            (index + 1) * item.chunkSize,
          ),
        },
      );
      if (!r.ok) {
        const e = await r.json();
        throw Error(e.error || "Upload failed");
      }
      toast(
        "Uploading " + Math.round(((index + 1) / item.totalChunks) * 100) + "%",
      );
    }
    await api(base + "/media/" + item.id + "/complete", "POST", {});
    return item.id;
  }
  function csv(text) {
    const rows = [];
    let row = [],
      value = "",
      quoted = false;
    for (let i = 0; i < text.length; i++) {
      const c = text[i];
      if (c === '"') {
        if (quoted && text[i + 1] === '"') {
          value += '"';
          i++;
        } else quoted = !quoted;
      } else if (c === "," && !quoted) {
        row.push(value);
        value = "";
      } else if ((c === "\n" || c === "\r") && !quoted) {
        if (c === "\r" && text[i + 1] === "\n") i++;
        row.push(value);
        if (row.some((x) => x.trim())) rows.push(row);
        row = [];
        value = "";
      } else value += c;
    }
    if (quoted) throw Error("CSV contains an unclosed quotation");
    row.push(value);
    if (row.some((x) => x.trim())) rows.push(row);
    const headers = rows.shift()?.map((x) => x.trim().toLowerCase()) || [];
    if (!headers.includes("phone") || !headers.includes("name"))
      throw Error("CSV requires phone and name columns");
    return rows
      .map((r) =>
        Object.fromEntries(headers.map((h, i) => [h, (r[i] || "").trim()])),
      )
      .map((r) => ({
        phone: r.phone,
        name: r.name,
        consent: r.consent === "true",
        tags: r.tags ? r.tags.split(";") : [],
      }));
  }
  async function render(ctx) {
    const { tab, base, p, api, esc, form, on, toast } = ctx;
    const field = (id, label, type = "text", extra = "") =>
      `<label for="${id}">${label}</label><input id="${id}" name="${id}" type="${type}" ${extra}>`;
    const text = (id, label, extra = "") =>
      `<label for="${id}">${label}</label><textarea id="${id}" name="${id}" ${extra}></textarea>`;
    const submit = (label) =>
      `<div class="actions"><button type="submit" class="btn primary">${label}</button></div>`;
    const box = (title, body) =>
      `<section class="card"><h3>${title}</h3>${body}</section>`;
    const refresh = () => render(ctx).catch((e) => toast(e.message));
    const list = (rows, fn, empty = "Nothing here yet.") =>
      rows.length ? rows.map(fn).join("") : `<p class="hint">${empty}</p>`;
    p.innerHTML = '<div class="loading">Loading…</div>';
    if (tab === "analytics") {
      const data = await api(base + "/analytics");
      p.innerHTML =
        box(
          "Instance analytics",
          '<p class="hint">Persistent counts for this instance. Receipts depend on WhatsApp delivery and privacy settings.</p><button class="btn" id="refreshAnalytics">Refresh</button>',
        ) +
        Object.entries(data)
          .map(([name, counts]) =>
            box(
              esc(name),
              '<div class="metrics">' +
                Object.entries(counts)
                  .map(
                    ([status, count]) =>
                      `<div class="card metric"><div class="hint">${esc(status || "Records")}</div><div class="value">${count}</div></div>`,
                  )
                  .join("") +
                "</div>",
            ),
          )
          .join("");
      on("refreshAnalytics", refresh);
    }
    if (tab === "media") {
      const rows = await api(base + "/media");
      p.innerHTML =
        box(
          "Upload a file",
          `<p class="hint">Encrypted persistent storage. Upload in chunks; default limit 100 MB per file. Provider limits also apply.</p><form id="mediaUpload">${field("libraryFile", "File", "file", "required")}${submit("Upload file")}</form>`,
        ) +
        box(
          "Media library",
          list(
            rows,
            (m) =>
              `<div class="record row"><div><strong>${esc(m.filename)}</strong><p class="hint">${Math.ceil(m.size / 1024)} KB · ${esc(m.status)}</p><div class="key">${esc(m.id)}</div></div>${m.status === "ready" ? `<div><a class="btn" href="/api${base}/media/${m.id}/download">Download</a>${/^(image|video|audio)\//.test(m.mimetype) ? `<div class="chat-media"><button class="btn" data-preview="/api${base}/media/${m.id}/download" data-kind="${esc(m.mimetype.split("/")[0])}">Preview</button></div>` : ""}</div>` : ""}</div>`,
          ),
        );
      bindPreviews(p);
      form("mediaUpload", async () => {
        await upload(
          base,
          document.querySelector("#libraryFile").files[0],
          api,
          toast,
        );
        toast("Upload complete");
        await refresh();
      });
    }
    if (tab === "contacts") {
      const rows = await api(base + "/contacts");
      p.innerHTML =
        `<div class="split">${box("Save a contact", `<form id="contactForm">${field("phone", "Phone number", "tel", "required")}${field("name", "Name", "text", "required")}${field("tags", "Tags (separated by commas)")}<label class="checkbox"><input name="consent" type="checkbox">Recipient has agreed to receive messages</label>${submit("Save contact")}</form>`)}${box("Import CSV", `<p class="hint">Columns: phone,name,consent,tags. Use true for consent and semicolons between tags. Up to 1,000 contacts per import. Existing opt-outs must be preserved.</p><form id="contactImport">${field("csvFile", "CSV file", "file", 'accept=".csv,text/csv" required')}${submit("Import contacts")}</form>`)}</div>` +
        box(
          "Address book",
          `<input id="contactSearch" aria-label="Search contacts" placeholder="Search name, phone or tag"><div id="contactsRows"></div>`,
        );
      const draw = (q) => {
        document.querySelector("#contactsRows").innerHTML = list(
          rows.filter((c) => JSON.stringify(c).toLowerCase().includes(q)),
          (c) =>
            `<div class="record row"><div><strong>${esc(c.name || c.notify || c.chatId)}</strong><p class="hint">${esc(c.phone || c.chatId)} · ${esc((c.tags || []).join(", "))} · ${c.optedOut ? "Opted out" : c.consent ? "Consent recorded" : "Consent not recorded"}</p></div><div>${!c.optedOut ? `<button class="btn" data-optout="${c.id}">Opt out</button>` : ""}<button class="btn" data-block="${esc(c.phone || c.chatId)}">Block</button></div></div>`,
        );
        document.querySelectorAll("[data-optout]").forEach(
          (b) =>
            (b.onclick = async () => {
              try {
                await api(
                  base + "/contacts/" + b.dataset.optout + "/opt-out",
                  "POST",
                  {},
                );
                await refresh();
              } catch (e) {
                toast(e.message);
              }
            }),
        );
        document.querySelectorAll("[data-block]").forEach(
          (b) =>
            (b.onclick = async () => {
              try {
                await api(base + "/contacts/block", "PUT", {
                  phone: b.dataset.block,
                  blocked: true,
                });
                toast("Contact blocked");
              } catch (e) {
                toast(e.message);
              }
            }),
        );
      };
      draw("");
      document.querySelector("#contactSearch").oninput = (e) =>
        draw(e.target.value.toLowerCase());
      form("contactForm", async (d, e) => {
        await api(base + "/contacts", "POST", {
          ...d,
          tags: d.tags
            .split(",")
            .map((x) => x.trim())
            .filter(Boolean),
          consent: e.target.elements.consent.checked,
        });
        await refresh();
      });
      form("contactImport", async () => {
        const contacts = csv(
          await document.querySelector("#csvFile").files[0].text(),
        );
        const result = await api(base + "/contacts/import", "POST", {
          contacts,
        });
        toast(result.saved + " contacts imported");
        await refresh();
      });
    }
    function bindPreviews(container) {
      container.querySelectorAll("[data-preview]").forEach(button => {
          button.onclick = async () => {
            button.disabled = true;
            button.textContent = "Loading media…";
            try {
              const response = await fetch(button.dataset.preview);
              if (!response.ok) {
                const error = await response.json();
                throw Error(error.error || "This media is unavailable. Reconnect WhatsApp or retry.");
              }
              const blob = await response.blob();
              const objectUrl = URL.createObjectURL(blob);
              const type = button.dataset.kind;
              const element = document.createElement(type === "audio" ? "audio" : type === "video" ? "video" : "img");
              if (type === "audio" || type === "video") element.controls = true;
              else element.alt = "WhatsApp attachment";
              element.src = objectUrl;
              button.parentElement.replaceChildren(element);
              const observer = new MutationObserver(() => {
                if (!element.isConnected) { URL.revokeObjectURL(objectUrl); observer.disconnect(); }
              });
              observer.observe(document.querySelector("#workspace"), { childList: true, subtree: true });
              element.onerror = () => { element.replaceWith(document.createTextNode("Preview unsupported. Use Download to open this file.")); };
            } catch (error) {
              button.disabled = false;
              button.textContent = "Retry preview";
              toast(error.message);
            }
          };
        });
    }
    function messageBody(m) {
      let body = m.quotedText ? `<div class="message-detail">Replying to: ${esc(m.quotedText)}</div>` : "";
      if (m.hasMedia) {
        const url = `/api${base}/inbox/${encodeURIComponent(m.waId)}/media`;
        body += ["image", "sticker", "video", "audio"].includes(m.type)
          ? `<div class="chat-media"><button class="btn" data-preview="${esc(url)}" data-kind="${esc(m.type)}">${m.type === "audio" ? "Play audio" : "View " + esc(m.type)}${m.durationSeconds ? " · " + m.durationSeconds + "s" : ""}</button></div>`
          : `<div class="message-detail">Document: ${esc(m.filename || "Attachment")}<br><a class="btn mini" href="${esc(url)}">Download file</a></div>`;
      }
      if (m.location && Number.isFinite(m.location.latitude) && Number.isFinite(m.location.longitude))
        body += `<div class="message-detail"><strong>${esc(m.location.name || "Shared location")}</strong><br>${esc(m.location.address)}<br><a href="https://www.google.com/maps?q=${encodeURIComponent(m.location.latitude + "," + m.location.longitude)}" target="_blank" rel="noopener noreferrer">View location ↗</a></div>`;
      for (const contact of m.contacts || []) body += `<details class="message-detail"><summary>${esc(contact.name)}</summary><pre>${esc(contact.vcard)}</pre></details>`;
      if (m.pollOptions?.length) body += `<div class="message-detail"><strong>Poll</strong>${m.pollOptions.map(option => `<div>○ ${esc(option)}</div>`).join("")}</div>`;
      body += esc(m.text || (!m.hasMedia && !m.location && !m.contacts?.length && !m.pollOptions?.length ? "[" + (m.type || "Message") + "]" : ""));
      return body;
    }
    if (tab === "inbox") {
      document.body.classList.remove("inbox-lock");
      const ICON = {
        group: '<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>',
        expand: '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M8 3H5a2 2 0 0 0-2 2v3m18 0V5a2 2 0 0 0-2-2h-3m0 18h3a2 2 0 0 0 2-2v-3M3 16v3a2 2 0 0 0 2 2h3"/></svg>',
        refresh: '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M21 12a9 9 0 0 0-15-6.7L3 8"/><path d="M3 3v5h5"/><path d="M3 12a9 9 0 0 0 15 6.7L21 16"/><path d="M21 21v-5h-5"/></svg>',
        plus: '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>',
        back: '<svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m12 19-7-7 7-7"/><path d="M19 12H5"/></svg>',
        send: '<svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m22 2-7 20-4-9-9-4z"/><path d="M22 2 11 13"/></svg>',
        clip: '<svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m21.44 11.05-9.19 9.19a6 6 0 0 1-8.49-8.49l8.57-8.57A4 4 0 1 1 18 8.84l-8.59 8.57a2 2 0 0 1-2.83-2.83l8.49-8.48"/></svg>',
      };
      const initial = (n) => (String(n || "?").replace(/^[^\p{L}\p{N}]+/u, "")[0] || "?").toUpperCase();
      const fmtTime = (iso) => {
        const d = new Date(iso);
        if (!iso || isNaN(d)) return "";
        const now = new Date();
        if (d.toDateString() === now.toDateString()) return d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
        if (d.toDateString() === new Date(now - 864e5).toDateString()) return "Yesterday";
        return d.toLocaleDateString([], { day: "numeric", month: "short" });
      };
      const fmtDay = (iso) => {
        const d = new Date(iso);
        if (isNaN(d)) return "";
        const now = new Date();
        if (d.toDateString() === now.toDateString()) return "Today";
        if (d.toDateString() === new Date(now - 864e5).toDateString()) return "Yesterday";
        return d.toLocaleDateString([], { weekday: "long", day: "numeric", month: "long", year: "numeric" });
      };
      const avatarFor = (c, cls = "") =>
        `<span class="avatar ${c?.kind === "group" ? "group" : ""} ${cls}">${c?.kind === "group" ? ICON.group : esc(initial(c?.name || c?.chatId))}</span>`;
      async function getChats(cursor) {
        const q = "?limit=100" + (cursor ? "&before=" + encodeURIComponent(cursor.createdAt) + "&beforeId=" + encodeURIComponent(cursor.id) : "");
        const r = await fetch("/api" + base + "/chats" + q);
        const rows = await r.json();
        if (!r.ok) throw Error(rows.error || "Could not load conversations");
        const header = (k) => r.headers?.get?.(k);
        return {
          rows,
          more: header("X-Has-More") != null ? header("X-Has-More") === "true" : rows.length === 100,
          cursor: header("X-Cursor-Created") ? { createdAt: header("X-Cursor-Created"), id: header("X-Cursor-Id") } : rows.at(-1),
        };
      }
      const mergeChats = (current, incoming) => {
        const byId = new Map(current.map((c) => [c.chatId, c]));
        for (const c of incoming) byId.set(c.chatId, c);
        return [...byId.values()].sort((a, b) => (b.pinned ? 1 : 0) - (a.pinned ? 1 : 0) || Date.parse(b.createdAt || 0) - Date.parse(a.createdAt || 0));
      };
      const first = await getChats();
      let chats = mergeChats([], first.rows),
        hasMoreChats = first.more,
        chatCursor = first.cursor,
        chat = null,
        meta = null,
        messages = [],
        quotedId,
        filter = "all";
      p.innerHTML = `<div class="inboxlayout"><section class="card chatlist"><div class="inbox-bar"><h3>Chats</h3><div class="inbox-tools"><button class="icon-btn flat" id="newChatBtn" title="New conversation" aria-label="New conversation">${ICON.plus}</button><button class="icon-btn flat" id="reloadInbox" title="Refresh" aria-label="Refresh conversations">${ICON.refresh}</button><button class="icon-btn flat" id="fullInbox" title="Full screen" aria-label="Full screen">${ICON.expand}</button></div></div><form id="openChat" hidden>${field("newChat", "New conversation", "tel", 'placeholder="+97450000000" required')}${submit("Open chat")}</form><input id="chatSearch" aria-label="Search conversations" placeholder="Search name or number"><div class="chat-filters" role="tablist"><button class="chip active" data-filter="all">All</button><button class="chip" data-filter="unread">Unread</button><button class="chip" data-filter="groups">Groups</button></div><div id="chatRows"></div><button class="btn mini" id="moreChats">Load more conversations</button></section><section class="card conversation" id="conversation"><div class="empty"><h3>Your shared inbox</h3><p>Select a conversation to read messages and reply.</p></div></section></div>`;
      const layout = () => document.querySelector(".inboxlayout");
      const drawChats = () => {
        const q = document.querySelector("#chatSearch").value.toLowerCase();
        const rows = chats.filter(
          (c) =>
            ((c.name || "") + " " + (c.chatId || "") + " " + (c.phone || "")).toLowerCase().includes(q) &&
            (filter === "all" || (filter === "unread" && c.unread > 0) || (filter === "groups" && c.kind === "group")),
        );
        document.querySelector("#chatRows").innerHTML = list(
          rows,
          (c) =>
            `<button class="chatentry ${chat === c.chatId ? "active" : ""}" data-chat="${esc(c.chatId)}">${avatarFor(c)}<div class="chat-copy"><div class="chat-top"><strong>${esc(c.name || c.chatId)}</strong><time>${esc(fmtTime(c.createdAt))}</time></div><div class="chat-bottom"><span class="chat-preview">${esc(c.lastPreview || "No messages yet")}</span>${c.unread ? `<b class="badge">${c.unread > 99 ? "99+" : c.unread}</b>` : c.pinned ? '<span class="pin">Pinned</span>' : ""}</div></div></button>`,
          "No conversations match.",
        );
        document.querySelectorAll("[data-chat]").forEach((b) => (b.onclick = () => open(b.dataset.chat).catch((e) => toast(e.message))));
      };
      document.querySelectorAll("[data-filter]").forEach((b) => (b.onclick = () => {
        filter = b.dataset.filter;
        document.querySelectorAll("[data-filter]").forEach((x) => x.classList.toggle("active", x === b));
        drawChats();
      }));
      const moreButton = document.querySelector("#moreChats");
      moreButton.hidden = !hasMoreChats;
      moreButton.onclick = async () => {
        moreButton.disabled = true;
        try {
          const next = await getChats(chatCursor);
          chats = mergeChats(chats, next.rows);
          chatCursor = next.cursor || chatCursor;
          hasMoreChats = next.more;
          moreButton.hidden = !hasMoreChats;
          drawChats();
        } catch (error) { toast(error.message); }
        finally { moreButton.disabled = false; }
      };
      drawChats();
      document.querySelector("#chatSearch").oninput = drawChats;
      document.querySelector("#newChatBtn").onclick = () => {
        const f = document.querySelector("#openChat");
        f.hidden = !f.hidden;
        if (!f.hidden) document.querySelector("#newChat").focus();
      };
      const setFull = (on) => {
        const el = layout();
        if (!el) return;
        el.classList.toggle("inbox-full", on);
        document.body.classList.toggle("inbox-lock", on);
        for (const b of document.querySelectorAll("#fullInbox,#fullInbox2")) {
          b.title = on ? "Exit full screen" : "Full screen";
          b.classList.toggle("on", on);
        }
        if (on) el.requestFullscreen?.().catch(() => {});
        else if (document.fullscreenElement) document.exitFullscreen?.().catch(() => {});
      };
      const toggleFull = () => setFull(!layout()?.classList.contains("inbox-full"));
      document.querySelector("#fullInbox").onclick = toggleFull;
      const onFsChange = () => {
        if (!p.isConnected) return document.removeEventListener("fullscreenchange", onFsChange);
        if (!document.fullscreenElement && layout()?.classList.contains("inbox-full") && layout().dataset.native === "1") setFull(false);
        if (document.fullscreenElement) layout().dataset.native = "1";
      };
      document.addEventListener("fullscreenchange", onFsChange);
      const onEsc = (e) => {
        if (!p.isConnected) return document.removeEventListener("keydown", onEsc);
        if (e.key === "Escape" && layout()?.classList.contains("inbox-full")) setFull(false);
      };
      document.addEventListener("keydown", onEsc);
      let polling = false;
      ctx.startPolling?.(async () => {
        if (polling || !p.isConnected || document.hidden) return;
        polling = true;
        try {
          chats = mergeChats(chats, (await getChats()).rows);
          if (!p.isConnected) return;
          drawChats();
          if (chat && messages.length <= 50) {
            const recent = await api(base + "/chats/" + encodeURIComponent(chat) + "/messages?limit=50");
            if (!p.isConnected || JSON.stringify(recent) === JSON.stringify(messages)) return;
            const draft = document.querySelector("#replyText")?.value || "";
            const attachment = document.querySelector("#replyAttachment")?.files.length;
            const actionOpen = document.querySelector("#inboxAction")?.textContent;
            if (!draft && !attachment && !quotedId && !actionOpen) await open(chat, false, true);
            else document.querySelector("#refreshChat").textContent = "New messages";
          }
        } catch { /* Keep the current conversation and draft during outages. */ }
        finally { polling = false; }
      }, 5000);
      on("reloadInbox", async () => {
        chats = mergeChats(chats, (await getChats()).rows);
        drawChats();
        toast("Conversations refreshed");
      });
      form("openChat", async (d) => {
        document.querySelector("#openChat").hidden = true;
        await open(d.newChat);
      });
      async function open(id, older = false, keepScroll = false) {
        chat = id;
        meta = chats.find((x) => x.chatId === id) || window.__zelonChatMeta?.id === id && window.__zelonChatMeta || { chatId: id, name: id };
        const last = messages.at(-1),
          suffix = older && last ? "&before=" + encodeURIComponent(last.createdAt) + "&beforeId=" + encodeURIComponent(last.id) : "";
        const rows = await api(base + "/chats/" + encodeURIComponent(id) + "/messages?limit=50" + suffix);
        messages = older ? [...messages, ...rows] : rows;
        quotedId = undefined;
        const isGroup = meta.kind === "group" || /@g\.us$/.test(id);
        const c = document.querySelector("#conversation");
        const keep = c.querySelector(".messages");
        const prevScroll = keep ? keep.scrollHeight - keep.scrollTop : 0;
        let day = "";
        const bubbles = [...messages].reverse().map((m) => {
          const d = fmtDay(m.createdAt);
          const sep = d && d !== day ? `<div class="daysep"><span>${esc(d)}</span></div>` : "";
          day = d || day;
          return sep + `<article class="bubble ${m.fromMe ? "outgoing" : ""}"><div class="hint">${!m.fromMe && (isGroup || m.name) ? esc(m.name || m.participant || "Contact") : ""}</div><div class="messagebody">${messageBody(m)}</div><small>${esc(new Date(m.createdAt).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }))}${m.fromMe ? " · " + esc(m.status) : ""}</small><div class="actions"><button class="btn mini" data-quote="${esc(m.waId)}">Reply</button><button class="btn mini" data-react="${esc(m.waId)}">React</button><button class="btn mini" data-forward="${esc(m.waId)}">Forward</button>${m.fromMe ? `<button class="btn mini" data-edit="${esc(m.waId)}">Edit</button><button class="btn mini" data-delete="${esc(m.waId)}">Delete</button>` : ""}${m.hasMedia ? `<a class="btn mini" href="/api${base}/inbox/${encodeURIComponent(m.waId)}/media">Download</a>` : ""}${m.pollOptions?.length ? `<button class="btn mini" data-votes="${esc(m.waId)}">Poll votes</button>` : ""}</div></article>`;
        }).join("");
        c.innerHTML = `<div class="row conv-head"><button class="btn" id="chatBack" aria-label="Back to conversations">${ICON.back}</button>${avatarFor(meta)}<div class="conv-title"><h3>${esc(meta.name || id)}</h3><span class="hint">${esc(isGroup ? (meta.participants ? meta.participants + " participants" : "Group") : meta.phone || "")}</span></div><button class="icon-btn flat" id="refreshChat" title="Refresh" aria-label="Refresh chat">${ICON.refresh}</button><button class="icon-btn flat" id="fullInbox2" title="Full screen" aria-label="Full screen">${ICON.expand}</button></div><div class="actions chat-actions"><button class="btn" id="readChat">Mark read</button><button class="btn" id="archiveChat">Archive</button><button class="btn" id="pinChat">Pin</button></div><div class="messages">${rows.length === 50 ? '<button class="btn mini" id="olderMessages">Load older messages</button>' : ""}${bubbles || '<p class="hint center">No local messages in this conversation yet.</p>'}</div><div id="quoteHint" class="hint"></div><form id="replyForm"><label class="attach" title="Attach a file">${ICON.clip}<input id="replyAttachment" name="replyAttachment" type="file" aria-label="Attach an image, video, audio or document"></label>${text("replyText", "Reply", 'maxlength="20000" placeholder="Type a message…" rows="1"')}<button type="submit" class="btn primary send-btn" aria-label="Send">${ICON.send}</button></form><div id="inboxAction"></div>`;
        layout().classList.add("chat-open");
        document.querySelectorAll("[data-chat]").forEach((button) => button.classList.toggle("active", button.dataset.chat === id));
        on("chatBack", () => layout().classList.remove("chat-open"));
        document.querySelector("#fullInbox2").onclick = toggleFull;
        document.querySelector("#fullInbox2").classList.toggle("on", layout().classList.contains("inbox-full"));
        bindPreviews(c);
        const timeline = c.querySelector(".messages");
        if (older) timeline.scrollTop = timeline.scrollHeight - prevScroll;
        else if (!keepScroll || prevScroll < 600) timeline.scrollTop = timeline.scrollHeight;
        else timeline.scrollTop = timeline.scrollHeight - prevScroll;
        const replyText = document.querySelector("#replyText");
        replyText.onkeydown = (e) => {
          if (e.key === "Enter" && !e.shiftKey && !e.isComposing) { e.preventDefault(); document.querySelector("#replyForm").requestSubmit(); }
        };
        on("refreshChat", () => open(id));
        on("olderMessages", () => open(id, true));
        const setting = (id2, body, done) => on(id2, async () => {
          await api(base + "/chats/" + encodeURIComponent(chat) + "/settings", "PUT", body);
          toast(done);
        });
        setting("readChat", { read: true }, "Marked read");
        setting("archiveChat", { archive: true }, "Chat archived");
        setting("pinChat", { pin: true }, "Chat pinned");
        const replyForm = document.querySelector("#replyForm");
        replyForm.dataset.key = crypto.randomUUID();
        replyForm.oninput = () => (replyForm.dataset.key = crypto.randomUUID());
        form("replyForm", async (d) => {
          const file = document.querySelector("#replyAttachment").files[0];
          if (!file && !d.replyText?.trim()) throw Error("Write a message or attach a file");
          const payload = { to: chat, type: "text", text: d.replyText, quotedId };
          if (file) {
            payload.type = file.type.startsWith("image/") ? "image" : file.type.startsWith("video/") ? "video" : file.type.startsWith("audio/") ? "audio" : "document";
            payload.mediaId = await upload(base, file, api, toast);
            payload.caption = d.replyText || undefined;
            delete payload.text;
          }
          await api(base + "/messages", "POST", payload, { "Idempotency-Key": replyForm.dataset.key });
          toast("Message queued");
          replyForm.reset();
          replyForm.dataset.key = crypto.randomUUID();
          quotedId = undefined;
          document.querySelector("#quoteHint").textContent = "";
        });
        document.querySelectorAll("[data-quote]").forEach((b) => (b.onclick = () => {
          quotedId = b.dataset.quote;
          const original = messages.find((m) => m.waId === quotedId);
          document.querySelector("#quoteHint").textContent = "Replying to: " + (original?.text || original?.type || quotedId).slice(0, 80);
          document.querySelector("#replyText").focus();
        }));
        const action = (attr, label, fn) =>
          document.querySelectorAll("[data-" + attr + "]").forEach((b) => (b.onclick = () => {
            const mid = b.dataset[attr],
              target = document.querySelector("#inboxAction");
            target.innerHTML = box(label, `<form id="actionForm">${field("value", label, "text", "required")}${submit("Confirm")}</form>`);
            form("actionForm", async (d) => {
              await fn(mid, d.value);
              target.innerHTML = "";
              toast("Request completed");
            });
          }));
        action("react", "Reaction emoji (e.g. 👍)", (mid, value) => api(base + "/inbox/" + encodeURIComponent(mid) + "/reaction", "POST", { emoji: value }));
        action("edit", "New message text", (mid, value) => api(base + "/inbox/" + encodeURIComponent(mid) + "/text", "PUT", { text: value }));
        action("forward", "Forward to phone or group JID", (mid, value) =>
          api(base + "/messages", "POST", { to: value, type: "forward", forwardId: mid }, { "Idempotency-Key": crypto.randomUUID() }));
        document.querySelectorAll("[data-delete]").forEach((b) => (b.onclick = () => {
          const target = document.querySelector("#inboxAction");
          target.innerHTML = box("Delete message for everyone", '<p>WhatsApp time and group permissions apply.</p><button class="btn danger" id="confirmDelete">Delete message</button>');
          on("confirmDelete", async () => {
            await api(base + "/inbox/" + encodeURIComponent(b.dataset.delete) + "/delete", "POST", {});
            toast("Delete submitted");
            target.innerHTML = "";
          });
        }));
        document.querySelectorAll("[data-votes]").forEach((b) => (b.onclick = async () => {
          try {
            const votes = await api(base + "/polls/" + encodeURIComponent(b.dataset.votes) + "/votes");
            const rows2 = Array.isArray(votes) ? votes : Object.entries(votes || {}).map(([name, voters]) => ({ name, voters }));
            document.querySelector("#inboxAction").innerHTML = box("Poll results", list(rows2, (v) => `<div class="record row"><strong>${esc(v.name)}</strong><span class="status">${(v.voters || []).length} vote${(v.voters || []).length === 1 ? "" : "s"}</span></div>`, "No votes yet."));
          } catch (e) { toast(e.message); }
        }));
      }
      const pending = window.__zelonChatMeta;
      if (pending) {
        open(pending.id).catch((e) => toast(e.message)).finally(() => { window.__zelonChatMeta = undefined; });
      }
    }
    if (tab === "campaigns") {
      const rows = await api(base + "/campaigns"),
        templates = await api(base + "/templates");
      p.innerHTML =
        box(
          "Create a campaign",
          `<p class="hint">Send to recipients who agreed to receive messages. STOP replies opt recipients out. Use {{name}} and {{phone}} to personalize text. Pausing affects queued messages; already submitted sends may finish.</p><form id="campaignForm">${field("campaignName", "Campaign name", "text", 'required maxlength="60"')}<label for="campaignTemplate">Saved template</label><select id="campaignTemplate"><option value="">Write a message</option>${templates.map((t) => `<option value="${t.id}">${esc(t.name)}</option>`).join("")}</select>${text("campaignText", "Message", 'required maxlength="20000"')}${text("recipients", "Recipients: phone,name on each line", "required")}${field("intervalSeconds", "Seconds between recipients", "number", 'value="5" min="1" max="3600" required')}${field("startAt", "Schedule start (optional)", "datetime-local")}<label class="checkbox"><input id="consentConfirmed" type="checkbox" required>All listed recipients agreed to receive this campaign</label>${submit("Create campaign")}</form>`,
        ) +
        box(
          "Campaign history",
          list(
            rows,
            (c) =>
              `<div class="record"><div class="row"><h3>${esc(c.name)}</h3><span class="status">${esc(c.status)}</span></div><p class="hint">${c.total} recipients · ${c.skipped} opted out · ${esc(JSON.stringify(c.counts))}</p><div class="actions">${["running", "paused"].includes(c.status) ? `<button class="btn" data-campaign="${c.id}" data-status="${c.status === "running" ? "paused" : "running"}">${c.status === "running" ? "Pause" : "Resume"}</button><button class="btn danger" data-campaign="${c.id}" data-status="cancelled">Cancel queued sends</button>` : ""}</div></div>`,
          ) +
            '<button class="btn" id="refreshCampaigns">Refresh history</button>',
        );
      document.querySelector("#campaignTemplate").onchange = (e) => {
        const t = templates.find((t) => t.id === e.target.value);
        if (t) document.querySelector("#campaignText").value = t.text;
      };
      const campaignForm = document.querySelector("#campaignForm");
      campaignForm.dataset.key = crypto.randomUUID();
      campaignForm.oninput = () =>
        (campaignForm.dataset.key = crypto.randomUUID());
      form("campaignForm", async (d) => {
        const recipients = d.recipients
          .split("\n")
          .map((s) => s.trim())
          .filter(Boolean)
          .map((s) => {
            const comma = s.indexOf(",");
            return comma < 0
              ? s
              : {
                  to: s.slice(0, comma).trim(),
                  name: s.slice(comma + 1).trim(),
                };
          });
        await api(
          base + "/campaigns",
          "POST",
          {
            name: d.campaignName,
            recipients,
            message: { type: "text", text: d.campaignText },
            intervalSeconds: Number(d.intervalSeconds),
            ...(d.startAt
              ? { startAt: new Date(d.startAt).toISOString() }
              : {}),
            consentConfirmed: true,
          },
          { "Idempotency-Key": campaignForm.dataset.key },
        );
        toast("Campaign created");
        await refresh();
      });
      on("refreshCampaigns", refresh);
      document.querySelectorAll("[data-campaign]").forEach(
        (b) =>
          (b.onclick = async () => {
            try {
              await api(base + "/campaigns/" + b.dataset.campaign, "PUT", {
                status: b.dataset.status,
              });
              await refresh();
            } catch (e) {
              toast(e.message);
            }
          }),
      );
    }
    if (tab === "automation") {
      const rules = await api(base + "/rules"),
        templates = await api(base + "/templates");
      p.innerHTML =
        `<div class="split">${box("Create an auto reply", `<form id="ruleForm">${field("ruleName", "Rule name", "text", "required")}<label for="match">Match</label><select name="match" id="match"><option value="contains">Contains keyword</option><option value="exact">Exact keyword</option><option value="any">Any incoming text</option></select>${field("keyword", "Keyword")}${text("reply", "Reply text", "required")}${field("cooldownSeconds", "Cooldown per contact (seconds)", "number", 'min="0" max="86400" value="60" required')}${submit("Create rule")}</form><p class="hint">Direct incoming messages only. Variables: {{name}}, {{phone}}, {{message}}. STOP is handled before rules.</p>`)}${box("Save a reusable template", `<form id="templateForm">${field("templateName", "Template name", "text", "required")}${text("templateText", "Template text", "required")}${submit("Save template")}</form>`)}</div>` +
        box(
          "Auto reply rules",
          list(
            rules,
            (r) =>
              `<div class="record row"><div><strong>${esc(r.name)}</strong><p>${esc(r.reply)}</p><p class="hint">${esc(r.match)} · ${esc(r.keyword)} · ${r.cooldownSeconds}s cooldown</p></div><div class="actions"><button class="btn" data-rule="${r.id}" data-enabled="${!r.enabled}">${r.enabled ? "Disable" : "Enable"}</button><button class="btn danger" data-remove-rule="${r.id}">Delete</button></div></div>`,
          ),
        ) +
        box(
          "Templates",
          list(
            templates,
            (t) =>
              `<div class="record row"><div><strong>${esc(t.name)}</strong><p>${esc(t.text)}</p></div><button class="btn danger" data-remove-template="${t.id}">Delete</button></div>`,
          ),
        );
      form("ruleForm", async (d) => {
        await api(base + "/rules", "POST", {
          name: d.ruleName,
          match: d.match,
          keyword: d.keyword,
          reply: d.reply,
          cooldownSeconds: Number(d.cooldownSeconds),
        });
        await refresh();
      });
      form("templateForm", async (d) => {
        await api(base + "/templates", "POST", {
          name: d.templateName,
          text: d.templateText,
        });
        await refresh();
      });
      document.querySelectorAll("[data-rule]").forEach(
        (b) =>
          (b.onclick = async () => {
            try {
              await api(base + "/rules/" + b.dataset.rule, "PUT", {
                enabled: b.dataset.enabled === "true",
              });
              await refresh();
            } catch (e) {
              toast(e.message);
            }
          }),
      );
      for (const kind of ["rule", "template"])
        document.querySelectorAll("[data-remove-" + kind + "]").forEach(
          (b) =>
            (b.onclick = async () => {
              try {
                await api(
                  base +
                    "/" +
                    (kind === "rule" ? "rules" : "templates") +
                    "/" +
                    b.dataset[
                      kind === "rule" ? "removeRule" : "removeTemplate"
                    ],
                  "DELETE",
                );
                await refresh();
              } catch (e) {
                toast(e.message);
              }
            }),
        );
    }
    if (tab === "statuses") {
      const rows = await api(base + "/statuses");
      p.innerHTML =
        box(
          "Publish a WhatsApp status",
          `<p class="hint">Choose an explicit audience of WhatsApp contacts. WhatsApp privacy rules and expiration apply. Existing status media may be downloadable only while available.</p><form id="statusForm"><label for="statusType">Type</label><select id="statusType" name="type"><option value="text">Text</option><option value="image">Image</option><option value="video">Video</option><option value="audio">Audio</option></select>${text("statusText", "Text or caption")}${field("statusFile", "Media (required for image/video/audio)", "file")}${field("backgroundColor", "Text background", "color", 'value="#087e75"')}${text("statusAudience", "Audience phone numbers, one per line", "required")}${submit("Queue status")}</form>`,
        ) +
        box(
          "Status journal",
          list(
            rows,
            (m) =>
              `<div class="record"><strong>${esc(m.name || m.chatId)}</strong><div class="messagebody">${messageBody(m)}</div><small>${esc(m.createdAt)} · ${esc(m.status)}</small></div>`,
          ),
        );
      bindPreviews(p);
      const f = document.querySelector("#statusForm");
      f.dataset.key = crypto.randomUUID();
      f.oninput = () => (f.dataset.key = crypto.randomUUID());
      form("statusForm", async (d) => {
        const message = {
          type: d.type,
          text: d.statusText,
          backgroundColor: d.backgroundColor,
          statusAudience: d.statusAudience
            .split("\n")
            .map((x) => x.trim())
            .filter(Boolean),
        };
        if (d.type !== "text")
          message.mediaId = await upload(
            base,
            document.querySelector("#statusFile").files[0],
            api,
            toast,
          );
        await api(base + "/statuses", "POST", message, {
          "Idempotency-Key": f.dataset.key,
        });
        toast("Status queued");
        await refresh();
      });
    }
    if (tab === "group-tools") {
      p.innerHTML =
        box(
          "Group administration",
          `<form id="groupSettings">${field("groupJid", "Group", "text", 'required list="groupOptions" placeholder="Pick a group or paste its JID" autocomplete="off"')}<datalist id="groupOptions"></datalist>${field("subject", "New subject")}${text("description", "New description")}<label for="announcement">Who can send</label><select name="announcement" id="announcement"><option value="">Keep current setting</option><option value="true">Administrators only</option><option value="false">All members</option></select><label for="locked">Who can edit settings</label><select name="locked" id="locked"><option value="">Keep current setting</option><option value="true">Administrators only</option><option value="false">All members</option></select><label for="ephemeralSeconds">Disappearing messages</label><select name="ephemeralSeconds" id="ephemeralSeconds"><option value="">Keep current setting</option><option value="0">Disabled</option><option value="86400">24 hours</option><option value="604800">7 days</option><option value="7776000">90 days</option></select>${submit("Update group")}</form><div class="actions"><button class="btn" id="groupInfo">Read group details</button><button class="btn" id="groupInvite">Get invite</button><button class="btn" id="revokeInvite">Replace invite</button></div><div id="groupOutput" class="group-output"></div>`,
        ) +
        box(
          "Join a group",
          `<form id="joinGroup">${field("inviteCode", "Invite code", "text", "required")}${submit("Join group")}</form>`,
        ) +
        box(
          "Leave a group",
          `<form id="leaveGroup">${field("leaveJid", "Group", "text", 'required list="groupOptions" placeholder="Pick a group or paste its JID" autocomplete="off"')}<label class="checkbox"><input type="checkbox" required>I want this number to leave the group</label>${submit("Leave group")}</form>`,
        );
      form("groupSettings", async (d) => {
        const body = {};
        if (d.subject) body.name = d.subject;
        if (d.description) body.description = d.description;
        for (const k of ["announcement", "locked"])
          if (d[k]) body[k] = d[k] === "true";
        if (d.ephemeralSeconds !== "")
          body.ephemeralSeconds = Number(d.ephemeralSeconds);
        await api(
          base + "/groups/" + encodeURIComponent(d.groupJid),
          "PUT",
          body,
        );
        toast("Group updated");
      });
      const group = () =>
        encodeURIComponent(document.querySelector("#groupJid").value);
      api(base + "/groups").then((all) => {
        document.querySelector("#groupOptions").innerHTML = Object.values(all || {}).map((g) => `<option value="${esc(g.id)}">${esc(g.subject)}</option>`).join("");
      }).catch(() => {});
      const showLink = (code) => {
        const url = "https://chat.whatsapp.com/" + code;
        document.querySelector("#groupOutput").innerHTML = `<div class="paircode"><span>Invite link</span><a href="${esc(url)}" target="_blank" rel="noopener noreferrer">${esc(url)}</a><button type="button" class="btn mini" id="copyInvite">Copy link</button></div>`;
        on("copyInvite", async () => { await navigator.clipboard?.writeText(url); toast("Link copied"); });
      };
      on("groupInfo", async () => {
        const g = await api(base + "/groups/" + group() + "/overview");
        document.querySelector("#groupOutput").innerHTML = `<div class="group-card"><h4>${esc(g.subject)}</h4><p class="hint">${g.createdAt ? "Created " + esc(new Date(g.createdAt).toLocaleDateString()) : ""}${g.owner ? " · Owner " + esc(g.owner) : ""}</p>${g.description ? `<p>${esc(g.description)}</p>` : ""}<div class="chips"><span class="status ${g.announce ? "queued" : "connected"}">${g.announce ? "Only admins can send" : "Everyone can send"}</span><span class="status ${g.restrict ? "queued" : "connected"}">${g.restrict ? "Only admins edit info" : "Everyone can edit info"}</span></div><h4>${g.participants.length} participants</h4>${g.participants.map((u) => `<div class="record row"><div><strong>${esc(u.name || u.phone)}</strong>${u.name ? `<div class="hint">${esc(u.phone)}</div>` : ""}</div>${u.admin ? `<span class="status connected">${u.admin === "superadmin" ? "Owner" : "Admin"}</span>` : ""}</div>`).join("")}</div>`;
      });
      on("groupInvite", async () => {
        showLink((await api(base + "/groups/" + group() + "/invite")).code);
      });
      on("revokeInvite", async () => {
        const r = await api(
          base + "/groups/" + group() + "/invite/revoke",
          "POST",
          {},
        );
        showLink(r.code);
      });
      form("joinGroup", async (d) => {
        const r = await api(base + "/groups/join", "POST", {
          code: d.inviteCode,
        });
        toast("Joined " + r.groupId);
      });
      form("leaveGroup", async (d) => {
        await api(
          base + "/groups/" + encodeURIComponent(d.leaveJid) + "/leave",
          "POST",
          {},
        );
        toast("Group left");
      });
    }
    if (tab === "tools") {
      const settings = await api(base + "/settings");
      let prof = null,
        blocked = null;
      try { prof = await api(base + "/profile"); } catch { /* not connected */ }
      if (prof) try { blocked = await api(base + "/blocklist"); } catch { /* optional */ }
      const phone = (id) => (id ? "+" + String(id).split("@")[0].split(":")[0] : "");
      const aboutOf = (a) => {
        const v = Array.isArray(a) ? a[0]?.status : a;
        return String((typeof v === "string" ? v : v?.status) || "").trim();
      };
      const dayNames = { sun: "Sunday", mon: "Monday", tue: "Tuesday", wed: "Wednesday", thu: "Thursday", fri: "Friday", sat: "Saturday" };
      const hhmm = (m) => String(Math.floor(m / 60)).padStart(2, "0") + ":" + String(m % 60).padStart(2, "0");
      const hoursRow = (key) => {
        const h = (prof?.business?.business_hours?.business_config || []).find((x) => x.day_of_week === key);
        const label = !h ? "Closed" : h.mode === "open_24h" ? "Open 24 hours" : h.mode === "appointment_only" ? "By appointment" : h.open_time !== undefined ? hhmm(h.open_time) + " – " + hhmm(h.close_time) : h.mode;
        return `<li><span>${dayNames[key]}</span><b class="${!h ? "muted" : ""}">${esc(label)}</b></li>`;
      };
      const row = (label, value) => (value ? `<div><dt>${label}</dt><dd>${esc(value)}</dd></div>` : "");
      const b = prof?.business;
      const profileCard = prof
        ? `<div class="profile-head"><span class="avatar xl">${esc((prof.name || "W")[0].toUpperCase())}</span><div><h3>${esc(prof.name || "WhatsApp account")}</h3><div class="hint">${esc(phone(prof.id))}</div></div><span class="status connected">Online</span></div><dl class="kv">${row("About", aboutOf(prof.about))}${row("Phone", phone(prof.id))}</dl>${b ? `<h4>Business profile</h4><dl class="kv">${row("Description", b.description)}${row("Category", b.category)}${row("Address", b.address)}${row("Email", b.email)}${row("Website", (b.website || []).join(", "))}</dl>${b.business_hours?.business_config ? `<h4>Opening hours${b.business_hours.timezone ? ` <span class="hint">(${esc(b.business_hours.timezone)})</span>` : ""}</h4><ul class="hours">${Object.keys(dayNames).map(hoursRow).join("")}</ul>` : ""}` : ""}<h4>Edit profile</h4><form id="profileForm">${field("profileName", "Display name", "text", `value="${esc(prof.name || "")}"`)}${field("profileAbout", "About (139 characters)", "text", `maxlength="139" value="${esc(aboutOf(prof.about))}"`)}${submit("Update profile")}</form>`
        : `<div class="empty compact"><h3>Number not connected</h3><p>Connect your WhatsApp number to view and edit its profile.</p><button class="btn primary" id="goConnect">Go to Connection</button></div>`;
      const blockList = blocked === null
        ? '<p class="hint">Connect your number to load blocked contacts.</p>'
        : list(blocked, (id) => `<div class="record row"><strong>${esc(phone(id))}</strong><button class="btn mini" data-unblock="${esc(id)}">Unblock</button></div>`, "No blocked contacts.");
      p.innerHTML = box("WhatsApp profile", profileCard) +
        box("Delivery settings", `<form id="settingsForm">${field("sendIntervalMs", "Minimum interval between sends (milliseconds)", "number", `min="0" max="60000" value="${settings.sendIntervalMs}"`)}${text("webhookEvents", "Webhook events, comma separated (blank = all)")}${submit("Save settings")}</form><p class="hint">Events: message, receipt, connection, group, group-participants, presence, call, history, error.</p>`) +
        box("Blocked contacts", `<div id="blocklist">${blockList}</div><form id="unblockForm">${field("unblockPhone", "Unblock another number", "text", "required")}${submit("Unblock contact")}</form>`);
      p.classList.add("stack");
      document.querySelector("#webhookEvents").value = settings.webhookEvents.join(", ");
      on("goConnect", () => document.querySelector('[data-tab="connection"]')?.click());
      document.querySelectorAll("[data-unblock]").forEach((btn) => (btn.onclick = async () => {
        try {
          await api(base + "/contacts/block", "PUT", { phone: btn.dataset.unblock, blocked: false });
          toast("Contact unblocked");
          await refresh();
        } catch (e) { toast(e.message); }
      }));
      if (prof)
        form("profileForm", async (d) => {
          await api(base + "/profile", "PUT", {
            ...(d.profileName ? { name: d.profileName } : {}),
            ...(d.profileAbout ? { about: d.profileAbout } : {}),
          });
          toast("Profile updated");
          await refresh();
        });
      form("settingsForm", async (d) => {
        await api(base + "/settings", "PUT", {
          sendIntervalMs: Number(d.sendIntervalMs),
          webhookEvents: d.webhookEvents.split(",").map((x) => x.trim()).filter(Boolean),
        });
        toast("Settings saved");
      });
      form("unblockForm", async (d) => {
        await api(base + "/contacts/block", "PUT", { phone: d.unblockPhone, blocked: false });
        toast("Contact unblocked");
        await refresh();
      });
    }
  }
  return { tabs, upload, render, csv };
})();
