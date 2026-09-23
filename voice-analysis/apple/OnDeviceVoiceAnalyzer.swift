import Foundation

public enum VoiceAnalysisError: Error, LocalizedError {
    case invalidAudio, runtimeUnavailable, analysisFailed, alreadyAnalyzing

    public var errorDescription: String? {
        switch self {
        case .invalidAudio: return "Use a nonempty mono/stereo recording up to 90 seconds and 16 MiB."
        case .runtimeUnavailable: return "The bundled voice analysis runtime could not be loaded."
        case .analysisFailed: return "Voice measurements could not be calculated."
        case .alreadyAnalyzing: return "This analyzer is already processing a recording."
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
    public init() {}

    /// Caller supplies a finalized local file and holds any security-scoped access
    /// until this returns. Acoustic-only mode does not access Speech or its assets.
    public func analyze(fileURL: URL, acousticsOnly: Bool = false) async throws -> VoiceAnalysisReport {
        guard !isAnalyzing else { throw VoiceAnalysisError.alreadyAnalyzing }
        try Task.checkCancellation()
        isAnalyzing = true
        defer { isAnalyzing = false }
        // A detached worker ensures decoding and synchronous JS do not occupy the UI actor.
        let worker = Task.detached(priority: .userInitiated) {
            let samples = try DeviceAudioDecoder.decode(fileURL)
            try Task.checkCancellation()
            let transcript = acousticsOnly ? nil : try await RecordedSpeechTranscriber().transcribe(fileURL: fileURL)
            let json = try DeviceAnalysisRuntime.analyze(samples: samples, transcript: transcript)
            return VoiceAnalysisReport(json: json)
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
}
