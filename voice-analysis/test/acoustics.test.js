import test from 'node:test';
import assert from 'node:assert/strict';
import { analyzeAcoustics, removePitchOutliers } from '../src/acoustics.js';
import { configuration } from '../src/config.js';
import { signal } from './helpers.js';

for (const hz of [100, 220, 440]) {
  test(`Pitchy measures a ${hz} Hz tone within 2%, with quiet gaps`, () => {
    const result = analyzeAcoustics(signal(15, undefined, { hz }));
    assert.equal(result.pitchReliable, true);
    assert.ok(Math.abs(result.metrics.medianPitchHz.value / hz - 1) < 0.02);
    assert.ok(result.metrics.pitchRangeSemitones.value < 0.1);
    assert.ok(Math.abs(result.metrics.longestPauseSeconds.value - 1) < 0.08);
    assert.ok(result.metrics.responseSeconds.value < 13.1);
  });
}

test('silence never becomes a perfect delivery measurement', () => {
  const result = analyzeAcoustics(new Float32Array(16000 * 3));
  assert.equal(result.activityReliable, false);
  assert.equal(result.metrics.pauseRatio.value, null);
  assert.equal(result.metrics.medianPitchHz.value, null);
  assert.ok(result.flags.includes('low_signal'));
});

test('insufficient quiet/speech separation suppresses interpretation', () => {
  const result = analyzeAcoustics(signal(5, [{ start: 0, end: 5 }]));
  assert.equal(result.activityReliable, false);
  assert.equal(result.metrics.volumeSpreadDb.value, null);
});

test('a genuine octave change spans about twelve semitones', () => {
  const samples = signal(15, [{ start: 1, end: 7 }], { hz: 110 });
  const higher = signal(15, [{ start: 8, end: 14 }], { hz: 220 });
  for (let i = 0; i < samples.length; i++) samples[i] += higher[i];
  const result = analyzeAcoustics(samples);
  assert.ok(Math.abs(result.metrics.pitchRangeSemitones.value - 12) < 0.2);
});

test('doubling sustained amplitude produces roughly 6.02 dB of level spread', () => {
  const samples = signal(15, [{ start: 1, end: 7 }], { amplitude: 0.1 });
  const louder = signal(15, [{ start: 8, end: 14 }], { amplitude: 0.2 });
  for (let i = 0; i < samples.length; i++) samples[i] += louder[i];
  const result = analyzeAcoustics(samples);
  assert.ok(Math.abs(result.metrics.volumeSpreadDb.value - 6.0206) < 0.2);
});

test('clipping disables acoustic interpretation', () => {
  const samples = signal();
  samples.fill(1, 16000, 32000);
  const result = analyzeAcoustics(samples);
  assert.ok(result.flags.includes('clipping'));
  assert.equal(result.metrics.pitchRangeSemitones.value, null);
});

test('isolated octave errors are removed without flattening sustained changes', () => {
  const track = Array.from({ length: 15 }, (_, i) => ({ time: i * 0.01, hz: i === 7 ? 440 : 220, clarity: 1 }));
  assert.equal(removePitchOutliers(track)[7].hz, null);
  const sustained = track.map((p, i) => ({ ...p, hz: i > 7 ? 440 : 220 }));
  assert.equal(removePitchOutliers(sustained)[10].hz, 440);
});

test('very short audio and invalid configuration fail safely', () => {
  assert.equal(analyzeAcoustics(new Float32Array(20)).metrics.pitchRangeSemitones.value, null);
  assert.throws(() => analyzeAcoustics(Float32Array.of(NaN)), /finite/);
  assert.throws(() => configuration({ madeUp: true }), /Unknown/);
  assert.throws(() => configuration({ minPitchClarity: 2 }), /<= 1/);
  assert.throws(() => configuration({ insightsEnabled: 'yes' }), /boolean/);
});
