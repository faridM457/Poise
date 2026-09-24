import Foundation
import XCTest
@testable import PoiseVoiceAnalysis

final class ConversationTests: XCTestCase {
    private func clip(words count: Int = 20, fillers: Int = 2, wordSeconds: Double = 0.5,
                      pitch: Double? = 5, pitchSeconds: Double = 4, volume: Double = 10) throws -> VoiceAnalysisReport {
        let total = count + fillers
        let words: [[String: Any]] = (0..<total).map { i in
            ["text": i < fillers ? "um," : "word", "start": 1 + Double(i) * (wordSeconds + 0.1),
             "end": 1 + Double(i) * (wordSeconds + 0.1) + wordSeconds]
        }
        let span = Double(total) * (wordSeconds + 0.1) - 0.1
        func metric(_ value: Double?, _ unit: String) -> [String: Any] {
            ["value": value as Any? ?? NSNull(), "unit": unit, "status": value == nil ? "unavailable" : "experimental",
             "reason": value == nil ? "insufficient_reliable_pitch" : "test_estimate"]
        }
        let metrics: [String: Any] = [
            "speakingRateWpm": metric(span >= 10 && count >= 20 ? 60 * Double(count) / span : nil, "words/minute"),
            "detectedFillersPer100Words": metric(count > 0 ? 100 * Double(fillers) / Double(count) : nil, "events/100 words"),
            "medianPitchHz": metric(pitch == nil ? nil : 100, "Hz"), "pitchRangeSemitones": metric(pitch, "semitones"),
            "pitchCoverage": metric(0.5, "ratio"), "reliablePitchSeconds": metric(pitchSeconds, "seconds"),
            "activeSeconds": metric(Double(total) * wordSeconds, "seconds"), "responseSeconds": metric(span, "seconds"),
            "pauseSeconds": metric(0, "seconds"), "pauseRatio": metric(0, "ratio"),
            "timestampGapRatio": metric(0, "ratio"), "volumeSpreadDb": metric(volume, "dB"),
        ]
        let input = String(decoding: try JSONSerialization.data(withJSONObject: metrics), as: UTF8.self)
        let scoring = try JSONSerialization.jsonObject(with: DeviceAnalysisRuntime.evaluate("score", arguments: [input])) as! [String: Any]
        let body: [String: Any] = [
            "schemaVersion": 1, "analysisVersion": "apple-speech-2", "status": pitch == nil || span < 10 ? "partial" : "complete",
            "durationSeconds": span + 2, "overallVoiceScore": scoring["overallVoiceScore"]!,
            "transcript": ["text": words.map { $0["text"] as! String }.joined(separator: " "),
                           "words": words, "timingsValid": true, "timingIssues": []],
            "lexicalWordCount": count, "detectedFillerCount": fillers, "metrics": metrics, "scoring": scoring,
            "evidence": ["fillers": Array(words.prefix(fillers)), "timestampGaps": [], "energyPauses": []],
        ]
        return VoiceAnalysisReport(json: try JSONSerialization.data(withJSONObject: body))
    }
    private func output(_ turns: [ConversationVoiceTurn]) throws -> [String: Any] {
        let payload = try ConversationVoicePayload.build(conversationID: "conversation-1", turns: turns)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: payload.json) as? [String: Any])
    }
    private func metric(_ body: [String: Any], _ name: String) -> [String: Any] {
        (body["aggregates"] as! [String: Any])["metrics"].flatMap { ($0 as? [String: [String: Any]])?[name] }!
    }

    func testWeightedConversationAndEvidenceIdentity() throws {
        let first = try clip(words: 20, fillers: 2, pitch: 4, pitchSeconds: 4, volume: 10)
        let second = try clip(words: 60, fillers: 3, pitch: 8, pitchSeconds: 12, volume: 20)
        let turns: [ConversationVoiceTurn] = [
            .init(id: "npc-1", role: .npc, text: "Question"),
            .init(id: "user-1", role: .user, text: "Edited reply", voice: .analyzed(first)),
            .init(id: "npc-2", role: .npc, text: "Another question"),
            .init(id: "user-2", role: .user, text: "Second reply", voice: .analyzed(second)),
        ]
        let body = try output(turns)
        let dialogue = body["dialogue"] as! [[String: Any]]
        XCTAssertEqual(dialogue.map { $0["turnId"] as! String }, ["npc-1", "user-1", "npc-2", "user-2"])
        XCTAssertNil(dialogue[0]["analysis"])
        XCTAssertEqual(metric(body, "speechOnlyRateWpm")["value"] as! Double, 60 * 80 / 42.5, accuracy: 0.0001)
        XCTAssertEqual(metric(body, "responseSpanRateWpm")["value"] as! Double, 60 * 80 / 50.8, accuracy: 0.0001)
        XCTAssertEqual(metric(body, "observedFillersPer100Words")["value"] as! Double, 6.25)
        XCTAssertEqual(metric(body, "timeWeightedWithinTurnPitchRangeSemitones")["value"] as! Double, 7)
        XCTAssertEqual(metric(body, "timeWeightedWithinTurnVolumeSpreadDb")["value"] as! Double, (10 * 11 + 20 * 31.5) / 42.5, accuracy: 0.0001)
        let analysis = dialogue[1]["analysis"] as! [String: Any]
        let evidence = analysis["evidence"] as! [String: [[String: Any]]]
        XCTAssertEqual(evidence["fillers"]![0]["turnId"] as? String, "user-1")
        XCTAssertEqual(evidence["fillers"]![0]["start"] as? Double, 1)
        XCTAssertEqual(evidence["fillers"]![0]["timebase"] as? String, "clip_seconds")
        XCTAssertEqual((body["coverage"] as! [String: Any])["status"] as? String, "complete")
        XCTAssertNil(body["overallVoiceScore"])
        XCTAssertNil((body["aggregates"] as! [String: Any])["overallVoiceScore"])
        XCTAssertEqual(try ConversationVoicePayload.build(conversationID: "conversation-1", turns: turns).json,
                       try ConversationVoicePayload.build(conversationID: "conversation-1", turns: turns).json)
    }

    func testMixedCoverageAndUnavailablePitchNeverBecomeZero() throws {
        let body = try output([
            .init(id: "u1", role: .user, text: "Spoken", voice: .analyzed(try clip(pitch: nil))),
            .init(id: "u2", role: .user, text: "Typed", voice: .typed),
            .init(id: "u3", role: .user, text: "Missing", voice: .missingAudio),
            .init(id: "u4", role: .user, text: "Failed", voice: .failed(.interrupted)),
        ])
        let coverage = body["coverage"] as! [String: Any]
        XCTAssertEqual(coverage["status"] as? String, "partial")
        XCTAssertEqual(coverage["analyzedFraction"] as? Double, 0.25)
        XCTAssertEqual(coverage["partialAnalysisTurnIds"] as? [String], ["u1"])
        XCTAssertEqual((coverage["perTurn"] as! [[String: Any]]).map { $0["state"] as! String }, ["analyzed", "typed", "missing_audio", "failed"])
        XCTAssertTrue(metric(body, "timeWeightedWithinTurnPitchRangeSemitones")["value"] is NSNull)
        XCTAssertEqual(metric(body, "speechOnlyRateWpm")["coversAllUserTurns"] as? Bool, false)
    }

    func testEmptyTypedOnlyFailedAndMalformedConversations() throws {
        for turns: [ConversationVoiceTurn] in [[], [.init(id: "n", role: .npc, text: "Hello")],
            [.init(id: "u", role: .user, text: "Typed", voice: .typed)],
            [.init(id: "u", role: .user, text: "Failed", voice: .failed(.analysisFailed))],
            [.init(id: "u", role: .user, text: "Malformed", voice: .analyzed(VoiceAnalysisReport(json: Data("{}".utf8))))]] {
            let body = try output(turns)
            XCTAssertTrue(metric(body, "observedFillersPer100Words")["value"] is NSNull)
            XCTAssertTrue(metric(body, "speechOnlyRateWpm")["value"] is NSNull)
            XCTAssertNotEqual((body["coverage"] as! [String: Any])["status"] as? String, "complete")
        }
        let one = ConversationVoiceTurn(id: "u", role: .user, text: "Reply", voice: .typed)
        XCTAssertThrowsError(try output([one, one]))
        XCTAssertThrowsError(try output([.init(id: "n", role: .npc, text: "Hello", voice: .typed)]))
        XCTAssertThrowsError(try output([.init(id: "u", role: .user, text: "Reply")]))
        XCTAssertThrowsError(try output([.init(id: "u", role: .user, text: "", voice: .typed)]))
    }

    func testShortTurnsCombineWithoutAveragingOrPerTurnEligibilityBias() throws {
        let short = try clip(words: 10, fillers: 0, wordSeconds: 0.5, pitchSeconds: 3)
        let body = try output((0..<2).map { .init(id: "u\($0)", role: .user, text: "Reply", voice: .analyzed(short)) })
        XCTAssertEqual(metric(body, "speechOnlyRateWpm")["value"] as? Double, 120)
        XCTAssertEqual(metric(body, "observedFillersPer100Words")["value"] as? Double, 0)
        let single = try output([.init(id: "u", role: .user, text: "Reply", voice: .analyzed(short))])
        XCTAssertTrue(metric(single, "speechOnlyRateWpm")["value"] is NSNull)
    }

    func testMissingPitchOnlyExcludesThatTurnsPitchContribution() throws {
        let body = try output([
            .init(id: "u1", role: .user, text: "One", voice: .analyzed(try clip(pitch: 4))),
            .init(id: "u2", role: .user, text: "Two", voice: .analyzed(try clip(pitch: nil))),
        ])
        XCTAssertEqual(metric(body, "timeWeightedWithinTurnPitchRangeSemitones")["value"] as? Double, 4)
        XCTAssertEqual(metric(body, "timeWeightedWithinTurnPitchRangeSemitones")["contributingTurnIds"] as? [String], ["u1"])
        XCTAssertEqual(metric(body, "timeWeightedWithinTurnPitchRangeSemitones")["coversAllUserTurns"] as? Bool, false)
        XCTAssertEqual(metric(body, "speechOnlyRateWpm")["coversAllUserTurns"] as? Bool, true)
    }

    func testMalformedWordsDoNotPoisonOtherTurnsAndLimitsRejectWithoutTruncation() throws {
        let good = try clip()
        var source = try JSONSerialization.jsonObject(with: good.json) as! [String: Any]
        var transcript = source["transcript"] as! [String: Any]
        var words = transcript["words"] as! [[String: Any]]
        words[0]["end"] = 500
        transcript["words"] = words
        source["transcript"] = transcript
        let bad = VoiceAnalysisReport(json: try JSONSerialization.data(withJSONObject: source))
        let body = try output([
            .init(id: "good", role: .user, text: "Good", voice: .analyzed(good)),
            .init(id: "bad", role: .user, text: "Bad", voice: .analyzed(bad)),
        ])
        let coverage = body["coverage"] as! [String: Any]
        XCTAssertEqual(coverage["analyzedTurnIds"] as? [String], ["good"])
        XCTAssertEqual(coverage["failedTurnIds"] as? [String], ["bad"])
        XCTAssertThrowsError(try output((0..<21).map { .init(id: "u\($0)", role: .user, text: "Reply", voice: .typed) }))
        let long = try clip(words: 60, fillers: 3, wordSeconds: 1)
        XCTAssertThrowsError(try output((0..<5).map { .init(id: "u\($0)", role: .user, text: "Reply", voice: .analyzed(long)) }))
    }
}
