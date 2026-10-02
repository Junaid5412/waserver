import test from "node:test";
import assert from "node:assert/strict";
import http from "node:http";
import { Zelon, ZelonError } from "../sdk/zelon.mjs";
test("Node SDK sends authenticated idempotent messages, uploads exact chunks and exposes API errors", async (t) => {
  const requests = [];
  const server = http.createServer(async (req, res) => {
    const bytes = [];
    for await (const b of req) bytes.push(b);
    const data = Buffer.concat(bytes);
    requests.push({ url: req.url, headers: req.headers, data });
    res.setHeader("Content-Type", "application/json");
    if (req.url.endsWith("/fail")) {
      res.statusCode = 409;
      res.end(JSON.stringify({ error: "Conflict" }));
    } else if (req.url.endsWith("/media"))
      res.end(JSON.stringify({ id: "upload", chunkSize: 4, totalChunks: 2 }));
    else res.end(JSON.stringify({ id: "job", status: "queued" }));
  });
  server.listen(0, "127.0.0.1");
  await new Promise((r) => server.once("listening", r));
  t.after(() => new Promise((r) => server.close(r)));
  const c = new Zelon({
    url: "http://127.0.0.1:" + server.address().port,
    instanceId: "a",
    apiKey: "secret",
  });
  await c.send({ to: "+97450000001", text: "Hello" }, { key: "same-request" });
  assert.equal(requests[0].headers.authorization, "Bearer secret");
  assert.equal(requests[0].headers["idempotency-key"], "same-request");
  await c.uploadBytes(Buffer.from("abcdefgh"), "test.bin");
  assert.equal(requests[2].data.toString(), "abcd");
  assert.equal(requests[3].data.toString(), "efgh");
  assert.equal(requests[2].headers["content-type"], "application/octet-stream");
  await assert.rejects(
    c.request("/fail"),
    (e) => e instanceof ZelonError && e.status === 409,
  );
});
