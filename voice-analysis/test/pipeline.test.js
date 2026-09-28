import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, readdir, readFile, rm, mkdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { analyzeConversation } from '../src/index.js';
import { parseCanonicalWav } from '../src/audio.js';
import { runProcess } from '../src/process.js';
import { wavBytes, signal } from './helpers.js';

async function workspace(t) {
  const dir = await mkdtemp(path.join(tmpdir(), 'voice-test-'));
  t.after(() => rm(dir, { recursive: true, force: true }));
  const temporary = path.join(dir, 'temporary');
  await mkdir(temporary);
  const audio = path.join(dir, 'clip with spaces.wav');
  await writeFile(audio, wavBytes(signal()));
  return { dir, temporary, audio };
}

test('canonical PCM16 WAV path works without FFmpeg or Whisper and cleans up', async (t) => {
  const { temporary, audio } = await workspace(t);
  const report = await analyzeConversation([{ id: 'one', file: audio }], {
    acousticsOnly: true, ffmpegPath: '/does/not/exist', tempRoot: temporary, totalAcceptedTurnCount: 2,
  });
  assert.equal(report.status, 'partial');
  assert.equal(report.coverage.decodedTurnCount, 1);
  assert.equal(report.coverage.totalAcceptedTurnCount, 2);
  assert.ok(Math.abs(report.turns[0].metrics.medianPitchHz.value - 220) < 2);
  assert.equal(report.turns[0].transcript.reason, 'acoustics_only');
  assert.deepEqual(await readdir(temporary), []);
  assert.ok((await readFile(audio)).length > 100);
});

test('a failed input does not discard another turn', async (t) => {
  const { temporary, audio, dir } = await workspace(t);
  const report = await analyzeConversation([{ id: 'bad', file: path.join(dir, 'missing') }, { id: 'good', file: audio }], {
    acousticsOnly: true, tempRoot: temporary,
  });
  assert.equal(report.turns[0].status, 'failed');
  assert.equal(report.coverage.decodedTurnCount, 1);
  assert.deepEqual(await readdir(temporary), []);
});

test('Whisper failure leaves acoustic measurements available', async (t) => {
  const { temporary, audio } = await workspace(t);
  const report = await analyzeConversation([{ id: 'one', file: audio }], {
    whisperPath: '/missing/whisper', modelPath: audio, tempRoot: temporary,
  });
  assert.equal(report.turns[0].transcript.reason, 'transcription_failed');
  assert.ok(report.metrics.pitchRangeSemitones.value !== null);
  assert.deepEqual(await readdir(temporary), []);
});

test('Whisper adapter arguments and JSON round trip with an explicit executable fixture', async (t) => {
  const { temporary, audio, dir } = await workspace(t);
  const executable = path.join(dir, 'fixture-whisper');
  await writeFile(executable, `#!/usr/bin/env node
import {writeFileSync} from 'node:fs';
const args = process.argv.slice(2);
if (!args.includes('-ojf') || !args.includes('-sow') || args.includes('--no-timestamps')) process.exit(3);
const prefix = args[args.indexOf('-of') + 1];
writeFileSync(prefix + '.json', JSON.stringify({transcription:[{text:' Um hello.',tokens:[{text:' Um',offsets:{from:1000,to:1200}},{text:' hello',offsets:{from:1300,to:1600}}]}]}));
`, { mode: 0o700 });
  const report = await analyzeConversation([{ id: 'one', file: audio }], {
    whisperPath: executable, modelPath: audio, tempRoot: temporary,
  });
  assert.equal(report.turns[0].transcript.source, 'whisper.cpp');
  assert.equal(report.turns[0].detectedFillerCount, 1);
  assert.equal(report.turns[0].transcript.words[0].start, 1);
  assert.deepEqual(await readdir(temporary), []);
});

test('input contracts and duration limits are enforced', async (t) => {
  const { audio, temporary } = await workspace(t);
  await assert.rejects(analyzeConversation([{ id: 'x', file: audio }, { id: 'x', file: audio }]), /unique/);
  await assert.rejects(analyzeConversation([{ id: 'x', file: audio }], { totalAcceptedTurnCount: 0 }), /include/);
  const report = await analyzeConversation([{ id: 'x', file: audio }], {
    acousticsOnly: true, tempRoot: temporary, config: { maxInputBytes: 10 },
  });
  assert.equal(report.status, 'unavailable');
  assert.deepEqual(await readdir(temporary), []);
  assert.throws(() => parseCanonicalWav(wavBytes(signal()), 1), /duration/);
});

test('CLI emits JSON and respects manifest-relative paths', async (t) => {
  const { dir, audio } = await workspace(t);
  const manifest = path.join(dir, 'manifest.json');
  await writeFile(manifest, JSON.stringify({ turns: [{ id: 'one', file: path.basename(audio) }] }));
  const cli = path.resolve('src/cli.js');
  const result = await runProcess(process.execPath, [cli, '--manifest', manifest, '--acoustics-only']);
  const report = JSON.parse(result.stdout);
  assert.equal(report.turns[0].id, 'one');
  assert.equal(report.coverage.decodedTurnCount, 1);
});

test('process execution times out, bounds output, and reports missing executables', async () => {
  await assert.rejects(runProcess(process.execPath, ['-e', 'setInterval(()=>{},1000)'], { timeoutMs: 50 }), /timed out/);
  await assert.rejects(runProcess(process.execPath, ['-e', 'process.stdout.write("x".repeat(10000))'], { maxOutputBytes: 100 }), /safety limit/);
  await assert.rejects(runProcess('/missing/executable', []), /ENOENT/);
});

test('explicit cancellation rejects instead of quietly reporting success', async () => {
  const controller = new AbortController();
  const pending = runProcess(process.execPath, ['-e', 'setInterval(()=>{},1000)'], { signal: controller.signal });
  controller.abort(new Error('user cancelled'));
  await assert.rejects(pending, /user cancelled/);
  await assert.rejects(analyzeConversation([{ id: 'one', file: 'unused.wav' }], { signal: controller.signal }), /user cancelled/);
});
