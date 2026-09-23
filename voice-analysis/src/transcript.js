import { readFile, stat } from 'node:fs/promises';
import path from 'node:path';
import { runProcess } from './process.js';

const lexicalPattern = /[A-Za-z0-9]+(?:['\u2019][A-Za-z]+|[.,][0-9]+)*/g;
export function lexicalWords(text) {
  return [...text.matchAll(lexicalPattern)].map((match) => match[0].toLowerCase().replaceAll('\u2019', "'"));
}

function timing(offsets, duration) {
  if (!offsets || !Number.isFinite(offsets.from) || !Number.isFinite(offsets.to)) return null;
  const start = offsets.from / 1000;
  const end = offsets.to / 1000;
  return start >= 0 && end > start && end <= duration + 0.02 ? { start, end: Math.min(end, duration) } : null;
}

export function parseWhisperJSON(json, duration) {
  if (!Number.isFinite(duration) || duration <= 0) throw new Error('Invalid audio duration');
  if (!json || !Array.isArray(json.transcription)) throw new Error('Invalid whisper.cpp JSON: transcription array missing');
  const words = [];
  const texts = [];
  for (const segment of json.transcription) {
    if (typeof segment.text !== 'string') throw new Error('Invalid whisper.cpp segment');
    if (/^\s*(?:\[[^\]]+\]|<\|[^|]+\|>)\s*$/.test(segment.text)) continue;
    texts.push(segment.text.trim());
    const expected = lexicalWords(segment.text);
    let parsed = [];
    if (Array.isArray(segment.tokens)) {
      let joined = '';
      const pieces = [];
      for (const token of segment.tokens) {
        if (typeof token.text !== 'string') throw new Error('Invalid Whisper token text');
        if (/^(<\|.*\|>|\[_.*_\])$/.test(token.text)) continue;
        const startChar = joined.length;
        joined += token.text;
        pieces.push({ startChar, endChar: joined.length, time: timing(token.offsets, duration) });
      }
      const matches = [...joined.matchAll(lexicalPattern)];
      parsed = matches.map((match) => {
        const overlap = pieces.filter((p) => p.startChar < match.index + match[0].length && p.endChar > match.index);
        // A token spanning multiple words cannot establish their boundaries.
        const sharedToken = overlap.some((p) => matches.filter((m) => p.startChar < m.index + m[0].length && p.endChar > m.index).length > 1);
        const valid = overlap.length > 0 && !sharedToken && overlap.every((p) => p.time);
        return {
          text: lexicalWords(match[0])[0],
          start: valid ? overlap[0].time.start : null,
          end: valid ? overlap.at(-1).time.end : null,
        };
      });
    }
    if (parsed.map((w) => w.text).join(' ') !== expected.join(' ')) {
      // Segment timing is safe as a word interval only for a single-word segment.
      const time = expected.length === 1 ? timing(segment.offsets, duration) : null;
      parsed = expected.map((text) => ({ text, start: time?.start ?? null, end: time?.end ?? null }));
    }
    words.push(...parsed);
  }
  let previousEnd = 0;
  let timingsValid = words.length > 0 && words.every((word) => {
    if (word.start === null || word.end === null || word.start < previousEnd || word.end <= word.start) return false;
    previousEnd = word.end;
    return true;
  });
  // Inconsistent timing must not become precise-looking evidence.
  if (!timingsValid) for (const word of words) { word.start = null; word.end = null; }
  return {
    status: 'available', text: texts.join(' '), words, timingsValid,
    warnings: [
      'whisper_may_omit_or_invent_disfluencies',
      ...(timingsValid ? ['approximate_word_timing'] : ['word_timing_unavailable']),
    ],
    source: 'whisper.cpp',
  };
}

export async function transcribe(wavPath, directory, duration, config, {
  whisperPath = process.env.WHISPER_CLI_PATH,
  modelPath = process.env.WHISPER_MODEL_PATH,
  signal,
} = {}) {
  if (!whisperPath || !modelPath) throw new Error('Set WHISPER_CLI_PATH and WHISPER_MODEL_PATH, or use --acoustics-only');
  const model = path.resolve(modelPath);
  if (!(await stat(model)).isFile()) throw new Error('Whisper model must be a local file');
  const outputPrefix = path.join(directory, 'transcript');
  await runProcess(whisperPath, [
    '-m', model, '-f', wavPath, '-l', 'en', '-ojf', '-of', outputPrefix,
    '-ml', '1', '-sow', '-tp', '0', '-tpi', '0', '-np',
  ], { timeoutMs: config.timeoutMs, signal });
  const outputPath = `${outputPrefix}.json`;
  if ((await stat(outputPath)).size > 8 * 1024 * 1024) throw new Error('Whisper JSON exceeded safety limit');
  return { ...parseWhisperJSON(JSON.parse(await readFile(outputPath, 'utf8')), duration), model: path.basename(model) };
}
