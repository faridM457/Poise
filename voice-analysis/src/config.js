export const VERSION = '0.1.0';
export const SAMPLE_RATE = 16000;

// These are measurement definitions and provisional quality gates, not norms.
export const DEFAULTS = Object.freeze({
  maxInputBytes: 16 * 1024 * 1024,
  maxTurnSeconds: 90,
  maxConversationSeconds: 300,
  maxTurns: 20,
  timeoutMs: 180000,
  frameSamples: 400,
  hopSamples: 160,
  pitchFrameSamples: 1024,
  minPitchHz: 60,
  maxPitchHz: 500,
  minPitchClarity: 0.90,
  minPitchSeconds: 3,
  minPitchCoverage: 0.20,
  minDynamicRangeDb: 15,
  minActiveLevelDb: -45,
  minPauseSeconds: 0.30,
  maxClippedFraction: 0.01,
  minPaceWords: 20,
  minPaceSeconds: 10,
  insightsEnabled: false,
});

export function configuration(overrides = {}) {
  if (!overrides || typeof overrides !== 'object' || Array.isArray(overrides)) {
    throw new TypeError('config must be an object');
  }
  for (const key of Object.keys(overrides)) {
    if (!(key in DEFAULTS)) throw new TypeError(`Unknown config key: ${key}`);
  }
  const config = { ...DEFAULTS, ...overrides };
  for (const [key, value] of Object.entries(config)) {
    if (key === 'insightsEnabled') {
      if (typeof value !== 'boolean') throw new TypeError(`${key} must be boolean`);
    } else if (key === 'minActiveLevelDb') {
      if (!Number.isFinite(value) || value >= 0) throw new TypeError(`${key} must be negative`);
    } else if (!Number.isFinite(value) || value <= 0) {
      throw new TypeError(`${key} must be a positive finite number`);
    }
  }
  for (const key of ['maxInputBytes', 'maxTurns', 'timeoutMs', 'frameSamples', 'hopSamples', 'pitchFrameSamples']) {
    if (!Number.isSafeInteger(config[key])) throw new TypeError(`${key} must be an integer`);
  }
  if (config.minPitchHz >= config.maxPitchHz || config.maxPitchHz >= SAMPLE_RATE / 2) {
    throw new TypeError('Invalid pitch frequency range');
  }
  for (const key of ['minPitchClarity', 'minPitchCoverage', 'maxClippedFraction']) {
    if (config[key] > 1) throw new TypeError(`${key} must be <= 1`);
  }
  return config;
}
