import { readFile } from "node:fs/promises";
import { basename } from "node:path";
export class ZelonError extends Error {
  constructor(status, body) {
    super(body.error || `HTTP ${status}`);
    this.status = status;
    this.body = body;
  }
}
/** Node 22+ client. Keep URL, instance ID and key in environment variables. */
export class Zelon {
  constructor({ url, instanceId, apiKey, timeoutMs = 30000 }) {
    this.url =
      url.replace(/\/$/, "") +
      "/api/instances/" +
      encodeURIComponent(instanceId);
    this.apiKey = apiKey;
    this.timeoutMs = timeoutMs;
  }
  async request(path, { method = "GET", body, key, raw = false } = {}) {
    const r = await fetch(this.url + path, {
      method,
      headers: {
        Authorization: "Bearer " + this.apiKey,
        ...(body
          ? {
              "Content-Type": raw
                ? "application/octet-stream"
                : "application/json",
            }
          : {}),
        ...(key ? { "Idempotency-Key": key } : {}),
      },
      body: body ? (raw ? body : JSON.stringify(body)) : undefined,
      signal: AbortSignal.timeout(this.timeoutMs),
    });
    const data = await r.json();
    if (!r.ok) throw new ZelonError(r.status, data);
    return data;
  }
  send(message, { key = crypto.randomUUID() } = {}) {
    return this.request("/messages", { method: "POST", body: message, key });
  }
  getMessage(id) {
    return this.request("/messages/" + encodeURIComponent(id));
  }
  async upload(filePath, mimetype = "application/octet-stream") {
    const bytes = await readFile(filePath);
    return this.uploadBytes(bytes, basename(filePath), mimetype);
  }
  async uploadBytes(bytes, filename, mimetype = "application/octet-stream") {
    const m = await this.request("/media", {
      method: "POST",
      body: { filename, mimetype, size: bytes.length },
    });
    for (let i = 0; i < m.totalChunks; i++)
      await this.request(`/media/${m.id}/chunks/${i}`, {
        method: "PUT",
        raw: true,
        body: bytes.subarray(i * m.chunkSize, (i + 1) * m.chunkSize),
      });
    return this.request("/media/" + m.id + "/complete", {
      method: "POST",
      body: {},
    });
  }
}
