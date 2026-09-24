# Standalone voice analysis

**End-of-conversation handoff:**
[VOICE_ANALYSIS_LLM_INTEGRATION.md](VOICE_ANALYSIS_LLM_INTEGRATION.md) documents
ordered dialogue, per-turn data, time-weighted aggregates, and explicit coverage.
This assembly is on-device and makes no LLM calls or new conversation score.

**On-device package:** see [ON_DEVICE.md](ON_DEVICE.md). The Swift library now runs
decoding, Apple transcription, Pitchy measurements, and scoring entirely on device
using AVFoundation, Speech, and JavaScriptCore. Microphone hookup and storage are
still deferred. The Node commands below remain local reference/testing tools.

## Apple transcription path (new)

Run a Voice Memo through Apple SpeechAnalyzer/SpeechTranscriber plus the existing
Pitchy acoustic analysis:

```sh
cd /Users/kaustubhmaheshwari/Poise/voice-analysis
npm run analyze:apple -- --audio "$HOME/Downloads/voice-test.m4a"
```

For a new memo, change the filename. Requires macOS 26+, supported Apple hardware,
full Xcode at `/Applications/Xcode.app` (or set `DEVELOPER_DIR`), Node 22.13+,
installed npm dependencies, and FFmpeg for M4A. Apple may download language assets
on first use; transcription itself runs on device. Run from normal Terminal:
restricted sandboxes can prevent Apple's model service from reporting locales.
Each native stage has a 180-second timeout; a slow first model download may need
a retry. Recordings must be nonempty, at most 90 seconds and 16 MiB.

Output includes untouched Apple transcript text, word start/end seconds, observed
um/uh count and timed evidence, timestamp-based pace and inter-word gaps, and the
existing energy/pitch/level metrics. Pitch gates are unchanged; unavailable pitch
stays null. `overallVoiceScore` stays null when a required scoring category is
unavailable; otherwise it is a provisional delivery score (see below).
Missing/invalid timing fails explicitly
(exit 1), without fabricated timing or automatic Whisper fallback. A partial
acoustic result is not a transcription failure. A successful exit does not certify
filler completeness or timing accuracy. Compare the text against your recording,
including deliberate um, uh, repetitions, and false starts. No verbatim toggle is
exposed by Apple's API. False starts remain raw transcript text, not scored events.

All new code lives here. `apple/RecordedSpeechTranscriber.swift` is the reusable
iOS 26+/macOS 26+ service, with no Node dependency. `RecordedSpeechCheck.swift` is
only its local test entry point. The Node runner combines this service's output
with the existing Pitchy code for local evaluation; it is not an iPhone runtime
architecture. No app capture/UI files are changed. Native acoustic integration
is now available through the Swift package; app wiring remains future work.
No recordings or reports are saved;
temporary binaries and converted audio are cleaned up. Original audio is untouched.

Use `npm --silent run analyze:apple -- --audio ...` for JSON-only stdout.
Progress goes to stderr. The original `npm run analyze -- ...` Whisper command and
its implementation are unchanged; the sections below describe that original path.

### Deterministic scoring (Apple report version 2)

`scoreVoiceMetrics(metrics, configOverrides?)` in `src/scoring.js` is pure and
returns `categories`, `overallVoiceScore`, reliability, reasons, coverage, and
structured `feedback`. The Apple runner exposes this under `scoring`; the existing
Whisper implementation is unchanged. No network or LLM is involved in scoring.

All sub-scores use 0-100. Define the band curve B(x; a,b,c,d) as 0 at/beyond
the outer bounds a,d, 100 within [b,c], linear from 0 to 100 between a,b, and
linear from 100 to 0 between c,d:

| Category | Sub-score | Weight |
| --- | --- | --- |
| Pace p (words/minute) | B(p; 60,120,180,260) | 45% |
| Pitch range s (semitones, P90-P10) | B(s; 0,3,8,16) | 35% |
| Observed um/uh rate r (per 100 lexical words) | 100 / (1 + (r/6)^2) | 20% |

