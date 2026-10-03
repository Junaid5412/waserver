import test from "node:test";
import assert from "node:assert/strict";
import { describeMessage } from "../src/inbox.js";

test("Inbox DTO preserves attachment captions, contact cards, locations, polls and quotes", () => {
  const image = describeMessage({ imageMessage: { caption: "Receipt", mimetype: "image/jpeg", contextInfo: { quotedMessage: { conversation: "Send receipt" } } } });
  assert.equal(image.text, "Receipt");
  assert.equal(image.hasMedia, true);
  assert.equal(image.quotedText, "Send receipt");
  const location = describeMessage({ locationMessage: { degreesLatitude: 25.2, degreesLongitude: 51.5, name: "Office", address: "Doha" } });
  assert.deepEqual(location.location, { latitude: 25.2, longitude: 51.5, name: "Office", address: "Doha" });
  const contact = describeMessage({ contactsArrayMessage: { contacts: [{ displayName: "Sam", vcard: "TEL:+97450000001" }] } });
  assert.deepEqual(contact.contacts, [{ name: "Sam", vcard: "TEL:+97450000001" }]);
  const poll = describeMessage({ pollCreationMessage: { name: "Available?", options: [{ optionName: "Yes" }, { optionName: "No" }] } });
  assert.deepEqual(poll.pollOptions, ["Yes", "No"]);
  const document = describeMessage({ documentMessage: { fileName: "invoice.pdf", mimetype: "application/pdf" } });
  assert.equal(document.filename, "invoice.pdf");
  assert.equal(document.hasMedia, true);
});
