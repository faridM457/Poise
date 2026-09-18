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

export function rateLimit(bucket, { limit = LIMIT, windowMs = WINDOW_MS } = {}) {
  return (req, res, next) => {
    const key = `${bucket}:${req.poiseUser}`;
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
