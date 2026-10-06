import nodemailer from "nodemailer";
import { ImapFlow } from "imapflow";
import { simpleParser } from "mailparser";
import { callGeminiWithFailover } from "./ai.js";

/**
 * Creates the Business Email Service engine.
 */
export function createEmailService(store, enc) {
  // In-memory IMAP client connection pool for fast interactive responsiveness
  const clientPool = new Map();

  function getClientKey(account) {
    return `${account.id}:${account.email}`;
  }

  function createImapClient(account) {
    const imapConfig = account.imap;
    const isSecure = imapConfig.secure !== false && imapConfig.port !== 143;
    return new ImapFlow({
      host: imapConfig.host,
      port: Number(imapConfig.port) || (isSecure ? 993 : 143),
      secure: isSecure,
      auth: {
        user: imapConfig.auth?.user || account.email,
        pass: imapConfig.auth?.pass,
      },
      logger: false,
      emitLogs: false,
      verifyOnly: false,
      clientInfo: {
        name: "Zelon Business Mail",
        version: "1.0.0",
      },
    });
  }

  /**
   * Test IMAP and SMTP connectivity and verify credentials.
   */
  async function testConnection(accountData) {
    const diagnostics = {
      imap: { ok: false, error: null },
      smtp: { ok: false, error: null },
    };

    // 1. Test IMAP
    let imapClient = null;
    try {
      imapClient = createImapClient(accountData);
      await imapClient.connect();
      diagnostics.imap.ok = true;
      await imapClient.logout().catch(() => {});
    } catch (err) {
      diagnostics.imap.error = err.message || "Failed to connect to IMAP server";
      if (imapClient) {
        try { imapClient.close(); } catch (_) {}
      }
    }

    // 2. Test SMTP
    try {
      const smtpConfig = accountData.smtp;
      const isSecure = smtpConfig.secure === true || smtpConfig.port === 465;
      const transporter = nodemailer.createTransport({
        host: smtpConfig.host,
        port: Number(smtpConfig.port) || (isSecure ? 465 : 587),
        secure: isSecure,
        auth: {
          user: smtpConfig.auth?.user || accountData.email,
          pass: smtpConfig.auth?.pass,
        },
        tls: {
          rejectUnauthorized: false,
        },
      });
      await transporter.verify();
      diagnostics.smtp.ok = true;
    } catch (err) {
      diagnostics.smtp.error = err.message || "Failed to verify SMTP credentials";
    }

    const overallSuccess = diagnostics.imap.ok && diagnostics.smtp.ok;
    return {
      success: overallSuccess,
      diagnostics,
      message: overallSuccess
        ? "IMAP and SMTP verified successfully! Your business email is ready to use."
        : `Verification issue: ${diagnostics.imap.error || diagnostics.smtp.error}`,
    };
  }

  /**
   * Save or update an email account for a user.
   */
  async function saveAccount(userId, accountData) {
    const list = (await store.get("email_accounts", userId)) || [];
    const id = accountData.id || `acc_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;
    const isFirst = list.length === 0;

    const account = {
      id,
      userId,
      email: accountData.email.trim().toLowerCase(),
      name: accountData.name?.trim() || accountData.email.split("@")[0],
      imap: {
        host: accountData.imap.host.trim(),
        port: Number(accountData.imap.port) || 993,
        secure: accountData.imap.secure !== false,
        auth: {
          user: (accountData.imap.auth?.user || accountData.email).trim(),
          pass: accountData.imap.auth?.pass || "",
        },
      },
      smtp: {
        host: accountData.smtp.host.trim(),
        port: Number(accountData.smtp.port) || 465,
        secure: accountData.smtp.secure !== false,
        auth: {
          user: (accountData.smtp.auth?.user || accountData.email).trim(),
          pass: accountData.smtp.auth?.pass || "",
        },
      },
      isDefault: accountData.isDefault ?? isFirst,
      updatedAt: new Date().toISOString(),
      createdAt: accountData.createdAt || new Date().toISOString(),
    };

    const existingIndex = list.findIndex((a) => a.id === id);
    if (existingIndex >= 0) {
      list[existingIndex] = account;
    } else {
      if (account.isDefault) {
        for (const a of list) a.isDefault = false;
      }
      list.push(account);
    }

    await store.set("email_accounts", userId, list);
    return sanitizeAccount(account);
  }

  /**
   * Get all accounts for a user (without passwords exposed).
   */
  async function getAccounts(userId) {
    const list = (await store.get("email_accounts", userId)) || [];
    return list.map(sanitizeAccount);
  }

  /**
   * Delete an email account.
   */
  async function deleteAccount(userId, accountId) {
    let list = (await store.get("email_accounts", userId)) || [];
    list = list.filter((a) => a.id !== accountId);
    if (list.length > 0 && !list.some((a) => a.isDefault)) {
      list[0].isDefault = true;
    }
    await store.set("email_accounts", userId, list);
    return { ok: true };
  }

  async function getRawAccount(userId, accountId) {
    const list = (await store.get("email_accounts", userId)) || [];
    if (accountId) {
      return list.find((a) => a.id === accountId) || null;
    }
    return list.find((a) => a.isDefault) || list[0] || null;
  }

  function sanitizeAccount(acc) {
    return {
      id: acc.id,
      email: acc.email,
      name: acc.name,
      isDefault: !!acc.isDefault,
      imap: {
        host: acc.imap.host,
        port: acc.imap.port,
        secure: acc.imap.secure,
        user: acc.imap.auth?.user,
      },
      smtp: {
        host: acc.smtp.host,
        port: acc.smtp.port,
        secure: acc.smtp.secure,
        user: acc.smtp.auth?.user,
      },
      createdAt: acc.createdAt,
    };
  }

  /**
   * Get Mailbox folders (Inbox, Sent, Drafts, Trash, Starred, Outbox).
   */
  async function getFolders(userId, accountId) {
    const account = await getRawAccount(userId, accountId);
    if (!account) throw new Error("No business email account configured");

    const client = createImapClient(account);
    await client.connect();
    try {
      const list = await client.list();
      const standardFolders = [
        { id: "INBOX", name: "Inbox", icon: "inbox", count: 0, unread: 0 },
        { id: "Sent", name: "Sent", icon: "send", count: 0, unread: 0 },
        { id: "Drafts", name: "Drafts", icon: "drafts", count: 0, unread: 0 },
        { id: "Trash", name: "Trash", icon: "delete", count: 0, unread: 0 },
        { id: "Starred", name: "Starred", icon: "star", count: 0, unread: 0, isVirtual: true },
        { id: "Outbox", name: "Outbox", icon: "outbox", count: 0, unread: 0, isLocal: true },
      ];

      // Inspect INBOX status for unread count
      try {
        const status = await client.status("INBOX", { messages: true, unseen: true });
        const inboxItem = standardFolders.find((f) => f.id === "INBOX");
        if (inboxItem) {
          inboxItem.count = status.messages || 0;
          inboxItem.unread = status.unseen || 0;
        }
      } catch (_) {}

      // Map any custom IMAP folders returned by server
      for (const f of list) {
        const p = f.path;
        const low = p.toLowerCase();
        let matched = null;
        if (low === "inbox") matched = "INBOX";
        else if (low.includes("sent")) matched = "Sent";
        else if (low.includes("draft")) matched = "Drafts";
        else if (low.includes("trash") || low.includes("deleted") || low.includes("bin")) matched = "Trash";

        if (matched) {
          try {
            const s = await client.status(p, { messages: true, unseen: true });
            const item = standardFolders.find((x) => x.id === matched);
            if (item) {
              item.path = p;
              item.count = Math.max(item.count, s.messages || 0);
              item.unread = Math.max(item.unread, s.unseen || 0);
            }
          } catch (_) {}
        }
      }

      return { folders: standardFolders, activeAccount: sanitizeAccount(account) };
    } finally {
      await client.logout().catch(() => {});
    }
  }

  /**
   * Fetch paginated emails from a folder.
   */
  async function fetchMessages(userId, accountId, options = {}) {
    const { folder = "INBOX", page = 1, limit = 30, search = "", filter = "all" } = options;
    const account = await getRawAccount(userId, accountId);
    if (!account) throw new Error("No business email account configured");

    const client = createImapClient(account);
    await client.connect();
    try {
      const targetFolder = folder === "Starred" ? "INBOX" : folder;
      const mailbox = await client.mailboxOpen(targetFolder);
      const totalMessages = mailbox.exists || 0;

      if (totalMessages === 0) {
        return { messages: [], total: 0, page, hasMore: false };
      }

      // Search query
      const searchQuery = {};
      if (filter === "unread") searchQuery.seen = false;
      if (folder === "Starred" || filter === "starred") searchQuery.flagged = true;
      if (search && search.trim().length > 0) {
        searchQuery.or = [
          { subject: search.trim() },
          { from: search.trim() },
          { body: search.trim() },
        ];
      }

      let uids = [];
      try {
        uids = await client.search(searchQuery, { uid: true });
      } catch (_) {
        uids = await client.search({ all: true }, { uid: true });
      }

      // Sort newest first
      uids.sort((a, b) => b - a);

      const startIndex = (page - 1) * limit;
      const paginatedUids = uids.slice(startIndex, startIndex + limit);

      if (!paginatedUids.length) {
        return { messages: [], total: uids.length, page, hasMore: false };
      }

      const messages = [];
      for await (const msg of client.fetch(paginatedUids, {
        uid: true,
        flags: true,
        envelope: true,
        internalDate: true,
        bodyStructure: true,
        size: true,
      })) {
        const env = msg.envelope || {};
        const fromObj = env.from?.[0] || {};
        const fromName = fromObj.name || fromObj.address || "Unknown Sender";
        const fromAddress = fromObj.address || "";
        const subject = env.subject || "(No Subject)";
        const date = env.date || msg.internalDate || new Date().toISOString();
        const isRead = msg.flags?.has("\\Seen") || false;
        const isStarred = msg.flags?.has("\\Flagged") || false;

        // Check if attachments exist in bodyStructure
        const hasAttachments = !!(
          msg.bodyStructure?.childNodes?.some((node) => node.disposition === "attachment" || (node.filename && node.type !== "text"))
        );

        messages.push({
          uid: msg.uid,
          subject,
          fromName,
          fromAddress,
          to: (env.to || []).map((t) => t.address || t.name),
          date: new Date(date).toISOString(),
          isRead,
          isStarred,
          hasAttachments,
          size: msg.size,
          folder,
        });
      }

      // Ensure descending order
      messages.sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime());

      return {
        messages,
        total: uids.length,
        page,
        hasMore: startIndex + limit < uids.length,
      };
    } finally {
      await client.logout().catch(() => {});
    }
  }

  /**
   * Fetch full message content (HTML, Text, Attachments metadata).
   */
  async function fetchMessageDetail(userId, accountId, folder, uid) {
    const account = await getRawAccount(userId, accountId);
    if (!account) throw new Error("No business email account configured");

    const client = createImapClient(account);
    await client.connect();
    try {
      const targetFolder = folder === "Starred" ? "INBOX" : folder;
      await client.mailboxOpen(targetFolder);

      const downloadResult = await client.download(String(uid), undefined, { uid: true });
      if (!downloadResult?.content) throw new Error("Could not retrieve message content");

      const parsed = await simpleParser(downloadResult.content);

      // Auto-mark as read
      try {
        await client.messageFlagsAdd({ uid: Number(uid) }, ["\\Seen"], { uid: true });
      } catch (_) {}

      const attachments = (parsed.attachments || []).map((att, idx) => ({
        id: idx,
        filename: att.filename || `attachment_${idx + 1}`,
        contentType: att.contentType || "application/octet-stream",
        size: att.size || att.content?.length || 0,
        contentId: att.cid || null,
      }));

      return {
        uid: Number(uid),
        folder,
        subject: parsed.subject || "(No Subject)",
        from: {
          name: parsed.from?.value?.[0]?.name || "",
          address: parsed.from?.value?.[0]?.address || "",
        },
        to: (parsed.to?.value || []).map((t) => ({ name: t.name || "", address: t.address || "" })),
        cc: (parsed.cc?.value || []).map((t) => ({ name: t.name || "", address: t.address || "" })),
        date: parsed.date ? parsed.date.toISOString() : new Date().toISOString(),
        messageId: parsed.messageId,
        inReplyTo: parsed.inReplyTo,
        references: parsed.references,
        text: parsed.text || "",
        html: parsed.html || (parsed.textAsHtml ? parsed.textAsHtml : null) || `<pre style="white-space: pre-wrap; font-family: inherit;">${parsed.text || ""}</pre>`,
        attachments,
      };
    } finally {
      await client.logout().catch(() => {});
    }
  }

  /**
   * Download a single attachment buffer.
   */
  async function getAttachment(userId, accountId, folder, uid, attachmentIndex) {
    const account = await getRawAccount(userId, accountId);
    if (!account) throw new Error("No business email account configured");

    const client = createImapClient(account);
    await client.connect();
    try {
      const targetFolder = folder === "Starred" ? "INBOX" : folder;
      await client.mailboxOpen(targetFolder);

      const downloadResult = await client.download(String(uid), undefined, { uid: true });
      const parsed = await simpleParser(downloadResult.content);
      const att = parsed.attachments?.[Number(attachmentIndex)];
      if (!att) throw new Error("Attachment not found");

      return {
        filename: att.filename || "attachment",
        contentType: att.contentType || "application/octet-stream",
        content: att.content,
      };
    } finally {
      await client.logout().catch(() => {});
    }
  }

  /**
   * Send Email via SMTP.
   */
  async function sendEmail(userId, accountId, emailData) {
    const account = await getRawAccount(userId, accountId);
    if (!account) throw new Error("No business email account configured");

    const smtpConfig = account.smtp;
    const isSecure = smtpConfig.secure === true || smtpConfig.port === 465;

    const transporter = nodemailer.createTransport({
      host: smtpConfig.host,
      port: Number(smtpConfig.port) || (isSecure ? 465 : 587),
      secure: isSecure,
      auth: {
        user: smtpConfig.auth?.user || account.email,
        pass: smtpConfig.auth?.pass,
      },
      tls: {
        rejectUnauthorized: false,
      },
    });

    const mailOptions = {
      from: `"${account.name}" <${account.email}>`,
      to: emailData.to,
      cc: emailData.cc || undefined,
      bcc: emailData.bcc || undefined,
      subject: emailData.subject || "(No Subject)",
      text: emailData.text || "",
      html: emailData.html || (emailData.text ? `<p style="font-family: sans-serif; font-size: 14px; line-height: 1.5;">${emailData.text.replace(/\n/g, "<br/>")}</p>` : undefined),
      inReplyTo: emailData.inReplyTo || undefined,
      references: emailData.references || undefined,
      attachments: (emailData.attachments || []).map((att) => ({
        filename: att.filename,
        content: Buffer.from(att.base64Data, "base64"),
        contentType: att.mimetype,
      })),
    };

    const info = await transporter.sendMail(mailOptions);

    // Save copy to IMAP Sent mailbox if available
    try {
      const client = createImapClient(account);
      await client.connect();
      const list = await client.list();
      const sentBox = list.find((f) => f.path.toLowerCase().includes("sent"))?.path || "Sent";
      if (sentBox) {
        const rawContent = await transporter.sendMail({ ...mailOptions, streamTransport: true });
        const chunks = [];
        for await (const c of rawContent.message) chunks.push(c);
        const fullMime = Buffer.concat(chunks);
        await client.append(sentBox, fullMime, ["\\Seen"]);
      }
      await client.logout().catch(() => {});
    } catch (_) {}

    return {
      ok: true,
      messageId: info.messageId,
      envelope: info.envelope,
    };
  }

  /**
   * Flag a message (Mark read/unread, star/unstar).
   */
  async function flagMessage(userId, accountId, folder, uid, { read, star }) {
    const account = await getRawAccount(userId, accountId);
    if (!account) throw new Error("No business email account configured");

    const client = createImapClient(account);
    await client.connect();
    try {
      const targetFolder = folder === "Starred" ? "INBOX" : folder;
      await client.mailboxOpen(targetFolder);

      if (read === true) await client.messageFlagsAdd({ uid: Number(uid) }, ["\\Seen"], { uid: true });
      if (read === false) await client.messageFlagsRemove({ uid: Number(uid) }, ["\\Seen"], { uid: true });

      if (star === true) await client.messageFlagsAdd({ uid: Number(uid) }, ["\\Flagged"], { uid: true });
      if (star === false) await client.messageFlagsRemove({ uid: Number(uid) }, ["\\Flagged"], { uid: true });

      return { ok: true };
    } finally {
      await client.logout().catch(() => {});
    }
  }

  /**
   * Delete or move email to trash.
   */
  async function deleteMessage(userId, accountId, folder, uid, permanent = false) {
    const account = await getRawAccount(userId, accountId);
    if (!account) throw new Error("No business email account configured");

    const client = createImapClient(account);
    await client.connect();
    try {
      const targetFolder = folder === "Starred" ? "INBOX" : folder;
      await client.mailboxOpen(targetFolder);

      if (!permanent && targetFolder.toLowerCase() !== "trash") {
        const list = await client.list();
        const trashBox = list.find((f) => f.path.toLowerCase().includes("trash") || f.path.toLowerCase().includes("bin") || f.path.toLowerCase().includes("deleted"))?.path || "Trash";
        try {
          await client.messageMove({ uid: Number(uid) }, trashBox, { uid: true });
          return { ok: true, movedTo: trashBox };
        } catch (_) {}
      }

      await client.messageDelete({ uid: Number(uid) }, { uid: true });
      return { ok: true, deleted: true };
    } finally {
      await client.logout().catch(() => {});
    }
  }

  /**
   * AI For Email Response:
   * Generates 3 professional corporate reply suggestions and brief summary using Gemini 3.1+.
   */
  async function generateAiEmailReply(geminiKeys, preferredModel, emailContext) {
    const { subject, senderName, senderEmail, emailBody, userIntent } = emailContext;

    const systemInstruction = `You are a high-level executive Business Email AI Assistant.
You compose polished, professional, courteous, and articulate email drafts for business correspondence.
Always match the language of the incoming email (English, Urdu/Hindi, Roman Urdu, Arabic, etc.).
STRICTLY output valid JSON.`;

    let prompt = `Here is the business email received:
Subject: ${subject || "(No Subject)"}
From: ${senderName || "Sender"} <${senderEmail || ""}>
Content:
"""
${(emailBody || "").slice(0, 4000)}
"""

Task:
`;

    if (userIntent && userIntent.trim().length > 0) {
      prompt += `The user specifically wants to reply with this intent or instructions:
"${userIntent.trim()}"

Provide:
1. "summary": A brief 1-sentence summary of the incoming email.
2. "replies": An array of 3 distinct, complete, professional corporate email variations matching the user's intent. Format each variation with a greeting, well-structured body paragraphs, and professional closing sign-off.
`;
    } else {
      prompt += `Analyze this email and provide:
1. "summary": A brief 1-sentence summary of what the sender is communicating or requesting.
2. "replies": An array of 3 distinct professional corporate reply variations:
   - Variation 1: "Formal Acceptance / Confirmation" (Agree, confirm details, next steps)
   - Variation 2: "Polite Request for More Information / Clarification" (Ask clarifying questions, request documentation)
   - Variation 3: "Diplomatic Decline / Propose Alternative" (Politely decline or reschedule)
Format each variation with a greeting, well-structured paragraphs, and professional closing sign-off.
`;
    }

    prompt += `
STRICTLY return ONLY a raw JSON object with this exact schema:
{
  "summary": "1-sentence summary",
  "replies": [
    { "type": "Accept / Confirm", "subject": "Re: ...", "body": "Dear ...\\n\\n..." },
    { "type": "Request Info", "subject": "Re: ...", "body": "Dear ...\\n\\n..." },
    { "type": "Alternative / Decline", "subject": "Re: ...", "body": "Dear ...\\n\\n..." }
  ]
}
`;

    const rawResponse = await callGeminiWithFailover(geminiKeys, preferredModel || "gemini-3.1-pro", prompt, systemInstruction);

    try {
      const cleanJson = rawResponse.replace(/```(?:json)?/gi, "").replace(/```/g, "").trim();
      const parsed = JSON.parse(cleanJson);
      return parsed;
    } catch (_) {
      return {
        summary: "Email received from " + (senderName || senderEmail),
        replies: [
          {
            type: "Professional Confirmation",
            subject: "Re: " + (subject || "Inquiry"),
            body: `Dear ${senderName || "Sir/Madam"},\n\nThank you for reaching out. I have reviewed your message and confirm that we are proceeding accordingly.\n\nPlease let me know if you need any additional details.\n\nBest regards,\n`,
          },
          {
            type: "Acknowledge & Review",
            subject: "Re: " + (subject || "Inquiry"),
            body: `Dear ${senderName || "Sir/Madam"},\n\nThank you for your email. I am currently reviewing the details and will get back to you with a comprehensive update shortly.\n\nBest regards,\n`,
          },
        ],
      };
    }
  }

  return {
    testConnection,
    saveAccount,
    getAccounts,
    deleteAccount,
    getFolders,
    fetchMessages,
    fetchMessageDetail,
    getAttachment,
    sendEmail,
    flagMessage,
    deleteMessage,
    generateAiEmailReply,
  };
}
