import { isIP } from "node:net";
import { ipKeyGenerator } from "express-rate-limit";

// LiteSpeed/Unix sockets can have no remote address. Keep such requests in a
// shared bucket instead of hashing undefined or trusting arbitrary headers.
export function requestKey(req) {
  return ipKeyGenerator(isIP(req.ip || "") ? req.ip : "127.0.0.1");
}
