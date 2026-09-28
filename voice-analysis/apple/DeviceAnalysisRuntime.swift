import Foundation
import JavaScriptCore

// Each call owns its VM on the calling worker; JSContext never crosses actors.
enum DeviceAnalysisRuntime {
    static func evaluate(_ function: String, arguments: [Any]) throws -> Data {
        guard let url = Bundle.module.url(forResource: "voice-analysis", withExtension: "js"),
              let context = JSContext() else { throw VoiceAnalysisError.runtimeUnavailable }
        context.evaluateScript(try String(contentsOf: url, encoding: .utf8))
        guard context.exception == nil,
              let api = context.objectForKeyedSubscript("PoiseVoice"),
              let method = api.objectForKeyedSubscript(function), !method.isUndefined else {
            throw VoiceAnalysisError.runtimeUnavailable
        }
        let result = method.call(withArguments: arguments)
        guard context.exception == nil, let json = result?.toString(), let data = json.data(using: .utf8) else {
            throw VoiceAnalysisError.analysisFailed
        }
        _ = try JSONSerialization.jsonObject(with: data)
        return data
    }

    static func analyze(samples: [Float], transcript: RecordedSpeechTranscript?) throws -> Data {
        try Task.checkCancellation()
        let text: Any
        if let transcript {
            text = String(decoding: try JSONEncoder().encode(transcript), as: UTF8.self)
        } else {
            text = NSNull()
        }
        let report = try evaluate("analyze", arguments: [samples, text])
        try Task.checkCancellation()
        return report
    }
}
