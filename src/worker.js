import { hash } from "./security.js";
import { deliver } from "./webhooks.js";
export function createWorker(store, enc, wa, content) {
  let pending = null,
    stopped = false;
  async function execute() {
    try {
      await store.health();
      for (const x of await store.query("instances", {
        status: "connected",
        limit: 1000,
      })) {
        if (x.archived || (await store.get("users", x.userId))?.disabled)
          continue;
        for (const row of await store.query("messages", {
          instanceId: x.id,
          status: "queued",
          dueBefore: Date.now(),
          limit: 25,
          ascending: true,
        })) {
          if (row.campaignId) {
            const campaign = await store.get("campaigns", row.campaignId);
            if (campaign?.status !== "running") continue;
          }
          if (
            (row.campaignId || row.automationRuleId) &&
            (await store.get("contacts", hash(x.id + ":" + row.to)))?.optedOut
          ) {
            const cancelled = {
              ...row,
              status: "cancelled",
              error: "Recipient opted out before submission",
            };
            await store.transition("messages", row.id, "queued", cancelled);
            continue;
          }
          if (x.sendIntervalMs && x.nextSendAt > Date.now()) break;
          row.status = "sending";
          if (!(await store.transition("messages", row.id, "queued", row)))
            continue;
          let submitted = false;
          try {
            const d = JSON.parse(enc.open(row.payload));
            const built = await content(d, x);
            const sent = await wa
              .active(x.id)
              .sendMessage(d.to, built.content || built, built.options || {});
            submitted = true;
            if (wa.recordSent) await wa.recordSent(x, sent, row);
            row.status = "sent";
            row.waId = sent?.key?.id;
            if (row.waId) {
              const receipt = await store.get(
                "receipts",
                hash(x.id + ":" + row.waId),
              );
              if (receipt) row.status = receipt.status;
            }
          } catch {
            row.status = submitted ? "unknown" : "failed";
            row.error = submitted
              ? "WhatsApp accepted the send but persistence failed; check delivery before retrying"
              : "Send failed; check connection before manually retrying";
          }
          await store.set("messages", row.id, row);
          if (x.sendIntervalMs) {
            x.nextSendAt = Date.now() + x.sendIntervalMs;
            await store.patch("instances", x.id, { nextSendAt: x.nextSendAt });
            break;
          }
        }
      }
      for (const h of await store.query("hooks", {
        status: "pending",
        dueBefore: Date.now(),
        limit: 100,
        ascending: true,
      })) {
        const x = await store.get("instances", h.instanceId);
        if (!x?.webhookUrl) {
          h.status = "cancelled";
          await store.set("hooks", h.id, h);
          continue;
        }
        try {
          await deliver(
            x.webhookUrl,
            JSON.parse(enc.open(h.event)),
            enc.open(x.webhookSecret),
          );
          h.status = "delivered";
        } catch (e) {
          h.attempts++;
          h.error = e.message;
          h.nextAt = Date.now() + Math.min(3600000, 10000 * 2 ** h.attempts);
          if (h.attempts >= 8) h.status = "failed";
        }
        await store.set("hooks", h.id, h);
      }
    } finally {
    }
  }
  const work = () => {
    if (stopped) return Promise.resolve();
    if (pending) return pending;
    pending = execute().finally(() => {
      pending = null;
    });
    return pending;
  };
  work.stop = async () => {
    stopped = true;
    await pending;
  };
  return work;
}
