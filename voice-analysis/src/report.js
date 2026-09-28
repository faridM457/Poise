import { metric, spread, unavailable } from './math.js';
import { VERSION } from './config.js';

const isFiller = (word) => word.text === 'um' || word.text === 'uh';

export function buildTurnReport(id, acoustic, transcript, config, capture = {}) {
  const flags = [...acoustic.flags];
  const captureInvalid = capture.interrupted === true || capture.incomplete === true;
  if (captureInvalid) flags.push('incomplete_capture');
  const words = transcript.words ?? [];
  const wordCount = words.filter((w) => !isFiller(w)).length;
  const fillers = words.filter(isFiller);
  const span = acoustic.metrics.responseSeconds.value;
  let timingAgrees = true;
  if (transcript.timingsValid && acoustic.intervals.length && words.length) {
    const tolerance = Math.max(0.75, span * 0.25);
    timingAgrees = Math.abs(words[0].start - acoustic.intervals[0].start) <= tolerance &&
      Math.abs(words.at(-1).end - acoustic.intervals.at(-1).end) <= tolerance;
    if (!timingAgrees) flags.push('transcript_activity_mismatch');
  }
  const paceEligible = !captureInvalid && acoustic.activityReliable && timingAgrees &&
    transcript.status === 'available' && wordCount > 0;
  const enoughPace = paceEligible && wordCount >= config.minPaceWords && span >= config.minPaceSeconds;
  const metrics = { ...acoustic.metrics };
  if (captureInvalid) {
    for (const key of Object.keys(metrics)) {
      if (!['clippedFraction', 'pitchCoverage', 'reliablePitchSeconds'].includes(key)) {
        metrics[key] = unavailable(metrics[key].unit, 'incomplete_capture');
      }
    }
  }
  metrics.speakingRateWpm = enoughPace ? metric(60 * wordCount / span, 'words/minute', 'experimental', 'asr_and_energy_estimate')
    : unavailable('words/minute', paceEligible ? 'insufficient_words_or_duration' : 'unreliable_or_missing_input');
  metrics.detectedFillersPer100Words = !captureInvalid && transcript.status === 'available' && wordCount > 0
    ? metric(100 * fillers.length / wordCount, 'events/100 words', 'experimental', 'not_a_verbatim_transcript')
    : unavailable('events/100 words', 'unreliable_or_missing_transcript');
  const insights = [];
  const add = (code, message, interval = null) => insights.push({ code, message, turnId: id,
    startSeconds: interval?.start ?? null, endSeconds: interval?.end ?? null });
  if (flags.length) add('recording_quality', 'Some measurements are unavailable because this recording did not meet the analysis quality checks.');
  if (config.insightsEnabled && !captureInvalid) {
    const wpm = metrics.speakingRateWpm.value;
    if (wpm !== null && (wpm < 100 || wpm > 180)) {
      add('pace_observation', `Your estimated pace was ${Math.round(wpm)} words per minute. Try another take with a deliberate pause around your key request.`);
    }
    const longest = [...acoustic.pauses].sort((a, b) => (b.end - b.start) - (a.end - a.start))[0];
    if (longest && longest.end - longest.start >= 1) {
      add('quiet_gap', `A quiet gap lasted ${(longest.end - longest.start).toFixed(1)} seconds. Consider whether it gave the other person useful space.`, longest);
    }
    const windows = acoustic.evidence.pitchWindows;
    for (let i = 1; i < windows.length; i++) {
      const previous = windows[i - 1], current = windows[i];
      if (previous.end === current.start && previous.range < 2 && current.range < 2) {
        add('limited_pitch_change', 'Pitch changed little in this section. Try emphasizing the key request on your next attempt.', { start: previous.start, end: current.end });
        break;
      }
    }
    const volume = acoustic.evidence.volumeWindows;
    for (let i = 1; i < volume.length; i++) {
      const previous = volume[i - 1], current = volume[i];
      if (previous.end === current.start && Math.abs(current.db - previous.db) >= 6) {
        add('level_change', 'Recorded volume changed noticeably here. Microphone movement can also cause this.', { start: previous.start, end: current.end });
        break;
      }
    }
  }
  return {
    id, status: transcript.status !== 'available' || Object.values(metrics).some((m) => m.status === 'unavailable') ? 'partial' : 'complete',
    durationSeconds: acoustic.duration, capture, flags, transcript, metrics,
    lexicalWordCount: transcript.status === 'available' ? wordCount : null,
    detectedFillerCount: transcript.status === 'available' ? fillers.length : null,
    evidence: { pauses: captureInvalid ? [] : acoustic.pauses, fillers: captureInvalid ? [] : fillers.filter((w) => w.start !== null) },
    insights: insights.slice(0, 2),
    _aggregation: {
      paceWords: paceEligible ? wordCount : 0, paceSeconds: paceEligible ? span : 0,
      pauseSeconds: !captureInvalid && acoustic.activityReliable ? metrics.pauseSeconds.value : 0,
      activitySpan: !captureInvalid && acoustic.activityReliable ? span : 0,
      semitones: captureInvalid ? [] : acoustic.distributions.semitones,
      levels: captureInvalid ? [] : acoustic.distributions.levels,
      fillerWords: !captureInvalid && transcript.status === 'available' ? wordCount : 0,
      fillerCount: !captureInvalid && transcript.status === 'available' ? fillers.length : 0,
    },
  };
}

