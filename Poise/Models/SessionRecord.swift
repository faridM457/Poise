import Foundation

// One finished conversation. This is the app's only record of what the user
// has actually done, and everything on the Progress page is derived from a
// list of these: the practice calendar, the streak, the weekly goal, the
// checkpoint results and every badge.
//
// Deriving rather than storing those separately is the point. The previous
// version kept a hardcoded `weeklyCompleted` beside a hardcoded calendar and
// a hardcoded `streakDays`, and the three disagreed with each other -- the
// same week read as 3 conversations in one card and 4 in another. Numbers
// that are computed from one list cannot drift apart.
struct SessionRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let lessonID: String
    let unitNumber: Int
    let isCheckpoint: Bool
    let finishedAt: Date
    // PoiseSkill.rawValue -> SkillLevel.rawValue. Stored by raw value rather
    // than as the enums so adding a skill or reordering the levels later
    // can't silently reinterpret records already on disk.
    let skillLevels: [String: Int]
    let criteriaMet: Int
    let criteriaTotal: Int

    init(
        id: UUID = UUID(),
        lessonID: String,
        unitNumber: Int,
        isCheckpoint: Bool,
        finishedAt: Date = Date(),
        skillLevels: [String: Int],
        criteriaMet: Int,
        criteriaTotal: Int
    ) {
        self.id = id
        self.lessonID = lessonID
        self.unitNumber = unitNumber
        self.isCheckpoint = isCheckpoint
        self.finishedAt = finishedAt
        self.skillLevels = skillLevels
        self.criteriaMet = criteriaMet
        self.criteriaTotal = criteriaTotal
    }

    func level(for skill: PoiseSkill) -> SkillLevel? {
        skillLevels[skill.rawValue].flatMap(SkillLevel.init(rawValue:))
    }

    // One tier for the whole conversation: the rounded mean of the three
    // skills. This is the number the checkpoint chart plots -- averaging the
    // three was always the plan for an overall score, and a single bar per
    // checkpoint needs a single value.
    var overallLevel: SkillLevel? {
        let levels = PoiseSkill.allCases.compactMap { level(for: $0)?.rawValue }
        guard !levels.isEmpty else { return nil }
        let mean = Double(levels.reduce(0, +)) / Double(levels.count)
        return SkillLevel(rawValue: Int(mean.rounded()))
    }

    var skills: [PoiseSkill: SkillLevel] {
        var result: [PoiseSkill: SkillLevel] = [:]
        for skill in PoiseSkill.allCases {
            if let level = level(for: skill) { result[skill] = level }
        }
        return result
    }
}
