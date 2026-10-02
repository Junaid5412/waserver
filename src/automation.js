import { hash } from "./security.js";
import { enqueueMessage } from "./messages.js";
import { describeMessage } from "./inbox.js";
export const renderTemplate = (value, contact = {}) =>
  String(value).replace(/\{\{\s*(name|phone|message)\s*\}\}/g, (_, key) =>
    String(contact[key] || ""),
  );
export function createAutomation(store, enc) {
  return async (instance, message, { notify = true } = {}) => {
    if ((await store.get("users", instance.userId))?.disabled) return;
    if (
      !notify ||
      message.key?.fromMe ||
      !message.key?.remoteJid ||
      message.key.remoteJid === "status@broadcast"
    )
      return;
    const chatId = message.key.remoteJid;
    if (chatId.endsWith("@g.us")) return;
    const info = describeMessage(message.message),
      text = info.text.trim();
    if (!text) return;
    const contactId = hash(instance.id + ":" + chatId),
      contact = await store.get("contacts", contactId);
    if (/^(stop|unsubscribe|cancel subscription)$/i.test(text)) {
      await store.set("contacts", contactId, {
        ...contact,
        id: contactId,
        instanceId: instance.id,
        userId: instance.userId,
        chatId,
        lookupKey: chatId,
        createdAt: contact?.createdAt || new Date().toISOString(),
        optedOut: true,
        consent: false,
      });
      return;
    }
    if (contact?.optedOut) return;
    const rules = await store.query("rules", {
      instanceId: instance.id,
      status: "enabled",
      limit: 1000,
    });
    for (const rule of rules) {
      const match =
        rule.match === "any" ||
        (rule.match === "exact" &&
          text.toLowerCase() === rule.keyword.toLowerCase()) ||
        (rule.match === "contains" &&
          text.toLowerCase().includes(rule.keyword.toLowerCase()));
      if (!match) continue;
      const stateId = hash(rule.id + ":" + chatId);
      await store.insert("rule-state", stateId, {
        id: stateId,
        instanceId: instance.id,
        nextAt: 0,
      });
      let reserved = false;
      await store.patch("rule-state", stateId, (state) => {
        if (state.nextAt > Date.now()) return state;
        reserved = true;
        return { ...state, nextAt: Date.now() + rule.cooldownSeconds * 1000 };
      });
      if (!reserved) continue;
      const key = "rule:" + hash(rule.id + ":" + message.key.id);
      await enqueueMessage(
        store,
        enc,
        instance,
        {
          to: chatId,
          type: "text",
          text: renderTemplate(rule.reply, {
            name: contact?.name || message.pushName || "",
            phone: chatId.split("@")[0],
            message: text,
          }),
        },
        key,
        () => {},
        { automationRuleId: rule.id },
      );
      if (rule.stopAfterMatch !== false) break;
    }
  };
}
