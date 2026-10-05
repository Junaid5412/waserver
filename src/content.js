import { z } from "zod";
import { Readable } from "node:stream";
import { jid } from "./security.js";
import { fail } from "./errors.js";
export const messageSchema = z.object({
  to: z.string(),
  type: z
    .enum([
      "text",
      "image",
      "video",
      "audio",
      "document",
      "sticker",
      "location",
      "contact",
      "poll",
      "forward",
    ])
    .default("text"),
  text: z.string().max(20000).optional(),
  data: z.string().max(750000).optional(),
  mediaId: z.string().uuid().optional(),
  mimetype: z.string().max(120).optional(),
  filename: z.string().max(200).optional(),
  ptt: z.boolean().optional(),
  latitude: z.number().min(-90).max(90).optional(),
  longitude: z.number().min(-180).max(180).optional(),
  name: z.string().max(100).optional(),
  address: z.string().max(300).optional(),
  phone: z
    .string()
    .regex(/^\+?[1-9]\d{6,14}$/)
    .optional(),
  options: z.array(z.string().min(1).max(100)).min(2).max(12).optional(),
  selectableCount: z.number().int().min(1).max(12).default(1),
  mentions: z.array(z.string()).max(100).optional(),
  quotedId: z.string().max(200).optional(),
  forwardId: z.string().max(200).optional(),
  sendAt: z.iso.datetime().optional(),
  statusAudience: z.array(z.string()).min(1).max(5000).optional(),
  backgroundColor: z
    .string()
    .regex(/^#[a-fA-F0-9]{6}$/)
    .optional(),
});
export async function validateMessage(
  instance,
  d,
  media,
  loadMessage,
  { status = false } = {},
) {
  d.to = status ? "status@broadcast" : jid(d.to);
  if (d.mentions) d.mentions = d.mentions.map(jid);
  if (d.statusAudience) d.statusAudience = d.statusAudience.map(jid);
  if (d.statusAudience?.some((v) => v.endsWith("@g.us")))
    fail(400, "Status audience must contain individual contacts");
  if (!status && d.statusAudience)
    fail(400, "Use the statuses endpoint to publish to a status audience");
  if (status && !["text", "image", "video", "audio"].includes(d.type))
    fail(400, "Statuses support text, image, video and audio");
  if (d.type === "text" && !d.text?.trim())
    fail(400, "Message text is required");
  if (["image", "video", "audio", "document", "sticker"].includes(d.type)) {
    if (d.mediaId) {
      const m = await media.owned(instance, d.mediaId);
      if (m.status !== "ready") fail(409, "Finalize the media upload first");
    } else if (
      !d.data ||
      !/^([A-Za-z0-9+/]{4})*([A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(
        d.data,
      )
    )
      fail(400, "Upload a media file or provide valid base64 data");
  }
  if (
    d.type === "location" &&
    (d.latitude === undefined || d.longitude === undefined)
  )
    fail(400, "Latitude and longitude are required");
  if (d.type === "contact" && (!d.name || !d.phone))
    fail(400, "Contact name and phone are required");
  if (
    d.type === "poll" &&
    (!d.text || !d.options || d.selectableCount > d.options.length)
  )
    fail(400, "Provide a poll question, options and a valid selectableCount");
  if (d.type === "forward" && !d.forwardId)
    fail(400, "A forwardId is required");
  for (const id of [d.quotedId, d.forwardId].filter(Boolean)) {
    const m = await loadMessage(instance.id, id);
    if (!m) fail(404, "Referenced message not found");
    if (id === d.quotedId && m.key?.remoteJid !== d.to)
      fail(400, "Quoted message must belong to the recipient chat");
  }
  return d;
}
export function buildContent(media, loadMessage) {
  return async (d, instance) => {
    const options = {};
    if (d.quotedId) options.quoted = await loadMessage(instance.id, d.quotedId);
    if (d.statusAudience) {
      options.broadcast = true;
      options.statusJidList = d.statusAudience;
      options.backgroundColor = d.backgroundColor || "#087e75";
      options.font = 1;
    }
    let content;
    if (d.type === "text") content = { text: d.text, mentions: d.mentions };
    else if (
      ["image", "video", "audio", "document", "sticker"].includes(d.type)
    ) {
      const stored = d.mediaId ? await media.owned(instance, d.mediaId) : null;
      content = {
        [d.type]: d.mediaId
          ? { stream: Readable.from(media.stream(instance, d.mediaId)) }
          : Buffer.from(d.data, "base64"),
        caption: d.text || "",
        mimetype:
          d.mimetype ||
          stored?.mimetype ||
          {
            image: "image/jpeg",
            video: "video/mp4",
            audio: "audio/mpeg",
            document: "application/octet-stream",
            sticker: "image/webp",
          }[d.type],
        fileName: d.filename || stored?.filename || "attachment",
        ...(d.type === "audio" ? { ptt: d.ptt || false } : {}),
        mentions: d.mentions,
      };
    } else if (d.type === "location")
      content = {
        location: {
          degreesLatitude: d.latitude,
          degreesLongitude: d.longitude,
          name: d.name,
          address: d.address,
        },
      };
    else if (d.type === "poll")
      content = {
        poll: {
          name: d.text,
          values: d.options,
          selectableCount: d.selectableCount || 1,
        },
      };
    else if (d.type === "forward")
      content = {
        forward: await loadMessage(instance.id, d.forwardId),
        force: true,
      };
    else {
      const name = d.name.replace(/[\r\n:;]/g, " ");
      content = {
        contacts: {
          displayName: name,
          contacts: [
            {
              vcard: `BEGIN:VCARD\nVERSION:3.0\nFN:${name}\nTEL;type=CELL;waid=${d.phone.replace("+", "")}:${d.phone}\nEND:VCARD`,
            },
          ],
        },
      };
    }
    return { content, options };
  };
}
