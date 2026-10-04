import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import vm from "node:vm";
import { JSDOM } from "jsdom";
const script = await readFile(
  new URL("../public/app.js", import.meta.url),
  "utf8",
);
const wait = async (fn) => {
  for (let i = 0; i < 60; i++) {
    if (fn()) return;
    await new Promise((r) => setTimeout(r, 5));
  }
  assert.fail("Interface did not reach expected state");
};
function setup(role = "admin") {
  const requests = [];
  const instance = {
    id: "instance-one",
    name: "<script>alert(1)</script>",
    status: "disconnected",
    createdAt: "2026-10-01T00:00:00Z",
  };
  const dom = new JSDOM('<div id="root"></div><div id="toast"></div>', {
    url: "https://zelon.example/console",
    runScripts: "outside-only",
  });
  dom.window.fetch = async (url, options = {}) => {
    const body = options.body ? JSON.parse(options.body) : undefined;
    requests.push({ url, method: options.method || "GET", body });
    let data = { ok: true };
    if (url === "/api/me")
      data = { id: "owner", email: "owner@example.com", role };
    else if (url === "/api/instances" && options.method === "GET")
      data = [instance];
    else if (url === "/api/admin/users" && options.method === "GET")
      data = [{ id: "owner", email: "owner@example.com", role: "admin" }];
    else if (url === "/api/admin/users" && options.method === "POST")
      data = {
        id: "member",
        email: body.email,
        password: "test-generated-password",
      };
    else if (url.includes("/messages?"))
      data = [
        {
          id: "message-one",
          createdAt: "2026-10-01T00:00:00Z",
          status: "queued",
          to: "97450000000",
          text: "<img src=x onerror=alert(1)>",
        },
      ];
    else if (url.endsWith("/qr")) data = { qr: null, status: "disconnected" };
    return new Response(JSON.stringify(data), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  };
  vm.runInContext(script, dom.getInternalVMContext());
  return { dom, requests, document: dom.window.document };
}
test("Console escapes user content and keeps sign-out reachable on desktop and mobile", async () => {
  const { dom, document } = setup();
  try {
    await wait(() => document.querySelector("[data-instance]"));
    assert.equal(document.querySelectorAll("script").length, 0);
    assert(
      document.querySelector(".inst-list").textContent.includes("<script>"),
    );
    assert(document.querySelector("#logout"));
    assert(document.querySelector("#logout2"));
    assert(document.querySelector(".bottomnav [data-view]"));
    document.querySelector('[data-view="account"]').click();
    assert(document.querySelector("#passwordForm"));
  } finally {
    dom.window.close();
  }
});
test("Administrator + popup creates an account and displays credentials once", async () => {
  const { dom, document, requests } = setup();
  try {
    await wait(() => document.querySelector('[data-view="users"]'));
    document.querySelector('[data-view="users"]').click();
    await wait(() => document.querySelector("#addUser"));
    document.querySelector("#addUser").click();
    assert(document.querySelector('[role="dialog"]'));
    document.querySelector("#userEmail").value = "member@example.com";
    document
      .querySelector("#addUserForm")
      .dispatchEvent(
        new dom.window.Event("submit", { bubbles: true, cancelable: true }),
      );
    await wait(() => document.querySelector("#doneUser"));
    assert(
      document
        .querySelector(".modal")
        .textContent.includes("test-generated-password"),
    );
    assert(
      requests.some(
        (r) =>
          r.url === "/api/admin/users" &&
          r.method === "POST" &&
          r.body.email === "member@example.com",
      ),
    );
    document.querySelector("#doneUser").click();
    assert(!document.querySelector(".modal"));
  } finally {
    dom.window.close();
  }
});
test("Regular user has no administrator controls", async () => {
  const { dom, document } = setup("user");
  try {
    await wait(() => document.querySelector("[data-instance]"));
    assert.equal(document.querySelector('[data-view="users"]'), null);
  } finally {
    dom.window.close();
  }
});
test("Queued message cancellation uses the selected instance and safely renders text", async () => {
  const { dom, document, requests } = setup();
  try {
    await wait(() => document.querySelector("[data-instance]"));
    document.querySelector("[data-instance]").click();
    document.querySelector('[data-tab="inbox"]').click();
    await wait(() => document.querySelector('[data-tab="history"]'));
    document.querySelector('[data-tab="history"]').click();
    await wait(() => document.querySelector("[data-cancel]"));
    assert.equal(document.querySelector("#panel img"), null);
    document.querySelector("[data-cancel]").click();
    await wait(() =>
      requests.some(
        (r) =>
          r.url === "/api/instances/instance-one/messages/message-one/cancel",
      ),
    );
    assert(
      requests.some(
        (r) =>
          r.url === "/api/instances/instance-one/messages/message-one/cancel" &&
          r.method === "POST",
      ),
    );
  } finally {
    dom.window.close();
  }
});
