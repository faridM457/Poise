import { parseArgs } from 'node:util';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { runProcess } from './process.js';
import { decodeAudio } from './audio.js';
import { analyzeAcoustics } from './acoustics.js';
import { configuration } from './config.js';
import { buildAppleReport } from './apple-report.js';

const root = fileURLToPath(new URL('../', import.meta.url));
let directory;
try {
  const { values } = parseArgs({ options: {
    audio: { type: 'string' }, ffmpeg: { type: 'string' }, help: { type: 'boolean' },
  } });
  if (values.help) {
    console.log('Usage: npm run analyze:apple -- --audio /path/to/memo.m4a [--ffmpeg /path/to/ffmpeg]\nRequires macOS 26+, supported Apple hardware and full Xcode. First use may download Apple speech assets.\nJSON on stdout; progress on stderr. Exit 1: analysis/timing failure; 2: invalid invocation.');
  } else {
    if (!values.audio) throw new TypeError('Provide --audio /path/to/memo.m4a');
    if (process.platform !== 'darwin') throw new Error('Apple Speech requires macOS 26+ for this local runner');
    directory = await mkdtemp(path.join(tmpdir(), 'poise-apple-'));
    const config = configuration();
    // Honor explicit Xcode selection, otherwise use the standard installed app.
    const developer = process.env.DEVELOPER_DIR ?? '/Applications/Xcode.app/Contents/Developer';
    const swift = path.join(developer, 'Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc');
    const sdk = path.join(developer, 'Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk');
    const binary = path.join(directory, 'recorded-speech-check');
    process.stderr.write('Preparing audio and building the native Apple transcriber...\n');
    const { samples } = await decodeAudio(values.audio, directory, config, { ffmpegPath: values.ffmpeg });
    await runProcess(swift, ['-sdk', sdk, '-module-cache-path', path.join(directory, 'modules'), '-parse-as-library',
      path.join(root, 'apple/RecordedSpeechTranscriber.swift'), path.join(root, 'apple/RecordedSpeechCheck.swift'),
      '-o', binary], { timeoutMs: config.timeoutMs });
    process.stderr.write('Transcribing on device (Apple may download language assets on first use)...\n');
    const { stdout } = await runProcess(binary, [path.resolve(values.audio)], { timeoutMs: config.timeoutMs });
    const transcript = JSON.parse(stdout);
    const result = buildAppleReport(transcript, analyzeAcoustics(samples, config), config);
    process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
    process.stderr.write(`Observed um/uh: ${result.detectedFillerCount ?? 'unavailable'}; word timing: ${result.transcript.timingsValid ? 'PASS' : 'FAIL'}. Compare disfluencies with your recording.\n`);
    if (!result.transcript.timingsValid) process.exitCode = 1;
  }
} catch (error) {
  process.stderr.write(`${error.message}\n`);
  process.exitCode = error instanceof TypeError ? 2 : 1;
} finally {
  if (directory) await rm(directory, { recursive: true, force: true });
}
