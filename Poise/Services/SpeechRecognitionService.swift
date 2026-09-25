import AVFoundation
import Combine
import Speech

// On-device speech-to-text via Apple's Speech framework (SFSpeechRecognizer),
// so the user can speak their turn instead of typing it. Deliberately NOT
// whisper.cpp: that has a separate, unresolved filler-word-stripping issue
// investigated earlier this session, but basic mic input for turn CONTENT
// doesn't need perfect filler retention -- only a future delivery-analysis
// grading feature would, and that's out of scope here.
//
// Non-destructive by design: only ever fills the composer's text field via
// `transcript`, never sends anything itself -- same pattern as the browser
// mic button built earlier in conversation-engine.
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
    @Published var transcript = ""
    @Published var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

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
        if isListening {
            stopListening()
        } else {
            Task { await startListening() }
        }
    }

    private func startListening() async {
        guard !isListening else { return }
        errorMessage = nil

        let authorized = await Self.requestAuthorization()
        guard authorized else {
            errorMessage = ServiceError.permissionDenied.localizedDescription
            return
        }

        guard let recognizer, recognizer.isAvailable else {
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
            inputNode.removeTap(onBus: 0)
            // Feeds whichever request is CURRENT at the time each buffer
            // arrives (not a fixed request captured once) -- required so
            // the on-device -> server-based fallback below can swap in a
            // fresh request without restarting the audio engine.
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.request?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            transcript = ""
            isListening = true

            // Prefer on-device recognition first: server-based (network)
            // recognition is well-documented as unreliable in the iOS
            // Simulator, independent of the Simulator's mic-audio
            // passthrough (which works fine for raw AVAudioEngine capture).
            // But on-device recognition has its OWN separate Simulator
            // failure mode -- its models are provisioned via Apple's
            // MobileAsset system and are frequently missing on Simulator
            // devices (kLSRErrorDomain code 300, "Failed to initialize
            // recognizer") -- so if that happens, fall back once to
            // server-based recognition rather than giving up outright.
            beginRecognitionTask(recognizer: recognizer, preferOnDevice: recognizer.supportsOnDeviceRecognition, isFallback: false)
        } catch {
            errorMessage = error.localizedDescription
            stopListening()
        }
    }

    private func beginRecognitionTask(recognizer: SFSpeechRecognizer, preferOnDevice: Bool, isFallback: Bool) {
        task?.cancel()
        request?.endAudio()

        let newRequest = SFSpeechAudioBufferRecognitionRequest()
        newRequest.shouldReportPartialResults = true
        newRequest.taskHint = .dictation
        if preferOnDevice {
            newRequest.requiresOnDeviceRecognition = true
        }
        request = newRequest

        task = recognizer.recognitionTask(with: newRequest) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if let error {
                    print("[SpeechRecognitionService] recognition error (onDevice=\(preferOnDevice), fallback=\(isFallback)): \(error)")
                    // One fallback attempt maximum -- only retry if this was
                    // the first (on-device) attempt, never from a fallback.
                    if preferOnDevice && !isFallback {
                        self.beginRecognitionTask(recognizer: recognizer, preferOnDevice: false, isFallback: true)
                        return
                    }
                    self.errorMessage = error.localizedDescription
                    self.stopListening()
                    return
                }
                if result?.isFinal == true {
                    self.stopListening()
                }
            }
        }
    }

    func stopListening() {
        guard isListening || audioEngine.isRunning else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        isListening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
