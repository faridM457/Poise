// Per-user sliding-window rate limit for the two generation endpoints the
// client caches (scenario, opening line). A real user hits each once per
// lesson completion; anyone hitting them ten times an hour is not a user.
//
// In-memory on purpose for now: it is a first line against abuse, not an
// accounting system, and it does not survive restart or scale-out. Move it to
// the same store as the energy ledger (or Redis) before running more than one
// instance.
const WINDOW_MS = 60 * 60 * 1000;
const LIMIT = 10;

const hits = new Map(); // key -> [timestamps]

export function rateLimit(bucket) {
  return (req, res, next) => {
    const key = `${bucket}:${req.poiseUser}`;
    const now = Date.now();
    const recent = (hits.get(key) ?? []).filter((t) => now - t < WINDOW_MS);
    if (recent.length >= LIMIT) {
      const retryAfter = Math.ceil((recent[0] + WINDOW_MS - now) / 1000);
      res.set("Retry-After", String(retryAfter));
      return res.status(429).json({ error: `Too many ${bucket} requests. Try again in ${Math.ceil(retryAfter / 60)} minutes.` });
    }
    recent.push(now);
    hits.set(key, recent);
    next();
  };
}
