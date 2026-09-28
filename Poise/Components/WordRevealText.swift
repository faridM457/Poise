import SwiftUI

// Reveals `text` progressively, one word at a time, so NPC dialogue feels
// spoken rather than dumped on screen as a static block. Restarts cleanly
// whenever `text` changes (via `.task(id:)`), so the same instance can be
// reused across successive NPC lines.
//
// Timing is driven by `speechDuration` when it's provided (the real Pocket
// TTS audio clip's duration) -- Pocket TTS only returns total clip duration,
// not per-word timestamps, so true forced alignment isn't available. Instead
// of splitting that duration evenly across words, each word gets a share
// proportional to its length (character count), so short words ("a", "to")
// flash by quickly and longer words linger, approximating natural speech
// rhythm better than uniform timing while still summing to exactly the real
// clip length. Falls back to an estimated speaking pace (`wordsPerMinute`,
// weighted the same way) when no audio duration is available yet (e.g. TTS
// still synthesizing, or synthesis failed) so the conversation never blocks
// on voice.
struct WordRevealText: View {
    let text: String
    var wordsPerMinute: Double = 160
    var speechDuration: Double? = nil
    var font: Font = PoiseType.body(.bold)
    var color: Color = .primary
    var onRevealStart: (() -> Void)?
    var onRevealComplete: (() -> Void)?

    @State private var revealedWordCount = 0

    private var words: [String] { text.split(separator: " ").map(String.init) }

    // Per-word durations, length-weighted but summing to exactly the total
    // (real or estimated) speech duration -- only the distribution across
    // words changes, not the overall length of the reveal.
    private var wordDurations: [Double] {
        guard !words.isEmpty else { return [] }
        let totalDuration = speechDuration
            ?? (wordsPerMinute > 0 ? Double(words.count) * 60.0 / wordsPerMinute : Double(words.count) * 0.3)
        // +1 per word keeps very short words ("a", "I") from getting a
        // near-zero slice while still weighting longer words more heavily.
        let weights = words.map { Double($0.count) + 1 }
        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0 else {
            return Array(repeating: totalDuration / Double(words.count), count: words.count)
        }
        return weights.map { totalDuration * $0 / totalWeight }
    }

    var body: some View {
        Text(words.prefix(revealedWordCount).joined(separator: " "))
            .font(font)
            .foregroundStyle(color)
            .task(id: text) {
                revealedWordCount = 0
                let durations = wordDurations
                guard !words.isEmpty else {
                    onRevealComplete?()
                    return
                }
                onRevealStart?()
                for index in words.indices {
                    // Always call onRevealComplete, even on cancellation --
                    // a caller (LiveRoleplayView) uses onRevealStart/
                    // onRevealComplete to gate whether the user can send a
                    // reply, so a cancelled reveal that skipped this call
                    // would leave the composer permanently locked. If a new
                    // line's reveal starts right after, its own
                    // onRevealStart fires immediately behind this, so
                    // nothing is actually left unlocked that shouldn't be.
                    if Task.isCancelled {
                        onRevealComplete?()
                        return
                    }
                    revealedWordCount += 1
                    if revealedWordCount < words.count {
                        try? await Task.sleep(nanoseconds: UInt64(durations[index] * 1_000_000_000))
                    }
                }
                onRevealComplete?()
            }
    }
}
