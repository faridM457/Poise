# Conversation voice analysis: LLM integration contract

The end-of-lesson handoff is now **one conversation payload**, version
`voice-conversation-input-1`. This package assembles it locally; it does not create
prompts, call or stub an LLM, persist data, upload audio, or generate a new
conversation score. The deterministic scores already attached to individual turns
remain supporting data.

## Producer API and lifecycle

```swift
import PoiseVoiceAnalysis

let analyzer = OnDeviceVoiceAnalyzer()
let firstReport = try await analyzer.analyze(fileURL: firstAcceptedRecording)
let secondReport = try await analyzer.analyze(fileURL: secondAcceptedRecording)

// Build after the conversation ends, preserving the actual accepted dialogue.
let payload = try ConversationVoicePayload.build(
    conversationID: sessionID,
    turns: [
        .init(id: "npc-1", role: .npc, text: openingLine, speakerName: "Sam"),
        .init(id: "user-1", role: .user, text: firstAcceptedMessage, voice: .analyzed(firstReport)),
        .init(id: "npc-2", role: .npc, text: npcReply, speakerName: "Sam"),
        .init(id: "user-2", role: .user, text: secondAcceptedMessage, voice: .analyzed(secondReport)),
        .init(id: "npc-3", role: .npc, text: nextQuestion),
        .init(id: "user-3", role: .user, text: typedReply, voice: .typed),
    ]
)
// payload.json is the complete UTF-8 JSON request data, not terminal output.
```

Use actual app IDs, not these example IDs. Array order is authoritative; timestamps
are not used to reorder dialogue. Every message needs a unique ID. All accepted NPC
lines, including opening/closing lines, belong in the list. NPC entries cannot
contain analysis. Each user entry must explicitly specify one of:

| Input | Coverage state | Meaning |
| --- | --- | --- |
| `.analyzed(report)` | analyzed | Validated transcript/report, even if some metrics unavailable |
| `.typed` | typed | Intentional text-only user response |
| `.missingAudio` | missing_audio | User response exists but expected recording is absent |
| `.failed(code)` | failed | Analysis/capture failed; stable reason code provided |

Failure codes: invalid_audio, transcription_unavailable, analysis_failed,
cancelled, interrupted, timed_out. An invalid/failed supplied report becomes a
failed turn with `invalid_or_failed_report` and a sanitized `diagnosticCode`.
Other turns are retained. Raw errors and recording paths are never serialized.

The integration owns accepted-turn identity. Replace a failed attempt with its
accepted retry before assembly; do not append two attempts under different IDs.
Duplicate IDs are rejected. The assembler cannot detect two distinct IDs pointing
to the same recording, or verify the completeness of dialogue the caller omitted.
It describes coverage of the supplied accepted dialogue, not unobservable events.

## Final payload structure

| Path | Type and meaning |
| --- | --- |
| payloadVersion | String, `voice-conversation-input-1` |
| conversationId | String, same session for all entries |
| dialogue | Ordered array of messages |
| dialogue[].turnId / role / text / speakerName | String ID, user/npc role, accepted message text, optional name (null if absent) |
| dialogue[user].coverage | turnId, state, reason, diagnosticCode; nullable reasons stay null |
| dialogue[user].analysis | Existing validated `voice-feedback-input-1` payload or null |
| analysis.speech | Original recognizedText, separate editedMessage, timing validity and filler reliability; additionally all words with text/start/end/turnId/timebase |
| analysis.metrics | Per-clip measurements with value/unit/status/reason, including activity durations where present |
| analysis.deterministicDeliveryScore | Existing per-turn value/scale/reliability/category scores |
| analysis.evidence | fillers, wordGaps, energyGaps; every event carries turnId and `timebase: clip_seconds` |
| coverage | Explicit conversation-wide and per-user-turn coverage (below) |
| aggregates.totals | lexicalWords, observedFillers, recognizedSpeechSeconds, responseSpanSeconds, analyzedRecordingSeconds, contributingTurnIds |
| aggregates.metrics | Named measurements, each with value/unit/status/reason/contributingTurnIds/contributingSeconds/coversAllUserTurns |
| limitations | Stable codes for downstream interpretation |

