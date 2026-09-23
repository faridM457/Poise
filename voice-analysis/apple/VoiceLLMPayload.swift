import Foundation
import CoreFoundation

public enum VoicePayloadError: Error, LocalizedError {
    case invalid(String)

    public var errorDescription: String? {
        switch self {
        case .invalid(let field): return "Invalid voice feedback payload field: \(field)."
        }
    }
}

/// A transport-neutral JSON body. Construction performs validation, not storage,
/// authorization, network access, or prompt generation.
public struct VoiceLLMPayload: Sendable {
    public let json: Data

    public static func build(
        report: VoiceAnalysisReport,
        conversationID: String,
        turnID: String,
        editedMessage: String? = nil
    ) throws -> VoiceLLMPayload {
        func require(_ condition: Bool, _ field: String) throws {
            if !condition { throw VoicePayloadError.invalid(field) }
        }
        func number(_ value: Any?) -> Double? {
            guard let value = value as? NSNumber,
                  CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { return nil }
            return value.doubleValue
        }
        func identifier(_ value: String) -> Bool {
            !value.isEmpty && value.utf8.count <= 128 && value.utf8.allSatisfy {
                (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
            }
        }
        func optionalNumber(_ value: Any?, _ field: String, maximum: Double) throws {
            if value is NSNull { return }
            guard let n = number(value), n >= 0, n <= maximum else { throw VoicePayloadError.invalid(field) }
        }
        try require(identifier(conversationID), "conversationID")
        try require(identifier(turnID), "turnID")
        try require((editedMessage?.utf8.count ?? 0) <= 20_000, "editedMessage")
        try require(report.json.count <= 2 * 1024 * 1024, "report.size")
        guard let source = try JSONSerialization.jsonObject(with: report.json) as? [String: Any] else {
            throw VoicePayloadError.invalid("report")
        }
        try require(number(source["schemaVersion"]) == 1 && source["analysisVersion"] as? String == "apple-speech-2", "report.version")
        try require(["complete", "partial"].contains(source["status"] as? String ?? ""), "report.status")
        guard let duration = number(source["durationSeconds"]), duration > 0, duration <= 90,
              let transcript = source["transcript"] as? [String: Any],
              let text = transcript["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.utf8.count <= 20_000,
              let timing = transcript["timingsValid"] as? NSNumber,
              CFGetTypeID(timing) == CFBooleanGetTypeID(),
              let metrics = source["metrics"] as? [String: Any],
              let scoring = source["scoring"] as? [String: Any],
              let evidence = source["evidence"] as? [String: Any] else {
            throw VoicePayloadError.invalid("report.structure")
        }
        // An explicit allowlist prevents raw audio, file paths, config, and future
        // internal report fields from silently becoming remote-model inputs.
        let units = ["speakingRateWpm": "words/minute", "detectedFillersPer100Words": "events/100 words",
                     "medianPitchHz": "Hz", "pitchRangeSemitones": "semitones", "pitchCoverage": "ratio",
                     "reliablePitchSeconds": "seconds", "pauseRatio": "ratio", "pauseSeconds": "seconds",
                     "timestampGapRatio": "ratio", "volumeSpreadDb": "dB"]
        var selectedMetrics: [String: Any] = [:]
        for (name, unit) in units {
            guard let metric = metrics[name] as? [String: Any],
                  let status = metric["status"] as? String,
                  ["available", "experimental", "unavailable"].contains(status),
                  metric["unit"] as? String == unit else { throw VoicePayloadError.invalid("metrics.\(name)") }
            let value = metric["value"]
            if status == "unavailable" {
                try require(value is NSNull, "metrics.\(name).value")
            } else {
                try require(number(value) != nil && !(value is NSNull), "metrics.\(name).value")
            }
            try optionalNumber(value, "metrics.\(name).value", maximum: unit == "ratio" ? 1 : 1_000_000)
            guard metric["reason"] is NSNull || metric["reason"] is String else { throw VoicePayloadError.invalid("metrics.\(name).reason") }
            if let reason = metric["reason"] as? String { try require(reason.utf8.count <= 256, "metric.reason") }
            selectedMetrics[name] = ["value": value!, "unit": unit, "status": status, "reason": metric["reason"]!]
        }
        for name in ["lexicalWordCount", "detectedFillerCount"] {
            try optionalNumber(source[name], name, maximum: 20_000)
            if let count = number(source[name]) { try require(count.rounded() == count, name) }
        }
        try require(scoring["version"] as? String == "delivery-rules-1", "scoring.version")
        try require(["experimental", "unavailable"].contains(scoring["reliability"] as? String ?? ""), "scoring.reliability")
        try optionalNumber(scoring["overallVoiceScore"], "scoring.overallVoiceScore", maximum: 100)
        try optionalNumber(source["overallVoiceScore"], "overallVoiceScore", maximum: 100)
        try require(number(source["overallVoiceScore"]) == number(scoring["overallVoiceScore"]), "score.consistency")
        guard let categories = scoring["categories"] as? [[String: Any]], categories.count == 3 else {
            throw VoicePayloadError.invalid("scoring.categories")
        }
        var selectedCategories: [[String: Any]] = []
        var names = Set<String>()
        var missing = false
        let expectedWeights = ["pitch": 0.35, "fillers": 0.20, "pace": 0.45]
        for category in categories {
            guard let name = category["name"] as? String, names.insert(name).inserted,
                  let expected = expectedWeights[name], number(category["weight"]) == expected,
                  let reliability = category["reliability"] as? String,
                  ["available", "experimental", "unavailable"].contains(reliability),
                  let reasons = category["reasons"] as? [String], reasons.count <= 20,
                  reasons.allSatisfy({ $0.utf8.count <= 256 }) else { throw VoicePayloadError.invalid("scoring.category") }
            try optionalNumber(category["score"], "scoring.category.score", maximum: 100)
            try require((category["score"] is NSNull) == (reliability == "unavailable"), "scoring.category.reliability")
            missing = missing || reliability == "unavailable"
            selectedCategories.append(["name": name, "score": category["score"]!, "weight": expected,
                                       "reliability": reliability, "reasons": reasons])
        }
        try require((scoring["overallVoiceScore"] is NSNull) == missing, "scoring.completeness")
        try require((scoring["reliability"] as? String == "unavailable") == missing, "scoring.reliability")
        if let overall = number(scoring["overallVoiceScore"]) {
            let total = selectedCategories.reduce(0.0) { $0 + number($1["score"])! * number($1["weight"])! }
            try require(abs(total - overall) <= 0.11, "scoring.equation")
        }
        func intervals(_ key: String, fillers: Bool = false) throws -> [[String: Any]] {
            guard let entries = evidence[key] as? [[String: Any]], entries.count <= 2_000 else {
                throw VoicePayloadError.invalid("evidence.\(key)")
            }
            if !timing.boolValue && key != "energyPauses" {
                try require(entries.isEmpty, "evidence.invalidTiming")
            }
            var lastEnd = 0.0
            return try entries.map { entry in
                guard let start = number(entry["start"]), let end = number(entry["end"]),
                      start >= 0, end > start, end <= duration + 0.05, start >= lastEnd - 0.001 else {
                    throw VoicePayloadError.invalid("evidence.\(key).time")
                }
                lastEnd = end
                var interval: [String: Any] = ["start": start, "end": end]
                if fillers {
                    guard let token = entry["text"] as? String, token.utf8.count <= 32,
                          ["um", "uh"].contains(token.lowercased().trimmingCharacters(in: .punctuationCharacters)) else {
                        throw VoicePayloadError.invalid("evidence.filler.text")
                    }
                    interval["text"] = token
                }
                return interval
            }
        }
        let fillerEvidence = try intervals("fillers", fillers: true)
        if timing.boolValue {
            try require(number(source["detectedFillerCount"]) == Double(fillerEvidence.count), "fillerCount.consistency")
        }
        let body: [String: Any] = [
            "payloadVersion": "voice-feedback-input-1",
            "conversationId": conversationID, "turnId": turnID,
            "reportVersion": ["schemaVersion": 1, "analysisVersion": "apple-speech-2", "scoringVersion": "delivery-rules-1"],
            "reportStatus": source["status"]!, "durationSeconds": duration,
            "speech": ["recognizedText": text, "editedMessage": editedMessage as Any? ?? NSNull(),
                       "wordTimingsValid": timing.boolValue, "fillerPreservation": "unvalidated"],
            "counts": ["lexicalWords": source["lexicalWordCount"]!, "observedFillers": source["detectedFillerCount"]!],
            "metrics": selectedMetrics,
            "deterministicDeliveryScore": ["value": scoring["overallVoiceScore"]!, "scale": [0, 100],
                                           "reliability": scoring["reliability"]!, "categories": selectedCategories],
            "evidence": ["fillers": fillerEvidence, "wordGaps": try intervals("timestampGaps"),
                         "energyGaps": try intervals("energyPauses")],
            "limitations": ["observed_fillers_may_be_incomplete", "timestamps_are_estimates",
                             "energy_gaps_are_not_speech_vad", "delivery_score_is_provisional_not_final_assessment",
                             "pitch_does_not_measure_confidence_emotion_or_empathy"],
        ]
        return VoiceLLMPayload(json: try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]))
    }
}
