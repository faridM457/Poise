# On-device voice analysis

The local Swift package `PoiseVoiceAnalysis` accepts a finished audio file and
returns an in-memory JSON report. It targets iOS 26+ and macOS 26+. App microphone
capture, persistence, UI, uploads, and LLM requests are deliberately not connected.
No existing app project or source file is modified.

For the local, validated transcript/statistics handoff to future LLM feedback,
see [LLM_PAYLOAD.md](LLM_PAYLOAD.md). No sending or persistence is implemented.

## Execution

- AVFoundation reads/resamples mono or stereo audio to mono 16 kHz PCM.
- SpeechAnalyzer/SpeechTranscriber supplies the transcript and word timestamps.
- Apple's JavaScriptCore executes bundled Pitchy 4.1.0, fft.js 4.0.4, and the same
  pure acoustic/report/scoring functions as the reference Node pipeline.
- Swift returns the complete report as `VoiceAnalysisReport.json` (`Data`).

This is **on-device execution, not an all-Swift algorithm rewrite**. JavaScriptCore
is an Apple framework embedded in the process, not Node, WebView, a server, or a
downloaded runtime. The script is a package resource; no script is fetched at
runtime and no network/native bridges are exposed to it. Node/esbuild are only
development tools for regenerating that resource. The Swift package builds and
runs without npm, Node, FFmpeg, Whisper, or external Swift package dependencies.
Bundled dependency licenses are retained in Resources/ThirdPartyLicenses.txt.

Apple may download system speech assets on first use. Analysis and audio stay on
the device; this package does not upload anything. Unsupported hardware/locales
fail explicitly. Fillers remain observed counts, not a guaranteed verbatim count.

## Future app hookup

Add this directory as a local Swift package and link `PoiseVoiceAnalysis` when the
team is ready to integrate. The library product excludes the macOS test runner.

```swift
import PoiseVoiceAnalysis

let analyzer = OnDeviceVoiceAnalyzer()
let report = try await analyzer.analyze(fileURL: finalizedRecordingURL)
// report.json contains transcript, metrics, evidence, scoring, and reliability.
```

Reuse one analyzer; concurrent requests on that instance fail explicitly.
The caller supplies a finalized local file that will not change during analysis
and holds security-scoped file access, if applicable, until the call returns.
The caller owns the original recording and any future report persistence.
No microphone permission, recording, speech playback, or audio-session ownership
is involved. Work runs off the main actor. Files are not rewritten or deleted.

Limits: 16 MiB/file, 90 seconds, one or two channels. Bounds are checked before
speech work. Cancellation propagates to transcription and between decode buffers;
the synchronous JavaScript calculation cannot be interrupted mid-loop and its
result is discarded if cancelled. There is currently no native wall-clock timeout
for model installation/transcription (the reference report config's `timeoutMs`
belongs to the Node runner, not this Swift API). Speech/model errors throw; invalid
word timing returns an explicit failed report. The caller should inspect report
status and metric reasons, not treat every returned JSON object as success.

## Run a Voice Memo locally

From this directory, with full Xcode installed:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun swift run voice-analyze-native "$HOME/Downloads/voice-test-new.m4a"
```

Append `--acoustics-only` to skip Speech entirely. JSON prints to stdout; no report
file is saved. This is a macOS harness of the same library intended for the iPhone.
It is not evidence of runtime testing on a physical iPhone.

## Development and verification

```sh
npm ci
npm run build:device
npm test
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
```

Regenerate the resource after changes to shared JavaScript; the bundle freshness
test fails if the shipped resource is stale. Keep the bundle and license resource
with the package when sharing it. Native tests exercise JavaScriptCore pitch on
100/220/440 Hz tones, silence gates, scoring, report assembly, and AVFoundation
48 kHz stereo resampling. The shared JS tests cover remaining algorithm rules.

Verified September 22, 2026: library builds against the arm64 iOS 26 SDK target;
native tests run on macOS. The 36.52-second memo completed in 9.20 seconds using a
debug macOS build (182 MB maximum resident set size reported by `time -l`, excluding
Apple's external speech-model process). It returned three fillers, valid word
timing, ~190.8 WPM, ~108 Hz median pitch, ~5.34 semitones spread, and 90.2 provisional
score. No physical iPhone latency, memory, or background-lifecycle test yet.

AVFoundation decoding differs slightly from FFmpeg, particularly AAC priming and
resampling. This memo's decoded length changed from 36.565 to 36.521 seconds;
energy-based gaps and levels changed modestly, while transcript timing and score
were unchanged. Execution metadata identifies the decoder/runtime. Do not claim
bit-for-bit parity across decoders or silently compare decoder-sensitive metrics
without accounting for this difference.
