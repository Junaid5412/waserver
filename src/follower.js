import { createServer, request } from "node:http";
import path from "node:path";
import { readFileSync } from "node:fs";
import { storageConfig } from "./storage-config.js";

export function workerEndpoint() {
  const { driver, directory } = storageConfig();
  if (driver !== "sqlite" || !directory)
    throw Error("Shared SQLite startup requires a private DATA_DIR");
  return path.join(directory, "worker.json");
}

export async function startFollower() {
  const endpointFile = workerEndpoint();
  function endpoint() {
    const { port, secret } = JSON.parse(readFileSync(endpointFile, "utf8"));
    if (!Number.isInteger(port) || port < 1 || port > 65535 || typeof secret !== "string")
      throw Error("Invalid shared worker endpoint");
    return { hostname: "127.0.0.1", port, headers: { "x-zelon-worker-token": secret } };
  }
  let unavailableSince;
  let lastDiagnostic = 0;
  function report(error, target) {
    if (Date.now() - lastDiagnostic < 10000) return;
    lastDiagnostic = Date.now();
    // Never log request headers, cookies or the private endpoint credential.
    console.error("Zelon worker connection failed:", JSON.stringify({
      process: process.pid, code: error.code || "ENDPOINT_ERROR",
      syscall: error.syscall, address: target?.hostname, port: target?.port,
    }));
  }
  const server = createServer((incoming, outgoing) => {
    const headers = { ...incoming.headers };
    if (!headers["x-forwarded-for"])
      headers["x-forwarded-for"] = incoming.socket.remoteAddress;
    let target;
    try { target = endpoint(); } catch (error) {
      report(error);
      unavailableSince ??= Date.now();
      outgoing.writeHead(503, { "Retry-After": "5" });
      outgoing.end("Application worker initializing; retry shortly");
      incoming.resume();
      return;
    }
    const upstream = request({ ...target, path: incoming.url,
      method: incoming.method, headers: { ...headers, ...target.headers } }, (response) => {
      if (response.statusCode < 500) unavailableSince = undefined;
      else unavailableSince ??= Date.now();
      outgoing.writeHead(response.statusCode, response.headers);
      response.pipe(outgoing);
      response.on("error", () => outgoing.destroy());
    });
    upstream.setTimeout(120000, () => upstream.destroy());
    upstream.on("error", (error) => {
      report(error, target);
      unavailableSince ??= Date.now();
      if (!outgoing.headersSent) {
        outgoing.writeHead(503, { "Content-Type": "application/json", "Retry-After": "5" });
        outgoing.end(JSON.stringify({ error: "Application worker restarting; retry shortly" }));
      } else outgoing.destroy();
    });
    incoming.on("aborted", () => upstream.destroy());
    outgoing.on("close", () => upstream.destroy());
    incoming.pipe(upstream);
  });
  // A crashed leader loses its heartbeat lease after 30 seconds. Exit only
  // after a sustained outage so LiteSpeed restarts a contender for that lease.
  const monitor = setInterval(() => {
    let target;
    try { target = endpoint(); } catch (error) {
      report(error); unavailableSince ??= Date.now(); }
    const probe = target && request({ ...target, path: "/health", timeout: 3000 }, (res) => {
      res.resume();
      if (res.statusCode === 200) unavailableSince = undefined;
      else { report({ code: "HEALTH_HTTP_" + res.statusCode }, target); unavailableSince ??= Date.now(); }
    });
    probe?.on("timeout", () => probe.destroy());
    probe?.on("error", (error) => { report(error, target); unavailableSince ??= Date.now(); });
    probe?.end();
    if (unavailableSince && Date.now() - unavailableSince > 35000) {
      console.error("Zelon shared worker unavailable; restarting follower");
      process.exit(1);
    }
  }, 5000);
  monitor.unref();
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(Number(process.env.PORT || 3000), "0.0.0.0", resolve);
  });
  console.log("Zelon API listening (shared SQLite worker)");
  const stop = () => {
    clearInterval(monitor);
    setTimeout(() => process.exit(1), 15000).unref();
    server.close(() => process.exit(0));
  };
  process.once("SIGTERM", stop);
  process.once("SIGINT", stop);
}