export function aggregateReport(turns, config, { conversationId = null, totalAcceptedTurnCount = turns.length } = {}) {
  const valid = turns.filter((turn) => turn._aggregation);
  const sum = (key) => valid.reduce((s, t) => s + t._aggregation[key], 0);
  const paceWords = sum('paceWords'), paceSeconds = sum('paceSeconds'), span = sum('activitySpan');
  const semitones = valid.flatMap((t) => t._aggregation.semitones);
  const levels = valid.flatMap((t) => t._aggregation.levels);
  const fillerWords = sum('fillerWords');
  const metrics = {
    speakingRateWpm: paceWords >= config.minPaceWords && paceSeconds >= config.minPaceSeconds
      ? metric(60 * paceWords / paceSeconds, 'words/minute', 'experimental', 'asr_and_energy_estimate')
      : unavailable('words/minute', 'insufficient_reliable_words_or_duration'),
    pauseRatio: span > 0 ? metric(sum('pauseSeconds') / span, 'ratio', 'experimental', 'energy_based_activity') : unavailable('ratio', 'no_reliable_activity'),
    pitchRangeSemitones: semitones.length ? metric(spread(semitones), 'semitones') : unavailable('semitones', 'no_reliable_pitch'),
    volumeSpreadDb: levels.length ? metric(spread(levels), 'dB', 'experimental', 'recorded_level_not_physical_loudness') : unavailable('dB', 'no_reliable_levels'),
    detectedFillersPer100Words: fillerWords > 0 ? metric(100 * sum('fillerCount') / fillerWords, 'events/100 words', 'experimental', 'not_a_verbatim_transcript') : unavailable('events/100 words', 'no_usable_transcript'),
  };
  return {
    schemaVersion: 1, analysisVersion: VERSION, conversationId,
    status: valid.length === 0 ? 'unavailable' : turns.every((t) => t.status === 'complete') && totalAcceptedTurnCount === turns.length ? 'complete' : 'partial',
    overallVoiceScore: null,
    config: { ...config },
    coverage: {
      recordedTurnCount: turns.length, totalAcceptedTurnCount,
      decodedTurnCount: valid.length,
      analyzedSeconds: valid.reduce((s, t) => s + t.durationSeconds, 0),
      paceSeconds, paceWordCount: paceWords,
      pitchTurnCount: valid.filter((t) => t._aggregation.semitones.length).length,
      activityTurnCount: valid.filter((t) => t._aggregation.activitySpan > 0).length,
    },
    metrics,
    turns: turns.map(({ _aggregation, ...turn }) => turn),
    warnings: ['Energy-based gaps are not validated speech detection.', 'Whisper is not guaranteed verbatim; detected fillers are not a complete count.', 'No voice-quality, confidence, or management-ability score is calculated.'],
  };
}
