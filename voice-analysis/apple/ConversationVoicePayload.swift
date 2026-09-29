import Foundation

public enum VoiceTurnFailure: String, Sendable {
    case invalidAudio = "invalid_audio"
    case transcriptionUnavailable = "transcription_unavailable"
    case analysisFailed = "analysis_failed"
    case cancelled
    case interrupted
    case timedOut = "timed_out"
}

public enum UserVoiceAnalysis: Sendable {
    case analyzed(VoiceAnalysisReport)
    case typed
    case missingAudio
    case failed(VoiceTurnFailure)
}

/// Array order is dialogue order. Supply only accepted messages, once per ID.
public struct ConversationVoiceTurn: Sendable {
    public enum Role: String, Sendable { case user, npc }
    public let id: String
    public let role: Role
    public let text: String
    public let speakerName: String?
    public let voice: UserVoiceAnalysis?

    public init(id: String, role: Role, text: String, speakerName: String? = nil, voice: UserVoiceAnalysis? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.speakerName = speakerName
        self.voice = voice
    }
}

public struct ConversationVoicePayload: Sendable {
    public let json: Data

    /// Pure assembly of a finalized conversation. No inference, persistence, or I/O.
    public static func build(conversationID: String, turns: [ConversationVoiceTurn]) throws -> ConversationVoicePayload {
        guard validID(conversationID), turns.count <= 100,
              turns.filter({ $0.role == .user }).count <= 20 else {
            throw VoicePayloadError.invalid("conversation.identity_or_turn_limit")
        }
        var ids = Set<String>()
        var textBytes = 0
        var reportBytes = 0
        for turn in turns {
            guard validID(turn.id), ids.insert(turn.id).inserted,
                  !turn.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  turn.text.utf8.count <= 20_000, (turn.speakerName?.utf8.count ?? 0) <= 256 else {
                throw VoicePayloadError.invalid("conversation.turn")
            }
            guard (turn.role == .user) == (turn.voice != nil) else {
                throw VoicePayloadError.invalid("conversation.role_analysis_mismatch")
            }
            textBytes += turn.text.utf8.count
            if case .analyzed(let report) = turn.voice { reportBytes += report.json.count }
        }
        guard textBytes <= 200_000, reportBytes <= 8 * 1024 * 1024 else {
            throw VoicePayloadError.invalid("conversation.input_size")
        }

        var dialogue: [[String: Any]] = []
        var turnCoverage: [[String: Any]] = []
        var analyzedIDs: [String] = []
        var typedIDs: [String] = []
        var missingIDs: [String] = []
        var failedIDs: [String] = []
        var partialIDs: [String] = []
        var totals = ConversationTotals()

        for turn in turns {
            var message: [String: Any] = ["turnId": turn.id, "role": turn.role.rawValue, "text": turn.text,
                                           "speakerName": turn.speakerName as Any? ?? NSNull()]
            if turn.role == .npc {
                dialogue.append(message)
                continue
            }
            var state: String
            var reason: Any = NSNull()
            var diagnostic: Any = NSNull()
            var analysis: Any = NSNull()
            switch turn.voice! {
            case .typed:
                state = "typed"
                typedIDs.append(turn.id)
            case .missingAudio:
                state = "missing_audio"
                missingIDs.append(turn.id)
            case .failed(let failure):
                state = "failed"
                reason = failure.rawValue
                failedIDs.append(turn.id)
            case .analyzed(let report):
                do {
                    let payload = try VoiceLLMPayload.build(report: report, conversationID: conversationID,
                                                           turnID: turn.id, editedMessage: turn.text)
                    let summary = try JSONDecoder().decode(ConversationClip.self, from: report.json)
                    try summary.validate()
                    guard var body = try JSONSerialization.jsonObject(with: payload.json) as? [String: Any] else {
                        throw VoicePayloadError.invalid("conversation.turn_report")
                    }
                    // Reuse the existing payload, adding explicit clip-local references
                    // so individual evidence objects remain meaningful when extracted.
                    var evidence = body["evidence"] as! [String: [[String: Any]]]
                    for key in evidence.keys {
                        evidence[key] = evidence[key]!.map { entry in
                            var entry = entry
                            entry["turnId"] = turn.id
                            entry["timebase"] = "clip_seconds"
                            return entry
                        }
                    }
                    body["evidence"] = evidence
                    var speech = body["speech"] as! [String: Any]
                    speech["words"] = summary.transcript.words.map { word in
                        ["text": word.text, "start": word.start, "end": word.end,
                         "turnId": turn.id, "timebase": "clip_seconds"] as [String: Any]
                    }
                    body["speech"] = speech
                    analysis = body
                    state = "analyzed"
                    analyzedIDs.append(turn.id)
                    if summary.status == "partial" { partialIDs.append(turn.id) }
                    totals.add(summary, turnID: turn.id)
                } catch {
                    // An invalid report must not erase other turns or leak raw errors,
                    // transcripts, or device paths into the eventual model request.
                    state = "failed"
                    reason = "invalid_or_failed_report"
                    if case VoicePayloadError.invalid(let field) = error { diagnostic = field }
                    else { diagnostic = "report_decoding_failed" }
                    failedIDs.append(turn.id)
                }
            }
            let coverage: [String: Any] = ["turnId": turn.id, "state": state, "reason": reason, "diagnosticCode": diagnostic]
            message["coverage"] = coverage
            message["analysis"] = analysis
            dialogue.append(message)
            turnCoverage.append(coverage)
        }
        // One existing 50 ms boundary margin for the conversation, not per turn.
        guard totals.recordedSeconds <= 300.05 else { throw VoicePayloadError.invalid("conversation.duration_limit") }
        let userCount = turnCoverage.count
        let audioComplete = userCount > 0 && analyzedIDs.count == userCount
        // Short turns may satisfy aggregate pace gates together while remaining partial individually.
        let metricsComplete = audioComplete && totals.allMetricsCover(userCount)
        let coverage: [String: Any] = [
            "status": userCount == 0 ? "no_user_turns" : analyzedIDs.isEmpty ? "no_usable_audio" : metricsComplete ? "complete" : "partial",
            "allUserTurnsAnalyzed": audioComplete, "allMetricsCoverAllUserTurns": metricsComplete,
            "userTurnCount": userCount, "analyzedTurnCount": analyzedIDs.count,
            "analyzedTurnIds": analyzedIDs, "typedTurnIds": typedIDs, "missingAudioTurnIds": missingIDs,
            "failedTurnIds": failedIDs, "partialAnalysisTurnIds": partialIDs,
            "analyzedFraction": userCount > 0 ? Double(analyzedIDs.count) / Double(userCount) as Any : NSNull(),
            "perTurn": turnCoverage,
        ]
        let body: [String: Any] = [
            "payloadVersion": "voice-conversation-input-1", "conversationId": conversationID,
            "dialogue": dialogue, "coverage": coverage, "aggregates": totals.output(userCount: userCount),
            "limitations": ["observed_fillers_may_be_incomplete", "word_intervals_are_estimates_not_speech_vad",
                             "pitch_summary_is_time_weighted_within_turn_range_not_pooled_range",
                             "partial_coverage_must_not_be_presented_as_full_conversation_measurement",
                             "deterministic_turn_scores_are_supporting_inputs_not_final_conversation_scores"],
        ]
        let json = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        guard json.count <= 4 * 1024 * 1024 else { throw VoicePayloadError.invalid("conversation.output_size") }
        return ConversationVoicePayload(json: json)
    }

