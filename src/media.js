import { randomUUID, createHash } from "node:crypto";
import { z } from "zod";
import { fail } from "./errors.js";
export const CHUNK_SIZE = 512 * 1024;
const configuredMax = Number(process.env.MAX_MEDIA_MB || 100);
if (
  !Number.isInteger(configuredMax) ||
  configuredMax < 1 ||
  configuredMax > 256
)
  throw Error("MAX_MEDIA_MB must be an integer from 1 to 256");
export const MAX_MEDIA_BYTES = configuredMax * 1024 * 1024;
const schema = z.object({
  filename: z.string().min(1).max(200),
  mimetype: z
    .string()
    .max(120)
    .regex(/^[\w.+-]+\/[\w.+-]+$/)
    .default("application/octet-stream"),
  size: z.number().int().min(1).max(MAX_MEDIA_BYTES),
});
export function createMediaStore(store, enc) {
  const owned = async (instance, id) => {
    const m = await store.get("media", id);
    if (
      !m ||
      m.instanceId !== instance.id ||
      m.userId !== instance.userId ||
      m.status === "archived"
    )
      fail(404, "Media not found");
    return m;
  };
  async function create(instance, input) {
    const d = schema.parse(input),
      id = randomUUID();
    const row = {
      ...d,
      id,
      instanceId: instance.id,
      userId: instance.userId,
      status: "uploading",
      chunkSize: CHUNK_SIZE,
      totalChunks: Math.ceil(d.size / CHUNK_SIZE),
      createdAt: new Date().toISOString(),
    };
    await store.set("media", id, row);
    return row;
  }
  async function chunk(instance, id, index, bytes) {
    const m = await owned(instance, id);
    if (m.status !== "uploading") fail(409, "Upload is already finalized");
    if (!Number.isInteger(index) || index < 0 || index >= m.totalChunks)
      fail(400, "Invalid chunk index");
    const expected = Math.min(CHUNK_SIZE, m.size - index * CHUNK_SIZE);
    if (!Buffer.isBuffer(bytes) || bytes.length !== expected)
      fail(400, `Chunk must contain ${expected} bytes`);
    const key = String(index).padStart(8, "0"),
      digest = createHash("sha256").update(bytes).digest("hex");
    const previous = await store.get("media-chunks:" + id, key);
    if (previous) {
      if (previous.digest !== digest)
        fail(409, "This chunk index already contains different data");
      return { ok: true };
    }
    if (
      !(await store.insert("media-chunks:" + id, key, {
        id: key,
        digest,
        data: enc.seal(bytes.toString("base64")),
      }))
    ) {
      const saved = await store.get("media-chunks:" + id, key);
      if (saved.digest !== digest)
        fail(409, "This chunk index already contains different data");
    }
    return { ok: true };
  }
  async function complete(instance, id) {
    const m = await owned(instance, id);
    if (m.status === "ready") return m;
    const digest = createHash("sha256");
    for (let i = 0; i < m.totalChunks; i++) {
      const c = await store.get(
        "media-chunks:" + id,
        String(i).padStart(8, "0"),
      );
      if (!c) fail(409, `Missing upload chunk ${i}`);
      digest.update(Buffer.from(enc.open(c.data), "base64"));
    }
    return store.patch("media", id, {
      status: "ready",
      digest: digest.digest("hex"),
    });
  }
  async function* stream(instance, id) {
    const m = await owned(instance, id);
    if (m.status !== "ready") fail(409, "Upload has not been finalized");
    for (let i = 0; i < m.totalChunks; i++) {
      const c = await store.get(
        "media-chunks:" + id,
        String(i).padStart(8, "0"),
      );
      if (!c) fail(500, "Media storage is incomplete");
      yield Buffer.from(enc.open(c.data), "base64");
    }
  }
  async function buffer(instance, id) {
    const m = await owned(instance, id),
      chunks = [];
    if (m.status !== "ready") fail(409, "Upload has not been finalized");
    for await (const c of stream(instance, id)) chunks.push(c);
    return Buffer.concat(chunks, m.size);
  }
  return { create, chunk, complete, stream, buffer, owned };
}
