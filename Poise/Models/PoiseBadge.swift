import Foundation

// The badge catalogue. Every badge is a rule over the session history, never a
// stored flag -- so a badge can't be awarded by one code path and then be
// missing from the list another path reads, and rebuilding the rule
// retroactively re-awards it correctly against history already on disk.
//
// Badges the user has not earned are still shown, greyed. A list that only
// ever displays what is already won gives nobody anything to aim at, and the
// previous version's three hardcoded strings were exactly that.
struct PoiseBadge: Identifiable, Hashable {
    enum Group: String, CaseIterable {
        case milestones
        case units
        case checkpoints
        case consistency

        var title: String {
            switch self {
            case .milestones: return "Milestones"
            case .units: return "Units"
            case .checkpoints: return "Checkpoint mastery"
            case .consistency: return "Consistency"
            }
        }
    }

    let id: String
    let title: String
    // What earns it, phrased as an instruction so a locked badge tells the
    // user what to do rather than just naming a thing they don't have.
    let requirement: String
    let icon: String
    let group: Group
}

enum PoiseBadgeCatalogue {
    static let all: [PoiseBadge] = [
        PoiseBadge(
            id: "first-words",
            title: "First Words",
            requirement: "Finish your first conversation",
            icon: "bubble.left.fill",
            group: .milestones
        ),
        PoiseBadge(
            id: "full-circle",
            title: "Full Circle",
            requirement: "Finish every lesson in the app",
            icon: "checkmark.seal.fill",
            group: .milestones
        ),

        // Requirements say "every lesson" rather than a count: Unit 5 has one
        // more than the others, and a hardcoded number silently lies the next
        // time the curriculum moves.
        PoiseBadge(
            id: "unit-1",
            title: "Solid Ground",
            requirement: "Finish every lesson in Unit 1",
            icon: "person.2.fill",
            group: .units
        ),
        PoiseBadge(
            id: "unit-2",
            title: "Speak It Plainly",
            requirement: "Finish every lesson in Unit 2",
            icon: "text.bubble.fill",
            group: .units
        ),
        PoiseBadge(
            id: "unit-3",
            title: "Hold Your Line",
            requirement: "Finish every lesson in Unit 3",
            icon: "hand.raised.fill",
            group: .units
        ),
        PoiseBadge(
            id: "unit-4",
            title: "Heard in the Room",
            requirement: "Finish every lesson in Unit 4",
            icon: "megaphone.fill",
            group: .units
        ),
        PoiseBadge(
            id: "unit-5",
            title: "Steady in the Hardest Room",
            requirement: "Finish every lesson in Unit 5",
            icon: "exclamationmark.triangle.fill",
            group: .units
        ),

        PoiseBadge(
            id: "checkpoint-clarity",
            title: "Clear Under Pressure",
            requirement: "Score Strong on Clarity in a checkpoint",
            icon: "text.alignleft",
            group: .checkpoints
        ),
        PoiseBadge(
            id: "checkpoint-empathy",
            title: "Genuinely Heard",
            requirement: "Score Strong on Empathy in a checkpoint",
            icon: "heart.fill",
            group: .checkpoints
        ),
        PoiseBadge(
            id: "checkpoint-resolution",
            title: "Landed It",
            requirement: "Score Strong on Resolution in a checkpoint",
            icon: "flag.checkered",
            group: .checkpoints
        ),

        PoiseBadge(
            id: "streak-3",
            title: "Three Days Running",
            requirement: "Practice 3 days in a row",
            icon: "flame.fill",
            group: .consistency
        ),
        PoiseBadge(
            id: "streak-7",
            title: "A Full Week",
            requirement: "Practice 7 days in a row",
            icon: "flame.fill",
            group: .consistency
        ),
        PoiseBadge(
            id: "streak-30",
            title: "Thirty Days Steady",
            requirement: "Practice 30 days in a row",
            icon: "flame.fill",
            group: .consistency
        ),
    ]

    static func badge(id: String) -> PoiseBadge? {
        all.first { $0.id == id }
    }
}
