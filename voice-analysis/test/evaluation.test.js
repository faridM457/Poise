import test from 'node:test';
import assert from 'node:assert/strict';
import { compareWords, comparePauses, evaluateReport } from '../src/evaluation.js';

test('evaluation separates dropped fillers from invented fillers', () => {
  const result = compareWords('um I agree uh today', 'um I agree today um');
  assert.equal(result.fillers.truePositive, 1);
  assert.equal(result.fillers.falseNegative, 1);
  assert.equal(result.fillers.falsePositive, 1);
  assert.equal(result.wordCountErrorRatio, 0);
});

test('pause matching is one-to-one and reports extra detections', () => {
  const result = comparePauses([{ start: 1, end: 2 }], [{ start: 1.1, end: 2.1 }, { start: 1, end: 2 }]);
  assert.equal(result.truePositive, 1);
  assert.equal(result.falsePositive, 1);
});

test('missing reports count as missed speech; small datasets cannot pass the gate', () => {
  const result = evaluateReport({ turns: [] }, { samples: [{ id: 'a', speakerId: 'p1', split: 'held-out', reference: { text: 'um hello', pauses: [] } }] });
  assert.equal(result.heldOut.wordCountErrorRatio, 1);
  assert.equal(result.heldOut.fillerRecall, 0);
  assert.equal(result.fillerGate, 'insufficient_evidence');
});

test('speaker leakage is detected and duplicate labels are rejected', () => {
  const sample = { id: 'a', speakerId: 'p1', split: 'calibration', reference: { text: 'hello', pauses: [] } };
  const result = evaluateReport({ turns: [] }, { samples: [sample, { ...sample, id: 'b', split: 'held-out' }] });
  assert.equal(result.speakerLeakage, true);
  assert.throws(() => evaluateReport({ turns: [] }, { samples: [sample, sample] }), /unique/);
});
