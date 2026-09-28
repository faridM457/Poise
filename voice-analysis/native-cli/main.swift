import Foundation
import PoiseVoiceAnalysis

@main
struct NativeVoiceCLI {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        let payloadMode = args.count == 4 && args[1] == "--payload"
        guard args.count == 1 || (args.count == 2 && args[1] == "--acoustics-only") || payloadMode else {
            FileHandle.standardError.write(Data("Usage: voice-analyze-native /path/to/memo.m4a [--acoustics-only | --payload CONVERSATION_ID TURN_ID]\n".utf8))
            exit(2)
        }
        do {
            let report = try await OnDeviceVoiceAnalyzer().analyze(
                fileURL: URL(fileURLWithPath: args[0]), acousticsOnly: args.count == 2
            )
            let object = try JSONSerialization.jsonObject(with: report.json)
            let output = payloadMode ? try VoiceLLMPayload.build(report: report, conversationID: args[2], turnID: args[3]).json : report.json
            FileHandle.standardOutput.write(output)
            FileHandle.standardOutput.write(Data("\n".utf8))
            if let report = object as? [String: Any], report["status"] as? String == "failed" { exit(1) }
        } catch {
            FileHandle.standardError.write(Data("Analysis failed: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
