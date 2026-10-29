import { createHash, timingSafeEqual } from "node:crypto";
import { get, put } from "@vercel/blob";

function reply(response, status, data) {
  response.setHeader("Content-Type", "application/json; charset=utf-8");
  response.setHeader("Cache-Control", "private, no-store, max-age=0");
  response.setHeader("X-Content-Type-Options", "nosniff");
  return response.status(status).json(data);
}
function tokenHash(value) {
  return createHash("sha256").update(value, "utf8").digest("hex");
}
function matchesToken(value, expectedHash) {
  if (typeof value !== "string" || typeof expectedHash !== "string") return false;
  const actual = Buffer.from(tokenHash(value), "hex");
  const expected = Buffer.from(expectedHash, "hex");
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}
function validID(value) {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}
function validToken(value) {
  return typeof value === "string" && /^[A-Za-z0-9_-]{40,64}$/.test(value);
}
function bearer(request) {
  const header = request.headers?.authorization;
  const value = Array.isArray(header) ? header[0] : header;
  const match = typeof value === "string" ? value.match(/^Bearer ([A-Za-z0-9_-]{40,64})$/) : null;
  return match ? match[1] : null;
}
function normalizeEvents(value) {
  if (!Array.isArray(value) || value.length > 30) return null;
  const result = [];
  for (const event of value) {
    if (!event || typeof event !== "object" ||
        typeof event.uid !== "string" || event.uid.length > 500 ||
        typeof event.title !== "string" || event.title.length > 300 ||
        typeof event.startDate !== "number" || !Number.isFinite(event.startDate) ||
        typeof event.endDate !== "number" || !Number.isFinite(event.endDate) ||
        typeof event.notes !== "string" || event.notes.length > 3000 ||
        typeof event.isAllDay !== "boolean") return null;
    result.push({
      uid: event.uid,
      title: event.title,
      startDate: event.startDate,
      endDate: event.endDate,
      notes: event.notes,
      isAllDay: event.isAllDay
    });
  }
  return result;
}
async function readRecord(pathname) {
  const blob = await get(pathname, { access: "private" });
  if (!blob || blob.statusCode !== 200 || !blob.stream) return null;
  const raw = await new Response(blob.stream).text();
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}
function parseBody(body) {
  if (body && typeof body === "object" && !Buffer.isBuffer(body)) return body;
  if (Buffer.isBuffer(body)) body = body.toString("utf8");
  if (typeof body === "string" && body.length <= 100000) {
    try { return JSON.parse(body); } catch { return null; }
  }
  return null;
}

export default async function handler(request, response) {
  if (request.method !== "GET" && request.method !== "POST") {
    return reply(response, 405, { error: "Method not allowed" });
  }
  if (!process.env.BLOB_READ_WRITE_TOKEN) {
    return reply(response, 503, { error: "Private storage is not configured" });
  }
  const authToken = bearer(request);
  if (!authToken) return reply(response, 401, { error: "Missing or invalid bearer token" });

  if (request.method === "GET") {
    const url = new URL(request.url || "/", "https://librussync-widget-api.vercel.app");
    const id = url.searchParams.get("id");
    if (!validID(id)) return reply(response, 400, { error: "Invalid widget ID" });
    try {
      const record = await readRecord("librussync/" + id + ".json");
      if (!record) return reply(response, 404, { error: "Widget not registered yet" });
      if (!matchesToken(authToken, record.readKeyHash)) {
        return reply(response, 403, { error: "Invalid read token" });
      }
      return reply(response, 200, {
        events: normalizeEvents(record.events) || [],
        updatedAt: record.updatedAt || null
      });
    } catch (error) {
      console.error("Widget feed read failed", error);
      return reply(response, 503, { error: "Could not read private widget data" });
    }
  }

  const payload = parseBody(request.body);
  if (!payload) return reply(response, 400, { error: "Invalid JSON payload" });
  let payloadSize;
  try { payloadSize = JSON.stringify(payload).length; } catch { payloadSize = 100001; }
  if (payloadSize > 100000) return reply(response, 413, { error: "Payload too large" });

  const id = payload.id;
  const readToken = payload.readToken;
  const events = payload.events;
  if (!validID(id) || !validToken(readToken)) {
    return reply(response, 400, { error: "Invalid widget credentials" });
  }
  const safeEvents = normalizeEvents(events);
  if (!safeEvents) return reply(response, 400, { error: "Invalid events payload" });

  const pathname = "librussync/" + id + ".json";
  try {
    const existing = await readRecord(pathname);
    if (existing &&
        (!matchesToken(authToken, existing.writeKeyHash) ||
         !matchesToken(readToken, existing.readKeyHash))) {
      return reply(response, 403, { error: "Widget credentials do not match" });
    }
    const record = {
      readKeyHash: existing?.readKeyHash || tokenHash(readToken),
      writeKeyHash: existing?.writeKeyHash || tokenHash(authToken),
      events: safeEvents,
      updatedAt: new Date().toISOString()
    };
    await put(pathname, JSON.stringify(record), {
      access: "private",
      contentType: "application/json",
      cacheControlMaxAge: 60,
      allowOverwrite: true
    });
    return reply(response, 200, { ok: true, count: safeEvents.length, updatedAt: record.updatedAt });
  } catch (error) {
    console.error("Widget feed save failed", error);
    return reply(response, 503, { error: "Could not save private widget data" });
  }
}
