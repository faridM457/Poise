import Combine
import Foundation

// Single shared source of truth for the things that used to be hardcoded
// literals scattered across LearnView/ProgressDashboardView/ProfileView:
// streak, energy, and which of the 20 lessons are completed/available/locked.
// In-memory + UserDefaults only (no backend) -- this is a prototype's
// progress tracking, not a real account system.
@MainActor
final class LearnProgressStore: ObservableObject {
    static let shared = LearnProgressStore()

    static let freeEnergyCap = 3
    static let premiumEnergyCap = 10
    static let regenInterval: TimeInterval = 8 * 60 * 60

    @Published private(set) var completedLessonIDs: Set<String> = []
    // Which lesson was finished most recently. A Set can't answer "which unit
    // was the user last working in", and that's what the Learn hero keys off.
    // In-memory only, like completedLessonIDs -- persisting one without the
    // other would leave a pointer to a lesson no longer marked complete.
    @Published private(set) var lastCompletedLessonID: String?
    @Published private(set) var energyRemaining: Int
    // Mocked subscription flag -- no real StoreKit/IAP integration exists
    // yet, this is just a boolean for testing free vs. premium energy
    // behavior. Toggle lives on the Profile screen. Premium works the same
    // as free mechanically (still decrements per completed lesson, still
    // regenerates 1 / 8 real-world hours) -- only the cap differs (3 vs 10).
    @Published var isPremium: Bool {
        didSet {
            UserDefaults.standard.set(isPremium, forKey: Self.premiumKey)
            // The cap just changed -- reconcile immediately (e.g. clamp down
            // if energy was sitting above the new, lower free cap) rather
            // than waiting for the next regen tick.
            energyRemaining = min(energyRemaining, energyCap)
            persist()
        }
    }

    // Stable mock value, not wired to any real streak-tracking logic.
    let streak = 7

    private static let energyKey = "poise.energyRemaining"
    private static let lastRegenKey = "poise.lastEnergyRegenDate"
    private static let premiumKey = "poise.isPremiumMock"

    private var lastRegenDate: Date

    private init() {
        let defaults = UserDefaults.standard
        isPremium = defaults.bool(forKey: Self.premiumKey)
        if defaults.object(forKey: Self.energyKey) != nil {
            energyRemaining = defaults.integer(forKey: Self.energyKey)
        } else {
            energyRemaining = Self.freeEnergyCap
        }
        lastRegenDate = defaults.object(forKey: Self.lastRegenKey) as? Date ?? Date()
        applyRegenIfNeeded(now: Date())
        seedDevProgress()
    }

    // DEV SEED -- Unit 1 pre-completed so the finished-unit styling (and the
    // hero rolling over to Unit 2, Lesson 1) can be inspected without playing
    // through five lessons. Delete this method and its call to go back to an
    // empty account.
    private func seedDevProgress() {
        completedLessonIDs = Set(PoiseLessonLibrary.all.filter { $0.unitNumber == 1 }.map(\.id))
        lastCompletedLessonID = PoiseLessonLibrary.all.last { $0.unitNumber == 1 }?.id
    }

    var energyCap: Int { isPremium ? Self.premiumEnergyCap : Self.freeEnergyCap }

    var energyDisplayText: String { "\(energyRemaining)/\(energyCap)" }

    // Call on app foreground/launch to catch up on elapsed real-world regen
    // (see PoiseRootView's scenePhase observer) -- regen is time-based, not
    // tied to app launches themselves.
    func refreshRegen() {
        applyRegenIfNeeded(now: Date())
    }

    private func applyRegenIfNeeded(now: Date) {
        let cap = energyCap
        guard energyRemaining < cap else {
            lastRegenDate = now
            persist()
            return
        }
        let elapsed = now.timeIntervalSince(lastRegenDate)
        let periods = Int(elapsed / Self.regenInterval)
        guard periods > 0 else { return }
        energyRemaining = min(cap, energyRemaining + periods)
        // Once capped, anchor to `now` rather than carrying the leftover
        // fractional period forward -- unclaimed regen shouldn't accumulate
        // past the cap.
        lastRegenDate = energyRemaining >= cap
            ? now
            : lastRegenDate.addingTimeInterval(TimeInterval(periods) * Self.regenInterval)
        persist()
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(energyRemaining, forKey: Self.energyKey)
        defaults.set(lastRegenDate, forKey: Self.lastRegenKey)
    }

    // No chronological gating: every lesson in every unit is startable at any
    // time, in any order. These are workplace scenarios a manager picks by
    // what they're facing this week, not a language course where lesson 4
    // presumes lesson 3 -- so `.locked` is never returned. Completion is still
    // tracked (it drives per-unit progress and the weekly activity card), it
    // just no longer gates anything.
    func state(for lessonID: String) -> LessonNodeState {
        completedLessonIDs.contains(lessonID) ? .completed : .available
    }

    // Deliberately no HARD gating here based on energyRemaining -- starting
    // a lesson at 0 energy is still allowed (LearnView surfaces a dismissable
    // warning instead, purely for testing purposes).
    func markCompleted(_ lessonID: String) {
        // Set outside the guard: replaying a finished lesson still counts as
        // "the unit I was last working in", even though it adds no progress.
        lastCompletedLessonID = lessonID
        guard !completedLessonIDs.contains(lessonID) else { return }
        completedLessonIDs.insert(lessonID)
        energyRemaining = max(0, energyRemaining - 1)
        persist()
    }

    // What the Learn page's "Up next" offers: the first unfinished lesson in
    // the unit the user most recently worked in. If that unit is finished,
    // move to the next unit, wrapping around the curriculum -- so finishing
    // Unit 1's last lesson lands on Unit 2's first. Nil once everything is
    // done. With nothing completed yet this is simply Unit 1, Lesson 1.
    var upNext: (unit: LessonUnit, lesson: LessonNode, lessonNumber: Int)? {
        let allUnits = units
        guard !allUnits.isEmpty else { return nil }

        let startIndex = lastCompletedLessonID
            .flatMap { id in allUnits.firstIndex { $0.lessons.contains { $0.id == id } } } ?? 0

        for offset in 0..<allUnits.count {
            let unit = allUnits[(startIndex + offset) % allUnits.count]
            if let index = unit.lessons.firstIndex(where: { $0.state != .completed }) {
                return (unit, unit.lessons[index], index + 1)
            }
        }
        return nil
    }

    // All 4 units, each with its 5 lessons in curriculum order, states
    // computed fresh from completedLessonIDs on every access.
    var units: [LessonUnit] {
        let grouped = Dictionary(grouping: PoiseLessonLibrary.all, by: \.unitNumber)
        return grouped.keys.sorted().compactMap { unitNumber -> LessonUnit? in
            guard let contents = grouped[unitNumber], let info = PoiseLessonLibrary.unitInfo[unitNumber] else {
                return nil
            }
            let lessons = contents.map { content in
                LessonNode(
                    id: content.id,
                    title: content.title,
                    state: state(for: content.id),
                    icon: content.icon,
                    isCheckpoint: content.isCheckpoint,
                    skipGuide: content.isCheckpoint,
                    hintsEnabled: !content.isCheckpoint,
                    engineLessonId: content.id,
                    shortTitle: content.shortTitle,
                    character: content.character,
                    estimatedMinutes: content.estimatedMinutes
                )
            }
            return LessonUnit(id: "unit-\(unitNumber)", label: info.label, title: info.title, subtitle: info.subtitle, lessons: lessons)
        }
    }
}