Overall = 0.45 * pace + 0.35 * pitch + 0.20 * fillers. Compute on unrounded
sub-scores, then round display scores and overall to one decimal. These are
explicit **product hypotheses**, not research-backed ideal ranges or a validated
measure of empathy, confidence, emotion, or management ability. Pace has the most
weight as a delivery constraint for a listener processing a difficult message;
pitch is secondary, and fillers get the least weight because missed fillers can
inflate their score. No correction factor guesses the number of omitted fillers.
The filler curve is gradual (0,3,6,12 -> 100,80,50,20). Feedback uses a provisional
0-2 observed-fillers target, but the scoring curve has no hard cutoff there.
Pitch range cannot establish that delivery was erratic or flat throughout a clip.

**Missing policy: require all.** Any positive-weight category with unavailable,
missing, invalid, or nonfinite input makes the composite null, preserving comparable
meaning across recordings instead of silently changing the weighting. Other valid
sub-scores and feedback remain. Pitch also requires coverage >= configured minimum
(default 20%) and reliable pitch >= configured minimum (default 3 seconds).
Frame clarity >=0.9 is enforced by the acoustic extractor, not reconstructible
from a summary metric. The scorer trusts its metric statuses and never overrides
an upstream rejection. Pace sample-length gates are similarly enforced upstream.

Experimental inputs count at their stated weight. Output lists experimental and
missing categories, each category's source reason, and `weightCoverage` (fraction
of configured weight with usable inputs, **not** a probability of correctness).
Filler reliability is always experimental. Every emitted delivery composite is
also experimental because the scoring policy itself has not been validated.
Unavailable categories generate no feedback; feedback preserves the triggering
number/unit and uses cautious, observed-value language.

`combineCategories([{name, score, weight, reliability, reasons}, ...])` is generic:
it normalizes positive weights by their sum, ignores zero-weight entries, and
applies the same completeness checks to any number of categories. A future
independently computed category can be appended to this list and combined without
changing the combiner. Select its weight explicitly (and retune existing weights
if needed); do not interpret an external category's self-reported confidence as
calibrated reliability. No such category or provider is implemented here.

Examples with adequate pitch coverage/duration:
- 150 WPM, 5 semitones, 3 fillers/100 words -> pace 100, pitch 100, fillers 80;
  overall 96.0, experimental.
- Same inputs but unavailable pitch -> pitch null, overall null;
  weight coverage 65%; pace/filler feedback remains.
- 220 WPM, 12 semitones, 12 fillers/100 words -> pace 50, pitch 50, fillers 20;
  overall 44.0, experimental.

This package analyzes local user-turn recordings. It does not modify or import
the Swift app, existing Express server, RevenueCat integration, or lesson grading.
It makes no network requests and calls no paid API. It does not download models.

**Status:** working standalone implementation with synthetic/adapter tests.
Real iPhone recordings and real whisper.cpp inference still require evaluation.
This is not a validated confidence, emotion, or management-ability assessment.

## Setup

Use Node 22.13+ (or a newer supported Node release), then from this directory:

```sh
npm ci
npm test
node src/cli.js --help
```

Dependencies are isolated in this directory: Pitchy 4.1.0 and wavefile 11.0.0.
The root and conversation-engine dependency files are untouched.

For a mono, 16 kHz, signed PCM16 WAV, acoustic analysis needs no external binary:

```sh
node src/cli.js --audio /absolute/path/turn.wav --acoustics-only
```

For CAF, M4A, WebM, stereo WAV, or other sample rates, install FFmpeg separately
and supply `--ffmpeg /absolute/path/ffmpeg` or `FFMPEG_PATH`. Conversion downmixes
to mono; separately recorded channels and phase-inverted stereo are not supported
for accurate interpretation. Prefer native mono user-only recordings.

