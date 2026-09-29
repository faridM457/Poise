import AVFoundation
import Combine
import Speech
import PoiseVoiceAnalysis
import UIKit

// Live on-device dictation fills the composer without sending. The same tap
// saves an unprocessed recording for analysis after the user accepts the turn.
@MainActor
final class SpeechRecognitionService: NSObject, ObservableObject {
    enum ServiceError: Error, LocalizedError {
        case permissionDenied
        case recognizerUnavailable

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Microphone or speech recognition access was denied. You can still type your response."
            case .recognizerUnavailable:
                return "Speech recognition isn't available right now. You can still type your response."
            }
        }
    }

    @Published private(set) var isListening = false
    @Published private(set) var isStarting = false
    @Published private(set) var isFinalizing = false
    // True between stopping the mic and the transcriber delivering its final
    // text for the last stretch of speech. SpeechTranscriber only finalizes a
    // stretch once it hears what comes after it, so until then the tail of
    // the last sentence can still be a half-word guess ("I wanted to ta").
    @Published private(set) var isFinishingTranscript = false
    // Identifies the take whose results may still update `transcript`.
    // Separate from captureID, which stopListening resets immediately --
    // results for the take being finished must keep arriving after that.
    private var resultsTake = UUID()
    @Published var transcript = ""
    @Published var errorMessage: String?

    // Live text comes from SpeechAnalyzer + SpeechTranscriber, not
    // SFSpeechRecognizer. SFSpeechRecognizer's dictation (like
    // DictationTranscriber) strips "um"/"uh" with no option to keep them;
    // SpeechTranscriber keeps them, which matters here because the user is
    // practicing delivery and should see their own fillers. Same on-device
    // model the voice analysis already runs on the saved recording.
    private let audioEngine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var writer: VoiceRecordingWriter?
    private var finalization: Task<VoiceTurnInput, Never>?
    private var draft: VoiceTurnInput = .typed
    private var captureID = UUID()
    private var draftID = UUID()
    private var observers = Set<AnyCancellable>()
    // SpeechTranscriber reports each stretch of speech as volatile guesses
    // followed by one finalized result. Finalized stretches accumulate here
    // and the current volatile guess is appended for display, so a pause
    // never drops what came before it.
    private var finalizedText = ""
    private var volatileText = ""
    var isCapturing: Bool { isListening || isStarting || isFinalizing }

    override init() {
        super.init()
        for name in [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification,
                     UIApplication.didEnterBackgroundNotification, .AVAudioEngineConfigurationChange] {
            NotificationCenter.default.publisher(for: name).sink { [weak self] notification in
                let routeReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                let interruption = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                if name == AVAudioSession.routeChangeNotification,
                   routeReason != AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue,
                   routeReason != AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue { return }
                if name == AVAudioSession.interruptionNotification,
                   interruption != AVAudioSession.InterruptionType.began.rawValue { return }
                Task { @MainActor in
                    guard let self, self.isListening else { return }
                    if name == .AVAudioEngineConfigurationChange, self.audioEngine.isRunning { return }
                    self.errorMessage = "Recording was interrupted. Record again or send the text without voice analysis."
                    self.stopListening(failure: .interrupted)
                }
            }.store(in: &observers)
        }
    }

    // Both permissions this needs, read synchronously with no prompt --
    // used to drive Profile's real "Microphone access" toggle: whether to
    // show it on, and whether tapping it should re-request (only works once,
    // .notDetermined) or hand off to Settings (already decided either way).
    static var isAuthorized: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
            && AVAudioApplication.shared.recordPermission == .granted
    }

    static var isUndetermined: Bool {
        SFSpeechRecognizer.authorizationStatus() == .notDetermined
    }

    // Static, not instance-bound: doesn't touch `self`, and Profile's
    // permission toggle needs to call this without spinning up a whole
    // listening session's AVAudioEngine just to ask for access.
    static func requestAuthorization() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else { return false }

        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func toggleListening() {
        if isListening || isStarting {
            stopListening()
        } else if !isFinalizing {
            discardDraft()
            isStarting = true
            let id = captureID
            Task { await startListening(id: id) }
        }
    }

    private func startListening(id: UUID) async {
        errorMessage = nil
        let authorized = await Self.requestAuthorization()
        guard captureID == id, isStarting else { return }
        defer { isStarting = false }
        guard authorized else {
            errorMessage = ServiceError.permissionDenied.localizedDescription
            return
        }

        guard SpeechTranscriber.isAvailable,
              let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")) else {
            errorMessage = ServiceError.recognizerUnavailable.localizedDescription
            return
        }

        do {
            let transcriber = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [],
                reportingOptions: [.volatileResults, .fastResults],
                attributeOptions: []
            )
            if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await installation.downloadAndInstall()
            }
            guard captureID == id, isStarting else { return }

            let session = AVAudioSession.sharedInstance()
            // Same reasoning as NPCVoiceService.prepare(): don't assume the
            // session is idle just because this service last deactivated it
            // cleanly -- NPCVoiceService's .playback session is the other
            // side of every turn cycle here, so deactivate defensively
            // before reconfiguring rather than changing category on
            // whatever's currently active.
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            let recording = try VoiceRecordingWriter(format: format)
            writer = recording
            let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
                compatibleWith: [transcriber], considering: format
            ) ?? format
            let converter = AnalyzerBufferConverter(from: format, to: analyzerFormat)
            let (inputStream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
            inputContinuation = continuation
            let newAnalyzer = SpeechAnalyzer(modules: [transcriber])
            analyzer = newAnalyzer
            inputNode.removeTap(onBus: 0)
            // Capture immutable per-take references; never read main-actor state at the tap.
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                if recording.append(buffer) {
                    if let converted = converter.convert(buffer) {
                        continuation.yield(AnalyzerInput(buffer: converted))
                    }
                } else {
                    Task { @MainActor in
                        guard let self, self.captureID == id else { return }
                        self.errorMessage = "Recording reached a safety limit. Please record a shorter response."
                        self.stopListening(failure: .invalidAudio)
                    }
                }
            }

            audioEngine.prepare()
            try audioEngine.start()

            transcript = ""
            finalizedText = ""
            volatileText = ""
            isListening = true
            let take = UUID()
            resultsTake = take

            resultsTask = Task { [weak self] in
                do {
                    for try await result in transcriber.results {
                        guard let self, self.resultsTake == take else { return }
                        self.absorb(String(result.text.characters), isFinal: result.isFinal)
                    }
                } catch {
                    guard let self, self.captureID == id, self.isListening else { return }
                    self.errorMessage = "Live dictation stopped. You can edit the text before sending."
                    self.stopListening()
                }
            }
            try await newAnalyzer.start(inputSequence: inputStream)
        } catch {
            guard captureID == id else { return }
            errorMessage = "Recording could not start. You can still type your response."
            stopListening(failure: .invalidAudio)
        }
    }

    private func absorb(_ text: String, isFinal: Bool) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isFinal {
            if !cleaned.isEmpty {
                finalizedText = finalizedText.isEmpty ? cleaned : finalizedText + " " + cleaned
            }
            volatileText = ""
        } else {
            volatileText = cleaned
        }
        transcript = [finalizedText, volatileText].filter { !$0.isEmpty }.joined(separator: " ")
    }

    func stopListening(failure: VoiceTurnFailure? = nil) {
        captureID = UUID() // Invalidates pending permission requests and late dictation callbacks.
        isStarting = false
        let wasRunning = isListening || audioEngine.isRunning || writer != nil
        if wasRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        inputContinuation?.finish()
        inputContinuation = nil
        let pendingResults = resultsTask
        resultsTask = nil
        if let analyzer {
            self.analyzer = nil
            if failure == nil {
                // Finish instead of cancel, so the last stretch of speech gets
                // its finalized text. Bounded, so a transcriber that never
                // finishes can't leave Send disabled forever.
                let take = resultsTake
                isFinishingTranscript = true
                Task { [weak self] in
                    try? await analyzer.finalizeAndFinishThroughEndOfInput()
                    _ = await pendingResults?.value
                    if let self, self.resultsTake == take { self.isFinishingTranscript = false }
                }
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    guard let self, self.resultsTake == take, self.isFinishingTranscript else { return }
                    self.isFinishingTranscript = false
                    await analyzer.cancelAndFinishNow()
                }
            } else {
                resultsTake = UUID()
                pendingResults?.cancel()
                Task { await analyzer.cancelAndFinishNow() }
            }
        }
        if let recording = writer {
            writer = nil
            isFinalizing = true
            let currentDraft = draftID
            finalization = Task { [weak self] in
                let input: VoiceTurnInput
                do {
                    let clip = try await recording.finish()
                    input = failure.map { .failed($0) } ?? .recorded(clip)
                } catch { input = .failed(failure ?? .invalidAudio) }
                if let self, self.draftID == currentDraft {
                    self.draft = input
                    self.isFinalizing = false
                }
                return input
            }
        }
        isListening = false
        if wasRunning { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }

    /// Retains the draft for retry until the caller confirms acceptance.
    func finalizedInput() async -> VoiceTurnInput {
        stopListening()
        if let finalization { return await finalization.value }
        return draft
    }

    func discardDraft() {
        stopListening()
        // Stop any in-flight finalization from writing this take's text back
        // into a transcript the user just cleared.
        resultsTake = UUID()
        isFinishingTranscript = false
        draftID = UUID()
        finalization = nil
        draft = .typed
        isFinalizing = false
        transcript = ""
    }
}

// Converts mic tap buffers into the format SpeechAnalyzer wants. Runs on the
// audio thread inside the tap, so it only touches its own immutable state.
private final class AnalyzerBufferConverter: @unchecked Sendable {
    private let converter: AVAudioConverter?
    private let target: AVAudioFormat

    init(from source: AVAudioFormat, to target: AVAudioFormat) {
        self.target = target
        converter = source == target ? nil : AVAudioConverter(from: source, to: target)
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter else { return buffer }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil && output.frameLength > 0 ? output : nil
    }
}
