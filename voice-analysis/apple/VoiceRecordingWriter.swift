import AVFoundation
import Foundation
import OSLog

/// Owns a temporary recording. Keeping this object alive keeps its file alive.
public final class RecordedVoiceClip: Sendable {
    public let fileURL: URL
    public let durationSeconds: Double

    init(fileURL: URL, durationSeconds: Double) {
        self.fileURL = fileURL
        self.durationSeconds = durationSeconds
    }

    deinit {
        do { try FileManager.default.removeItem(at: fileURL) }
        catch {
            Logger(subsystem: "PoiseVoiceAnalysis", category: "recording")
                .error("Temporary recording cleanup failed.")
        }
    }
}

public enum VoiceRecordingError: Error, Sendable {
    case invalidFormat, limitExceeded, bufferOverflow, writeFailed, emptyRecording, alreadyFinished
}

/// Copies bounded PCM chunks at the tap, then downmixes/writes on a serial queue.
/// Mutable state is protected by lock; AVAudioFile is accessed only on queue.
public final class VoiceRecordingWriter: @unchecked Sendable {
    private final class Chunk: @unchecked Sendable {
        let buffer: AVAudioPCMBuffer
        init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
    }

    private let queue = DispatchQueue(label: "poise.voice-recording", qos: .userInitiated)
    private let lock = NSLock()
    private let format: AVAudioFormat
    private let url: URL
    private let maximumFrames: Int64
    private var file: AVAudioFile?
    private var pending = 0
    private var frames: Int64 = 0
    private var closed = false
    private var transferred = false
    private var failure: VoiceRecordingError?

    public init(format: AVAudioFormat) throws {
        guard format.commonFormat == .pcmFormatFloat32, !format.isInterleaved,
              format.sampleRate.isFinite, (8_000...192_000).contains(format.sampleRate),
              (1...2).contains(format.channelCount) else { throw VoiceRecordingError.invalidFormat }
        self.format = format
        maximumFrames = min(Int64(format.sampleRate * 90), (16 * 1024 * 1024 - 4096) / 2)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PoiseVoiceRecordings", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
        file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        #endif
    }

    /// Returns false if capture must stop. A dropped chunk invalidates the clip.
    @discardableResult
    public func append(_ buffer: AVAudioPCMBuffer) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !closed, failure == nil else { return false }
        guard buffer.format == format, buffer.frameLength > 0, buffer.frameLength <= 8192,
              let source = buffer.floatChannelData else {
            failure = .invalidFormat
            return false
        }
        guard frames + Int64(buffer.frameLength) <= maximumFrames else {
            failure = .limitExceeded
            return false
        }
        guard pending < 32 else { failure = .bufferOverflow; return false }
        guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: buffer.frameLength),
              let destination = copy.floatChannelData else { failure = .bufferOverflow; return false }
        copy.frameLength = buffer.frameLength
        for channel in 0..<Int(format.channelCount) {
            destination[channel].update(from: source[channel], count: Int(buffer.frameLength))
        }
        frames += Int64(buffer.frameLength)
        pending += 1
        let chunk = Chunk(copy)
        // Submission happens under lock so finish cannot overtake an accepted chunk.
        queue.async { [self] in
            do {
                guard let file,
                      let mono = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk.buffer.frameLength),
                      let output = mono.floatChannelData?[0], let input = chunk.buffer.floatChannelData else {
                    throw VoiceRecordingError.writeFailed
                }
                mono.frameLength = chunk.buffer.frameLength
                let channels = Int(chunk.buffer.format.channelCount)
                for i in 0..<Int(mono.frameLength) {
                    var value: Float = 0
                    for channel in 0..<channels { value += input[channel][i] / Float(channels) }
                    guard value.isFinite, abs(value) <= 1.00001 else { throw VoiceRecordingError.invalidFormat }
                    output[i] = value
                }
                try file.write(from: mono)
            } catch {
                lock.lock()
                failure = failure ?? .writeFailed
                lock.unlock()
            }
            lock.lock()
            pending -= 1
            lock.unlock()
        }
        return true
    }

    public func finish() async throws -> RecordedVoiceClip {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            defer { lock.unlock() }
            guard !closed else { continuation.resume(throwing: VoiceRecordingError.alreadyFinished); return }
            closed = true
            queue.async { [self] in
                file = nil // Close the WAV header before handing the URL to the analyzer.
                lock.lock()
                let error = failure ?? (frames == 0 ? .emptyRecording : nil)
                if error == nil { transferred = true }
                let duration = Double(frames) / format.sampleRate
                lock.unlock()
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: RecordedVoiceClip(fileURL: url, durationSeconds: duration)) }
            }
        }
    }

    deinit {
        file = nil
        if !transferred { try? FileManager.default.removeItem(at: url) }
    }
}
