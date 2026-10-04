import test from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import { readFile } from "node:fs/promises";
import { JSDOM } from "jsdom";
const features = await readFile(
    new URL("../public/features.js", import.meta.url),
    "utf8",
  ),
  app = await readFile(new URL("../public/app.js", import.meta.url), "utf8");
const wait = async (fn) => {
  for (let i = 0; i < 100; i++) {
    if (fn()) return;
    await new Promise((r) => setTimeout(r, 5));
  }
  assert.fail("UI did not reach state");
};
function fixture(t, { rich = false } = {}) {
  const dom = new JSDOM('<div id="root"></div><div id="toast"></div>', {
    url: "https://zelon.example/console",
    runScripts: "outside-only",
  });
  t.after(() => dom.window.close());
  const calls = [];
  dom.window.URL.createObjectURL = () => "blob:https://zelon.example/attachment";
  dom.window.URL.revokeObjectURL = () => {};
  dom.window.fetch = async (url, opts = {}) => {
    const body = opts.body ? JSON.parse(opts.body) : undefined;
    calls.push({
      url,
      method: opts.method || "GET",
      body,
      headers: opts.headers,
    });
    let data = { ok: true };
    if (url.endsWith("/media") && url.includes("/inbox/"))
      return new Response(new Uint8Array([1, 2, 3]), { headers: { "Content-Type": "image/png" } });
    if (url === "/api/me")
      data = { id: "user-a", role: "admin", email: "owner@example.com" };
    else if (url === "/api/instances")
      data = [{ id: "a", name: "Support", status: "disconnected" }];
    else if (url.endsWith("/qr")) data = { status: "disconnected" };
    else if (url.endsWith("/settings"))
      data = {
        sendIntervalMs: 1000,
        webhookEvents: [],
        maxMediaBytes: 104857600,
      };
    else if (url.includes("/chats/") && url.includes("/messages"))
      data = [
        {
          id: "row",
          waId: "wa-id",
          chatId: "97450000001@s.whatsapp.net",
          text: "<img onerror=evil()> hello",
          fromMe: false,
          status: "received",
          createdAt: "2026-10-02T01:00:00Z",
        },
      ];
    else if (url.includes("/chats?"))
      data = [
        {
          id: "chat",
          chatId: "97450000001@s.whatsapp.net",
          name: "Sam <script>",
          lastPreview: "hello",
          unread: 1,
        },
      ];
    else if (url.endsWith("/campaigns") && opts.method === "POST")
      data = { id: "campaign", status: "running" };
    else if (/\/(contacts|media|campaigns|templates|rules|statuses)$/.test(url))
      data = [];
    if (rich && url.includes("/chats/") && url.includes("/messages"))
      data.push(
        { id: "media", waId: "image-id", type: "image", hasMedia: true, text: "Photo caption", createdAt: "2026-10-02T01:00:00Z" },
        { id: "location", waId: "location-id", type: "location", location: { latitude: 25.2854, longitude: 51.531 }, createdAt: "2026-10-02T01:00:00Z" },
        { id: "poll", waId: "poll-id", type: "pollCreation", pollOptions: ["Yes <script>", "No"], text: "Are you available?", createdAt: "2026-10-02T01:00:00Z" },
        { id: "contact", waId: "contact-id", type: "contact", contacts: [{ name: "Sam", vcard: "TEL:+97450000001" }], createdAt: "2026-10-02T01:00:00Z" },
      );
    return new Response(JSON.stringify(data), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  };
  vm.runInContext(features, dom.getInternalVMContext());
  vm.runInContext(app, dom.getInternalVMContext());
  return { dom, calls, d: dom.window.document };
}
test("Extended inbox escapes names/messages and queues a quoted reply with a scoped idempotency key", async (t) => {
  const { dom, d, calls } = fixture(t);
  await wait(() => d.querySelector("[data-instance]"));
  d.querySelector("[data-instance]").click();
  d.querySelector('[data-tab="inbox"]').click();
  await wait(() => d.querySelector("[data-chat]"));
  assert.equal(d.querySelectorAll("script,img").length, 0);
  d.querySelector("[data-chat]").click();
  await wait(() => d.querySelector("[data-quote]"));
  assert.equal(d.querySelectorAll("script,img").length, 0);
  d.querySelector("[data-quote]").click();
  d.querySelector("#replyText").value = "Thanks";
  d.querySelector("#replyForm").dispatchEvent(
    new dom.window.Event("submit", { bubbles: true, cancelable: true }),
  );
  await wait(() =>
    calls.some((c) => c.url.endsWith("/messages") && c.method === "POST"),
  );
  const send = calls.find(
    (c) => c.url.endsWith("/messages") && c.method === "POST",
  );
  assert.equal(send.body.quotedId, "wa-id");
  assert.equal(send.body.to, "97450000001@s.whatsapp.net");
  assert.equal(send.body.text, "Thanks");
  assert(send.headers["Idempotency-Key"]);
});
test("Campaign form personalizes recipient input, requires consent and sends typed schedule settings", async (t) => {
  const { dom, d, calls } = fixture(t);
  await wait(() => d.querySelector("[data-instance]"));
  d.querySelector("[data-instance]").click();
  d.querySelector('[data-tab="campaigns"]').click();
  await wait(() => d.querySelector("#campaignForm"));
  assert(d.querySelector("#consentConfirmed").required);
  d.querySelector("#campaignName").value = "Launch";
  d.querySelector("#campaignText").value = "Hi {{name}}";
  d.querySelector("#recipients").value = "+97450000001,Sam\n+97450000002";
  d.querySelector("#consentConfirmed").checked = true;
  d.querySelector("#campaignForm").dispatchEvent(
    new dom.window.Event("submit", { bubbles: true, cancelable: true }),
  );
  await wait(() =>
    calls.some((c) => c.url.endsWith("/campaigns") && c.method === "POST"),
  );
  const send = calls.find(
    (c) => c.url.endsWith("/campaigns") && c.method === "POST",
  );
  assert.equal(send.body.consentConfirmed, true);
  assert.equal(send.body.intervalSeconds, 5);
  assert.deepEqual(send.body.recipients, [
    { to: "+97450000001", name: "Sam" },
    "+97450000002",
  ]);
  assert(send.headers["Idempotency-Key"]);
});
test("CSV parser handles quoted commas/newlines and rejects invalid headers", async (t) => {
  const { dom } = fixture(t);
  const csv = dom.window.ZelonFeatures.csv;
  const rows = csv(
    'phone,name,consent,tags\r\n+97450000001,"Sam, Jr",true,"team;vip"\r\n+97450000002,"Line\nTwo",false,',
  );
  assert.equal(rows[0].name, "Sam, Jr");
  assert.equal(rows[0].consent, true);
  assert.equal(rows[0].tags.join(","), "team,vip");
  assert.equal(rows[1].name, "Line\nTwo");
  assert.throws(() => csv("email,other\nx,y"));
  assert.throws(() => csv('phone,name\n123,"unclosed'));
});


test("Console navigation, grouped instance tabs and mobile chat back navigation work", async (t) => {
  const { d } = fixture(t);
  await wait(() => d.querySelector(".sidebar [data-view]"));
  assert(d.querySelector(".bottomnav [data-view]"));
  assert(d.querySelector(".sidebar .nav-item svg"));
  d.querySelector("[data-instance]").click();
  assert.equal(d.querySelectorAll(".gtab").length, 5);
  assert.equal(d.querySelectorAll(".ptab").length, 2);
  d.querySelector('[data-tab="inbox"]').click();
  await wait(() => d.querySelector("[data-chat]"));
  assert.equal(d.querySelectorAll(".ptab").length, 6);
  d.querySelector("[data-chat]").click();
  await wait(() => d.querySelector("#chatBack"));
  assert(d.querySelector(".inboxlayout").classList.contains("chat-open"));
  d.querySelector("#chatBack").click();
  assert(!d.querySelector(".inboxlayout").classList.contains("chat-open"));
  d.querySelector("#fullInbox").click();
  assert(d.querySelector(".inboxlayout").classList.contains("inbox-full"));
  d.querySelector("#fullInbox").click();
  assert(!d.querySelector(".inboxlayout").classList.contains("inbox-full"));
});

test("Chat shows rich data and securely fetches an inline media preview", async (t) => {
  const { d, calls } = fixture(t, { rich: true });
  await wait(() => d.querySelector("[data-instance]"));
  d.querySelector("[data-instance]").click();
  d.querySelector('[data-tab="inbox"]').click();
  await wait(() => d.querySelector("[data-chat]"));
  d.querySelector("[data-chat]").click();
  await wait(() => d.querySelector("[data-preview]"));
  assert.match(d.querySelector(".messages").textContent, /Photo caption/);
  assert.match(d.querySelector(".messages").textContent, /TEL:\+97450000001/);
  assert.match(d.querySelector(".messages").textContent, /Yes <script>/);
  assert(d.querySelector('a[href^="https://www.google.com/maps?q="]'));
  assert.equal(d.querySelectorAll("script").length, 0);
  assert(d.querySelector("#replyAttachment"));
  d.querySelector("[data-preview]").click();
  await wait(() => d.querySelector(".chat-media img"));
  assert.match(d.querySelector(".chat-media img").src, /^blob:/);
  assert(calls.some(call => call.url.endsWith("/inbox/image-id/media")));
});
