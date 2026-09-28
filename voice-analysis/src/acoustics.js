import { PitchDetector } from 'pitchy';
import { configuration, SAMPLE_RATE } from './config.js';
import { metric, quantile, spread, unavailable } from './math.js';

export function removePitchOutliers(track) {
  return track.map((point, i) => {
    if (point.hz === null) return point;
    const neighbors = track.slice(Math.max(0, i - 3), i)
      .concat(track.slice(i + 1, i + 4)).filter((p) => p.hz !== null);
    const before = neighbors.some((p) => p.time < point.time);
    const after = neighbors.some((p) => p.time > point.time);
    if (!before || !after || neighbors.length < 4) return point;
    const semitones = neighbors.map((p) => 12 * Math.log2(p.hz));
    const median = quantile(semitones, 0.5);
    if (Math.max(...semitones) - Math.min(...semitones) <= 3 &&
        Math.abs(12 * Math.log2(point.hz) - median) > 9) {
      return { ...point, hz: null };
    }
    return point;
  });
}

function activeIntervals(frames, hopSeconds, duration, onThreshold, offThreshold) {
  let active = false;
  let candidate = null;
  let start = null;
  const intervals = [];
  for (let i = 0; i < frames.length; i++) {
    const wantsChange = active ? frames[i] < offThreshold : frames[i] > onThreshold;
    if (!wantsChange) { candidate = null; continue; }
    candidate ??= i;
    if ((i - candidate + 1) * hopSeconds < 0.1 - 1e-9) continue;
    const boundary = candidate * hopSeconds;
    if (active) intervals.push({ start, end: boundary });
    else start = boundary;
    active = !active;
    candidate = null;
  }
  if (active) intervals.push({ start, end: duration });
  return intervals;
}

