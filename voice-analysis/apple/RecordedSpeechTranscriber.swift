import AVFoundation
import Foundation
import Speech

struct RecordedSpeechTranscript: Encodable, Sendable {
    struct Word: Codable, Sendable {
        let text: String
        let start: Double
        let end: Double
    }

    let text: String
    let words: [Word]
    let timingIssues: [String]
    let duration: Double
    // Filler completeness needs a human reference; detection alone cannot validate it.
    let fillerPreservation = "unvalidated"
    let overallVoiceScore: Double? = nil

    private enum CodingKeys: String, CodingKey {
        case text, words, timingIssues, duration, fillerPreservation, overallVoiceScore
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        try container.encode(words, forKey: .words)
        try container.encode(timingIssues, forKey: .timingIssues)
        try container.encode(duration, forKey: .duration)
        try container.encode(fillerPreservation, forKey: .fillerPreservation)
        try container.encodeNil(forKey: .overallVoiceScore)
    }

    var observedFillers: [Word] {
        words.filter {
            let token = $0.text.lowercased().trimmingCharacters(in: .punctuationCharacters)
            return token == "um" || token == "uh"
        }
    }
}

/// File transcription only. No recording, audio upload, dictation fallback, or text cleanup.
@available(iOS 26.0, macOS 26.0, *)
actor RecordedSpeechTranscriber {
    enum Failure: LocalizedError {
        case unavailable, unsupportedLocale, invalidRecording, emptyTranscript

        var errorDescription: String? {
            switch self {
            case .unavailable: return "On-device conversation transcription is unavailable on this device."
            case .unsupportedLocale: return "English conversation transcription is unavailable."
            case .invalidRecording: return "Choose a local recording between 0 and 90 seconds, up to 16 MB."
            case .emptyTranscript: return "No speech was transcribed from this recording."
            }
        }
    }

    func transcribe(fileURL: URL) async throws -> RecordedSpeechTranscript {
        guard SpeechTranscriber.isAvailable else { throw Failure.unavailable }
        guard fileURL.isFileURL else { throw Failure.invalidRecording }
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize,
              size > 0, size <= 16 * 1024 * 1024 else { throw Failure.invalidRecording }
        let file = try AVAudioFile(forReading: fileURL)
        let duration = Double(file.length) / file.processingFormat.sampleRate
        guard duration.isFinite, duration > 0, duration <= 90 else { throw Failure.invalidRecording }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")) else {
            throw Failure.unsupportedLocale
        }
        // The API exposes etiquette replacement, but no verbatim/disfluency switch.
        // Request finalized results with original text and audio timing attributes.
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange]
        )
        try Task.checkCancellation()
        if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await installation.downloadAndInstall()
        }
        try Task.checkCancellation()

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        return try await withTaskCancellationHandler {
            let collector = Task {
                var transcript = AttributedString()
                for try await result in transcriber.results {
                    try Task.checkCancellation()
                    transcript.append(result.text)
                }
                return transcript
            }
            do {
                if let end = try await analyzer.analyzeSequence(from: file) {
                    try await analyzer.finalizeAndFinish(through: end)
                } else {
                    await analyzer.cancelAndFinishNow()
                    throw Failure.emptyTranscript
                }
                let transcript = try await collector.value
                try Task.checkCancellation()
                return try Self.makeTranscript(transcript, duration: duration)
            } catch {
                collector.cancel()
                await analyzer.cancelAndFinishNow()
                _ = await collector.result
                throw error
            }
        } onCancel: {
            Task { await analyzer.cancelAndFinishNow() }
        }
    }

    private static func makeTranscript(_ attributed: AttributedString, duration: Double) throws -> RecordedSpeechTranscript {
        let text = String(attributed.characters)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Failure.emptyTranscript
        }
        var words: [RecordedSpeechTranscript.Word] = []
        var issues: [String] = []
        // Do not split a multiword timing span into invented individual timestamps.
        for run in attributed.runs {
            let token = String(attributed[run.range].characters).trimmingCharacters(in: .whitespacesAndNewlines)
            guard token.contains(where: { $0.isLetter || $0.isNumber }) else { continue }
            guard token.split(whereSeparator: { $0.isWhitespace }).count == 1 else {
                issues.append("multiword_timing_span: \(token)")
                continue
            }
            guard let range = run.audioTimeRange else {
                issues.append("missing_word_timing: \(token)")
                continue
            }
            let start = range.start.seconds
            let end = CMTimeRangeGetEnd(range).seconds
            guard start.isFinite, end.isFinite, start >= 0, end > start,
                  end <= duration + 0.05, start >= (words.last?.end ?? 0) - 0.001 else {
                issues.append("invalid_word_timing: \(token)")
                continue
            }
            words.append(.init(text: token, start: start, end: end))
        }
        if words.isEmpty { issues.append("word_timing_unavailable") }
        return RecordedSpeechTranscript(text: text, words: words, timingIssues: issues, duration: duration)
    }
}
