import {
  randomBytes,
  createHash,
  scryptSync,
  timingSafeEqual,
  createCipheriv,
  createDecipheriv,
} from "node:crypto";
export const token = () => randomBytes(32).toString("hex");
export const hash = (value) => createHash("sha256").update(value).digest("hex");
export function passwordHash(value) {
  const salt = token();
  return `${salt}:${scryptSync(value, salt, 64).toString("hex")}`;
}
export function passwordMatches(value, encoded) {
  try {
    const [salt, digest] = encoded.split(":");
    const expected = Buffer.from(digest, "hex");
    const actual = scryptSync(value, salt, 64);
    return (
      expected.length === actual.length && timingSafeEqual(expected, actual)
    );
  } catch {
    return false;
  }
}
export function cipher(base64) {
  const key = Buffer.from(base64 || "", "base64");
  if (key.length !== 32)
    throw Error("ENCRYPTION_KEY must be 32 bytes encoded as base64");
  return {
    seal(value) {
      const iv = randomBytes(12);
      const c = createCipheriv("aes-256-gcm", key, iv);
      const data = Buffer.concat([c.update(value, "utf8"), c.final()]);
      return Buffer.concat([iv, c.getAuthTag(), data]).toString("base64");
    },
    open(value) {
      const b = Buffer.from(value, "base64");
      const d = createDecipheriv("aes-256-gcm", key, b.subarray(0, 12));
      d.setAuthTag(b.subarray(12, 28));
      return Buffer.concat([d.update(b.subarray(28)), d.final()]).toString(
        "utf8",
      );
    },
  };
}
export function jid(value) {
  if (typeof value !== "string") throw Error("A recipient is required");
  if (/^\d{5,20}(-\d{5,20})?@g\.us$/.test(value)) return value;
  if (/^\d{7,15}@s\.whatsapp\.net$/.test(value)) return value;
  if (!/^\+?[1-9]\d{6,14}$/.test(value))
    throw Error("Use an international phone number or a group JID");
  return value.replace("+", "") + "@s.whatsapp.net";
}