export function analyzeAcoustics(samples, overrides = {}) {
  const config = configuration(overrides);
  if (!(samples instanceof Float32Array) || !samples.length) {
    throw new TypeError('samples must be a nonempty mono Float32Array at 16000 Hz');
  }
  const duration = samples.length / SAMPLE_RATE;
  if (duration > config.maxTurnSeconds) throw new RangeError('Audio exceeds maxTurnSeconds');
  let clipped = 0;
  for (const sample of samples) {
    if (!Number.isFinite(sample) || Math.abs(sample) > 1.00001) {
      throw new TypeError('PCM samples must be finite and normalized to [-1, 1]');
    }
    if (Math.abs(sample) >= 0.999) clipped++;
  }
  const hopSeconds = config.hopSamples / SAMPLE_RATE;
  const levels = [];
  for (let start = 0; start + config.frameSamples <= samples.length; start += config.hopSamples) {
    let power = 0;
    for (let j = start; j < start + config.frameSamples; j++) power += samples[j] ** 2;
    levels.push(20 * Math.log10(Math.max(Math.sqrt(power / config.frameSamples), 1e-8)));
  }
  const noise = quantile(levels, 0.1) ?? -160;
  const high = quantile(levels, 0.9) ?? -160;
  const clippedFraction = clipped / samples.length;
  const flags = [];
  if (high < config.minActiveLevelDb) flags.push('low_signal');
  if (high - noise < config.minDynamicRangeDb) flags.push('insufficient_level_separation');
  if (clippedFraction > config.maxClippedFraction) flags.push('clipping');
  const intervals = activeIntervals(levels, hopSeconds, duration,
    Math.max(-60, noise + 10), Math.max(-63, noise + 6));
  if (!intervals.length) flags.push('no_activity_detected');
  const activityReliable = flags.length === 0;
  const isActive = (time) => intervals.some((p) => time >= p.start && time < p.end);
  const pauses = intervals.slice(1).map((p, i) => ({ start: intervals[i].end, end: p.start }))
    .filter((p) => p.end - p.start >= config.minPauseSeconds);
  const responseSpan = intervals.length ? intervals.at(-1).end - intervals[0].start : 0;
  const pauseSeconds = pauses.reduce((sum, p) => sum + p.end - p.start, 0);
  const activeSeconds = intervals.reduce((sum, p) => sum + p.end - p.start, 0);

  const detector = PitchDetector.forFloat32Array(config.pitchFrameSamples);
  const track = [];
  let activePitchFrames = 0;
  for (let start = 0; start + config.pitchFrameSamples <= samples.length; start += config.hopSamples) {
    const time = (start + config.pitchFrameSamples / 2) / SAMPLE_RATE;
    const active = isActive(time);
    if (active) activePitchFrames++;
    let hz = null;
    let clarity = null;
    if (active) {
      [hz, clarity] = detector.findPitch(samples.subarray(start, start + config.pitchFrameSamples), SAMPLE_RATE);
      if (!Number.isFinite(hz) || !Number.isFinite(clarity) || clarity < config.minPitchClarity ||
          hz < config.minPitchHz || hz > config.maxPitchHz) hz = null;
    }
    track.push({ time, hz, clarity });
  }
  const cleanTrack = removePitchOutliers(track);
  const voiced = cleanTrack.filter((p) => p.hz !== null);
  const medianPitch = quantile(voiced.map((p) => p.hz), 0.5);
  const semitones = voiced.map((p) => 12 * Math.log2(p.hz / medianPitch));
  const pitchSeconds = voiced.length * hopSeconds;
  const coverage = activePitchFrames ? voiced.length / activePitchFrames : 0;
  const pitchReliable = activityReliable && pitchSeconds >= config.minPitchSeconds && coverage >= config.minPitchCoverage;
  const pitchWindows = [];
  for (let start = 0; start + 5 <= duration + 1e-9; start += 5) {
    const points = voiced.filter((p) => p.time >= start && p.time < start + 5);
    if (points.length * hopSeconds >= 1.5) {
      pitchWindows.push({ start, end: start + 5, range: spread(points.map((p) => 12 * Math.log2(p.hz / medianPitch))) });
    }
  }

  // Never smooth through an inactive interval or mix levels across turns.
  const smoothed = [];
  const halfWindow = Math.round(0.1 / hopSeconds);
  for (const interval of intervals) {
    const indices = levels.map((_, i) => i).filter((i) => {
      const center = i * hopSeconds + config.frameSamples / SAMPLE_RATE / 2;
      return center >= interval.start && center < interval.end;
    });
    for (let j = 0; j < indices.length; j++) {
      const neighborhood = indices.slice(Math.max(0, j - halfWindow), j + halfWindow + 1);
      smoothed.push({ time: indices[j] * hopSeconds, db: quantile(neighborhood.map((i) => levels[i]), 0.5) });
    }
  }
  const medianLevel = quantile(smoothed.map((p) => p.db), 0.5);
  const centeredLevels = smoothed.map((p) => p.db - medianLevel);
  const volumeWindows = [];
  for (let start = 0; start + 1 <= duration + 1e-9; start++) {
    const points = smoothed.filter((p) => p.time >= start && p.time < start + 1);
    if (points.length * hopSeconds >= 0.7) volumeWindows.push({ start, end: start + 1, db: quantile(points.map((p) => p.db), 0.5) });
  }
  const activityReason = flags[0] ?? 'insufficient_activity';
  const activityMetric = (value, unit) => activityReliable ? metric(value, unit, 'experimental', 'energy_based_activity') : unavailable(unit, activityReason);
  return {
    duration, flags, activityReliable, pitchReliable,
    intervals, pauses: activityReliable ? pauses : [],
    metrics: {
      responseSeconds: activityMetric(responseSpan, 'seconds'),
      activeSeconds: activityMetric(activeSeconds, 'seconds'),
      pauseSeconds: activityMetric(pauseSeconds, 'seconds'),
      pauseRatio: activityMetric(responseSpan ? pauseSeconds / responseSpan : 0, 'ratio'),
      longestPauseSeconds: activityMetric(Math.max(0, ...pauses.map((p) => p.end - p.start)), 'seconds'),
      medianPitchHz: pitchReliable ? metric(medianPitch, 'Hz') : unavailable('Hz', activityReliable ? 'insufficient_reliable_pitch' : activityReason),
      pitchRangeSemitones: pitchReliable ? metric(spread(semitones), 'semitones') : unavailable('semitones', activityReliable ? 'insufficient_reliable_pitch' : activityReason),
      pitchCoverage: metric(coverage, 'ratio'),
      reliablePitchSeconds: metric(pitchSeconds, 'seconds'),
      volumeSpreadDb: activityMetric(spread(centeredLevels), 'dB'),
      clippedFraction: metric(clippedFraction, 'ratio'),
    },
    // Internal sufficient statistics are removed from public JSON reports.
    evidence: { pitchWindows: pitchReliable ? pitchWindows : [], volumeWindows: activityReliable ? volumeWindows : [] },
    distributions: { semitones: pitchReliable ? semitones : [], levels: activityReliable ? centeredLevels : [] },
  };
}