    private static func validID(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.count <= 128 && id.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
        }
    }
}

private struct ConversationClip: Decodable {
    struct Metric: Decodable {
        let value: Double?
        let unit: String
        let status: String
        var usable: Double? {
            guard ["available", "experimental"].contains(status), let value, value.isFinite, value >= 0 else { return nil }
            return value
        }
    }
    struct Transcript: Decodable {
        struct Word: Decodable {
            let text: String
            let start: Double
            let end: Double
            var isFiller: Bool {
                ["um", "uh", "ah"].contains(text.lowercased().trimmingCharacters(in: .punctuationCharacters))
            }
        }
        let words: [Word]
        let timingsValid: Bool
        let timingIssues: [String]
    }
    let status: String
    let durationSeconds: Double
    let transcript: Transcript
    let lexicalWordCount: Int
    let detectedFillerCount: Int
    let metrics: [String: Metric]

    var responseSeconds: Double { transcript.words.last!.end - transcript.words.first!.start }
    var wordSeconds: Double {
        var previousEnd = 0.0
        return transcript.words.reduce(0) { total, word in
            let seconds = max(0, word.end - max(previousEnd, word.start))
            previousEnd = max(previousEnd, word.end)
            return total + seconds
        }
    }
    func validate() throws {
        guard transcript.timingsValid, transcript.timingIssues.isEmpty,
              !transcript.words.isEmpty, transcript.words.count <= 20_000 else { throw VoicePayloadError.invalid("conversation.word_timings") }
        var previousEnd = 0.0
        for word in transcript.words {
            guard !word.text.isEmpty, !word.text.contains(where: \.isWhitespace),
                  word.start.isFinite, word.end.isFinite, word.start >= 0, word.end > word.start,
                  word.end <= durationSeconds + 0.05, word.start >= previousEnd - 0.001 else {
                throw VoicePayloadError.invalid("conversation.word_time")
            }
            previousEnd = word.end
        }
        let fillers = transcript.words.filter(\.isFiller).count
        guard detectedFillerCount == fillers, lexicalWordCount == transcript.words.count - fillers else {
            throw VoicePayloadError.invalid("conversation.word_counts")
        }
        for key in ["activeSeconds", "responseSeconds", "pauseSeconds", "reliablePitchSeconds"] {
            guard let metric = metrics[key], metric.unit == "seconds",
                  ["available", "experimental", "unavailable"].contains(metric.status),
                  metric.status == "unavailable" ? metric.value == nil : metric.usable != nil else {
                throw VoicePayloadError.invalid("conversation.duration_metric")
            }
            if let value = metric.usable, value > durationSeconds + 0.05 { throw VoicePayloadError.invalid("conversation.duration_metric") }
        }
    }
}

