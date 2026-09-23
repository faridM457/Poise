import { lexicalWords } from './transcript.js';
import { quantile } from './math.js';

const filler = (word) => word === 'um' || word === 'uh';
const ratio = (a, b) => b > 0 ? a / b : null;

export function compareWords(referenceText, predictedText) {
  const reference = lexicalWords(referenceText), predicted = lexicalWords(predictedText);
  if (reference.length > 2000 || predicted.length > 2000) throw new Error('Evaluation transcripts limited to 2000 words');
  // Word alignment distinguishes correctly retained fillers from invented ones.
  const distance = Array.from({ length: reference.length + 1 }, () => new Uint16Array(predicted.length + 1));
  for (let i = 0; i <= reference.length; i++) distance[i][0] = i;
  for (let j = 0; j <= predicted.length; j++) distance[0][j] = j;
  for (let i = 1; i <= reference.length; i++) {
    for (let j = 1; j <= predicted.length; j++) {
      distance[i][j] = Math.min(
        distance[i - 1][j] + 1,
        distance[i][j - 1] + 1,
        distance[i - 1][j - 1] + (reference[i - 1] === predicted[j - 1] ? 0 : 1),
      );
    }
  }
  let i = reference.length, j = predicted.length;
  let truePositive = 0, falsePositive = 0, falseNegative = 0;
  while (i || j) {
    if (i && j && distance[i][j] === distance[i - 1][j - 1] + (reference[i - 1] === predicted[j - 1] ? 0 : 1)) {
      const a = reference[--i], b = predicted[--j];
      if (a === b && filler(a)) truePositive++;
      else if (a !== b) { if (filler(a)) falseNegative++; if (filler(b)) falsePositive++; }
    } else if (i && distance[i][j] === distance[i - 1][j] + 1) {
      if (filler(reference[--i])) falseNegative++;
    } else if (filler(predicted[--j])) falsePositive++;
  }
  const referenceLexicalCount = reference.filter((w) => !filler(w)).length;
  const predictedLexicalCount = predicted.filter((w) => !filler(w)).length;
  return {
    referenceLexicalCount, predictedLexicalCount,
    absoluteWordCountError: Math.abs(referenceLexicalCount - predictedLexicalCount),
    wordCountErrorRatio: ratio(Math.abs(referenceLexicalCount - predictedLexicalCount), referenceLexicalCount),
    wordErrorRate: ratio(distance[reference.length][predicted.length], reference.length),
    fillers: { truePositive, falsePositive, falseNegative },
  };
}

export function comparePauses(reference, predicted, tolerance = 0.2) {
  const actual = reference.filter((p) => p.end - p.start >= 0.5);
  const guesses = predicted.filter((p) => p.end - p.start >= 0.5);
  const used = new Set();
  const errors = [];
  for (const expected of actual) {
    let best = -1, bestError = Infinity;
    guesses.forEach((guess, index) => {
      if (used.has(index)) return;
      const error = Math.max(Math.abs(expected.start - guess.start), Math.abs(expected.end - guess.end));
      if (error <= tolerance && error < bestError) { best = index; bestError = error; }
    });
    if (best >= 0) { used.add(best); errors.push(bestError); }
  }
  return { truePositive: used.size, falsePositive: guesses.length - used.size,
    falseNegative: actual.length - used.size, boundaryErrorsSeconds: errors };
}

export function evaluateReport(report, labels) {
  if (!Array.isArray(report?.turns) || !Array.isArray(labels?.samples)) throw new Error('Expected report.turns and labels.samples');
  const byId = new Map(report.turns.map((t) => [t.id, t]));
  const ids = new Set();
  const samples = labels.samples.map((sample) => {
    if (!sample || typeof sample.id !== 'string' || ids.has(sample.id) || !sample.speakerId ||
        !['calibration', 'held-out'].includes(sample.split) || typeof sample.reference?.text !== 'string' ||
        !Array.isArray(sample.reference.pauses)) throw new Error('Every unique labeled sample needs speakerId, split, reference.text and reference.pauses');
    ids.add(sample.id);
    for (const pause of sample.reference.pauses) {
      if (!Number.isFinite(pause.start) || !Number.isFinite(pause.end) || pause.start < 0 || pause.end <= pause.start) throw new Error('Invalid reference pause');
    }
    const turn = byId.get(sample.id);
    const textAvailable = turn?.transcript?.status === 'available';
    const speech = compareWords(sample.reference.text, textAvailable ? turn.transcript.text : '');
    return { id: sample.id, speakerId: sample.speakerId, split: sample.split,
      transcriptAvailable: textAvailable, ...speech,
      pauses: comparePauses(sample.reference.pauses, turn?.evidence?.pauses ?? []) };
  });
  const calibrationSpeakers = new Set(samples.filter((s) => s.split === 'calibration').map((s) => s.speakerId));
  const heldOut = samples.filter((s) => s.split === 'held-out');
  const heldOutSpeakers = new Set(heldOut.map((s) => s.speakerId));
  const leakage = [...heldOutSpeakers].some((id) => calibrationSpeakers.has(id));
  const total = (get) => heldOut.reduce((sum, sample) => sum + get(sample), 0);
  const tp = total((s) => s.fillers.truePositive), fp = total((s) => s.fillers.falsePositive), fn = total((s) => s.fillers.falseNegative);
  const precision = ratio(tp, tp + fp), recall = ratio(tp, tp + fn);
  const sufficient = samples.length >= 20 && new Set(samples.map((s) => s.speakerId)).size >= 4 &&
    heldOut.length >= 8 && heldOutSpeakers.size >= 2 && tp + fn >= 20 && !leakage;
  return {
    samples,
    heldOut: {
      sampleCount: heldOut.length, speakerCount: heldOutSpeakers.size,
      transcriptionCoverage: ratio(total((s) => Number(s.transcriptAvailable)), heldOut.length),
      wordCountErrorRatio: ratio(total((s) => s.absoluteWordCountError), total((s) => s.referenceLexicalCount)),
      fillerPrecision: precision, fillerRecall: recall, referenceFillerCount: tp + fn,
      pausePrecision: ratio(total((s) => s.pauses.truePositive), total((s) => s.pauses.truePositive + s.pauses.falsePositive)),
      pauseRecall: ratio(total((s) => s.pauses.truePositive), total((s) => s.pauses.truePositive + s.pauses.falseNegative)),
      matchedPauseMedianBoundaryErrorSeconds: quantile(heldOut.flatMap((s) => s.pauses.boundaryErrorsSeconds), 0.5),
    },
    speakerLeakage: leakage,
    fillerGate: !sufficient ? 'insufficient_evidence' : precision !== null && precision >= 0.9 && recall >= 0.8 ? 'provisional_pass' : 'fail',
    warning: 'These engineering thresholds do not validate psychological or management-ability scores. Missing transcripts count as missed reference words/fillers.',
  };
}
