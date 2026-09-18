import { createHmac, timingSafeEqual } from "node:crypto";

// Request authentication and conversation tokens.

const APP_KEY = process.env.POISE_APP_KEY;
const TOKEN_SECRET = process.env.POISE_TOKEN_SECRET;
export const TOKEN_TTL_MS = 60 * 60 * 1000;

function constantTimeEquals(a, b) {
  const ab = Buffer.from(String(a));
  const bb = Buffer.from(String(b));
  return ab.length === bb.length && timingSafeEqual(ab, bb);
}

// Two headers on every API request.
//
// X-Poise-App-Key is a shared secret compiled into the app. Be honest about
// what that buys: an iOS binary can be unpacked and its strings read, so this
// is spam filtering against random internet traffic, not a security boundary.
// The boundary that matters is per-user energy enforcement below, and the
// eventual hardening is App Attest -- Apple vouching that the request comes
// from a genuine copy of this app -- which is what makes a client claim
// trustworthy. Until then, assume the key is public and design accordingly.
//
// X-Poise-User is the caller's RevenueCat app user id. It is the energy
// ledger key, and the id the server uses to ask RevenueCat whether this
// person is Pro -- the client is never asked, because the client can lie.
export function requireAuth(req, res, next) {
  if (!APP_KEY || !TOKEN_SECRET) {
    return res.status(500).json({
      error: "Server is missing POISE_APP_KEY or POISE_TOKEN_SECRET. Refusing to serve unauthenticated traffic.",
    });
  }
  const key = req.get("X-Poise-App-Key");
  if (!key || !constantTimeEquals(key, APP_KEY)) {
    return res.status(401).json({ error: "Missing or invalid app key." });
  }
  const user = req.get("X-Poise-User");
  if (!user || user.length > 200) {
    return res.status(401).json({ error: "Missing user id." });
  }
  req.poiseUser = user;
  next();
}

// A conversation token is issued when a conversation is paid for (turn 1)
// and must accompany every later turn and the feedback call. Without it,
// anyone could replay turnNumber: 2 forever and never be charged again. It
// binds user + lesson + issue time under an HMAC so it cannot be forged,
// re-pointed at another lesson, or handed to another user.
export function issueToken(userId, lessonId, now = Date.now()) {
  const payload = `${userId}|${lessonId}|${now}`;
  const sig = createHmac("sha256", TOKEN_SECRET).update(payload).digest("base64url");
  return `${Buffer.from(payload).toString("base64url")}.${sig}`;
}

// Returns null when valid, or a reason string.
export function verifyToken(token, userId, lessonId, now = Date.now()) {
  if (!token || typeof token !== "string") return "missing";
  const dot = token.lastIndexOf(".");
  if (dot < 0) return "malformed";
  const payloadB64 = token.slice(0, dot);
  const sig = token.slice(dot + 1);
  let payload;
  try {
    payload = Buffer.from(payloadB64, "base64url").toString();
  } catch {
    return "malformed";
  }
  const expected = createHmac("sha256", TOKEN_SECRET).update(payload).digest("base64url");
  if (!constantTimeEquals(sig, expected)) return "bad signature";
  const [u, l, issuedAt] = payload.split("|");
  if (u !== userId) return "wrong user";
  if (l !== lessonId) return "wrong lesson";
  if (now - Number(issuedAt) > TOKEN_TTL_MS) return "expired";
  return null;
}

// Middleware factory: the routes that continue a paid conversation.
export function requireConversation(req, res, next) {
  const reason = verifyToken(req.get("X-Poise-Conversation"), req.poiseUser, req.body?.lessonId);
  if (reason) {
    return res.status(401).json({ error: `Conversation token ${reason}. Start the conversation again.` });
  }
  next();
}
