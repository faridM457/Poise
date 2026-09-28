import Foundation
import SwiftUI

enum AppTab: Hashable {
    case learn
    case progress
    case profile
}

enum LessonNodeState: Hashable {
    case completed
    case available
    case locked
}

struct LessonNode: Identifiable, Hashable {
    // Stable across app launches -- matches a lessons.js lesson id, used as
    // the key for both mock-content lookup and lock/unlock progress tracking
    // (see LearnProgressStore), unlike the random UUID this used to be.
    let id: String
    let title: String
    let state: LessonNodeState
    let icon: String
    let isCheckpoint: Bool
    let skipGuide: Bool
    let hintsEnabled: Bool
    // When set, this node is backed by a real lesson from the conversation-engine
    // server (matches a lessons.js `id`) instead of the scripted mock flow.
    var engineLessonId: String? = nil
    // Shorter phrasing for the path node's label so every node renders its
    // title at the same fixed font size -- `title` (used for accessibility)
    // stays the full, descriptive version.
    var shortTitle: String? = nil
    var displayTitle: String { shortTitle ?? title }
    // Known statically (not just once a live session starts) so the Learn
    // page can show who the next lesson is with, e.g. in a thumbnail/caption,
    // before the user has tapped into it.
    var character: EngineCharacter? = nil
    // Rough read on how long this takes, derived in MockLessonContent. Shown
    // before the user commits -- the Learn hero's CTA otherwise asks for an
    // unknown amount of time.
    var estimatedMinutes: Int = 5
}

struct LessonUnit: Identifiable {
    let id: String
    let label: String
    let title: String
    // Shown on the Learn grid card instead of `title` when the full title
    // wraps to a second line at the card's fixed width -- same reasoning as
    // LessonNode.shortTitle: a shorter phrasing rather than a shrunk or
    // truncated one, and only where the card layout actually needs it.
    // `title` (the real unit name) is unchanged everywhere else: the detail
    // sheet, the Up Next line, accessibility labels, and the server's own
    // curriculum copy in conversation-engine/server/lessons.js.
    var shortTitle: String? = nil
    let subtitle: String
    let lessons: [LessonNode]
}

struct ConversationCriterion: Identifiable, Hashable {
    let id: Int
    let text: String
}

struct ConversationMessage: Identifiable, Hashable {
    enum Speaker: Hashable {
        case marcus
        // Generic NPC speaker for real, server-generated lessons where the
        // character isn't Marcus (see `characterName`). Kept separate from
        // `.marcus` so the existing scripted mock flow is untouched.
        case npc
        case user
    }

    let id = UUID()
    let speaker: Speaker
    let text: String
    // Real character name for `.npc` messages (e.g. "Sam"), shown in the UI
    // label. Unused for `.marcus`/`.user`.
    var characterName: String? = nil
}

// A real character from the conversation-engine server (name/role only --
// there's no per-character art yet, so the UI currently falls back to the
// Marcus avatar as a placeholder regardless of the actual character).
// The three dimensions every conversation is judged on. Regular lessons also
// show their own three specific criteria; checkpoints are graded on these
// alone, because a checkpoint that hands over its criteria is an answer key.
//
// The blurbs describe the dimension, never the lesson's criteria -- naming
// "clarity" is fair warning, naming "state the concrete impact" is the test.
enum PoiseSkill: String, CaseIterable, Identifiable {
    case clarity
    case empathy
    case resolution
    // How the user sounded, not what they said -- graded from on-device
    // acoustic analysis of their recorded turns (pace, pitch range, filler
    // words), when any turn had usable audio. See AGENTS.md's voice-delivery
    // exception and LiveLessonViewModel.finishVoiceSessionAndSummarize.
    // Absent (not a low score) when no turn was recorded aloud.
    case delivery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clarity: return "Clarity"
        case .empathy: return "Empathy"
        case .resolution: return "Resolution"
        case .delivery: return "Delivery"
        }
    }

    var blurb: String {
        switch self {
        case .clarity: return "Say what you mean, plainly and specifically."
        case .empathy: return "Make room for how the other person sees it."
        case .resolution: return "Land somewhere concrete before you finish."
        case .delivery: return "How you sounded saying it: pace, pitch, and filler words."
        }
    }

    var icon: String {
        switch self {
        case .clarity: return "text.alignleft"
        case .empathy: return "heart.fill"
        case .resolution: return "flag.checkered"
        case .delivery: return "waveform"
        }
    }

    var accent: Color {
        switch self {
        case .clarity: return .poiseBlueDark
        case .empathy: return .poisePurple
        case .resolution: return .poiseMintDark
        case .delivery: return .poiseGold
        }
    }
}

// How well a conversation went on one PoiseSkill. Four levels rather than
// three: with an odd number, a grader leans on the middle one.
enum SkillLevel: Int, CaseIterable {
    case needsWork = 0
    case developing = 1
    case solid = 2
    case strong = 3

