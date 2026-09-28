import { stat, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import wavefile from 'wavefile';
import { SAMPLE_RATE } from './config.js';
import { runProcess } from './process.js';

const { WaveFile } = wavefile;

export function parseCanonicalWav(bytes, maxSeconds = 90) {
  const wav = new WaveFile(bytes);
  if (wav.fmt.numChannels !== 1 || wav.fmt.sampleRate !== SAMPLE_RATE || wav.bitDepth !== '16') {
    throw new Error('Expected mono 16000 Hz PCM16 WAV; use FFmpeg for other formats');
  }
  const integers = wav.getSamples(true, Float64Array);
  if (!integers.length || integers.length / SAMPLE_RATE > maxSeconds) {
    throw Object.assign(new Error('Recording is empty or exceeds the duration limit'), { code: 'AUDIO_DURATION_LIMIT' });
  }
  return Float32Array.from(integers, (sample) => sample / 32768);
}

export async function decodeAudio(file, directory, config, { ffmpegPath = process.env.FFMPEG_PATH ?? 'ffmpeg', signal } = {}) {
  const input = path.resolve(file);
  const info = await stat(input);
  if (!info.isFile() || !info.size || info.size > config.maxInputBytes) {
    throw new Error('Input must be a nonempty file within maxInputBytes');
  }
  const wavPath = path.join(directory, 'audio.wav');
  const bytes = await readFile(input);
  // Already-canonical WAVs can be tested without installing any native tools.
  try {
    const samples = parseCanonicalWav(bytes, config.maxTurnSeconds);
    await writeFile(wavPath, bytes, { mode: 0o600 });
    return { samples, wavPath };
  } catch (error) {
    if (error.code === 'AUDIO_DURATION_LIMIT') throw error;
    // All other formats go through the same bounded conversion path.
  }
  await runProcess(ffmpegPath, [
    '-nostdin', '-hide_banner', '-loglevel', 'error', '-y',
    '-protocol_whitelist', 'file,pipe', '-i', input,
    '-map', '0:a:0', '-vn', '-ac', '1', '-ar', String(SAMPLE_RATE),
    '-t', String(config.maxTurnSeconds + 1), '-c:a', 'pcm_s16le', wavPath,
  ], { timeoutMs: config.timeoutMs, signal });
  const output = await readFile(wavPath);
  const samples = parseCanonicalWav(output, config.maxTurnSeconds);
  return { samples, wavPath };
}
