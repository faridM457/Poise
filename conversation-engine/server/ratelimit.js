// Per-user sliding-window rate limit, originally written for the two
// generation endpoints the client caches (scenario, opening line): a real
// user hits each once per lesson completion; anyone hitting them ten times
// an hour is not a user. `limit`/`windowMs` are overridable per bucket
// because not every endpoint has that shape -- a redeem-code guesser and a
// mid-conversation turn call need very different thresholds than that
// default.
//
// In-memory on purpose for now: it is a first line against abuse, not an
// accounting system, and it does not survive restart or scale-out. Move it to
// the same store as the energy ledger (or Redis) before running more than one
// instance.
const WINDOW_MS = 60 * 60 * 1000;
const LIMIT = 10;

const hits = new Map(); // key -> [timestamps]

// `keyBy: "ip"` closes a real gap in the default per-user key: X-Poise-User
// is a client-supplied header, not an authenticated identity, so a caller
// can reset their own counter just by sending a new one. IP isn't spoofable
// the same way (it's the TCP connection, not a header the client writes),
// so combining both on a route -- one call keyed by user, one by IP -- means
// rotating the header alone no longer resets anything. Requires the server
// to actually see the real client IP: `app.set("trust proxy", ...)` in
// index.js so Express reads it from X-Forwarded-For behind the Apache
// reverse proxy, instead of everything showing up as localhost.
export function rateLimit(bucket, { limit = LIMIT, windowMs = WINDOW_MS, keyBy = "user" } = {}) {
  return (req, res, next) => {
    const key = `${bucket}:${keyBy}:${keyBy === "ip" ? req.ip : req.poiseUser}`;
    const now = Date.now();
    const recent = (hits.get(key) ?? []).filter((t) => now - t < windowMs);
    if (recent.length >= limit) {
      const retryAfter = Math.ceil((recent[0] + windowMs - now) / 1000);
      res.set("Retry-After", String(retryAfter));
      return res.status(429).json({ error: `Too many ${bucket} requests. Try again in ${Math.ceil(retryAfter / 60)} minutes.` });
    }
    recent.push(now);
    hits.set(key, recent);
    next();
  };
}