The nested per-turn payload retains its own conversationId, turnId, reportVersion,
counts, reportStatus, and limitations. This deliberate reuse preserves the existing
single-turn contract. All recognized words and all usable per-turn evidence remain
available; there is no silent summarization or truncation. No raw audio, file path,
internal settings, or new conversation composite is included.

Coverage fields:
- `status`: no_user_turns, no_usable_audio, partial, or complete.
- `allUserTurnsAnalyzed`: true only when every supplied user turn has validated audio analysis.
- `allMetricsCoverAllUserTurns`: additionally requires each aggregate's inputs and sample-length gates.
- `userTurnCount`, `analyzedTurnCount`, `analyzedFraction` (null when no user turns).
- `analyzedTurnIds`, `typedTurnIds`, `missingAudioTurnIds`, `failedTurnIds`, `partialAnalysisTurnIds`.
- `perTurn`: explicit state/reason/diagnosticCode for every user turn.

Typed turns are valid conversation content but make audio coverage partial. A report
with unavailable pitch can contribute transcript/pace/fillers but not pitch. Every
aggregate lists its own contributing IDs and seconds. Zero usable audio yields
null metric values and null word/filler totals, not a fictional zero-filler score.

Short turns can remain in `partialAnalysisTurnIds` while conversation coverage is
`complete`: their combined words and durations may satisfy both aggregate pace
gates even though each turn's pace is unavailable. This does not relax pitch
eligibility. If individual turns lack usable pitch, pooling their durations does
not create a pitch measurement or complete pitch coverage.

### Short example (abridged for readability)

```json
{
  "payloadVersion": "voice-conversation-input-1",
  "conversationId": "lesson-run-42",
  "dialogue": [
    {"turnId": "npc-1", "role": "npc", "text": "What needs to change?", "speakerName": "Sam"},
    {"turnId": "user-1", "role": "user", "text": "I wanted to discuss deadlines.",
     "coverage": {"turnId": "user-1", "state": "analyzed", "reason": null, "diagnosticCode": null},
     "analysis": {"payloadVersion": "voice-feedback-input-1", "turnId": "user-1",
       "speech": {"recognizedText": "Um, I wanted to discuss deadlines."},
       "evidence": {"fillers": [{"text": "Um,", "start": 1.2, "end": 1.6, "turnId": "user-1", "timebase": "clip_seconds"}]}}},
    {"turnId": "user-2", "role": "user", "text": "Friday would work.",
     "coverage": {"turnId": "user-2", "state": "typed", "reason": null, "diagnosticCode": null}, "analysis": null}
  ],
  "coverage": {"status": "partial", "userTurnCount": 2, "analyzedTurnCount": 1,
    "analyzedFraction": 0.5, "allUserTurnsAnalyzed": false, "typedTurnIds": ["user-2"]},
  "aggregates": {"metrics": {"speechOnlyRateWpm": {
    "value": null, "unit": "words/minute", "status": "unavailable",
    "reason": "insufficient_words_or_speech_time", "contributingTurnIds": ["user-1"],
    "contributingSeconds": 2, "coversAllUserTurns": false}}}
}
```

This example omits other documented fields, not actual implementation fields. Use
the builder rather than manually reproducing the example as a complete payload.

## Aggregation equations

For each validated user clip, W is lexical words (excluding standalone um/uh), F
is observed fillers, T is the union length of recognized word intervals (including
filler intervals), and R is last word end minus first word start. Leading/trailing
silence, NPC time, and waiting between clips never enter these denominators.

