import Foundation
import XCTest
@testable import PoiseVoiceAnalysis

final class PayloadTests: XCTestCase {
    private func fixture() -> [String: Any] {
        let units = ["speakingRateWpm": "words/minute", "detectedFillersPer100Words": "events/100 words",
                     "medianPitchHz": "Hz", "pitchRangeSemitones": "semitones", "pitchCoverage": "ratio",
                     "reliablePitchSeconds": "seconds", "pauseRatio": "ratio", "pauseSeconds": "seconds",
                     "timestampGapRatio": "ratio", "volumeSpreadDb": "dB"]
        let metrics = units.mapValues { ["value": 0.5, "unit": $0, "status": "experimental", "reason": "test_estimate"] as [String: Any] }
        let categories: [[String: Any]] = [("pitch", 0.35), ("fillers", 0.2), ("pace", 0.45)].map {
            ["name": $0.0, "weight": $0.1, "score": 80, "reliability": "experimental", "reasons": ["test_estimate"]]
        }
        return [
            "schemaVersion": 1, "analysisVersion": "apple-speech-2", "status": "complete",
            "durationSeconds": 30, "overallVoiceScore": 80,
            "transcript": ["text": "Um, I wanted to ask.", "timingsValid": true],
            "lexicalWordCount": 5, "detectedFillerCount": 1, "metrics": metrics,
            "scoring": ["version": "delivery-rules-1", "overallVoiceScore": 80, "reliability": "experimental", "categories": categories],
            "evidence": ["fillers": [["text": "Um,", "start": 1, "end": 1.4]], "timestampGaps": [], "energyPauses": []],
            "config": ["internal": "private"], "file": "/private/recording.m4a", "audio": "must-not-ship",
        ]
    }

    private func build(_ source: [String: Any], conversation: String = "conversation-1", turn: String = "turn-1", edited: String? = nil) throws -> VoiceLLMPayload {
        let report = VoiceAnalysisReport(json: try JSONSerialization.data(withJSONObject: source))
        return try VoiceLLMPayload.build(report: report, conversationID: conversation, turnID: turn, editedMessage: edited)
    }

    func testAllowlistIdentityAndSeparateEditedText() throws {
        let result = try build(fixture(), edited: "I wanted to ask.")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: result.json) as? [String: Any])
        XCTAssertEqual(body["conversationId"] as? String, "conversation-1")
        XCTAssertEqual(body["payloadVersion"] as? String, "voice-feedback-input-1")
        let speech = try XCTUnwrap(body["speech"] as? [String: Any])
        XCTAssertEqual(speech["recognizedText"] as? String, "Um, I wanted to ask.")
        XCTAssertEqual(speech["editedMessage"] as? String, "I wanted to ask.")
        let text = String(decoding: result.json, as: UTF8.self)
        XCTAssertFalse(text.contains("must-not-ship"))
        XCTAssertFalse(text.contains("/private/"))
        XCTAssertNil(body["config"])
        XCTAssertEqual(try build(fixture(), edited: "I wanted to ask.").json, result.json)
    }

    func testPartialReportPreservesNullAndReasons() throws {
        var source = fixture()
        source["status"] = "partial"
        source["overallVoiceScore"] = NSNull()
        var metrics = source["metrics"] as! [String: [String: Any]]
        metrics["pitchRangeSemitones"] = ["value": NSNull(), "unit": "semitones", "status": "unavailable", "reason": "insufficient_reliable_pitch"]
        source["metrics"] = metrics
        var score = source["scoring"] as! [String: Any]
        var categories = score["categories"] as! [[String: Any]]
        categories[0]["score"] = NSNull()
        categories[0]["reliability"] = "unavailable"
        score["categories"] = categories
        score["overallVoiceScore"] = NSNull()
        score["reliability"] = "unavailable"
        source["scoring"] = score
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: build(source).json) as? [String: Any])
        XCTAssertTrue((body["deterministicDeliveryScore"] as? [String: Any])?["value"] is NSNull)
        let outputMetrics = body["metrics"] as! [String: [String: Any]]
        XCTAssertTrue(outputMetrics["pitchRangeSemitones"]?["value"] is NSNull)
        XCTAssertEqual(outputMetrics["pitchRangeSemitones"]?["reason"] as? String, "insufficient_reliable_pitch")
        XCTAssertTrue((body["speech"] as? [String: Any])?["editedMessage"] is NSNull)
    }

    func testInvalidReportsAndIdentifiersFailClosed() throws {
        XCTAssertThrowsError(try build(fixture(), conversation: ""))
        XCTAssertThrowsError(try build(fixture(), turn: "../turn"))
        XCTAssertThrowsError(try build(fixture(), edited: String(repeating: "a", count: 20_001)))
        for (key, value) in [("schemaVersion", 99 as Any), ("schemaVersion", true as Any),
                             ("status", "failed" as Any), ("overallVoiceScore", 81 as Any),
                             ("detectedFillerCount", 4 as Any), ("durationSeconds", -1 as Any)] {
            var source = fixture()
            source[key] = value
            XCTAssertThrowsError(try build(source))
        }
        var source = fixture()
        source["evidence"] = ["fillers": [["text": "um", "start": 20, "end": 100]], "timestampGaps": [], "energyPauses": []]
        XCTAssertThrowsError(try build(source))
        source = fixture()
        source["metrics"] = [:]
        XCTAssertThrowsError(try build(source))
    }
}