For transcription, install a tested [whisper.cpp](https://github.com/ggml-org/whisper.cpp)
build and download an English `base.en` model separately. Record their revisions
and the model checksum in your deployment configuration. No developer-specific
scratchpad path is assumed.

```sh
node src/cli.js --audio /absolute/path/turn.caf \
  --ffmpeg /absolute/path/ffmpeg \
  --whisper /absolute/path/whisper-cli \
  --model /absolute/path/ggml-base.en.bin
```

Alternatively set `WHISPER_CLI_PATH` and `WHISPER_MODEL_PATH`. The adapter uses
`-ojf -ml 1 -sow -tp 0 -tpi 0 -np` and English transcription. A binary without
these options returns a transcription failure, not fabricated text. Test a pinned
binary/model combination before deployment; `small.en` is an evaluation candidate,
not an automatic upgrade. Priming/sampling is deliberately not enabled.

Process turns together using `examples/conversation.json` as the contract:

```sh
node src/cli.js --manifest /absolute/path/conversation.json --acoustics-only
```

Manifest paths are relative to the manifest file. Only provide committed/accepted
user turns. `totalAcceptedTurnCount` includes typed-only turns, which have no audio
entry. Mark interrupted or incomplete captures explicitly. Per-turn IDs must be
unique ASCII letters, digits, underscores or hyphens (1-128 characters).

The CLI prints only JSON to stdout, diagnostics to stderr. Exit 0 means all audio
files were decoded; it does not mean all metrics are reliable. Exit 1 means an
audio/required-transcription stage failed (a partial report is still printed).
Exit 2 means an invalid invocation or manifest. Use `npm --silent run analyze --`
instead of plain `npm run analyze --` if redirecting stdout to a JSON report.

## Library contract

```js
import { analyzeConversation } from './voice-analysis/src/index.js';

const report = await analyzeConversation([
  { id: 'turn-1', file: '/private/path/user-turn.wav', interrupted: false },
], {
  conversationId: 'practice-uuid',
  totalAcceptedTurnCount: 2,
  whisperPath: '/path/to/whisper-cli',
  modelPath: '/path/to/ggml-base.en.bin',
  // acousticsOnly: true,
  config: { insightsEnabled: false },
  // signal: abortController.signal,
});
```

Options are local, trusted configuration. Never expose arbitrary file paths,
executable paths, or configuration directly to an untrusted HTTP client. The pure
`analyzeAcoustics(samples, config)` entry point requires a mono 16 kHz Float32Array
normalized to [-1, 1]; it does not infer or resample an arbitrary sample rate.

Output contains `schemaVersion`, `analysisVersion`, configuration, conversation ID,
coverage, aggregate metrics, and per-turn transcripts/metrics/evidence/insights.
Each metric has `{value, unit, status, reason}`. Missing values are `null`, never
zero. Evidence times are seconds relative to the original turn. `overallVoiceScore`
is always `null`. Internal frame arrays are not exported in conversation JSON.
Typed-only and failed turns are reflected in coverage; do not present a partial
report as covering the whole conversation.

## Measurements

- **Activity:** 25 ms RMS frames with 10 ms hops. Noise proxy is P10(level), upper
  level P90. Enter activity above max(-60, noise+10) dBFS; exit below
  max(-63, noise+6), after 100 ms persistence. Activity is energy-based, not a
  trained speech detector. Less than 15 dB separation, upper level below -45 dBFS,
  more than 1% near-full-scale samples, or no detected activity suppresses activity
  interpretation. Continuous speech without enough quiet may be unavailable.
- **Pauses:** internal inactive gaps of at least 300 ms. Leading/trailing quiet and
  between-turn waits are excluded. Ratio = total internal pause seconds / response
  span. Noise can obscure gaps; music can look active. These are experimental quiet
  gaps, not evidence that the person paused poorly.
- **Pace:** 60 * recognized lexical words / response-span seconds. Exclude standalone
  um/uh, punctuation and special tokens; retain repeated words and contractions.
  Numbers count as lexical tokens (normalization such as "twenty one" -> "21" can
  bias counts). Require 20 words and 10 seconds. Gross timestamp/activity disagreement
  suppresses pace. Aggregate counts/durations, never unweighted per-turn rates.
- **Pitch:** Pitchy's McLeod method, 1024-sample (64 ms) windows, 10 ms hops. Accept
  activity-region estimates with clarity >=0.9 and 60-500 Hz. Reject isolated jumps
  >9 semitones only when surrounding estimates agree within 3 semitones. No octave
  correction and no interpolation through unvoiced regions. Require three seconds
  of valid frame hops and 20% active-frame coverage. Overlapping windows are not
  counted as 64 ms of independent speech each.
- **Pitch range:** for valid f, p = 12*log2(f/median(f)); report P90(p)-P10(p).
  Conversation aggregation centers each turn on its own median, then pools equally
  spaced valid frames. A naturally high/low voice is not penalized. Pitchy clarity
  measures periodicity, not speaker confidence or calibrated statistical certainty.
- **Level:** dBFS = 20*log10(max(RMS, 1e-8)); 200 ms median smoothing within active
  intervals, P90-P10 spread. Center each turn's distribution before aggregation.
  This is recorded amplitude, not physical loudness. AGC, mic movement, and routes
  can dominate it. No normalization/denoising/silence removal is applied.
- **Fillers:** observed standalone um/uh events per 100 lexical words. Whisper can
  omit or invent disfluencies. A zero detected count is not evidence of zero actual
  fillers. No automatic scoring of "like", repetitions, false starts or stuttering.

All thresholds live in `src/config.js`. Coaching observations are **off by default**.
`--insights` enables provisional rules: pace outside 100-180 WPM; a quiet gap >=1 s;
two adjacent five-second pitch windows each spanning <2 semitones with >=1.5 s valid
pitch; or adjacent one-second level windows with >=0.7 s activity differing by >=6 dB.
At most two observations are emitted per turn, prioritized after recording quality.
These are testable product hypotheses, not scientifically established ideals.

## Evaluation on real recordings

Collect 20-30 consented clips across at least four speakers and actual target devices.
Include noise, quiet speech, fast speech, hesitations, repeated words, changing mic
distance and interruptions. Keep speakers separate between calibration and held-out
splits. Hand-label reference words including fillers and internal pauses >=500 ms.
Use `examples/labels.json` for the structure; its example text is NOT evaluation data.

```sh
node scripts/evaluate.js --report /path/to/report.json --labels /path/to/labels.json
```

The evaluator reports word-count error, WER, word-aligned filler precision/recall,
pause precision/recall (one-to-one matching within 200 ms on both boundaries), and
matched-pause boundary error. Missing transcripts count as missed words/fillers,
not as successful cases to drop. It detects cross-split speaker leakage.

A provisional filler gate requires >=20 labeled clips, >=4 speakers, >=8 held-out
clips from >=2 held-out speakers, >=20 held-out reference fillers, no speaker leakage,
precision >=90% and recall >=80%. That is still a small experiment, not population
validation. Pace target: <=10% word-count error on suitable clean clips. Examine
pause misses/false positives as well as timing of matched pauses. Listen to every
proposed insight before enabling coaching in a release.

`npm test` uses generated synthetic audio and an explicitly fake Whisper executable
to verify adapter behavior. It does not demonstrate real ASR accuracy. Real binaries,
model revision, phone recordings, cold/warm latency and memory usage must be evaluated
separately. No paid Bedrock or RevenueCat calls are needed for these tests.

## Bounds, privacy, and later integration

Default bounds: 16 MiB per input, 90 s per turn, 300 s per conversation, 20 turns,
180 s per turn timeout. Native processes use argument arrays (no shell), bounded
stdout/stderr, and cancellation. Audio is copied into private temporary directories;
derived files are deleted in `finally`, including failures/cancellation. Original
input files are never modified or deleted. The caller owns original-file/report
retention. Returned transcripts and error details can be sensitive; do not log them
by default. Decode protocols are restricted to local file/pipe access; this is not
a hardened public upload service or native-code sandbox.

Analysis is sequential. Acoustic computation runs synchronously in the calling
process and can block its event loop; put this package in a worker process/thread
when integrating a server. Cancellation is checked between stages and kills active
native processes; it cannot interrupt a synchronous JavaScript frame loop mid-call.
There is no HTTP server, upload endpoint, durable queue, account authentication,
RevenueCat gating, Swift capture change, or progress persistence in this package.

The future integration PR should capture from the existing SpeechRecognitionService
tap, finalize before NPC playback, assign stable run/turn IDs, authorize uploads,
run bounded durable jobs, and persist versioned results against SessionRecord IDs.
Keep Apple STT for live dialogue. Use HTTPS, verified ownership, clear audio-upload
disclosures and a deletion policy. A paid API is unnecessary, but production hosting
of Whisper/FFmpeg consumes real resources. These integration/release concerns are
deliberately outside this standalone branch's feature scope.
