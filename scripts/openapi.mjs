import { readFile, writeFile } from "node:fs/promises";
import { z } from "zod";
import { messageSchema } from "../src/content.js";
const spec = {
  openapi: "3.1.0",
  info: {
    title: "Zelon API",
    version: "0.3.0",
    description:
      "Self-hosted WhatsApp Web integration. Keys are scoped to one instance. Dashboard-only operations require a session and matching Origin. WhatsApp provider rules apply.",
  },
  servers: [{ url: "/" }],
  components: {
    securitySchemes: {
      instanceKey: { type: "http", scheme: "bearer" },
      consoleSession: { type: "apiKey", in: "cookie", name: "zelon_session" },
    },
    schemas: { Message: z.toJSONSchema(messageSchema) },
  },
  paths: {},
};
const schemas = {
  "/messages": { $ref: "#/components/schemas/Message" },
  "/statuses": z.toJSONSchema(
    messageSchema
      .omit({ to: true })
      .extend({ statusAudience: z.array(z.string()).min(1) }),
  ),
  "/media": {
    type: "object",
    required: ["filename", "size"],
    properties: {
      filename: { type: "string" },
      size: { type: "integer", minimum: 1, maximum: 104857600 },
      mimetype: { type: "string", default: "application/octet-stream" },
    },
  },
  "/contacts": {
    type: "object",
    required: ["phone", "name"],
    properties: {
      phone: { type: "string" },
      name: { type: "string" },
      consent: { type: "boolean" },
      optedOut: { type: "boolean" },
      tags: { type: "array", items: { type: "string" } },
    },
  },
  "/campaigns": {
    type: "object",
    required: ["name", "recipients", "message", "consentConfirmed"],
    properties: {
      name: { type: "string" },
      recipients: {
        type: "array",
        maxItems: 1000,
        items: {
          oneOf: [
            { type: "string" },
            {
              type: "object",
              required: ["to"],
              properties: { to: { type: "string" }, name: { type: "string" } },
            },
          ],
        },
      },
      message: {
        type: "object",
        description:
          "Message fields except to; personalized per recipient. See Message schema.",
      },
      intervalSeconds: {
        type: "number",
        minimum: 1,
        maximum: 3600,
        default: 5,
      },
      startAt: { type: "string", format: "date-time" },
      consentConfirmed: { const: true },
    },
  },
  "/rules": {
    type: "object",
    required: ["name", "match", "reply"],
    properties: {
      name: { type: "string" },
      match: { enum: ["any", "exact", "contains"] },
      keyword: { type: "string" },
      reply: { type: "string" },
      cooldownSeconds: { type: "integer", default: 60 },
      enabled: { type: "boolean", default: true },
      stopAfterMatch: { type: "boolean", default: true },
    },
  },
  "/templates": {
    type: "object",
    required: ["name", "text"],
    properties: { name: { type: "string" }, text: { type: "string" } },
  },
  "/settings": {
    type: "object",
    properties: {
      sendIntervalMs: { type: "integer", minimum: 0, maximum: 60000 },
      webhookEvents: {
        type: "array",
        items: {
          enum: [
            "message",
            "receipt",
            "connection",
            "group",
            "group-participants",
            "presence",
            "call",
            "history",
            "error",
          ],
        },
      },
    },
  },
  "/login": {
    type: "object",
    required: ["email", "password"],
    properties: {
      email: { type: "string", format: "email" },
      password: { type: "string" },
    },
  },
};
for (const [file, prefix] of [
  ["src/server.js", ""],
  ["src/features.js", "/api/instances/:id"],
]) {
  const source = await readFile(file, "utf8"),
    regex = /(?:app|router)\.(get|post|put|delete)\(\s*["']([^"']+)["']/g;
  for (const [, method, route] of source.matchAll(regex)) {
    if (!route.startsWith("/api") && !prefix) continue;
    const raw = prefix + route,
      path = raw.replace(/:([\w]+)/g, "{$1}"),
      parameters = [...raw.matchAll(/:([\w]+)/g)].map((m) => ({
        name: m[1],
        in: "path",
        required: true,
        schema: { type: "string" },
      }));
    const isConsole =
      /(login|logout|\/me$|\/account|\/admin|archived-instances|\/restore|\/name$|\/key$|\/qr$|\/connect$|\/disconnect$|\/archive$|\/restart$|\/pairing-code$|\/webhook(?:\/rotate)?$|\/webhooks$)/.test(
        raw,
      ) || raw === "/api/instances";
    const operation = {
      operationId: method + "_" + raw.replace(/[^a-zA-Z0-9]/g, "_"),
      summary: method.toUpperCase() + " " + raw,
      security:
        raw === "/api/login"
          ? []
          : isConsole
            ? [{ consoleSession: [] }]
            : [{ instanceKey: [] }, { consoleSession: [] }],
      parameters,
      responses: {
        200: { description: "Success" },
        400: { description: "Validation failed" },
        401: { description: "Invalid credentials" },
        403: { description: "Operation requires dashboard/admin privileges" },
        404: { description: "Record not found or outside your instance" },
        409: { description: "Connection/state/idempotency conflict" },
        429: { description: "Rate limited" },
      },
    };
    if (
      method === "get" &&
      /messages$|events$|chats$|contacts$|campaigns$|rules$|templates$|statuses$|webhooks$|media$/.test(
        raw,
      )
    )
      operation.parameters.push(
        ...[
          {
            name: "limit",
            in: "query",
            schema: { type: "integer", minimum: 1, maximum: 100, default: 100 },
          },
          {
            name: "before",
            in: "query",
            schema: { type: "string", format: "date-time" },
          },
          { name: "beforeId", in: "query", schema: { type: "string" } },
        ],
      );
    if (
      method === "post" &&
      ["/messages", "/statuses", "/campaigns"].includes(route)
    )
      operation.parameters.push({
        name: "Idempotency-Key",
        in: "header",
        schema: { type: "string", minLength: 8, maxLength: 200 },
        description:
          "Reuse the same key and payload when retrying. Different payload returns 409.",
      });
    if (["post", "put"].includes(method)) {
      const suffix = prefix ? route : raw.replace("/api", "");
      operation.requestBody = {
        required: true,
        content: {
          "application/json": { schema: schemas[suffix] || { type: "object" } },
        },
      };
    }
    if (raw.includes("/chunks/"))
      operation.requestBody = {
        required: true,
        content: {
          "application/octet-stream": {
            schema: { type: "string", format: "binary" },
          },
        },
      };
    if (raw.endsWith("/download") || raw.endsWith("/inbox/:message/media"))
      operation.responses[200] = {
        description: "Media stream",
        content: {
          "application/octet-stream": {
            schema: { type: "string", format: "binary" },
          },
        },
      };
    if (method === "post" && raw.endsWith("/messages"))
      operation.responses[202] = {
        description: "Queued; does not mean delivered",
      };
    spec.paths[path] ??= {};
    spec.paths[path][method] = operation;
  }
}
await writeFile("public/openapi.json", JSON.stringify(spec, null, 2) + "\n");
console.log(Object.keys(spec.paths).length + " API paths documented");
