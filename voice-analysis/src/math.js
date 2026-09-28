export function quantile(values, fraction) {
  if (!values.length) return null;
  const sorted = [...values].sort((a, b) => a - b);
  const index = (sorted.length - 1) * fraction;
  const lower = Math.floor(index);
  return sorted[lower] + (sorted[Math.ceil(index)] - sorted[lower]) * (index - lower);
}

export function spread(values) {
  return values.length ? quantile(values, 0.9) - quantile(values, 0.1) : null;
}

export function metric(value, unit, status = 'available', reason = null) {
  return { value: Number.isFinite(value) ? value : null, unit, status, reason };
}

export function unavailable(unit, reason) {
  return metric(null, unit, 'unavailable', reason);
}
