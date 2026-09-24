import Foundation
import OSLog

public struct VoiceAnalysisFailure: Error, LocalizedError, Sendable {
    public enum Stage: String, Sendable { case decoding, transcription, measurement }
    public let stage: Stage
    public let underlyingDomain: String
    public let underlyingCode: Int
    public var errorDescription: String? { "Voice analysis failed during \(stage.rawValue)." }

    init(stage: Stage, error: Error) {
        self.stage = stage
        let underlying = error as NSError
        underlyingDomain = underlying.domain
        underlyingCode = underlying.code
    }
}

public enum VoiceAnalysisError: Error, LocalizedError {
    case invalidAudio, runtimeUnavailable, analysisFailed, alreadyAnalyzing, timedOut, invalidTimeout

    public var errorDescription: String? {
        switch self {
        case .invalidAudio: return "Use a nonempty mono/stereo recording up to 90 seconds and 16 MiB."
        case .runtimeUnavailable: return "The bundled voice analysis runtime could not be loaded."
        case .analysisFailed: return "Voice measurements could not be calculated."
        case .alreadyAnalyzing: return "This analyzer is already processing a recording."
        case .timedOut: return "Voice analysis exceeded its processing deadline."
        case .invalidTimeout: return "Use a finite analysis timeout greater than zero and at most 1800 seconds."
        }
    }
}

/// An in-memory JSON report matching the Apple analysis schema. No persistence
/// or upload is performed; callers decide how to associate/store each turn.
public struct VoiceAnalysisReport: Sendable {
    public let json: Data
}

public actor OnDeviceVoiceAnalyzer {
    private var isAnalyzing = false
    private static let logger = Logger(subsystem: "PoiseVoiceAnalysis", category: "pipeline")
    public init() {}

    /// Caller supplies a finalized local file and holds any security-scoped access
    /// until this returns. Acoustic-only mode does not access Speech or its assets.
    public func analyze(fileURL: URL, acousticsOnly: Bool = false, timeoutSeconds: Double = 180) async throws -> VoiceAnalysisReport {
        guard !isAnalyzing else { throw VoiceAnalysisError.alreadyAnalyzing }
        try Task.checkCancellation()
        isAnalyzing = true
        defer { isAnalyzing = false }
        // A detached worker ensures decoding and synchronous JS do not occupy the UI actor.
        let worker = Task.detached(priority: .userInitiated) {
            try await AnalysisDeadline.run(seconds: timeoutSeconds) {
                var stage = VoiceAnalysisFailure.Stage.decoding
                do {
                    let samples = try DeviceAudioDecoder.decode(fileURL)
                    try Task.checkCancellation()
                    stage = .transcription
                    let transcript = acousticsOnly ? nil : try await RecordedSpeechTranscriber().transcribe(fileURL: fileURL)
                    stage = .measurement
                    let json = try DeviceAnalysisRuntime.analyze(samples: samples, transcript: transcript)
                    return VoiceAnalysisReport(json: json)
                } catch {
                    if Task.isCancelled || error is CancellationError { throw CancellationError() }
                    let failure = VoiceAnalysisFailure(stage: stage, error: error)
                    Self.logger.error("Analysis failed: stage=\(stage.rawValue, privacy: .public), code=\(failure.underlyingCode, privacy: .public)")
                    throw failure
                }
            }
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
}
