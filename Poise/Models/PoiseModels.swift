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
    let subtitle: String
    let lessons: [LessonNode]
}

struct ConversationCriterion: Identifiable, Hashable {
    let id: Int
    let text: String
}

struct ScriptedReply: Identifiable, Hashable {
    let id = UUID()
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
struct EngineCharacter: Codable, Hashable {
    let name: String
    let role: String
    let relationship: String?
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

struct ProgressSnapshot {
    let streakDays: Int
    let xp: Int
    let level: Int
    let levelProgress: Double
    let weeklyGoal: Int
    let weeklyCompleted: Int
    let xpHistory: [Int]
    let calendarDays: [PracticeDay]
    let skillRates: [SkillRate]
    let badges: [String]
}

extension ProgressSnapshot {
    // The seven days ending today. calendarDays is a 28-day window, so slice
    // back from today rather than assuming the last seven entries are it.
    var weekEndingToday: [PracticeDay] {
        guard !calendarDays.isEmpty else { return [] }
        let end = (calendarDays.lastIndex { $0.isToday } ?? calendarDays.count - 1) + 1
        return Array(calendarDays[max(0, end - 7)..<end])
    }

    // Counted from the same days the weekly card draws, so a summary of this
    // number can never contradict the marks underneath it. Deliberately not
    // `weeklyCompleted`, which is a separate hardcoded mock value that
    // disagrees with the calendar.
    var practicedThisWeek: Int { weekEndingToday.filter(\.practiced).count }

    var remainingThisWeek: Int { max(0, weeklyGoal - practicedThisWeek) }
}

struct PracticeDay: Identifiable {
    let id = UUID()
    let day: Int
    let weekday: String
    let practiced: Bool
    let isToday: Bool
}

struct SkillRate: Identifiable {
    let id = UUID()
    let label: String
    let rate: Double
}

struct UserProfile {
    let name: String
    let initial: String
    let level: Int
    let subtitle: String
    let plan: String
}
