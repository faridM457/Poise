import Foundation

// Exercises the reusable Swift service without requiring app integration.
@main
struct RecordedSpeechCheck {
    static func main() async {
        guard CommandLine.arguments.count == 2 else {
            FileHandle.standardError.write(Data("Usage: recorded-speech-check /absolute/path/recording.m4a\n".utf8))
            exit(2)
        }
        do {
            let result = try await RecordedSpeechTranscriber().transcribe(
                fileURL: URL(fileURLWithPath: CommandLine.arguments[1])
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            print(String(decoding: try encoder.encode(result), as: UTF8.self))
        } catch {
            FileHandle.standardError.write(Data("TRANSCRIPTION FAILED: \(error)\n".utf8))
            exit(1)
        }
    }
}
