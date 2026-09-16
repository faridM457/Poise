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

// Process-wide cache of the clip assets, so the roleplay screen doesn't build
// its AVPlayerItem from a cold file read the moment it appears.
//
// The briefing screen used to render a CharacterAnimationView, which warmed
// the player as a side effect. It now shows a landscape still instead, so
// nothing touched AVFoundation until roleplay opened -- and the gap between
// the view appearing and the first frame decoding showed as a blank screen.
// Call `preload` as early in the lesson flow as possible.
@MainActor
enum CharacterClipPreloader {
    private static var assets: [String: AVURLAsset] = [:]

    static func asset(named name: String) -> AVURLAsset? {
        if let cached = assets[name] { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp4") else { return nil }
        let asset = AVURLAsset(url: url)
        assets[name] = asset
        return asset
    }

    // Warms the clip assets so building the player item isn't a cold file
    // read. Called as the lesson flow opens.
    static func preload(_ moods: [CharacterAnimationView.Mood]) {
        for mood in moods {
            guard let asset = asset(named: mood.rawValue) else { continue }
            Task.detached(priority: .utility) {
                _ = try? await asset.load(.isPlayable, .tracks)
            }
        }
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
        var readyObserver: NSKeyValueObservation?

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
            clip.readyObserver?.invalidate()
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

        currentResourceName = resourceName
        for clip in clips.values { clip.layer.videoGravity = gravity }
        applyVisibility()
    }

    // Swap via opacity, not isHidden. A hidden AVPlayerLayer can stop being
    // actively composited, so when it's un-hidden it can show a stale frame
    // for an instant. Every layer stays at opacity 1/0 while continuously
    // rendering underneath, so there's nothing to catch up on.
    //
    // The isReadyForDisplay gate matters because an AVPlayerLayer that exists
    // but has no frame yet composites black. Raising opacity before then put
    // a black rectangle on screen. With the layer now mounted for the whole
    // lesson flow it is drawable long before the roleplay step shows it, but
    // the gate keeps that guaranteed rather than incidental.
    private func applyVisibility() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (name, clip) in clips {
            let visible = name == currentResourceName && clip.layer.isReadyForDisplay
            clip.layer.opacity = visible ? 1 : 0
        }
        CATransaction.commit()
    }

    private func loadClipIfNeeded(_ resourceName: String, gravity: AVLayerVideoGravity) {
        guard clips[resourceName] == nil else { return }
        // Reuses the warmed asset when preload() has already run.
        guard let asset = CharacterClipPreloader.asset(named: resourceName) else { return }

        let item = AVPlayerItem(asset: asset)
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
        clip.readyObserver = playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
            guard layer.isReadyForDisplay else { return }
            Task { @MainActor in self?.applyVisibility() }
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
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for clip in clips.values {
            clip.layer.frame = bounds
        }
        CATransaction.commit()
    }
}
