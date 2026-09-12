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
    case checkpoint
}

struct LessonNode: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let subtitle: String
    let state: LessonNodeState
    let icon: String
    let isCheckpoint: Bool
    let skipGuide: Bool
    let hintsEnabled: Bool
}

struct LessonUnit: Identifiable {
    let id = UUID()
    let label: String
    let title: String
    let subtitle: String
    let completion: String
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
        case user
    }

    let id = UUID()
    let speaker: Speaker
    let text: String
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
