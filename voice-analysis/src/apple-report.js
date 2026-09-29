import { metric, unavailable } from './math.js';
import { scoreVoiceMetrics } from './scoring.js';

// Apple text is kept verbatim; normalization is only for counting lexical tokens.
const normalize = (text) => text.toLowerCase().replace(/^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$/gu, '');
const isFiller = (word) => ['um', 'uh', 'ah'].includes(normalize(word.text));

export function buildAppleReport(transcript, acoustic, config) {
  if (typeof transcript?.text !== 'string' || !transcript.text.trim() ||
      !Array.isArray(transcript.words) || !Array.isArray(transcript.timingIssues) ||
      !Number.isFinite(transcript.duration) || transcript.duration <= 0) {
    throw new Error('Invalid Apple transcription output');
  }
  const issues = [...transcript.timingIssues];
  let previousEnd = 0;
  for (const word of transcript.words) {
    if (!word || typeof word.text !== 'string' || !word.text.trim() || /\s/.test(word.text) ||
        !Number.isFinite(word.start) || !Number.isFinite(word.end) || word.start < 0 ||
        word.end <= word.start || word.end > transcript.duration + 0.05 || word.start < previousEnd - 0.001) {
      issues.push('invalid_word_timing');
    }
    previousEnd = word?.end;
  }
  if (!transcript.words.length) issues.push('word_timing_unavailable');
  const timingsValid = issues.length === 0;
  // Do not compute counts from the subset of words that survived a timing failure.
  const words = timingsValid ? transcript.words : [];
  const fillers = words.filter(isFiller);
  const lexicalWordCount = words.filter((word) => !isFiller(word)).length;
  const span = words.length ? words.at(-1).end - words[0].start : 0;
  const gaps = [];
  for (let i = 1; i < words.length; i++) {
    if (words[i].start - words[i - 1].end >= config.minPauseSeconds) {
      gaps.push({ start: words[i - 1].end, end: words[i].start });
    }
  }
  const enoughPace = timingsValid && lexicalWordCount >= config.minPaceWords && span >= config.minPaceSeconds;
  const missing = timingsValid ? 'insufficient_words_or_duration' : 'word_timing_unavailable';
  const report = {
    schemaVersion: 1, analysisVersion: 'apple-speech-2',
    status: !timingsValid ? 'failed' : Object.values(acoustic.metrics).some((m) => m.value === null) ? 'partial' : 'complete',
    overallVoiceScore: null,
    transcriptionEngine: 'Apple SpeechAnalyzer / SpeechTranscriber',
    durationSeconds: acoustic.duration,
    transcript: { ...transcript, timingIssues: issues, timingsValid, fillerPreservation: 'unvalidated' },
    lexicalWordCount: timingsValid ? lexicalWordCount : null,
    detectedFillerCount: timingsValid ? fillers.length : null,
    metrics: {
      ...acoustic.metrics,
      speakingRateWpm: enoughPace
        ? metric(60 * lexicalWordCount / span, 'words/minute', 'experimental', 'apple_word_timing_estimate')
        : unavailable('words/minute', missing),
      timestampGapRatio: timingsValid && span > 0
        ? metric(gaps.reduce((sum, gap) => sum + gap.end - gap.start, 0) / span, 'ratio', 'experimental', 'gaps_between_recognized_words')
        : unavailable('ratio', 'word_timing_unavailable'),
      detectedFillersPer100Words: timingsValid && lexicalWordCount > 0
        ? metric(100 * fillers.length / lexicalWordCount, 'events/100 words', 'experimental', 'filler_completeness_unvalidated')
        : unavailable('events/100 words', missing),
    },
    evidence: { fillers, timestampGaps: gaps, energyPauses: acoustic.pauses },
    flags: acoustic.flags,
    config,
    warnings: [
      'Observed fillers are not a verified complete count; compare with the recording.',
      'Word timestamps are model estimates; gaps can include unrecognized speech.',
      'Acoustic pause metrics still use energy detection. Pitch quality gates are unchanged.',
      'Delivery scores use provisional product targets, not validated measures of communication ability.',
    ],
  };
  report.scoring = scoreVoiceMetrics(report.metrics, config);
  report.overallVoiceScore = report.scoring.overallVoiceScore;
  if (timingsValid && Object.values(report.metrics).some((m) => m.status === 'unavailable')) report.status = 'partial';
  return report;
}
