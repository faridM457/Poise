// Server-side Pro verification against RevenueCat.
//
// The app knows whether it thinks the user is Pro, but the app is the thing
// we are protecting against, so it is never asked. If REVENUECAT_SECRET_KEY
// is set, the server asks RevenueCat's REST API directly; if it is not, every
// user is free tier. There is no third option where a client claim is
// believed.
//
// The secret key (sk_...) is server-only and must never ship in the app.

const ENTITLEMENT_ID = "poise_pro";
const SECRET = process.env.REVENUECAT_SECRET_KEY;

// Injectable for tests so the code path can be exercised without a network
// call to RevenueCat.
let fetchImpl = globalThis.fetch;
export function _setFetch(f) {
  fetchImpl = f;
}

export function entitlementConfigured() {
  return Boolean(SECRET);
}

export async function verifyPro(userId) {
  if (!SECRET) return false;
  let res;
  try {
    res = await fetchImpl(`https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(userId)}`, {
      headers: { Authorization: `Bearer ${SECRET}`, "Content-Type": "application/json" },
    });
  } catch (err) {
    // A network failure must not silently promote or demote anyone; failing
    // closed to free tier is the safe direction for a cost control.
    console.error(`RevenueCat lookup failed for ${userId}: ${err.message}`);
    return false;
  }
  if (!res.ok) {
    console.error(`RevenueCat returned ${res.status} for ${userId}`);
    return false;
  }
  const body = await res.json();
  const ent = body?.subscriber?.entitlements?.[ENTITLEMENT_ID];
  if (!ent) return false;
  // A null expires_date is a lifetime entitlement; otherwise it must be in
  // the future.
  if (ent.expires_date == null) return true;
  return new Date(ent.expires_date).getTime() > Date.now();
}
