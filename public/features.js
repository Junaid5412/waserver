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
      await window.ZelonChat.render({ ...ctx, upload });
      return;
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
