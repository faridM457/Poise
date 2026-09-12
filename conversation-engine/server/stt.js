// Local speech-to-text test harness via whisper.cpp, run entirely on-device
// (no vendor API, no network call). This exists to answer one question: does
// whisper.cpp retain natural filler words ("um", "uh") that the browser's
// native SpeechRecognition strips out? See public/stt-test.js for the
// recording UI. Separate from server/tts.js's Deepgram-based NPC voice path.
//
// whisper.cpp itself isn't vendored into this repo -- it's built from source
// in a local scratchpad directory during development. Point
// WHISPER_CLI_PATH / WHISPER_MODELS_DIR at your own build to use this.
//
// Filler-word dropping is NOT a suppression flag we can just turn off --
// verified against whisper.cpp's own source (src/whisper.cpp): the only
// token-suppression mechanisms are --suppress-nst (off by default, and we
// don't set it), --suppress-regex (unset by default), and --suppress-blank
// (unrelated, just suppresses the empty-output token). None of those are
// active in our invocation. The dropping is a learned bias from Whisper's
// training data (caption-style transcripts that mostly omit disfluencies) --
// see https://github.com/openai/whisper/discussions/855. So the MODES below
// are decoding-strategy experiments, not a fix for a filter; they may not
// help, which is itself useful to learn.
import { spawn } from "node:child_process";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";

const WHISPER_CLI =
  process.env.WHISPER_CLI_PATH ||
  "/private/tmp/claude-501/-Users-sacchin-Documents-GitHub-manager-coach/1dd774f4-eda0-42a1-b178-e790f1730300/scratchpad/whisper.cpp/build/bin/whisper-cli";
const WHISPER_MODELS_DIR =
  process.env.WHISPER_MODELS_DIR ||
  "/private/tmp/claude-501/-Users-sacchin-Documents-GitHub-manager-coach/1dd774f4-eda0-42a1-b178-e790f1730300/scratchpad/whisper.cpp/models";

const MODELS = {
  tiny: path.join(WHISPER_MODELS_DIR, "ggml-tiny.en.bin"),
  base: path.join(WHISPER_MODELS_DIR, "ggml-base.en.bin"),
};

// Decoding-strategy experiments to A/B against the default. None of these
// disable a "filter" (there isn't one to disable) -- they change how the
// decoder searches, which is the only lever available against a learned bias.
const NATURAL_PRIME =
  "Um, let me think about that for a second. Uh, yeah, I think so. " +
  "Um, that's a good question, uh, let me get back to you on that.";

export const STT_MODES = {
  default: { label: "Default", args: [] },
  primed: {
    label: "Primed with a natural filler-heavy prompt",
    args: ["--prompt", NATURAL_PRIME],
  },
  sampling: {
    label: "Greedy off / sampling (best-of 1, beam 1, temp 0.6)",
    args: ["--best-of", "1", "--beam-size", "1", "--temperature", "0.6"],
  },
};

function runWhisper(modelPath, wavPath, extraArgs) {
  return new Promise((resolve, reject) => {
    const proc = spawn(WHISPER_CLI, [
      "-m",
      modelPath,
      "-f",
      wavPath,
      "--no-timestamps",
      "-np",
      ...extraArgs,
    ]);

    let stdout = "";
    let stderr = "";
    proc.stdout.on("data", (chunk) => (stdout += chunk));
    proc.stderr.on("data", (chunk) => (stderr += chunk));

    proc.on("error", reject);
    proc.on("close", (code) => {
      if (code !== 0) {
        reject(new Error(`whisper-cli exited ${code}: ${stderr.trim().slice(-500)}`));
        return;
      }
      resolve(stdout.trim());
    });
  });
}

/**
 * Transcribes a 16kHz mono 16-bit PCM WAV buffer with both tiny.en and
 * base.en, so the two can be compared side by side. `mode` selects a
 * decoding-strategy experiment from STT_MODES (default: "default").
 */
export async function transcribeWithWhisper(wavBuffer, mode = "default") {
  const modeConfig = STT_MODES[mode] || STT_MODES.default;
  const dir = await mkdtemp(path.join(tmpdir(), "stt-test-"));
  const wavPath = path.join(dir, "clip.wav");
  try {
    await writeFile(wavPath, wavBuffer);

    const [tiny, base] = await Promise.all([
      runWhisper(MODELS.tiny, wavPath, modeConfig.args),
      runWhisper(MODELS.base, wavPath, modeConfig.args),
    ]);

    return { tiny, base };
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}
