import { configuration } from './config.js';

export const SCORING_VERSION = 'delivery-rules-1';
const round = (value) => Math.round(value * 10) / 10;
const usable = (metric) => metric && ['available', 'experimental'].includes(metric.status) &&
  Number.isFinite(metric.value) && metric.value >= 0;

// Product hypotheses, not population norms. Plateau scores fall linearly to zero
// at each outer bound. Filler score = 100 / (1 + (rate / 6)^2).
export function bandScore(value, floor, low, high, ceiling) {
  if (![value, floor, low, high, ceiling].every(Number.isFinite) ||
      !(floor < low && low <= high && high < ceiling)) throw new TypeError('Invalid scoring band');
  if (value <= floor || value >= ceiling) return 0;
  if (value < low) return 100 * (value - floor) / (low - floor);
  if (value > high) return 100 * (ceiling - value) / (ceiling - high);
  return 100;
}

// A future externally computed category plugs in as another {name, score,
// weight, reliability, reasons} entry. No provider-specific logic belongs here.
// Strict completeness applies generically to every positive-weight category.
export function combineCategories(categories) {
  if (!Array.isArray(categories)) throw new TypeError('Categories must be an array');
  const names = new Set();
  for (const category of categories) {
    if (!category || typeof category.name !== 'string' || !category.name || names.has(category.name) ||
        !Number.isFinite(category.weight) || category.weight < 0 ||
        !['available', 'experimental', 'unavailable'].includes(category.reliability) ||
        (category.score !== null && (!Number.isFinite(category.score) || category.score < 0 || category.score > 100))) {
      throw new TypeError('Invalid or duplicate scoring category');
    }
    names.add(category.name);
  }
  const active = categories.filter((category) => category.weight > 0);
  const totalWeight = active.reduce((sum, category) => sum + category.weight, 0);
  if (!Number.isFinite(totalWeight)) throw new TypeError('Category weights overflow');
  const missing = active.filter((category) => category.score === null || category.reliability === 'unavailable');
  const experimental = active.filter((category) => category.reliability === 'experimental').map((category) => category.name);
  const observedWeight = active.filter((category) => category.score !== null && category.reliability !== 'unavailable')
    .reduce((sum, category) => sum + category.weight, 0);
  const complete = active.length > 0 && missing.length === 0;
  return {
    overallVoiceScore: complete ? round(active.reduce((sum, category) => sum + category.score * (category.weight / totalWeight), 0)) : null,
    reliability: !complete ? 'unavailable' : experimental.length ? 'experimental' : 'available',
    reason: !active.length ? 'no_weighted_categories' : missing.length ? 'required_categories_unavailable' : experimental.length ? 'experimental_inputs' : null,
    missingCategories: missing.map((category) => category.name),
    experimentalCategories: experimental,
    weightCoverage: totalWeight ? observedWeight / totalWeight : 0,
    missingPolicy: 'require_all',
  };
}

export function scoreVoiceMetrics(metrics, configOverrides = {}) {
  if (!metrics || typeof metrics !== 'object' || Array.isArray(metrics)) throw new TypeError('Metrics must be an object');
  const config = configuration(configOverrides);
  const categories = [];
  const feedback = [];
  function add(name, weight, metricName, score, extraIssues = [], dependencies = []) {
    const metric = metrics[metricName];
    const reasons = [...extraIssues];
    if (!usable(metric)) reasons.push(metric?.reason ?? 'invalid_or_missing_metric');
    const valid = reasons.length === 0;
    const inputs = [metric, ...dependencies];
    const reliability = !valid ? 'unavailable' : name === 'fillers' || inputs.some((input) => input?.status === 'experimental') ? 'experimental' : 'available';
    categories.push({ name, weight, score: valid ? score(metric.value) : null, reliability,
      metric: metricName, value: usable(metric) ? metric.value : null,
      reasons: valid ? [...new Set([...inputs.map((input) => input?.reason).filter(Boolean),
        ...(name === 'fillers' ? ['filler_completeness_unvalidated'] : [])])] : reasons });
    return valid;
  }
  const pitchIssues = [];
  if (!usable(metrics.pitchCoverage) || metrics.pitchCoverage.value > 1 || metrics.pitchCoverage.value < config.minPitchCoverage) {
    pitchIssues.push('insufficient_pitch_coverage');
  }
  if (!usable(metrics.reliablePitchSeconds) || metrics.reliablePitchSeconds.value < config.minPitchSeconds) {
    pitchIssues.push('insufficient_reliable_pitch_seconds');
  }
  // Frame-level clarity filtering happens upstream; a range marked unavailable
  // stays unavailable even when summary coverage passes these extra checks.
  if (add('pitch', 0.35, 'pitchRangeSemitones', (v) => bandScore(v, 0, 3, 8, 16), pitchIssues,
    [metrics.pitchCoverage, metrics.reliablePitchSeconds])) {
    const value = metrics.pitchRangeSemitones.value;
    const band = value < 3 ? 'below' : value > 8 ? 'above' : 'within';
    feedback.push({ category: 'pitch', code: `pitch_${band}_target`, value, unit: 'semitones', target: [3, 8],
      message: `Measured pitch variation was ${round(value)} semitones, ${band} the provisional 3-8 semitone target. This does not measure confidence or emotion.` });
  }
  if (add('fillers', 0.20, 'detectedFillersPer100Words', (v) => 100 / (1 + (v / 6) ** 2))) {
    const value = metrics.detectedFillersPer100Words.value;
    feedback.push({ category: 'fillers', code: value > 2 ? 'observed_fillers_above_target' : 'observed_fillers_within_target',
      value, unit: 'events/100 words', target: [0, 2],
      message: value === 0 ? 'No um/uh fillers were detected (0 per 100 words); this does not establish that none were spoken.'
        : `Detected ${round(value)} um/uh fillers per 100 words, ${value > 2 ? 'above' : 'within'} the provisional 0-2 target. Some spoken fillers may be missing.` });
  }
  if (add('pace', 0.45, 'speakingRateWpm', (v) => bandScore(v, 60, 120, 180, 260))) {
    const value = metrics.speakingRateWpm.value;
    const band = value < 120 ? 'below' : value > 180 ? 'above' : 'within';
    feedback.push({ category: 'pace', code: `pace_${band}_target`, value, unit: 'words/minute', target: [120, 180],
      message: `Estimated pace was ${round(value)} words/minute, ${band} the provisional 120-180 target.` });
  }
  const composite = combineCategories(categories);
  return {
    version: SCORING_VERSION, scale: [0, 100], ...composite,
    // Even fully available measurements do not validate the scoring policy.
    reliability: composite.overallVoiceScore === null ? 'unavailable' : 'experimental',
    reason: composite.overallVoiceScore === null ? composite.reason : 'unvalidated_scoring_policy',
    inputReliability: composite.reliability,
    categories: categories.map((category) => ({ ...category, score: category.score === null ? null : round(category.score) })),
    feedback,
  };
}
