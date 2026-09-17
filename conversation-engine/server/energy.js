import { DatabaseSync } from "node:sqlite";

// Server-side energy ledger.
//
// Until now energy was enforced only on the phone -- a number in UserDefaults
// that a modified client, or anyone replaying requests with curl, could ignore
// entirely. Energy is the app's cost control: it is what bounds how many
// billable model calls one user can trigger per day. Enforced only on the
// client, it bounded nothing. The server is the one counting now.
//
// The rules here MUST match LearnProgressStore in the app: free cap 3 with one
// unit back every 8 hours, Pro cap 12 with one back every 2 hours, regen
// applied lazily on read. The client keeps its own copy for mock mode and for
// instant display, but once the app is on the live path the number the server
// returns is the one that is true.

export const FREE_CAP = 3;
export const PRO_CAP = 12;
export const FREE_REGEN_MS = 8 * 60 * 60 * 1000;
export const PRO_REGEN_MS = 2 * 60 * 60 * 1000;

// How long a server-side Pro verdict is trusted before RevenueCat is asked
// again. Short enough that a lapsed subscription is noticed within the hour;
// long enough that a lesson's handful of requests share one lookup.
export const PRO_CHECK_TTL_MS = 10 * 60 * 1000;

const DB_PATH = process.env.ENGINE_DB_PATH || "./engine.db";

let db = null;

function open() {
  if (db) return db;
  db = new DatabaseSync(DB_PATH);
  db.exec(`
    CREATE TABLE IF NOT EXISTS energy (
      user_id        TEXT PRIMARY KEY,
      remaining      INTEGER NOT NULL,
      last_regen     REAL    NOT NULL,
      is_pro         INTEGER NOT NULL DEFAULT 0,
      pro_checked_at REAL    NOT NULL DEFAULT 0
    )
  `);
  return db;
}

function capFor(isPro) {
  return isPro ? PRO_CAP : FREE_CAP;
}

function regenFor(isPro) {
  return isPro ? PRO_REGEN_MS : FREE_REGEN_MS;
}

// Mirrors LearnProgressStore.applyRegenIfNeeded: whole elapsed periods are
// credited, and once at cap the clock is re-anchored to now so unclaimed regen
// never accumulates past the ceiling.
function applyRegen(row, now) {
  const cap = capFor(row.is_pro);
  if (row.remaining >= cap) {
    return { ...row, remaining: cap, last_regen: now };
  }
  const elapsed = now - row.last_regen;
  const periods = Math.floor(elapsed / regenFor(row.is_pro));
  if (periods <= 0) return row;
  const remaining = Math.min(cap, row.remaining + periods);
  const last_regen =
    remaining >= cap ? now : row.last_regen + periods * regenFor(row.is_pro);
  return { ...row, remaining, last_regen };
}

function load(userId, now) {
  const d = open();
  let row = d.prepare("SELECT * FROM energy WHERE user_id = ?").get(userId);
  if (!row) {
    row = { user_id: userId, remaining: FREE_CAP, last_regen: now, is_pro: 0, pro_checked_at: 0 };
    d.prepare(
      "INSERT INTO energy (user_id, remaining, last_regen, is_pro, pro_checked_at) VALUES (?, ?, ?, ?, ?)"
    ).run(row.user_id, row.remaining, row.last_regen, row.is_pro, row.pro_checked_at);
  }
  return row;
}

function save(row) {
  open()
    .prepare(
      "UPDATE energy SET remaining = ?, last_regen = ?, is_pro = ?, pro_checked_at = ? WHERE user_id = ?"
    )
    .run(row.remaining, row.last_regen, row.is_pro, row.pro_checked_at, row.user_id);
}

// The shape every energy-relevant response carries, so the client can adopt
// the server's number rather than keep guessing.
export function publicState(row, now = Date.now()) {
  const cap = capFor(row.is_pro);
  return {
    remaining: row.remaining,
    cap,
    nextRegenAt: row.remaining >= cap ? null : new Date(row.last_regen + regenFor(row.is_pro)).toISOString(),
  };
}

// Reads the user's current state, applying any regen that has accrued and
// refreshing the Pro verdict if it is stale. `verifyPro` is injected so this
// module never talks to RevenueCat itself.
export async function getState(userId, { verifyPro, now = Date.now() } = {}) {
  let row = load(userId, now);

  if (verifyPro && now - row.pro_checked_at > PRO_CHECK_TTL_MS) {
    const isPro = (await verifyPro(userId)) ? 1 : 0;
    if (isPro !== row.is_pro) {
      // Tier changed. Clamp down if the cap shrank; a freshly verified Pro
      // user keeps their balance and simply gains headroom.
      row = { ...row, is_pro: isPro, remaining: Math.min(row.remaining, capFor(isPro)) };
    }
    row = { ...row, is_pro: isPro, pro_checked_at: now };
  }

  row = applyRegen(row, now);
  save(row);
  return row;
}

// Charges one unit. Returns { ok: true, row } or { ok: false, row } when the
// user is at zero -- the caller turns that into a 402 carrying the state, so
// the client can show when the next unit lands rather than a bare refusal.
export async function spend(userId, opts) {
  const row = await getState(userId, opts);
  if (row.remaining <= 0) return { ok: false, row };
  const next = { ...row, remaining: row.remaining - 1 };
  // Leaving cap starts the regen clock, exactly as the client does.
  if (row.remaining >= capFor(row.is_pro)) next.last_regen = opts?.now ?? Date.now();
  save(next);
  return { ok: true, row: next };
}

// For tests and tooling only.
export function _close() {
  if (db) {
    db.close();
    db = null;
  }
}