private struct ConversationTotals {
    struct Weighted {
        var numerator = 0.0
        var seconds = 0.0
        var turnIDs: [String] = []
        mutating func add(_ value: Double, seconds weight: Double, id: String) {
            guard weight > 0 else { return }
            numerator += value * weight
            seconds += weight
            turnIDs.append(id)
        }
        var mean: Double? { seconds > 0 ? numerator / seconds : nil }
    }
    var words = 0
    var fillers = 0
    var speechSeconds = 0.0
    var responseSeconds = 0.0
    var recordedSeconds = 0.0
    var timedIDs: [String] = []
    var pitchRange = Weighted()
    var medianPitch = Weighted()
    var volume = Weighted()
    var activityIDs: [String] = []
    var activeSeconds = 0.0
    var pauseSeconds = 0.0
    var activityResponseSeconds = 0.0

    mutating func add(_ clip: ConversationClip, turnID: String) {
        words += clip.lexicalWordCount
        fillers += clip.detectedFillerCount
        speechSeconds += clip.wordSeconds
        responseSeconds += clip.responseSeconds
        recordedSeconds += clip.durationSeconds
        timedIDs.append(turnID)
        let m = clip.metrics
        if let coverage = m["pitchCoverage"]?.usable, coverage >= 0.2, coverage <= 1,
           let seconds = m["reliablePitchSeconds"]?.usable, seconds >= 3 {
            if let range = m["pitchRangeSemitones"]?.usable { pitchRange.add(range, seconds: seconds, id: turnID) }
            if let hz = m["medianPitchHz"]?.usable { medianPitch.add(hz, seconds: seconds, id: turnID) }
        }
        if let active = m["activeSeconds"]?.usable {
            if let db = m["volumeSpreadDb"]?.usable { volume.add(db, seconds: active, id: turnID) }
            if let span = m["responseSeconds"]?.usable, span > 0,
               let pause = m["pauseSeconds"]?.usable, pause <= span {
                activeSeconds += active
                pauseSeconds += pause
                activityResponseSeconds += span
                activityIDs.append(turnID)
            }
        }
    }
    func allMetricsCover(_ count: Int) -> Bool {
        timedIDs.count == count && pitchRange.turnIDs.count == count && medianPitch.turnIDs.count == count &&
        volume.turnIDs.count == count && activityIDs.count == count && words >= 20 && speechSeconds >= 10
    }
    func output(userCount: Int) -> [String: Any] {
        func metric(_ value: Double?, unit: String, method: String, ids: [String], seconds: Double,
                    unavailable: String = "no_usable_input") -> [String: Any] {
            ["value": value as Any? ?? NSNull(), "unit": unit,
             "status": value == nil ? "unavailable" : "experimental", "reason": value == nil ? unavailable : method,
             "contributingTurnIds": ids, "contributingSeconds": seconds,
             "coversAllUserTurns": value != nil && userCount > 0 && ids.count == userCount]
        }
        return [
            "totals": ["lexicalWords": timedIDs.isEmpty ? NSNull() : words as Any,
                       "observedFillers": timedIDs.isEmpty ? NSNull() : fillers as Any, "recognizedSpeechSeconds": speechSeconds,
                       "responseSpanSeconds": responseSeconds, "analyzedRecordingSeconds": recordedSeconds,
                       "contributingTurnIds": timedIDs] as [String: Any],
            "metrics": [
                "speechOnlyRateWpm": metric(words >= 20 && speechSeconds >= 10 ? 60 * Double(words) / speechSeconds : nil,
                                            unit: "words/minute", method: "total_lexical_words_over_union_of_word_intervals",
                                            ids: timedIDs, seconds: speechSeconds, unavailable: "insufficient_words_or_speech_time"),
                "responseSpanRateWpm": metric(words >= 20 && responseSeconds >= 10 ? 60 * Double(words) / responseSeconds : nil,
                                              unit: "words/minute", method: "total_lexical_words_over_summed_response_spans",
                                              ids: timedIDs, seconds: responseSeconds, unavailable: "insufficient_words_or_response_time"),
                "observedFillersPer100Words": metric(words > 0 ? 100 * Double(fillers) / Double(words) : nil,
                                                    unit: "events/100 words", method: "summed_observed_fillers_over_summed_lexical_words",
                                                    ids: timedIDs, seconds: speechSeconds),
                "timeWeightedWithinTurnPitchRangeSemitones": metric(pitchRange.mean, unit: "semitones",
                    method: "within_turn_ranges_weighted_by_reliable_pitch_seconds", ids: pitchRange.turnIDs, seconds: pitchRange.seconds),
                "timeWeightedTurnMedianPitchHz": metric(medianPitch.mean, unit: "Hz",
                    method: "turn_medians_weighted_by_reliable_pitch_seconds", ids: medianPitch.turnIDs, seconds: medianPitch.seconds),
                "timeWeightedWithinTurnVolumeSpreadDb": metric(volume.mean, unit: "dB",
                    method: "within_turn_spreads_weighted_by_active_seconds", ids: volume.turnIDs, seconds: volume.seconds),
                "energyPauseRatio": metric(activityResponseSeconds > 0 ? pauseSeconds / activityResponseSeconds : nil,
                    unit: "ratio", method: "summed_internal_energy_gaps_over_summed_response_spans", ids: activityIDs, seconds: activityResponseSeconds),
            ],
        ]
    }
}
