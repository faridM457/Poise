import AVFoundation
import XCTest
@testable import PoiseVoiceAnalysis

@MainActor
final class RecordingSessionTests: XCTestCase {
    private func recording() async throws -> RecordedVoiceClip {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let writer = try VoiceRecordingWriter(format: format)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
        buffer.frameLength = 1024
        for channel in 0..<2 {
            for i in 0..<1024 { buffer.floatChannelData![channel][i] = 0.1 }
        }
        XCTAssertTrue(writer.append(buffer))
        return try await writer.finish()
    }

    func testRecordingFinalizesDecodableAudioAndDeletesOnRelease() async throws {
        var clip: RecordedVoiceClip? = try await recording()
        let url = try XCTUnwrap(clip?.fileURL)
        XCTAssertGreaterThan(try DeviceAudioDecoder.decode(url).count, 300)
        clip = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testEmptyAndDoubleFinishFailWithoutProducingClips() async throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let writer = try VoiceRecordingWriter(format: format)
        do { _ = try await writer.finish(); XCTFail("Expected empty recording") }
        catch VoiceRecordingError.emptyRecording { }
        do { _ = try await writer.finish(); XCTFail("Expected already finished") }
        catch VoiceRecordingError.alreadyFinished { }
    }

    @MainActor
    func testSessionRetainsDialogueAndContainsAnalysisFailure() async throws {
        let session = VoiceConversationSession(conversationID: "test") { _ in throw VoiceAnalysisError.timedOut }
        try session.appendNPC(id: "n1", text: "Hello")
        try session.appendUser(id: "u1", text: "Edited reply", input: .recorded(try await recording()))
        try session.appendUser(id: "u2", text: "Typed", input: .typed)
        try session.appendUser(id: "u3", text: "Missing", input: .missingAudio)
        let result = try await session.finish()
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: result.json) as? [String: Any])
        let dialogue = try XCTUnwrap(body["dialogue"] as? [[String: Any]])
        XCTAssertEqual(dialogue.map { $0["turnId"] as? String }, ["n1", "u1", "u2", "u3"])
        XCTAssertEqual((dialogue[1]["coverage"] as? [String: Any])?["reason"] as? String, "timed_out")
        XCTAssertEqual(session.pendingCount, 0)
        let repeated = try await session.finish()
        XCTAssertEqual(repeated.json, result.json)
        XCTAssertThrowsError(try session.appendUser(id: "late", text: "Late", input: .typed))
    }

    @MainActor
    func testCancellationAndDuplicateIDsDoNotSilentlyOmitTurns() async throws {
        let session = VoiceConversationSession(conversationID: "test") { _ in
            try await Task.sleep(for: .seconds(60))
            throw VoiceAnalysisError.analysisFailed
        }
        try session.appendUser(id: "u1", text: "Reply", input: .recorded(try await recording()))
        XCTAssertThrowsError(try session.appendUser(id: "u1", text: "Duplicate", input: .typed))
        session.cancel()
        XCTAssertEqual(session.pendingCount, 0)
        do { _ = try await session.finish(); XCTFail("Expected cancelled session") }
        catch is CancellationError { }
    }
}
