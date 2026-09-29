import SwiftUI

// Thin router. Every lesson in PoiseLessonLibrary carries an engineLessonId,
// so this always resolves to the live flow -- the scripted fallback that used
// to live here (hardcoded replies, a fixed four-item checklist and a
// MockEvaluationService that scored by counting turns) was unreachable and is
// gone.
struct LessonFlowView: View {
    let lesson: LessonNode
    // Whether the lesson was actually completed (finished the scorecard) vs.
    // exited early via the header's close button.
    let onFinish: (Bool) -> Void

    var body: some View {
        LiveLessonFlowView(
            engineLessonId: lesson.engineLessonId ?? lesson.id,
            title: lesson.title,
            isCheckpoint: lesson.isCheckpoint,
            onFinish: onFinish
        )
    }
}

// The one view the deleted scripted flow owned that the live flow also
// uses. Kept here, unchanged, rather than being dragged along with the dead
// code that happened to be its neighbour.
struct MessageBubble: View {
    let message: ConversationMessage
    // Word-by-word reveal, used for the most recent NPC line in a live
    // (server-generated) conversation so it feels spoken rather than
    // dumped on screen. Defaulted off so the scripted mock flow (which
    // shows all its canned replies at once) is unaffected.
    var animateReveal: Bool = false
    // Real Pocket TTS clip duration for this line, when available -- see
    // WordRevealText. Left nil for the scripted mock flow (unaffected).
    var speechDuration: Double? = nil
    var onRevealStart: (() -> Void)?
    var onRevealComplete: (() -> Void)?

    var body: some View {
        HStack {
            if message.speaker == .user { Spacer(minLength: 34) }
            Group {
                if animateReveal {
                    WordRevealText(
                        text: message.text,
                        speechDuration: speechDuration,
                        font: PoiseType.body(.bold),
                        color: message.speaker == .user ? .white : .poiseNavy,
                        onRevealStart: onRevealStart,
                        onRevealComplete: onRevealComplete
                    )
                } else {
                    Text(message.text)
                        .font(PoiseType.body(.bold))
                        .foregroundStyle(message.speaker == .user ? Color.white : Color.poiseNavy)
                }
            }
                // Bounds height the reliable way -- a line count SwiftUI
                // sizes to directly, with no ambiguity about whether a
                // surrounding frame actually shrinks to short content or
                // reserves its max regardless (a maxHeight-based cap on
                // this bubble was tried in the live roleplay panel and, in
                // practice, did the latter -- the visible bubble sat
                // pinned to one edge of a much taller reserved block,
                // leaving a large empty gap on the other side of it).
                .lineLimit(6)
                .padding(18)
                .background(message.speaker == .user ? Color.poiseBlue : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(message.speaker == .user ? Color.poiseBlueDark.opacity(0.2) : Color.poiseBorder, lineWidth: 1.5)
                )
            if message.speaker != .user { Spacer(minLength: 34) }
        }
        .accessibilityLabel(message.speaker == .user ? "Your message" : "\(message.characterName ?? "Marcus") says")
    }
}
