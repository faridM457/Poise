import Foundation

enum PoiseMockData {
    static let criteria = [
        ConversationCriterion(id: 1, text: "Hear both perspectives before taking a position"),
        ConversationCriterion(id: 2, text: "Focus on what broke down, not who is to blame"),
        ConversationCriterion(id: 3, text: "Check that both people feel heard"),
        ConversationCriterion(id: 4, text: "Agree on a concrete next step")
    ]

    static let unit = LessonUnit(
        label: "Unit 1 · Speaking Up",
        title: "Confident Conversations",
        subtitle: "Build clarity, empathy, and courage",
        completion: "2 of 5 complete",
        lessons: [
            LessonNode(title: "Addressing an issue early", subtitle: "Completed", state: .completed, icon: "checkmark", isCheckpoint: false, skipGuide: false, hintsEnabled: true),
            LessonNode(title: "Giving critical feedback", subtitle: "Completed", state: .completed, icon: "checkmark", isCheckpoint: false, skipGuide: false, hintsEnabled: true),
            LessonNode(title: "Mediating a conflict", subtitle: "Continue", state: .available, icon: "text.bubble.fill", isCheckpoint: false, skipGuide: false, hintsEnabled: true),
            LessonNode(title: "Delivering an unpopular decision", subtitle: "Locked", state: .locked, icon: "lock.fill", isCheckpoint: false, skipGuide: false, hintsEnabled: true),
            LessonNode(title: "Checkpoint: calm under pressure", subtitle: "Locked", state: .checkpoint, icon: "flag.checkered", isCheckpoint: true, skipGuide: true, hintsEnabled: false)
        ]
    )

    static let scriptedReplies = [
        ScriptedReply(text: "I hear that, but Priya still sent her section late. I do not want this landing on me."),
        ScriptedReply(text: "If we had a clearer handoff, I could have flagged the risk earlier."),
        ScriptedReply(text: "I can agree to a shared next step if Priya does too.")
    ]

    static let openingMessage = ConversationMessage(
        speaker: .marcus,
        text: "I couldn't finish my part without Priya's section. I don't think this was on me."
    )

    static let progress = ProgressSnapshot(
        streakDays: 4,
        xp: 455,
        level: 3,
        levelProgress: 0.70,
        weeklyGoal: 5,
        weeklyCompleted: 3,
        xpHistory: [180, 240, 315, 420, 455],
        calendarDays: (1...28).map { day in
            PracticeDay(
                day: day,
                weekday: ["M", "T", "W", "T", "F", "S", "S"][(day - 1) % 7],
                practiced: [2, 4, 6, 9, 11, 12, 15, 17, 19, 22, 23, 24, 25].contains(day),
                isToday: day == 26
            )
        },
        skillRates: [
            SkillRate(label: "Session 1", rate: 0.60),
            SkillRate(label: "Session 2", rate: 0.67),
            SkillRate(label: "Session 3", rate: 0.80),
            SkillRate(label: "Session 4", rate: 0.75)
        ],
        badges: ["Feedback starter", "Steady listener", "Next-step closer"]
    )

    static let profile = UserProfile(
        name: "Farid",
        initial: "F",
        level: 3,
        subtitle: "practicing with purpose",
        plan: "Free plan"
    )
}

struct MockEvaluationService {
    func evaluate(messages: [ConversationMessage]) -> ScoreResult {
        let userTurns = messages.filter { $0.speaker == .user }
        let criteriaMet = min(3, max(2, userTurns.count + 1))
        let checklist = [
            ChecklistItem(title: "Hear both perspectives before taking a position", state: .met),
            ChecklistItem(title: "Focus on what broke down, not who is to blame", state: .met),
            ChecklistItem(title: "Check that both people feel heard", state: criteriaMet >= 3 ? .met : .needsWork),
            ChecklistItem(title: "Agree on a concrete next step", state: .needsWork)
        ]

        return ScoreResult(
            xpEarned: 35,
            criteriaMet: criteriaMet,
            totalCriteria: 4,
            checklist: checklist,
            feedback: "Strong start: you kept the conversation grounded in what happened and gave Marcus room to explain. Next time, close with a clearer shared action."
        )
    }
}
