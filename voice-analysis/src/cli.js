import { parseArgs } from 'node:util';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { analyzeConversation } from './index.js';

const help = `Local Poise voice analysis (no network or paid API calls)

Usage:
  npm run analyze -- --audio /path/to/turn.wav --acoustics-only
  npm run analyze -- --audio /path/to/turn.caf --whisper /path/to/whisper-cli --model /path/to/ggml-base.en.bin
  npm run analyze -- --manifest /path/to/conversation.json

Options:
  --audio PATH          One recording (may be repeated)
  --manifest PATH       JSON {conversationId?, totalAcceptedTurnCount?, turns:[{id,file,interrupted?,incomplete?}]}
  --acoustics-only      Skip transcription, return acoustic metrics
  --ffmpeg PATH         FFmpeg executable (default: ffmpeg)
  --whisper PATH        whisper.cpp executable (or WHISPER_CLI_PATH)
  --model PATH          Local model file (or WHISPER_MODEL_PATH)
  --insights            Enable provisional coaching observations (off by default)
  --help                Print this message

JSON goes to stdout. Exit 0: all turns decoded (individual metrics can be unavailable).
Exit 1: one or more turns failed, or requested transcription failed. Exit 2: invalid invocation.
Whisper and FFmpeg must be installed separately. Recordings and models are never downloaded.
`;

try {
  const { values, positionals } = parseArgs({ options: {
    audio: { type: 'string', multiple: true }, manifest: { type: 'string' },
    'acoustics-only': { type: 'boolean' }, ffmpeg: { type: 'string' },
    whisper: { type: 'string' }, model: { type: 'string' },
    insights: { type: 'boolean' }, help: { type: 'boolean' },
  }, allowPositionals: false });
  if (values.help) {
    process.stdout.write(help);
  } else {
    if (positionals.length || Boolean(values.audio) === Boolean(values.manifest)) throw new Error('Choose --audio or --manifest (not both)');
    let manifest;
    if (values.manifest) {
      manifest = JSON.parse(await readFile(values.manifest, 'utf8'));
      if (!manifest || !Array.isArray(manifest.turns)) throw new Error('Manifest requires turns');
      manifest.turns = manifest.turns.map((turn) => ({ ...turn,
        file: typeof turn.file === 'string' ? path.resolve(path.dirname(values.manifest), turn.file) : turn.file,
      }));
    } else manifest = { turns: values.audio.map((file, i) => ({ id: `turn-${i + 1}`, file })) };
    const result = await analyzeConversation(manifest.turns, {
      conversationId: manifest.conversationId,
      totalAcceptedTurnCount: manifest.totalAcceptedTurnCount,
      acousticsOnly: values['acoustics-only'] ?? false,
      ffmpegPath: values.ffmpeg,
      whisperPath: values.whisper ?? process.env.WHISPER_CLI_PATH,
      modelPath: values.model ?? process.env.WHISPER_MODEL_PATH,
      config: { insightsEnabled: values.insights ?? false },
    });
    process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
    if (result.turns.some((turn) => turn.status === 'failed' || turn.transcript?.reason === 'transcription_failed')) process.exitCode = 1;
  }
} catch (error) {
  process.stderr.write(`${error.message}\nRun with --help for usage.\n`);
  process.exitCode = 2;
}
