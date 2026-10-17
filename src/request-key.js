import { createHash } from "node:crypto";
import { isIP } from "node:net";
import { ipKeyGenerator } from "express-rate-limit";

// LiteSpeed/Unix sockets can have no remote address. Keep such requests in a
// shared bucket instead of hashing undefined or trusting arbitrary headers.
export function requestKey(req) {
  return ipKeyGenerator(isIP(req.ip || "") ? req.ip : "127.0.0.1");
}

// Signed-in API clients get their own bucket per session/API token. Without
// this, every phone behind LiteSpeed (no remote address) shares the single
// 127.0.0.1 bucket and one busy client can rate-limit everybody.
export function apiRequestKey(req) {
  const token = String(req.headers?.authorization || "").match(
    /^Bearer ([a-f0-9]{64})$/,
  )?.[1];
  if (token)
    return "t:" + createHash("sha256").update(token).digest("hex").slice(0, 32);
  return requestKey(req);
}