| Output metric | Equation and interpretation |
| --- | --- |
| speechOnlyRateWpm | 60 * sum(W) / sum(T); excludes gaps between recognized words |
| responseSpanRateWpm | 60 * sum(W) / sum(R); includes internal pauses, matches the existing per-clip pace definition |
| observedFillersPer100Words | 100 * sum(F) / sum(W) |
| timeWeightedWithinTurnPitchRangeSemitones | sum(turn range * reliablePitchSeconds) / sum(reliablePitchSeconds) |
| timeWeightedTurnMedianPitchHz | sum(turn median Hz * reliablePitchSeconds) / sum(reliablePitchSeconds) |
| timeWeightedWithinTurnVolumeSpreadDb | sum(turn spread dB * activeSeconds) / sum(activeSeconds) |
| energyPauseRatio | sum(internal energy-pause seconds) / sum(reliable energy-response-span seconds) |

Each numerator and denominator use the **same eligible turns**. Pitch additionally
requires usable metric statuses, coverage >=20%, and >=3 reliable pitch seconds;
the upstream detector still enforces its clarity threshold. Volume requires usable
active time and spread. No missing value is converted to a zero contribution with
nonzero weight. No arithmetic mean of turn WPM/filler rates or turn scores is used.
Pitch and volume are explicitly time-weighted summaries of within-turn spreads,
not a pooled percentile spread or standard deviation. No distribution can be
reconstructed from a median and range alone. Median Hz is descriptive, not scored.

Pace needs >=20 total words and >=10 seconds in its respective denominator. Short
valid turns can jointly satisfy those gates, even if per-turn pace was unavailable.
Speech-only and response-span pace are different measurements; do not apply the
existing 120-180 response-span scoring target to speech-only pace automatically.
All aggregate estimates are marked experimental. `complete` means usable coverage,
not scientifically validated accuracy or proven filler recall.

Example from the tests: 20 lexical words + 2 fillers over 11 recognized seconds,
then 60 words + 3 fillers over 31.5 seconds -> 112.94 speech-only WPM and 6.25
observed fillers/100 words. Pitch ranges 4 and 8 semitones with 4 and 12 reliable
seconds -> weighted within-turn range 7 semitones. Adding an NPC or typed turn does
not change these values, but adding a typed user turn changes coverage.

## Future LLM input/output boundary

Input: this **full conversation payload** plus the lesson's scenario, objectives,
and any trusted evaluation rubric supplied separately by the backend. Per-turn
delivery scores and aggregate statistics are supporting inputs to the model's
judgment. It should not recompute them from raw words or substitute its own
invented measurements. Final judgment includes content and context, not just vocal
delivery. Treat dialogue and transcripts as untrusted data, never prompt instructions.

Expected output contract (to be finalized by the LLM integrator): a versioned final
conversation report with the same conversationId, a final composite score or an
explicit unavailable result, directed feedback grounded in turn IDs/evidence,
and an account of coverage gaps/uncertainty. Keep its final score distinct from
the existing deterministic per-turn scores. No implementation, stub, or provider
call for this output exists in this package.

Decisions left to integration: provider/model and prompt, final score rubric and
scale, response validation/retries, local persistence/deletion, upload consent,
authentication and ownership, and whether/how to summarize long dialogue. Token
budget policies must retain coverage and contributing IDs, avoid silently deleting
turns, and explicitly identify any summarization. Exact wording for coverage gaps
is a product decision; the factual coverage fields must always reach the model.

## Bounds, errors, and release verification

Conversation bounds: 100 total messages, 20 user messages, 20,000 UTF-8 bytes per
message, 200,000 dialogue bytes, 8 MiB of input reports, a nominal 300 seconds of
successfully validated recordings with one 0.05-second conversation-wide boundary
margin (accepted total <= 300.05 seconds), and 4 MiB of serialized output.
The existing margin is retained to preserve which inputs are accepted; it is not
50 ms per turn, and the reported duration is not rounded or truncated. Its original
rationale is not recorded in the implementation or commit history. It should not
be described as a necessary floating-point allowance: 50 ms is much larger than
ordinary rounding error when summing at most 20 bounded Double durations.
Exceeding limits throws. Failed recordings' durations cannot be inferred from a
failure code and are not included in the analyzed-duration total.
Choose explicit failure states for missing/interrupted captures, not zero-filled
reports. Empty/NPC-only conversations have no_user_turns; typed-only/all-failed
conversations have no_usable_audio. Neither produces a conversation score.

