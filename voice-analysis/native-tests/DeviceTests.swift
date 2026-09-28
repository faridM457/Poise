import AVFoundation
import Foundation
import XCTest
@testable import PoiseVoiceAnalysis

final class DeviceTests: XCTestCase {
    private func tone(_ hz: Double, amplitude: Double = 0.3) -> [Float] {
        (0..<128_000).map { i in
            i < 16_000 || i >= 112_000 ? 0 : Float(amplitude * sin(2 * .pi * hz * Double(i) / 16_000))
        }
    }

    private func report(_ samples: [Float]) throws -> [String: Any] {
        let data = try DeviceAnalysisRuntime.analyze(samples: samples, transcript: nil)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testBundledPitchAndSilenceGates() throws {
        for hz in [100.0, 220.0, 440.0] {
            let result = try report(tone(hz))
            let metrics = try XCTUnwrap(result["metrics"] as? [String: [String: Any]])
            let measured = try XCTUnwrap(metrics["medianPitchHz"]?["value"] as? Double)
            XCTAssertEqual(measured, hz, accuracy: hz * 0.02)
            XCTAssertTrue(result["overallVoiceScore"] is NSNull)
        }
        let silent = try report(Array(repeating: 0, count: 128_000))
        let metrics = try XCTUnwrap(silent["metrics"] as? [String: [String: Any]])
        XCTAssertTrue(metrics["medianPitchHz"]?["value"] is NSNull)
        XCTAssertThrowsError(try report([Float.nan]))
    }

    func testScoringInJavaScriptCore() throws {
        let metrics: [String: Any] = [
            "pitchRangeSemitones": ["value": 5, "status": "available"],
            "pitchCoverage": ["value": 0.3, "status": "available"],
            "reliablePitchSeconds": ["value": 8, "status": "available"],
            "speakingRateWpm": ["value": 150, "status": "experimental"],
            "detectedFillersPer100Words": ["value": 3, "status": "experimental"],
        ]
        let input = String(decoding: try JSONSerialization.data(withJSONObject: metrics), as: UTF8.self)
        let data = try DeviceAnalysisRuntime.evaluate("score", arguments: [input])
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(result["overallVoiceScore"] as? Double, 96)
        XCTAssertEqual(result["reliability"] as? String, "experimental")
    }

    func testNativeResamplingAndBounds() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tone.caf")
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000))
        buffer.frameLength = 48_000
        for channel in 0..<2 {
            for i in 0..<48_000 { buffer.floatChannelData![channel][i] = Float(0.2 * sin(2 * .pi * 220 * Double(i) / 48_000)) }
        }
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }
        let samples = try DeviceAudioDecoder.decode(url)
        XCTAssertEqual(Double(samples.count), 16_000, accuracy: 32)
        XCTAssertGreaterThan(samples.map { abs($0) }.max() ?? 0, 0.15)
        XCTAssertThrowsError(try DeviceAudioDecoder.decode(URL(string: "https://example.com/audio.wav")!))
        XCTAssertThrowsError(try DeviceAudioDecoder.decode(directory.appendingPathComponent("missing.wav")))
    }

    func testNativeReportIncludesTranscriptAndScoring() throws {
        let words = (0..<25).map { i in RecordedSpeechTranscript.Word(text: i == 0 ? "Um," : "word", start: 1 + Double(i) * 0.2, end: 1.1 + Double(i) * 0.2) }
        let transcript = RecordedSpeechTranscript(text: words.map(\.text).joined(separator: " "), words: words, timingIssues: [], duration: 8)
        let data = try DeviceAnalysisRuntime.analyze(samples: tone(220), transcript: transcript)
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(result["detectedFillerCount"] as? Int, 1)
        XCTAssertTrue(result["overallVoiceScore"] is NSNull) // Too short for pace.
        XCTAssertEqual((result["execution"] as? [String: Any])?["runtime"] as? String, "on_device")
        let payload = try VoiceLLMPayload.build(report: VoiceAnalysisReport(json: data), conversationID: "session-1", turnID: "turn-1")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: payload.json) as? [String: Any])
        XCTAssertEqual((body["counts"] as? [String: Any])?["observedFillers"] as? Int, 1)
    }
}
