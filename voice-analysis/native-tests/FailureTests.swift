import Foundation
import XCTest
@testable import PoiseVoiceAnalysis

final class FailureTests: XCTestCase {
    func testDeadlineSuccessTimeoutAndInvalidConfiguration() async throws {
        let result = try await AnalysisDeadline.run(seconds: 1) { 42 }
        XCTAssertEqual(result, 42)
        do {
            let _: Int = try await AnalysisDeadline.run(seconds: 0.01) {
                try await Task.sleep(for: .seconds(10))
                return 1
            }
            XCTFail("Expected deadline")
        } catch VoiceAnalysisError.timedOut { } catch { XCTFail("Unexpected error: \(error)") }
        do {
            let _: Int = try await AnalysisDeadline.run(seconds: .nan) { 1 }
            XCTFail("Expected invalid timeout")
        } catch VoiceAnalysisError.invalidTimeout { }
    }

    func testDecodeFailureHasStageWithoutLeakingFilePath() async throws {
        do {
            _ = try await OnDeviceVoiceAnalyzer().analyze(fileURL: URL(fileURLWithPath: "/nonexistent/private-recording.wav"), acousticsOnly: true)
            XCTFail("Expected decoding failure")
        } catch let failure as VoiceAnalysisFailure {
            XCTAssertEqual(failure.stage, .decoding)
            XCTAssertFalse(failure.localizedDescription.contains("private-recording"))
            XCTAssertFalse(failure.underlyingDomain.isEmpty)
        }
    }
}