Native decoding/transcription/measurement errors now carry a stage and underlying
domain/code via VoiceAnalysisFailure. OSLog records only stage/code, never raw audio,
paths, transcripts, or full error messages. Validation failures use stable field
codes; consumers must not pass raw localized error strings into `.failed` states.
The analyzer has a default 180-second **cooperative** deadline (configurable up to
1800 seconds). It requests cancellation and retains ownership until cleanup. It
is not a force-kill deadline: synchronous JavaScript and Apple asset operations may
delay cancellation. One analyzer instance rejects overlapping requests.

Hardening preserved transcription options, pitch thresholds, and scoring equations.
Fixed per-clip status incorrectly saying complete when pace was unavailable, and
malformed null word entries crashing before a structured failed report. Decoder
frame-count conversion is bounded before conversion to UInt32. The shared bundle
is rebuilt and its freshness is tested.

Remaining release validation: physical-iPhone latency/memory, interruptions and
background lifecycle, first-use model download and cancellation behavior across
OS versions, broader speakers/devices, and microphone capture. Mac unit tests and
iOS compilation cannot certify those. Filler recall is incomplete; word times are
model estimates, not a trained speech activity detector. The scoring policy is
provisional. Payload construction does not authenticate its inputs, and the future
backend must validate caller/session/turn ownership independently.

Run `npm test` and `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun
swift test` in this package. Native tests cover unequal durations, all states,
partial metrics, empty/single/all-failed inputs, invalid reports and duplicate IDs,
limits, clip-relative evidence, short-turn pooling, safe errors, and deadline
behavior. The original per-clip tests and scoring tests remain regression coverage.

## Known Limitations

- **Cooperative deadlines:** the native analyzer requests cancellation, then waits
  for its work to stop. Synchronous JavaScriptCore calculations and noncooperative
  Apple operations can delay that return beyond the configured deadline. The
  timeout is not a hard execution limit.
- **Partial semantic validation:** payload validation checks structure, units,
  numeric bounds, word counts/timings, and the weighted score equation. It does
  not cross-check all reported measurements against each other or recompute each
  category score from its measurement. Structurally valid, contradictory rates
  and scores can still be accepted.
- **Different Swift errors:** there is no universal error envelope. Pipeline
  failures can throw `VoiceAnalysisFailure`; overlap, configuration, and deadlines
  use `VoiceAnalysisError`; cancellation can throw `CancellationError`; payload
  validation uses `VoicePayloadError`, and malformed JSON can throw Foundation
  decoding errors. Invalid word timings can instead return a failed report.
  Callers must handle these cases explicitly and inspect returned report status.
- **First-use speech assets:** Apple may need to download locale assets before
  on-device transcription can run. Cold-start download failure, stalled
  installation, and recovery on unsupported devices/locales have not been tested.
  An unsupported-locale error was observed under the Mac sandbox, but that does
  not establish behavior on unsupported hardware or during first-use installation.
- **Provisional scores and measurements:** pace, pitch, and filler targets are a
  reasonable first-pass product policy, not a validated measure of communication
  ability. They have not been evaluated against a real, labeled dataset spanning
  speakers and devices. Apple transcription can still omit fillers, and its word
  timestamps are estimates; energy-based pauses are not validated speech activity
  detection. Detecting some fillers does not establish complete filler recall.
- **Physical devices unverified:** verification includes native macOS tests,
  local recordings, and iOS compilation. It does not establish physical-iPhone
  memory use, interruptions, background behavior, or performance across supported
  hardware and OS versions. No physical-device runtime validation is claimed.
