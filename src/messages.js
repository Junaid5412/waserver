import { randomUUID } from "node:crypto";
import { hash } from "./security.js";
const fail = (status, message) => {
  throw Object.assign(Error(message), { status });
};
export async function enqueueMessage(
  store,
  enc,
  instance,
  data,
  requestKey,
  ensureConnected,
) {
  if (
    requestKey &&
    (typeof requestKey !== "string" ||
      requestKey.length < 8 ||
      requestKey.length > 200)
  )
    fail(400, "Idempotency-Key must be 8 to 200 characters");
  const id = requestKey
    ? "idem_" + hash(instance.id + ":" + requestKey)
    : randomUUID();
  const fingerprint = hash(JSON.stringify(data));
  const replay = (previous) => {
    if (previous.fingerprint !== fingerprint)
      fail(409, "Idempotency key was used for different message content");
    return { httpStatus: 200, id, status: previous.status };
  };
  const previous = await store.get("messages", id);
  if (previous) return replay(previous);
  ensureConnected();
  const sendAt = data.sendAt ? Date.parse(data.sendAt) : Date.now();
  if (sendAt < Date.now() - 60000) fail(400, "Scheduled time is in the past");
  const row = {
    id,
    fingerprint,
    instanceId: instance.id,
    userId: instance.userId,
    status: "queued",
    to: data.to,
    type: data.type,
    payload: enc.seal(JSON.stringify(data)),
    sendAt,
    createdAt: new Date().toISOString(),
  };
  if (!(await store.insert("messages", id, row)))
    return replay(await store.get("messages", id));
  return { httpStatus: 202, id, status: "queued" };
}
