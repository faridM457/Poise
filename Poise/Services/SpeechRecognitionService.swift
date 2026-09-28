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
    @Published var transcript = ""
    @Published var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var writer: VoiceRecordingWriter?
    private var finalization: Task<VoiceTurnInput, Never>?
    private var draft: VoiceTurnInput = .typed
    private var captureID = UUID()
    private var draftID = UUID()
    private var observers = Set<AnyCancellable>()
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

        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            errorMessage = ServiceError.recognizerUnavailable.localizedDescription
            return
        }

        do {
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
            let newRequest = SFSpeechAudioBufferRecognitionRequest()
            newRequest.shouldReportPartialResults = true
            newRequest.taskHint = .dictation
            newRequest.requiresOnDeviceRecognition = true
            request = newRequest
            inputNode.removeTap(onBus: 0)
            // Capture immutable per-take references; never read main-actor state at the tap.
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                if recording.append(buffer) {
                    newRequest.append(buffer)
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
            isListening = true

            task = recognizer.recognitionTask(with: newRequest) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let final = result?.isFinal == true
                let failed = error != nil
                Task { @MainActor in
                    guard let self, self.captureID == id, self.isListening else { return }
                    if let text { self.transcript = text }
                    if failed {
                        self.errorMessage = "Live dictation stopped. You can edit the text before sending."
                        self.stopListening()
                    } else if final { self.stopListening() }
                }
            }
        } catch {
            errorMessage = "Recording could not start. You can still type your response."
            stopListening(failure: .invalidAudio)
        }
    }

    func stopListening(failure: VoiceTurnFailure? = nil) {
        captureID = UUID() // Invalidates pending permission requests and late dictation callbacks.
        isStarting = false
        let wasRunning = isListening || audioEngine.isRunning || writer != nil
        if wasRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
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
        draftID = UUID()
        finalization = nil
        draft = .typed
        isFinalizing = false
        transcript = ""
    }
}
