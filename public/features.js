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
      let chats = await api(base + "/chats?limit=100"),
        chat = null,
        messages = [],
        quotedId;
      let hasMoreChats = chats.length === 100;
      let chatCursor = chats.at(-1);
      p.innerHTML = `<div class="inboxlayout"><section class="card chatlist"><div class="row"><h3>Conversations</h3><button class="btn" id="reloadInbox">Refresh</button></div><input id="chatSearch" aria-label="Search conversations" placeholder="Search conversations"><div id="chatRows"></div><button class="btn" id="moreChats">Load more conversations</button><form id="openChat">${field("newChat", "New conversation", "tel", 'placeholder="+97450000000" required')}${submit("Open chat")}</form></section><section class="card conversation" id="conversation"><div class="empty"><h3>Your shared inbox</h3><p>Select a conversation to read messages and reply.</p></div></section></div>`;
      const drawChats = (q) => {
        document.querySelector("#chatRows").innerHTML = list(
          chats.filter((c) =>
            (c.name + " " + c.chatId).toLowerCase().includes(q),
          ),
          (c) =>
            `<button class="chatentry ${chat === c.chatId ? "active" : ""}" data-chat="${esc(c.chatId)}"><span class="avatar">${esc((c.name || c.chatId || "C").slice(0, 1).toUpperCase())}</span><div class="chat-copy"><strong>${esc(c.name || c.chatId)}</strong><span>${esc(c.lastPreview || "Start a conversation")}</span><small>${c.unread ? c.unread + " unread · " : ""}${c.archived ? "Archived" : c.pinned ? "Pinned" : "WhatsApp"}</small></div></button>`,
          "Conversations appear after WhatsApp syncs.",
        );
        document
          .querySelectorAll("[data-chat]")
          .forEach(
            (b) =>
              (b.onclick = () =>
                open(b.dataset.chat).catch((e) => toast(e.message))),
          );
      };
      const moreButton = document.querySelector("#moreChats");
      moreButton.hidden = !hasMoreChats;
      moreButton.onclick = async () => {
        moreButton.disabled = true;
        try {
          const next = await api(base + "/chats?limit=100&before=" + encodeURIComponent(chatCursor.createdAt) + "&beforeId=" + encodeURIComponent(chatCursor.id));
          const known = new Set(chats.map(row => row.id));
          chats.push(...next.filter(row => !known.has(row.id)));
          chatCursor = next.at(-1) || chatCursor;
          hasMoreChats = next.length === 100;
          moreButton.hidden = !hasMoreChats;
          drawChats(document.querySelector("#chatSearch").value.toLowerCase());
        } catch (error) { toast(error.message); }
        finally { moreButton.disabled = false; }
      };
      drawChats("");
      document.querySelector("#chatSearch").oninput = (e) =>
        drawChats(e.target.value.toLowerCase());
      let polling = false;
      ctx.startPolling?.(async () => {
        if (polling || !p.isConnected || document.hidden) return;
        polling = true;
        try {
          const freshChats = await api(base + "/chats?limit=100");
          const freshIds = new Set(freshChats.map(row => row.id));
          chats = [...freshChats, ...chats.filter(row => !freshIds.has(row.id))];
          if (!p.isConnected) return;
          drawChats(document.querySelector("#chatSearch").value.toLowerCase());
          if (chat && messages.length <= 50) {
            const recent = await api(base + "/chats/" + encodeURIComponent(chat) + "/messages?limit=50");
            if (!p.isConnected || JSON.stringify(recent) === JSON.stringify(messages)) return;
            const draft = document.querySelector("#replyText")?.value || "";
            const attachment = document.querySelector("#replyAttachment")?.files.length;
            const actionOpen = document.querySelector("#inboxAction")?.textContent;
            if (!draft && !attachment && !quotedId && !actionOpen) await open(chat);
            else document.querySelector("#refreshChat").textContent = "New updates · Refresh";
          }
        } catch { /* Keep the current conversation and draft during outages. */ }
        finally { polling = false; }
      }, 5000);
      on("reloadInbox", refresh);
      form("openChat", async (d) => open(d.newChat));
      async function open(id, older = false) {
        chat = id;
        const last = messages.at(-1),
          suffix =
            older && last
              ? "&before=" +
                encodeURIComponent(last.createdAt) +
                "&beforeId=" +
                encodeURIComponent(last.id)
              : "";
        const rows = await api(
          base +
            "/chats/" +
            encodeURIComponent(id) +
            "/messages?limit=50" +
            suffix,
        );
        messages = older ? [...messages, ...rows] : rows;
        quotedId = undefined;
        const c = document.querySelector("#conversation");
        c.innerHTML = `<div class="row"><button class="btn" id="chatBack" aria-label="Back to conversations">←</button><span class="avatar">${esc((chats.find(x => x.chatId === id)?.name || "C").slice(0, 1).toUpperCase())}</span><h3>${esc(chats.find((x) => x.chatId === id)?.name || id)}</h3><button class="btn" id="refreshChat">Refresh</button></div><div class="actions"><button class="btn" id="readChat">Mark read</button><button class="btn" id="archiveChat">Archive</button><button class="btn" id="pinChat">Pin</button></div><div class="messages">${list([...messages].reverse(), (m) => `<article class="bubble ${m.fromMe ? "outgoing" : ""}"><div class="hint">${esc(m.name || m.participant || (m.fromMe ? "You" : "Contact"))}</div><div class="messagebody">${messageBody(m)}</div><small>${esc(new Date(m.createdAt).toLocaleString())} · ${esc(m.status)}</small><div class="actions"><button class="btn mini" data-quote="${esc(m.waId)}">Reply</button><button class="btn mini" data-react="${esc(m.waId)}">React</button><button class="btn mini" data-forward="${esc(m.waId)}">Forward</button>${m.fromMe ? `<button class="btn mini" data-edit="${esc(m.waId)}">Edit</button><button class="btn mini" data-delete="${esc(m.waId)}">Delete</button>` : ""}${m.hasMedia ? `<a class="btn mini" href="/api${base}/inbox/${encodeURIComponent(m.waId)}/media">Download</a>` : ""}${m.pollOptions?.length ? `<button class="btn mini" data-votes="${esc(m.waId)}">Poll votes</button>` : ""}</div></article>`, "No local messages in this conversation yet.")}</div>${rows.length === 50 ? '<button class="btn" id="olderMessages">Load older messages</button>' : ""}<div id="quoteHint" class="hint"></div><form id="replyForm">${text("replyText", "Reply", 'maxlength="20000" placeholder="Type a message…"')}${submit("Send")}${field("replyAttachment", "Attach file", "file", 'aria-label="Attach an image, video, audio or document"')}</form><div id="inboxAction"></div>`;
        document.querySelector(".inboxlayout").classList.add("chat-open");
        document.querySelectorAll("[data-chat]").forEach(button => button.classList.toggle("active", button.dataset.chat === id));
        on("chatBack", () => document.querySelector(".inboxlayout").classList.remove("chat-open"));
        bindPreviews(c);
        if (!older) { const timeline = c.querySelector(".messages"); timeline.scrollTop = timeline.scrollHeight; }
        on("refreshChat", () => open(id));
        on("olderMessages", () => open(id, true));
        on("readChat", async () => {
          await api(
            base + "/chats/" + encodeURIComponent(chat) + "/settings",
            "PUT",
            { read: true },
          );
          toast("Marked read");
        });
        on("archiveChat", async () => {
          await api(
            base + "/chats/" + encodeURIComponent(chat) + "/settings",
            "PUT",
            { archive: true },
          );
          toast("Chat archived");
        });
        on("pinChat", async () => {
          await api(
            base + "/chats/" + encodeURIComponent(chat) + "/settings",
            "PUT",
            { pin: true },
          );
          toast("Chat pinned");
        });
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
          await api(
            base + "/messages",
            "POST",
            payload,
            { "Idempotency-Key": replyForm.dataset.key },
          );
          toast("Reply queued");
          replyForm.reset();
          replyForm.dataset.key = crypto.randomUUID();
          quotedId = undefined;
          document.querySelector("#quoteHint").textContent = "";
        });
        document.querySelectorAll("[data-quote]").forEach(
          (b) =>
            (b.onclick = () => {
              quotedId = b.dataset.quote;
              document.querySelector("#quoteHint").textContent =
                "Replying to " + quotedId;
              document.querySelector("#replyText").focus();
            }),
        );
        const action = (attr, label, fn) =>
          document.querySelectorAll("[data-" + attr + "]").forEach(
            (b) =>
              (b.onclick = () => {
                const id = b.dataset[attr],
                  target = document.querySelector("#inboxAction");
                target.innerHTML = box(
                  label,
                  `<form id="actionForm">${field("value", label, "text", "required")}${submit("Confirm")}</form>`,
                );
                form("actionForm", async (d) => {
                  await fn(id, d.value);
                  target.innerHTML = "";
                  toast("Request completed");
                });
              }),
          );
        action("react", "Reaction emoji (e.g. 👍)", (id, value) =>
          api(base + "/inbox/" + encodeURIComponent(id) + "/reaction", "POST", {
            emoji: value,
          }),
        );
        action("edit", "New message text", (id, value) =>
          api(base + "/inbox/" + encodeURIComponent(id) + "/text", "PUT", {
            text: value,
          }),
        );
        action("forward", "Forward to phone or group JID", (id, value) =>
          api(
            base + "/messages",
            "POST",
            { to: value, type: "forward", forwardId: id },
            { "Idempotency-Key": crypto.randomUUID() },
          ),
        );
        document.querySelectorAll("[data-delete]").forEach(
          (b) =>
            (b.onclick = () => {
              const target = document.querySelector("#inboxAction");
              target.innerHTML = box(
                "Delete message for everyone",
                '<p>WhatsApp time and group permissions apply.</p><button class="btn danger" id="confirmDelete">Delete message</button>',
              );
              on("confirmDelete", async () => {
                await api(
                  base +
                    "/inbox/" +
                    encodeURIComponent(b.dataset.delete) +
                    "/delete",
                  "POST",
                  {},
                );
                toast("Delete submitted");
                target.innerHTML = "";
              });
            }),
        );
        document.querySelectorAll("[data-votes]").forEach(
          (b) =>
            (b.onclick = async () => {
              try {
                document.querySelector("#inboxAction").textContent =
                  JSON.stringify(
                    await api(
                      base +
                        "/polls/" +
                        encodeURIComponent(b.dataset.votes) +
                        "/votes",
                    ),
                    null,
                    2,
                  );
              } catch (e) {
                toast(e.message);
              }
            }),
        );
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
          `<form id="groupSettings">${field("groupJid", "Group JID", "text", "required")}${field("subject", "New subject")}${text("description", "New description")}<label for="announcement">Who can send</label><select name="announcement" id="announcement"><option value="">Keep current setting</option><option value="true">Administrators only</option><option value="false">All members</option></select><label for="locked">Who can edit settings</label><select name="locked" id="locked"><option value="">Keep current setting</option><option value="true">Administrators only</option><option value="false">All members</option></select><label for="ephemeralSeconds">Disappearing messages</label><select name="ephemeralSeconds" id="ephemeralSeconds"><option value="">Keep current setting</option><option value="0">Disabled</option><option value="86400">24 hours</option><option value="604800">7 days</option><option value="7776000">90 days</option></select>${submit("Update group")}</form><div class="actions"><button class="btn" id="groupInfo">Read group details</button><button class="btn" id="groupInvite">Get invite</button><button class="btn" id="revokeInvite">Replace invite</button></div><pre id="groupOutput" class="doccode"></pre>`,
        ) +
        box(
          "Join a group",
          `<form id="joinGroup">${field("inviteCode", "Invite code", "text", "required")}${submit("Join group")}</form>`,
        ) +
        box(
          "Leave a group",
          `<form id="leaveGroup">${field("leaveJid", "Group JID", "text", "required")}<label class="checkbox"><input type="checkbox" required>I want this number to leave the group</label>${submit("Leave group")}</form>`,
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
      on("groupInfo", async () => {
        document.querySelector("#groupOutput").textContent = JSON.stringify(
          await api(base + "/groups/" + group()),
          null,
          2,
        );
      });
      on("groupInvite", async () => {
        const r = await api(base + "/groups/" + group() + "/invite");
        document.querySelector("#groupOutput").textContent =
          "https://chat.whatsapp.com/" + r.code;
      });
      on("revokeInvite", async () => {
        const r = await api(
          base + "/groups/" + group() + "/invite/revoke",
          "POST",
          {},
        );
        document.querySelector("#groupOutput").textContent =
          "https://chat.whatsapp.com/" + r.code;
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
      p.innerHTML =
        `<div class="split">${box("Connection tools", `<form id="pairForm">${field("pairPhone", "WhatsApp number", "tel", "required")}${submit("Request pairing code")}</form><div id="pairCode" class="key"></div><button class="btn" id="restartInstance">Restart connection</button><p class="hint">Pairing codes are for an unlinked number. Use WhatsApp → Linked devices → Link with phone number.</p>`)}${box("Profile", `<button class="btn" id="loadProfile">Read profile</button><div id="profileDetails"></div><form id="profileForm">${field("profileName", "Display name")}${field("profileAbout", "About (139 characters)", "text", 'maxlength="139"')}${submit("Update profile")}</form>`)}</div>` +
        box(
          "Delivery settings",
          `<form id="settingsForm">${field("sendIntervalMs", "Minimum interval between sends (milliseconds)", "number", `min="0" max="60000" value="${settings.sendIntervalMs}"`)}${text("webhookEvents", "Webhook events, comma separated (blank = all)")}${submit("Save settings")}</form><p class="hint">Events: message, receipt, connection, group, group-participants, presence, call, history, error.</p>`,
        ) +
        box(
          "Blocklist",
          `<button id="loadBlocklist" class="btn">Load blocked contacts</button><div id="blocklist"></div><form id="unblockForm">${field("unblockPhone", "Phone or contact JID", "text", "required")}${submit("Unblock contact")}</form>`,
        );
      document.querySelector("#webhookEvents").value =
        settings.webhookEvents.join(", ");
      form("pairForm", async (d) => {
        const r = await api(base + "/pairing-code", "POST", {
          phone: d.pairPhone,
        });
        document.querySelector("#pairCode").textContent = r.code;
      });
      on("restartInstance", async () => {
        await api(base + "/restart", "POST", {});
        toast("Connection restarting");
      });
      on("loadProfile", async () => {
        document.querySelector("#profileDetails").textContent = JSON.stringify(
          await api(base + "/profile"),
        );
      });
      form("profileForm", async (d) => {
        await api(base + "/profile", "PUT", {
          ...(d.profileName ? { name: d.profileName } : {}),
          ...(d.profileAbout ? { about: d.profileAbout } : {}),
        });
        toast("Profile updated");
      });
      form("settingsForm", async (d) => {
        await api(base + "/settings", "PUT", {
          sendIntervalMs: Number(d.sendIntervalMs),
          webhookEvents: d.webhookEvents
            .split(",")
            .map((x) => x.trim())
            .filter(Boolean),
        });
        toast("Settings saved");
      });
      on("loadBlocklist", async () => {
        document.querySelector("#blocklist").textContent = (
          await api(base + "/blocklist")
        ).join(", ");
      });
      form("unblockForm", async (d) => {
        await api(base + "/contacts/block", "PUT", {
          phone: d.unblockPhone,
          blocked: false,
        });
        toast("Contact unblocked");
      });
    }
  }
  return { tabs, upload, render, csv };
})();