    var title: String {
        switch self {
        case .needsWork: return "Needs work"
        case .developing: return "Developing"
        case .solid: return "Solid"
        case .strong: return "Strong"
        }
    }

    // Ink colours for the level chips, kept separate from the general palette
    // because they have a job the palette tokens don't: they are 11pt text on
    // a 13% wash of themselves, and they must be told apart at a glance.
    //
    // The palette versions all failed on both counts -- measured on the chip
    // as rendered: orange 2.89:1, gold 2.58:1, blue 3.46:1, mint 3.23:1
    // against the 4.5:1 that size needs. Orange and gold were also only 20
    // degrees apart in hue, so "Needs work" and "Developing" read as the same
    // colour. These are the least-darkened versions of each hue that clear
    // 4.5:1, with red replacing orange to put 42 degrees between the bottom
    // two levels.
    // How full the checkpoint chart's bar is. Four tiers over a bar that can
    // also be empty, so the ladder is 25 / 50 / 75 / 100 with 0 reserved for
    // a checkpoint that hasn't been taken.
    var barFraction: Double {
        Double(rawValue + 1) / Double(SkillLevel.allCases.count)
    }

    var tint: Color {
        switch self {
        case .needsWork: return Color(red: 0.698, green: 0.176, blue: 0.176)
        case .developing: return Color(red: 0.518, green: 0.388, blue: 0.082)
        case .solid: return Color(red: 0.180, green: 0.416, blue: 0.678)
        case .strong: return Color(red: 0.133, green: 0.459, blue: 0.361)
        }
    }
}

struct EngineCharacter: Codable, Hashable {
    // `var`, not `let`: the custom-scenario builder lets the user hand-edit
    // a generated character's name/role before starting practice (see
    // CustomScenarioFlowView). Confirmed safe -- this type is never used as
    // a Set/Dictionary key anywhere.
    var name: String
    var role: String
    let relationship: String?
    // "male" or "female" -- picks which of the app's three bundled
    // character models this NPC renders as (see CharacterAppearance).
    // Optional, and tolerated as missing on decode (a plain Optional
    // already decodes a missing key as nil), because the deployed
    // conversation-engine server is a separate process from the app and
    // isn't guaranteed to have been redeployed with this field the moment
    // a new client build ships.
    let gender: String?

    // The exact `role` phrases the engine's lesson definitions use (see
    // lessons.js/PoiseLessonContent.swift), translated to plain language for
    // the chip. `role` itself is left alone -- on the live path it's also
    // fed straight into the model's system prompt in third person ("you are
    // roleplaying as Dani, Direct report"), so rewriting it to a "Your ..."
    // phrasing there would read backwards to the model. Only the on-screen
    // label changes. "report" is org-chart jargon ("direct report" = an
    // employee who reports to you) that reads as unclear outside that
    // context; "peer manager" has the same problem.
    private static let plainLanguageRoles: [String: String] = [
        "New report": "Your new employee",
        "Direct report": "Your employee",
        "Two reports": "Your employees",
        "Peer manager": "Your co-worker",
        "Leadership": "Senior leadership",
    ]

    // `role` is written for the language model's benefit -- "Peer, coworker on
    // an adjacent team" -- which is far too long for the name chip on the
    // briefing screen. Everything before the first comma is the role proper;
    // what follows is scenario colour that already belongs in the briefing
    // text. Derived rather than stored because in live mode the character
    // comes from the conversation engine, so this has to cope with strings
    // the app has never seen, not just the five in the mock library.
    var shortRole: String {
        let head = role.split(separator: ",").first.map(String.init) ?? role
        let trimmed = head.trimmingCharacters(in: .whitespaces)
        if let plain = Self.plainLanguageRoles[trimmed] { return plain }

        let cleaned = trimmed
            .replacingOccurrences(of: "The user's own ", with: "Your ")
            .replacingOccurrences(of: "The user's ", with: "Your ")
        // Backstop for anything the engine sends without a comma: keep it to
        // two words rather than letting a sentence into the chip. Drop a
        // leading article first, so a long description reduces to "Senior
        // stakeholder" rather than "A senior".
        var words = cleaned.split(separator: " ")
        guard words.count > 3 else { return cleaned }
        if let first = words.first, ["a", "an", "the"].contains(first.lowercased()) {
            words.removeFirst()
        }
        let short = words.prefix(2).joined(separator: " ")
        return short.prefix(1).uppercased() + short.dropFirst()
    }
}

struct ScoreResult {
    let xpEarned: Int
    let criteriaMet: Int
    let totalCriteria: Int
    let checklist: [ChecklistItem]
    let feedback: String
}

struct ChecklistItem: Identifiable {
    enum State {
        case met
        case needsWork
    }

    let id = UUID()
    let title: String
    let state: State
}

struct PracticeDay: Identifiable {
    let id = UUID()
    let day: Int?
    let practiced: Bool
    let isToday: Bool
    // Single-letter column label, used by the Learn page's week strip. Empty
    // for the calendar grid, which labels its columns once in a header row
    // rather than per cell.
    var weekday: String = ""
}

