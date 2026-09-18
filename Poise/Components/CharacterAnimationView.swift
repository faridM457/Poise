import SwiftUI
import AVFoundation

// Plays a real, looping character video clip bundled from Resources/
// CharacterAnimations/ (originally ~/Downloads/Char1-Animations), replacing
// the hand-drawn MarcusAvatar placeholder in the live lesson flow. Muted --
// this is a silent visual loop, not a source of dialogue audio.
//
// Mood mapping is currently minimal: only .idleNeutral and .talkNeutral are
// actually used (briefing/scorecard vs. mid-conversation). The Positive/
// Negative variants exist as real bundled assets but aren't wired to the
// server's appropriateness/respect_and_empathy grades yet -- a real gap,
// not a hidden one.
struct CharacterAnimationView: View {
    enum Mood: String {
        case idleNeutral = "Idle_Neutral"
        case idlePositive = "Idle_Positive"
        case idleNegative = "Idle_Negative"
        case talkNeutral = "Talk_Neutral"
        case talkPositive = "Talk_Positive"
        case talkNegative = "Talk_Negative"
    }

    var mood: Mood = .idleNeutral
    var height: CGFloat = 220
    // When true, renders as an edge-to-edge background (aspect-fill, cropped)
    // instead of the boxed avatar-card presentation -- used by the roleplay
    // screen so the office scene reads as the room you're standing in, not a
    // video next to a chat log. `height` is ignored in this mode.
    var fillScreen: Bool = false

    // Source clips are portrait (1178x2556, roughly 0.46:1) -- preserve that
    // instead of guessing a square/circular crop like the old placeholder.
    private var width: CGFloat { height * (1178.0 / 2556.0) }

    var body: some View {
        Group {
            if fillScreen {
                LoopingVideoPlayer(resourceName: mood.rawValue, gravity: .resizeAspectFill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                LoopingVideoPlayer(resourceName: mood.rawValue, gravity: .resizeAspect)
                    .frame(width: width, height: height)
            }
        }
        .accessibilityLabel("Character animation")
    }
}

private struct LoopingVideoPlayer: UIViewRepresentable {
    let resourceName: String
    var gravity: AVLayerVideoGravity = .resizeAspect

    func makeUIView(context: Context) -> LoopingPlayerUIView {
        LoopingPlayerUIView(resourceName: resourceName, gravity: gravity)
    }

    func updateUIView(_ uiView: LoopingPlayerUIView, context: Context) {
        uiView.updateClip(resourceName: resourceName, gravity: gravity)
    }
}

// Switching moods used to tear down the AVQueuePlayer/AVPlayerLayer and build
// a fresh one from scratch, which left a visible blank frame while the new
// player item loaded. Fix: keep every mood we've been asked to show as its
// own continuously-looping, always-playing player, and just flip which
// layer is on top/visible -- since both are already decoding and playing,
// the swap is instant with nothing to wait on.
//
// Looping itself was originally done with AVPlayerLooper, which has a
// well-documented tendency to produce a brief black-frame flash at each
// clip's own loop boundary (independent of mood switching) -- especially
// noticeable on short clips. Replaced with a manual seek-to-zero-and-replay
// on AVPlayerItemDidPlayToEndTime, which is commonly more reliably seamless
// for this single-item silent-loop use case.
final class LoopingPlayerUIView: UIView {
    private final class LoadedClip {
        let player: AVQueuePlayer
        let layer: AVPlayerLayer
        var endObserver: NSObjectProtocol?

        init(player: AVQueuePlayer, layer: AVPlayerLayer) {
            self.player = player
            self.layer = layer
        }
    }

    private var clips: [String: LoadedClip] = [:]
    private var currentResourceName: String?

    init(resourceName: String, gravity: AVLayerVideoGravity) {
        super.init(frame: .zero)
        backgroundColor = .clear
        updateClip(resourceName: resourceName, gravity: gravity)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        for clip in clips.values {
            if let token = clip.endObserver {
                NotificationCenter.default.removeObserver(token)
            }
        }
    }

    func updateClip(resourceName: String, gravity: AVLayerVideoGravity) {
        loadClipIfNeeded(resourceName, gravity: gravity)
        // Its likely Idle/Talk counterpart (e.g. "Idle_Neutral" <->
        // "Talk_Neutral") is preloaded too, so toggling between the two
        // moods a screen actually uses never hits the cold-load path.
        if let pair = pairedResourceName(for: resourceName) {
            loadClipIfNeeded(pair, gravity: gravity)
        }

        // Swap via opacity, not isHidden. A hidden AVPlayerLayer can stop
        // being actively composited, so when it's un-hidden it can show a
        // stale/catching-up frame for an instant -- that's the flash. Every
        // layer stays at opacity 1/0 while continuously, actively rendering
        // underneath, so there's nothing to "catch up" on when it reappears.
        // Explicitly disabling implicit actions makes the opacity change
        // instant rather than a quick implicit cross-fade.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (name, clip) in clips {
            clip.layer.videoGravity = gravity
            clip.layer.opacity = (name == resourceName) ? 1 : 0
        }
        CATransaction.commit()
        currentResourceName = resourceName
    }

    private func loadClipIfNeeded(_ resourceName: String, gravity: AVLayerVideoGravity) {
        guard clips[resourceName] == nil else { return }
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "mp4") else { return }

        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer(playerItem: item)
        player.isMuted = true
        // We loop manually below; don't let the player pause itself first.
        player.actionAtItemEnd = .none

        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = gravity
        playerLayer.frame = bounds
        playerLayer.opacity = 0
        layer.addSublayer(playerLayer)

        let clip = LoadedClip(player: player, layer: playerLayer)
        clip.endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            player?.play()
        }
        clips[resourceName] = clip
        player.play()
    }

    private func pairedResourceName(for resourceName: String) -> String? {
        if resourceName.hasPrefix("Idle_") {
            return "Talk_" + resourceName.dropFirst("Idle_".count)
        } else if resourceName.hasPrefix("Talk_") {
            return "Idle_" + resourceName.dropFirst("Talk_".count)
        }
        return nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        for clip in clips.values {
            clip.layer.frame = bounds
        }
    }
}
