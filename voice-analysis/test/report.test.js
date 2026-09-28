import test from 'node:test';
import assert from 'node:assert/strict';
import { analyzeAcoustics } from '../src/acoustics.js';
import { aggregateReport, buildTurnReport } from '../src/report.js';
import { configuration } from '../src/config.js';
import { signal, transcript } from './helpers.js';

const config = configuration();
test('conversation pace is duration-weighted, not a mean of turn rates', () => {
  const a = buildTurnReport('a', analyzeAcoustics(signal()), transcript('word '.repeat(30)), config);
  const b = buildTurnReport('b', analyzeAcoustics(signal(25, [{ start: 2, end: 22 }])), transcript('word '.repeat(30)), config);
  const report = aggregateReport([a, b], config);
  assert.ok(Math.abs(report.metrics.speakingRateWpm.value - 3600 / (a.metrics.responseSeconds.value + b.metrics.responseSeconds.value)) < 1e-8);
  assert.equal(report.overallVoiceScore, null);
  assert.equal('_aggregation' in report.turns[0], false);
});

test('missing STT leaves real acoustics intact and filler data unavailable', () => {
  const turn = buildTurnReport('a', analyzeAcoustics(signal()), { status: 'unavailable', words: [] }, config);
  assert.equal(turn.metrics.detectedFillersPer100Words.value, null);
  assert.equal(turn.metrics.speakingRateWpm.value, null);
  assert.ok(turn.metrics.medianPitchHz.value > 200);
});

test('interrupted capture is excluded from aggregate measurements', () => {
  const turn = buildTurnReport('a', analyzeAcoustics(signal()), transcript('word '.repeat(30)), config, { interrupted: true });
  const report = aggregateReport([turn], config);
  assert.equal(report.metrics.pitchRangeSemitones.value, null);
  assert.equal(report.metrics.speakingRateWpm.value, null);
  assert.equal(report.coverage.activityTurnCount, 0);
});

test('fillers match whole tokens and insights are opt-in', () => {
  const text = transcript('um umbrella uh human ' + 'word '.repeat(30));
  const off = buildTurnReport('a', analyzeAcoustics(signal()), text, config);
  assert.equal(off.detectedFillerCount, 2);
  assert.equal(off.lexicalWordCount, 32);
  assert.equal(off.insights.length, 0);
  const on = buildTurnReport('a', analyzeAcoustics(signal()), text, configuration({ insightsEnabled: true }));
  assert.ok(on.insights.length > 0 && on.insights.length <= 2);
});

test('long transcript/activity disagreement disables pace', () => {
  const text = transcript('word '.repeat(30));
  text.timingsValid = true;
  text.words[0].start = 8;
  text.words.at(-1).end = 9;
  const turn = buildTurnReport('a', analyzeAcoustics(signal()), text, config);
  assert.equal(turn.metrics.speakingRateWpm.value, null);
  assert.ok(turn.flags.includes('transcript_activity_mismatch'));
});
