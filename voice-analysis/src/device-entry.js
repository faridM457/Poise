import { analyzeAcoustics } from './acoustics.js';
import { buildAppleReport } from './apple-report.js';
import { scoreVoiceMetrics } from './scoring.js';
import { configuration } from './config.js';

export function analyze(samples, transcriptJSON) {
  const config = configuration();
  const acoustic = analyzeAcoustics(new Float32Array(samples), config);
  if (transcriptJSON === null) {
    return JSON.stringify({ analysisVersion: 'device-acoustics-1', overallVoiceScore: null,
      ...acoustic, scoring: scoreVoiceMetrics(acoustic.metrics, config) }, null, 2);
  }
  const report = buildAppleReport(JSON.parse(transcriptJSON), acoustic, config);
  report.execution = { runtime: 'on_device', audioDecoder: 'AVFoundation', signalProcessing: 'JavaScriptCore',
    pitchDetector: 'Pitchy 4.1.0', scoringVersion: report.scoring.version };
  return JSON.stringify(report, null, 2);
}

export function score(metricsJSON) {
  return JSON.stringify(scoreVoiceMetrics(JSON.parse(metricsJSON)));
}
