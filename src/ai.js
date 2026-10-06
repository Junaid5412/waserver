export const SUPPORTED_GEMINI_MODELS = [
  "gemini-3.8-flash",
  "gemini-3.6-flash",
  "gemini-3.1-pro",
  "gemini-2.5-pro",
  "gemini-2.5-flash",
  "gemini-2.5-flash-lite",
  "gemini-2.0-flash",
  "gemini-2.0-flash-lite",
  "gemini-1.5-pro",
  "gemini-1.5-flash",
];

/**
 * Gemini AI Engine with Automatic Multi-Key Rotation and Multi-Model Failover
 */
export async function callGeminiWithFailover(keys, preferredModel, prompt, systemInstruction = null) {
  if (!keys || !keys.length) {
    throw new Error("No Gemini API keys configured. Please add an API key in Admin Control Center.");
  }

  // Model fallback chain: preferred -> 2.5-flash -> 2.0-flash -> 1.5-flash
  const modelsToTry = [
    preferredModel,
    "gemini-2.5-flash",
    "gemini-2.0-flash",
    "gemini-1.5-flash",
  ].filter((m, idx, arr) => m && arr.indexOf(m) === idx);

  let lastError = null;

  for (let k = 0; k < keys.length; k++) {
    const apiKey = keys[k]?.trim();
    if (!apiKey) continue;

    for (let m = 0; m < modelsToTry.length; m++) {
      const targetModel = modelsToTry[m];

      try {
        const url = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(
          targetModel
        )}:generateContent?key=${encodeURIComponent(apiKey)}`;

        const payload = {
          contents: [
            {
              role: "user",
              parts: [{ text: prompt }],
            },
          ],
          generationConfig: {
            temperature: 0.7,
            maxOutputTokens: 600,
          },
        };

        if (systemInstruction) {
          payload.systemInstruction = {
            parts: [{ text: systemInstruction }],
          };
        }

        const res = await fetch(url, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(payload),
          signal: AbortSignal.timeout(15000),
        });

        const data = await res.json().catch(() => null);

        if (!res.ok || data?.error) {
          const status = res.status;
          const errorMsg = data?.error?.message || `HTTP ${status}`;

          // If model not found (404), try next model on the same key
          if (status === 404 || errorMsg.toLowerCase().includes("not found")) {
            console.warn(`[Gemini] Model ${targetModel} not available on key #${k + 1}. Trying fallback model...`);
            lastError = new Error(`Model ${targetModel}: ${errorMsg}`);
            continue;
          }

          // If rate limited or quota exceeded (429) or invalid auth (400/403), switch key
          console.warn(`[Gemini Failover] Key #${k + 1} failed: ${errorMsg}. Rotating to next key...`);
          lastError = new Error(`Key #${k + 1} (${apiKey.slice(0, 6)}...): ${errorMsg}`);
          break; // break inner model loop and try next key
        }

        const text = data?.candidates?.[0]?.content?.parts?.[0]?.text;
        if (text) {
          return {
            text: text.trim(),
            model: targetModel,
            keyIndexUsed: k,
            totalKeys: keys.length,
          };
        } else {
          lastError = new Error("Empty response parts from Gemini API");
        }
      } catch (err) {
        console.warn(`[Gemini Failover] Network/Timeout error on key #${k + 1} with model ${targetModel}: ${err.message}`);
        lastError = err;
      }
    }
  }

  throw new Error(`All ${keys.length} Gemini API keys failed. Last error: ${lastError?.message || "Unknown error"}`);
}

/**
 * Intelligent Smart Reply Generator based on WhatsApp chat history
 */
export async function generateSmartReplies(keys, model, chatContext) {
  const { contactName, messages, userPrompt } = chatContext;

  // Build conversational transcript from recent messages
  const transcriptLines = (messages || []).map((m) => {
    const sender = m.fromMe ? "Me" : (contactName || "Contact");
    const content = m.text || (m.type === "image" ? "[Image]" : m.type === "audio" ? "[Voice note]" : `[${m.type}]`);
    return `${sender}: ${content}`;
  });

  const transcript = transcriptLines.slice(-20).join("\n");

  const systemInstruction = `You are an intelligent WhatsApp AI assistant. You read previous messages in a conversation and generate smart, natural, highly contextual suggested replies for the user to respond with. 
Your suggestions should match the tone and language of the conversation (English, Urdu/Hindi, Roman Urdu, Arabic, etc.).
Keep suggestions concise, polite, and ready-to-send without quotation marks.`;

  let prompt = `Here is the recent conversation transcript:\n${transcript}\n\n`;

  if (userPrompt && userPrompt.trim().length > 0) {
    prompt += `The user specifically wants to reply with this intent/instruction: "${userPrompt.trim()}".\n`;
    prompt += `Provide 3 variations of suitable replies matching this intent based on the conversation history. Format as JSON array of 3 strings: ["reply 1", "reply 2", "reply 3"]. Return ONLY raw valid JSON array.`;
  } else {
    prompt += `Based on the latest messages above, analyze what the other person is asking or saying, and generate 3 smart reply suggestions for 'Me'.
Format as a raw JSON array of 3 strings: ["reply 1", "reply 2", "reply 3"]. Return ONLY valid JSON array with no extra markdown code fences.`;
  }

  const result = await callGeminiWithFailover(keys, model, prompt, systemInstruction);

  let suggestions = [];
  try {
    let cleanJson = result.text.trim();
    if (cleanJson.startsWith("```json")) {
      cleanJson = cleanJson.replace(/^```json\s*/, "").replace(/\s*```$/, "");
    } else if (cleanJson.startsWith("```")) {
      cleanJson = cleanJson.replace(/^```\s*/, "").replace(/\s*```$/, "");
    }
    const parsed = JSON.parse(cleanJson);
    if (Array.isArray(parsed)) {
      suggestions = parsed.map((s) => String(s).trim()).filter(Boolean);
    }
  } catch (_) {
    // Fallback: split by newlines if JSON parsing fails
    suggestions = result.text
      .split("\n")
      .map((line) => line.replace(/^[\d\.\-\*]\s*/, "").trim())
      .filter((line) => line.length > 0 && !line.startsWith("{") && !line.startsWith("["));
  }

  if (!suggestions.length) {
    suggestions = [result.text];
  }

  return {
    suggestions: suggestions.slice(0, 3),
    rawText: result.text,
    model: result.model,
    keyIndexUsed: result.keyIndexUsed,
  };
}
