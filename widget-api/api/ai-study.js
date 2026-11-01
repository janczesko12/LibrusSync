import { createHash, timingSafeEqual } from "node:crypto";
import { get } from "@vercel/blob";

function reply(res, status, data) {
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  res.setHeader("Cache-Control", "private, no-store, max-age=0");
  res.setHeader("X-Content-Type-Options", "nosniff");
  return res.status(status).json(data);
}
function hash(value) {
  return createHash("sha256").update(value, "utf8").digest("hex");
}
function matchesToken(value, expectedHash) {
  if (typeof value !== "string" || typeof expectedHash !== "string") return false;
  const a = Buffer.from(hash(value), "hex");
  const b = Buffer.from(expectedHash, "hex");
  return a.length === b.length && timingSafeEqual(a, b);
}
function bearer(req) {
  const header = req.headers?.authorization;
  const value = Array.isArray(header) ? header[0] : header;
  const match = typeof value === "string" ? value.match(/^Bearer ([A-Za-z0-9_-]{40,64})$/) : null;
  return match ? match[1] : null;
}
function parseBody(body) {
  if (body && typeof body === "object" && !Buffer.isBuffer(body)) return body;
  if (Buffer.isBuffer(body)) body = body.toString("utf8");
  if (typeof body === "string" && body.length <= 25000) {
    try { return JSON.parse(body); } catch { return null; }
  }
  return null;
}
async function verifyInstall(token) {
  const match = token.match(/^([0-9a-f-]{36})\|([A-Za-z0-9_-]{40,64})$/i);
  // The app sends its private per-install ID as a second header, never as a query parameter.
  return match;
}
export default async function handler(req, res) {
  if (req.method !== "POST") return reply(res, 405, { error: "Method not allowed" });
  const token = bearer(req);
  const installID = req.headers["x-librussync-install"];
  if (!token || typeof installID !== "string" ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(installID)) {
    return reply(res, 401, { error: "Missing install credentials" });
  }
  if (!process.env.BLOB_READ_WRITE_TOKEN || !process.env.CF_ACCOUNT_ID || !process.env.CF_API_TOKEN) {
    return reply(res, 503, { error: "AI service is not configured by the app administrator" });
  }

  const payload = parseBody(req.body);
  if (!payload || typeof payload.subject !== "string" || typeof payload.topic !== "string" ||
      typeof payload.assessmentDate !== "string" || typeof payload.materials !== "string" ||
      payload.subject.length > 80 || payload.topic.length < 2 || payload.topic.length > 500 ||
      payload.materials.length > 18000) {
    return reply(res, 400, { error: "Invalid study request" });
  }

  try {
    const blob = await get("librussync/" + installID + ".json", { access: "private" });
    if (!blob || blob.statusCode !== 200 || !blob.stream) {
      return reply(res, 403, { error: "Synchronize LibrusSync once before using AI Teacher" });
    }
    const record = JSON.parse(await new Response(blob.stream).text());
    if (!matchesToken(token, record.writeKeyHash)) {
      return reply(res, 403, { error: "Invalid install credentials" });
    }

    const system = [
      "Jesteś cierpliwym nauczycielem szkoły podstawowej. Odpowiadasz po polsku.",
      "Przygotuj praktyczny plan przygotowania do sprawdzianu na podstawie przedmiotu, tematu i materiałów ucznia.",
      "Nie twierdź, że znasz dokładny zakres nauczyciela, jeśli nie został podany. Wyraźnie oznacz zagadnienia, które są propozycją.",
      "Jeśli materiały są podane, traktuj je jako główne źródło i nie dopisuj sprzecznych faktów.",
      "Uwzględnij liczbę dni do daty sprawdzianu; jeśli termin jest bliski, ułóż krótszy plan.",
      "Zwróć Markdown: cel nauki, lista zagadnień, plan dzień po dniu (15-25 minut), krótkie wyjaśnienia, 8 pytań quizowych ABCD z kluczem i wyjaśnieniami na końcu, próbny test 10 pytań i kryteria samooceny.",
      "Nie pokazuj odpowiedzi bezpośrednio pod pytaniami quizu; umieść klucz w osobnej sekcji na końcu.",
      "Jeśli temat jest niejednoznaczny, wskaż to i poproś o zdjęcie lub doprecyzowanie."
    ].join("\n");

    const user = [
      "Przedmiot: " + payload.subject,
      "Temat: " + payload.topic,
      "Data sprawdzianu: " + payload.assessmentDate,
      "Materiały ucznia (OCR/notatki):",
      payload.materials || "(brak – oprzyj się na standardowej wiedzy szkolnej i zaznacz, że zakres jest orientacyjny)"
    ].join("\n\n");

    const url = "https://api.cloudflare.com/client/v4/accounts/" +
      encodeURIComponent(process.env.CF_ACCOUNT_ID) + "/ai/run/@cf/meta/llama-3.1-8b-instruct";
    const ai = await fetch(url, {
      method: "POST",
      headers: {
        "Authorization": "Bearer " + process.env.CF_API_TOKEN,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        messages: [{ role: "system", content: system }, { role: "user", content: user }],
        max_tokens: 2800,
        temperature: 0.35
      }),
      signal: AbortSignal.timeout(75000)
    });
    const result = await ai.json().catch(() => null);
    if (!ai.ok || !result?.success || typeof result?.result?.response !== "string") {
      console.error("Cloudflare AI request failed", ai.status);
      return reply(res, 502, { error: "Nie udało się wygenerować planu. Spróbuj ponownie później." });
    }
    return reply(res, 200, { plan: result.result.response });
  } catch (error) {
    console.error("AI study handler failed", error);
    return reply(res, 503, { error: "Usługa AI jest chwilowo niedostępna." });
  }
}
