import test from 'node:test';
import assert from 'node:assert/strict';
import { bandScore, combineCategories, scoreVoiceMetrics } from '../src/scoring.js';

const metric = (value, status = 'available', reason = null) => ({ value, status, reason });
const inputs = () => ({
  pitchRangeSemitones: metric(5), pitchCoverage: metric(0.3), reliablePitchSeconds: metric(8),
  speakingRateWpm: metric(150, 'experimental', 'apple_word_timing_estimate'),
  detectedFillersPer100Words: metric(0, 'experimental', 'filler_completeness_unvalidated'),
});

test('Target inputs score 100 but remain experimental, deterministic and immutable', () => {
  const input = inputs();
  const before = structuredClone(input);
  const result = scoreVoiceMetrics(input);
  assert.equal(result.overallVoiceScore, 100);
  assert.equal(result.reliability, 'experimental');
  assert.equal(result.weightCoverage, 1);
  assert.equal(result.feedback.length, 3);
  assert.match(result.feedback.find((f) => f.category === 'fillers').message, /does not establish/);
  assert.deepEqual(scoreVoiceMetrics(input), result);
  assert.deepEqual(input, before);
});

test('Pitch must pass status, finite values, coverage and duration independently', () => {
  for (const patch of [
    { pitchRangeSemitones: metric(null, 'unavailable', 'insufficient_reliable_pitch') },
    { pitchRangeSemitones: metric(5, 'unavailable', 'upstream_clarity_failure') },
    { pitchRangeSemitones: metric(NaN) }, { pitchCoverage: metric(0.199) },
    { pitchCoverage: metric(1.1) }, { reliablePitchSeconds: metric(2.99) },
    { pitchCoverage: metric(0.5, 'unavailable') },
  ]) {
    const result = scoreVoiceMetrics({ ...inputs(), ...patch });
    assert.equal(result.overallVoiceScore, null);
    assert.deepEqual(result.missingCategories, ['pitch']);
    assert.equal(result.reliability, 'unavailable');
    assert.equal(result.feedback.some((f) => f.category === 'pitch'), false);
    assert.equal(result.categories.find((c) => c.name === 'pitch').score, null);
  }
  assert.equal(scoreVoiceMetrics({ ...inputs(), pitchCoverage: metric(0.2), reliablePitchSeconds: metric(3) }).overallVoiceScore, 100);
  assert.equal(scoreVoiceMetrics(inputs(), { minPitchCoverage: 0.4 }).overallVoiceScore, null);
});

test('Two-sided bands have exact boundaries and continuous shoulders', () => {
  for (const [value, expected] of [[0, 0], [60, 0], [90, 50], [120, 100], [180, 100], [220, 50], [260, 0], [400, 0]]) {
    assert.equal(bandScore(value, 60, 120, 180, 260), expected);
  }
  for (const [value, expected] of [[0, 0], [1.5, 50], [3, 100], [8, 100], [12, 50], [16, 0]]) {
    assert.equal(bandScore(value, 0, 3, 8, 16), expected);
  }
  assert.ok(bandScore(180.001, 60, 120, 180, 260) > 99.99);
});

test('Fillers have a gradual penalty and weighted contribution', () => {
  for (const [rate, score, overall] of [[0, 100, 100], [3, 80, 96], [6, 50, 90], [12, 20, 84]]) {
    const result = scoreVoiceMetrics({ ...inputs(), detectedFillersPer100Words: metric(rate) });
    assert.equal(result.categories.find((c) => c.name === 'fillers').score, score);
    assert.equal(result.overallVoiceScore, overall);
    assert.equal(result.categories.find((c) => c.name === 'fillers').reliability, 'experimental');
  }
});

test('Malformed or unavailable pace/fillers produce neither score nor feedback for that category', () => {
  for (const key of ['speakingRateWpm', 'detectedFillersPer100Words']) {
    for (const value of [undefined, metric(-1), metric(Infinity), metric(5, 'unknown'), metric(5, 'unavailable', 'low_signal')]) {
      const result = scoreVoiceMetrics({ ...inputs(), [key]: value });
      assert.equal(result.overallVoiceScore, null);
      assert.equal(result.feedback.length, 2);
    }
  }
  assert.equal(scoreVoiceMetrics({}).feedback.length, 0);
});

test('Generic combination supports arbitrary categories, weights and strict missing handling', () => {
  const categories = ['a', 'b', 'c', 'd'].map((name, i) => ({ name, score: 20 * (i + 1), weight: i + 1, reliability: 'available' }));
  assert.equal(combineCategories(categories).overallVoiceScore, 60);
  assert.equal(combineCategories(categories).reliability, 'available');
  categories[3].reliability = 'experimental';
  assert.equal(combineCategories(categories).reliability, 'experimental');
  categories[3].score = null;
  assert.equal(combineCategories(categories).overallVoiceScore, null);
  assert.equal(combineCategories(categories).weightCoverage, 0.6);
  categories[3].weight = 0;
  assert.equal(combineCategories(categories).overallVoiceScore, 46.7);
  assert.equal(combineCategories([]).overallVoiceScore, null);
  assert.throws(() => combineCategories([...categories, categories[0]]), TypeError);
});
