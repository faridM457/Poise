import AVFoundation
import Foundation

// Synthesizes NPC dialogue on-device via Pocket TTS (kyutai-labs, ported
// from the working PocketTTSDemo harness built earlier this session) and
// plays it back. Jean is the only voice wired in for this first pass -- of
// Pocket TTS's built-in voices, it's the one Kyutai's own catalog officially
// labels "conversation" rather than "reading" (see project notes), and it's
// the only one whose embedding is bundled here.
// Not ObservableObject -- nothing observes this directly as a SwiftUI view
// model; LiveLessonViewModel calls it and republishes what the UI needs
// (currentSpeechDuration, isSynthesizingSpeech) itself.
@available(iOS 17.0, *)
@MainActor
final class NPCVoiceService: NSObject {
    static let shared = NPCVoiceService()

    struct Speech {
        let audioData: Data
        let durationSeconds: Double
    }

    // Confirmed from the working PocketTTSDemo harness's TTSVoice enum
    // (case jean = 3), not guessed.
    private static let jeanVoiceIndex: UInt32 = 3

    private var engine: PocketTTSSwift?
    private var loadTask: Task<PocketTTSSwift, Error>?
    private var player: AVAudioPlayer?
    private var playerDelegate: AudioPlayerCompletionDelegate?

    /// Synthesizes `text` in Jean's voice. Loads the model lazily on first
    /// call (staging bundle resources into a real directory tree first --
    /// see PocketTTSModelStaging) and reuses it afterward.
    func speak(_ text: String) async throws -> Speech {
        let engine = try await loadedEngine()
        let result = try await engine.synthesize(text: text, voice: Self.jeanVoiceIndex)
        return Speech(audioData: result.audioData, durationSeconds: result.durationSeconds)
    }

    /// Prepares (but does not start) playback for previously-synthesized
    /// audio (WAV bytes from `speak`). Split from actually starting playback
    /// so the caller can warm up `AVAudioPlayer` (construction + decoding +
    /// `prepareToPlay()`) ahead of the moment audio should actually become
    /// audible -- calling `AVAudioPlayer(data:)` and `.play()` back to back
    /// had a perceptible startup lag that showed up as the word-reveal
    /// visibly starting before any sound did. Returns `false` (never throws)
    /// on failure, since TTS playback is additive, not load-bearing.
    func prepare(_ audioData: Data) -> Bool {
        do {
            let session = AVAudioSession.sharedInstance()
            // Deactivate before changing category rather than switching an
            // already-active session -- SpeechRecognitionService leaves the
            // session active in .playAndRecord after the user's turn (its own
            // stopListening() deactivates it, but the two services alternate
            // turn by turn, so this side must not assume it's inheriting an
            // idle session). Apple's own guidance is deactivate, change
            // category, then reactivate; changing category on a session
            // that's still active for a different category is exactly the
            // kind of thing that works once and then silently misbehaves.
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true)

            let newPlayer = try AVAudioPlayer(data: audioData)
            let delegate = AudioPlayerCompletionDelegate { [weak self] in
                self?.player = nil
                self?.playerDelegate = nil
                // Release the session on completion, not just the player --
                // otherwise the session sits active in .playback until
                // something else forces a change, which is the same
                // conflict this fix is closing, just shifted from "stop()
                // never deactivates" to "natural completion never does".
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
            newPlayer.delegate = delegate
            newPlayer.prepareToPlay()
            playerDelegate = delegate
            player = newPlayer
            return true
        } catch {
            print("[NPCVoiceService] Prepare failed: \(error)")
            return false
        }
    }

    /// Starts playback of whatever was most recently prepared via
    /// `prepare(_:)`. No-op if nothing is prepared, preparation failed, or
    /// playback was already stopped (e.g. the user left before this fired).
    func playPrepared() {
        player?.play()
    }

    /// Immediately halts playback, if any is in progress. Idempotent.
    func stop() {
        player?.stop()
        player = nil
        playerDelegate = nil
        // See prepare()'s comment: natural completion releases the session
        // via the player delegate, but an interrupted stop (user leaves
        // mid-line) skips that callback entirely, so it has to happen here
        // too or the session is left active in .playback indefinitely.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func loadedEngine() async throws -> PocketTTSSwift {
        if let engine { return engine }
        if let loadTask {
            return try await loadTask.value
        }

        let task = Task<PocketTTSSwift, Error> {
            let modelDir = try PocketTTSModelStaging.stagedModelDirectory()
            let newEngine = PocketTTSSwift(modelPath: modelDir.path)
            try await newEngine.load()
            try await newEngine.configure(.init(voiceIndex: Self.jeanVoiceIndex, useFixedSeed: true))
            return newEngine
        }
        loadTask = task

        do {
            let loaded = try await task.value
            engine = loaded
            loadTask = nil
            return loaded
        } catch {
            loadTask = nil
            throw error
        }
    }
}

// AVAudioPlayer.delegate is weak, so the delegate must be retained
// separately by the caller for the duration of playback.
private final class AudioPlayerCompletionDelegate: NSObject, AVAudioPlayerDelegate {
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }
}
