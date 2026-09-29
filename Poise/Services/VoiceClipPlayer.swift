import AVFoundation
import Combine

// Plays back the user's own recorded turn audio (see VoiceConversationSession's
// retained RecordedVoiceClips) on demand -- e.g. a "play your recording" button
// in the transcript sheet. Deliberately separate from NPCVoiceService: that one
// is a process-wide singleton meant to own NPC dialogue playback for a whole
// lesson; this is a small, view-scoped player for one sheet's own on-demand
// replay, so it's created and torn down with that sheet instead.
@MainActor
final class VoiceClipPlayer: NSObject, ObservableObject {
    @Published private(set) var playingURL: URL?
    // Ticks once a second while playing so a caller can render a normal
    // "0:13 / 0:59" transport readout instead of a bare play/stop toggle.
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var progressTimer: Timer?

    // Same URL tapped again -- stop rather than restart, so the button also
    // works as its own stop control.
    func toggle(_ url: URL) {
        if playingURL == url {
            stop()
            return
        }
        stop()
        do {
            let session = AVAudioSession.sharedInstance()
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true)
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.delegate = self
            newPlayer.play()
            player = newPlayer
            playingURL = url
            duration = newPlayer.duration
            currentTime = 0
            startProgressTimer()
        } catch {
            player = nil
            playingURL = nil
        }
    }

    func stop() {
        progressTimer?.invalidate()
        progressTimer = nil
        player?.stop()
        player = nil
        playingURL = nil
        currentTime = 0
        duration = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startProgressTimer() {
        // 1/4 second, not a full second -- ticking the displayed seconds
        // exactly on the second (rather than up to a second late) needs a
        // sampling rate finer than the unit it's displaying.
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        progressTimer = timer
    }

    private func tick() {
        guard let player else { return }
        currentTime = player.currentTime
    }
}

extension VoiceClipPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in self?.stop() }
    }
}

// "0:13" / "1:05" -- the compact transport-readout format every stock audio
// UI uses, not "00:13". Not localized (a raw duration readout, not text).
extension TimeInterval {
    var voiceClipTimestamp: String {
        let total = Int(self.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
