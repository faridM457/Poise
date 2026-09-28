import AVFoundation
import Foundation

enum DeviceAudioDecoder {
    static func decode(_ url: URL) throws -> [Float] {
        guard url.isFileURL else { throw VoiceAnalysisError.invalidAudio }
        let properties = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard properties.isRegularFile == true, let size = properties.fileSize,
              size > 0, size <= 16 * 1024 * 1024 else { throw VoiceAnalysisError.invalidAudio }
        let file = try AVAudioFile(forReading: url)
        let source = file.processingFormat
        let seconds = Double(file.length) / source.sampleRate
        guard seconds.isFinite, seconds > 0, seconds <= 90,
              source.channelCount > 0, source.channelCount <= 2,
              let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                         channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: source, to: target),
              let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: 4096),
              let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: 4096) else {
            throw VoiceAnalysisError.invalidAudio
        }
        var samples: [Float] = []
        samples.reserveCapacity(Int(ceil(seconds * 16_000)))
        var readError: Error?
        while true {
            try Task.checkCancellation()
            var conversionError: NSError?
            let status = converter.convert(to: output, error: &conversionError) { requested, inputStatus in
                do {
                    try Task.checkCancellation()
                    let remaining = file.length - file.framePosition
                    guard remaining > 0 else {
                        inputStatus.pointee = .endOfStream
                        return nil
                    }
                    let boundedRemaining = AVAudioFrameCount(min(remaining, AVAudioFramePosition(input.frameCapacity)))
                    try file.read(into: input, frameCount: min(requested, boundedRemaining))
                    inputStatus.pointee = input.frameLength == 0 ? .endOfStream : .haveData
                    return input.frameLength == 0 ? nil : input
                } catch {
                    readError = error
                    inputStatus.pointee = .endOfStream
                    return nil
                }
            }
            if let readError { throw readError }
            if let conversionError { throw conversionError }
            guard status != .error, let channel = output.floatChannelData?[0] else {
                throw VoiceAnalysisError.invalidAudio
            }
            samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
            guard samples.count <= 90 * 16_000 else { throw VoiceAnalysisError.invalidAudio }
            if status == .endOfStream { break }
            guard output.frameLength > 0 else { throw VoiceAnalysisError.invalidAudio }
        }
        guard !samples.isEmpty else { throw VoiceAnalysisError.invalidAudio }
        // Match the original PCM16 analysis input, without gain normalization.
        // Reject out-of-range input rather than hiding decoder overshoot/clipping.
        return try samples.map { value in
            guard value.isFinite, abs(value) <= 1.00001 else { throw VoiceAnalysisError.invalidAudio }
            return max(-32768, min(32767, (value * 32768).rounded())) / 32768
        }
    }
}
