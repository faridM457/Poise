import test from 'node:test';
import assert from 'node:assert/strict';
import { buildAppleReport } from '../src/apple-report.js';
import { configuration } from '../src/config.js';

const acoustic = {
  duration: 31, metrics: { medianPitchHz: { value: null, reason: 'insufficient_reliable_pitch' } },
  pauses: [], flags: ['insufficient_reliable_pitch'],
};
const transcript = () => ({
  text: 'Um, uh. ' + 'word '.repeat(20), duration: 31, timingIssues: [],
  words: ['Um,', 'uh.', ...Array(20).fill('word')].map((text, i) => ({ text, start: i, end: i + 0.5 })),
});

test('Apple fillers retain punctuation in evidence and pace uses timestamp span, not energy', () => {
  const source = transcript();
  const report = buildAppleReport(source, acoustic, configuration());
  assert.equal(report.detectedFillerCount, 2);
  assert.equal(report.lexicalWordCount, 20);
  assert.equal(report.metrics.speakingRateWpm.value, 60 * 20 / 21.5);
  assert.equal(report.evidence.fillers[0].text, 'Um,');
  assert.equal(report.transcript.text, source.text);
  assert.equal(report.overallVoiceScore, null);
  assert.deepEqual(report.scoring.missingCategories, ['pitch']);
  assert.equal(report.status, 'partial');
  assert.equal(report.metrics.medianPitchHz.value, null);
  assert.equal(report.evidence.timestampGaps.length, 21);
});

test('Apple report exposes the scoring breakdown and composite when all required metrics qualify', () => {
  const available = (value) => ({ value, status: 'available', reason: null });
  const report = buildAppleReport(transcript(), { ...acoustic, metrics: {
    pitchRangeSemitones: available(5), pitchCoverage: available(0.4), reliablePitchSeconds: available(8),
  } }, configuration());
  assert.equal(report.analysisVersion, 'apple-speech-2');
  assert.equal(typeof report.overallVoiceScore, 'number');
  assert.equal(report.overallVoiceScore, report.scoring.overallVoiceScore);
  assert.equal(report.scoring.feedback.length, 3);
});

test('Incomplete or invalid timings fail explicitly without computing partial filler counts', () => {
  for (const modify of [
    (t) => { t.words[0].start = null; },
    (t) => { t.words[0].end = 99; },
    (t) => { t.words[1].start = 0; },
    (t) => { t.timingIssues.push('multiword_timing_span'); },
    (t) => { t.words = []; },
  ]) {
    const source = transcript();
    modify(source);
    const report = buildAppleReport(source, acoustic, configuration());
    assert.equal(report.status, 'failed');
    assert.equal(report.detectedFillerCount, null);
    assert.equal(report.metrics.speakingRateWpm.value, null);
    assert.equal(report.transcript.timingsValid, false);
    assert.equal(report.transcript.text, source.text);
  }
});

test('A zero detected filler count remains unvalidated and short clips do not get pace', () => {
  const source = { text: 'Hello.', duration: 2, timingIssues: [], words: [{ text: 'Hello.', start: 0.5, end: 1 }] };
  const report = buildAppleReport(source, acoustic, configuration());
  assert.equal(report.detectedFillerCount, 0);
  assert.equal(report.transcript.fillerPreservation, 'unvalidated');
  assert.equal(report.metrics.speakingRateWpm.value, null);
});
