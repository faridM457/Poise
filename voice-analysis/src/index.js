import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { configuration } from './config.js';
import { analyzeAcoustics } from './acoustics.js';
import { decodeAudio } from './audio.js';
import { transcribe } from './transcript.js';
import { aggregateReport, buildTurnReport } from './report.js';

export { analyzeAcoustics } from './acoustics.js';
export { parseWhisperJSON } from './transcript.js';
export { configuration } from './config.js';

export async function analyzeConversation(turns, options = {}) {
  const config = configuration(options.config);
  if (!Array.isArray(turns) || !turns.length || turns.length > config.maxTurns) {
    throw new TypeError(`Provide between 1 and ${config.maxTurns} recorded turns`);
  }
  const ids = new Set();
  for (const turn of turns) {
    if (!turn || typeof turn.id !== 'string' || !/^[\w-]{1,128}$/.test(turn.id) || ids.has(turn.id)) {
      throw new TypeError('Turn IDs must be unique, 1-128 letters, digits, underscores or hyphens');
    }
    if (typeof turn.file !== 'string' || !turn.file) throw new TypeError('Every turn requires a local file path');
    for (const key of ['interrupted', 'incomplete']) {
      if (turn[key] !== undefined && typeof turn[key] !== 'boolean') throw new TypeError(`${key} must be boolean`);
    }
    ids.add(turn.id);
  }
  const totalAcceptedTurnCount = options.totalAcceptedTurnCount ?? turns.length;
  if (!Number.isSafeInteger(totalAcceptedTurnCount) || totalAcceptedTurnCount < turns.length) {
    throw new TypeError('totalAcceptedTurnCount must include all recorded turns');
  }
  let durationUsed = 0;
  const reports = [];
  for (const turn of turns) {
    options.signal?.throwIfAborted();
    const directory = await mkdtemp(path.join(options.tempRoot ?? tmpdir(), 'poise-voice-'));
    const timeout = AbortSignal.timeout(config.timeoutMs);
    const signal = options.signal ? AbortSignal.any([options.signal, timeout]) : timeout;
    try {
      const remaining = config.maxConversationSeconds - durationUsed;
      if (remaining <= 0) throw new Error('Conversation audio duration limit reached');
      const { samples, wavPath } = await decodeAudio(turn.file, directory,
        { ...config, maxTurnSeconds: Math.min(config.maxTurnSeconds, remaining) }, { ...options, signal });
      durationUsed += samples.length / 16000;
      signal.throwIfAborted();
      const acoustic = analyzeAcoustics(samples, config);
      let transcript = { status: 'unavailable', text: null, words: [], timingsValid: false, reason: 'acoustics_only' };
      if (!options.acousticsOnly && !acoustic.flags.includes('low_signal')) {
        try {
          transcript = await transcribe(wavPath, directory, acoustic.duration, config, { ...options, signal });
        } catch (error) {
          options.signal?.throwIfAborted();
          transcript = { ...transcript, reason: 'transcription_failed', error: error.message };
        }
      } else if (!options.acousticsOnly) transcript.reason = 'low_signal';
      reports.push(buildTurnReport(turn.id, acoustic, transcript, config, {
        interrupted: turn.interrupted ?? false, incomplete: turn.incomplete ?? false,
      }));
    } catch (error) {
      options.signal?.throwIfAborted();
      reports.push({ id: turn.id, status: 'failed', error: { code: 'analysis_failed', message: error.message } });
    } finally {
      await rm(directory, { recursive: true, force: true });
    }
  }
  return aggregateReport(reports, config, { conversationId: options.conversationId, totalAcceptedTurnCount });
}
