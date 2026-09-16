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
    static let premiumEnergyCap = 12

    // Pro changes both halves of the energy model, not just the ceiling: a
    // bigger reserve AND a faster refill. Free is one unit per 8 hours (3 a
    // day); Pro is one per 2 hours (12 a day), which is why its cap is 12 --
    // a full day of regen fills exactly one full reserve.
    static let freeRegenInterval: TimeInterval = 8 * 60 * 60
    static let premiumRegenInterval: TimeInterval = 2 * 60 * 60

    // Every finished conversation, oldest first. The single source of truth:
    // completions, the practice calendar, the streak, the weekly goal, the
    // checkpoint results and all badges are computed from this one list, so
    // none of them can disagree with another. Persisted -- energy used to
    // survive a relaunch while progress didn't, so you could lose everything
    // you'd done and keep the depletion it cost you.
    @Published private(set) var sessions: [SessionRecord] = [] {
        didSet { completedLessonIDs = Set(sessions.map(\.lessonID)) }
    }

    // Cached rather than computed on every access. `units` asks `state(for:)`
    // once per lesson, so a computed set rebuilt the whole thing 20 times per
    // render of the Learn grid.
    @Published private(set) var completedLessonIDs: Set<String> = []
    @Published private(set) var energyRemaining: Int
    // Whether the user is on Poise Pro. Owned by RevenueCat and pushed down
    // here by SubscriptionStore.applyEntitlement -- never set directly, or the
    // app could believe someone is subscribed when the store disagrees.
    //
    // Cached in UserDefaults so the correct cap and regen interval are in
    // place on the very first frame after launch, before the entitlement
    // check returns. The check then confirms or corrects it.
    @Published private(set) var isPremium: Bool {
        didSet {
            UserDefaults.standard.set(isPremium, forKey: Self.premiumKey)
            // The cap just changed -- reconcile immediately (e.g. clamp down
            // if energy was sitting above the new, lower free cap) rather
            // than waiting for the next regen tick.
            energyRemaining = min(energyRemaining, energyCap)
            // The regen interval changed with the tier, so the pending
            // deadline was computed against the wrong one -- catch up now
            // rather than leaving a countdown that is off by hours.
            applyRegenIfNeeded(now: Date())
            persist()
        }
    }


    private static let sessionsKey = "poise.sessions"
    private static let dayOffsetKey = "poise.debugDayOffset"
    private static let skipRoleplayKey = "poise.debugSkipRoleplay"
    private static let energyKey = "poise.energyRemaining"
    private static let lastRegenKey = "poise.lastEnergyRegenDate"
    private static let premiumKey = "poise.isPremium"

    private var lastRegenDate: Date

    // TESTING ONLY -- days to shift "today" by, always <= 0. A streak needs
    // practice on consecutive real days, which cannot be produced in one
    // sitting, so this moves the app's idea of today backwards: stand on
    // yesterday, finish a lesson, come back to today, finish another, and the
    // streak is 2. Only the progress clock moves (completions, calendar,
    // streak, weekly count); energy regen keeps the real clock, since running
    // its 8-hour countdown backwards would just corrupt the balance -- the
    // energy cheats next to this one cover that case directly.
    @Published var debugDayOffset: Int {
        didSet { UserDefaults.standard.set(debugDayOffset, forKey: Self.dayOffsetKey) }
    }

    // The app's "today" for everything progress-related. Real Date() in normal
    // use, since the offset is 0 unless a tester has moved it.
    var now: Date {
        guard debugDayOffset != 0 else { return Date() }
        return Calendar.current.date(byAdding: .day, value: debugDayOffset, to: Date()) ?? Date()
    }

    var isTimeTravelling: Bool { debugDayOffset != 0 }

    // TESTING ONLY -- send "Let's practice" straight to the scorecard instead
    // of running the roleplay. Energy is still spent, so the cost model and
    // the out-of-energy block behave exactly as they do in a real run; only
    // the conversation itself is skipped.
    @Published var debugSkipRoleplay: Bool {
        didSet { UserDefaults.standard.set(debugSkipRoleplay, forKey: Self.skipRoleplayKey) }
    }

    private init() {
        let defaults = UserDefaults.standard
        isPremium = defaults.bool(forKey: Self.premiumKey)
        debugDayOffset = defaults.integer(forKey: Self.dayOffsetKey)
        // Defaults on: this was added because the roleplay is the slow part of
        // every trip to the results screen. Flip it off to exercise the real flow.
        debugSkipRoleplay = defaults.object(forKey: Self.skipRoleplayKey) as? Bool ?? true
        if defaults.object(forKey: Self.energyKey) != nil {
            energyRemaining = defaults.integer(forKey: Self.energyKey)
        } else {
            energyRemaining = Self.freeEnergyCap
        }
        lastRegenDate = defaults.object(forKey: Self.lastRegenKey) as? Date ?? Date()
        if let data = defaults.data(forKey: Self.sessionsKey),
           let decoded = try? JSONDecoder().decode([SessionRecord].self, from: data) {
            sessions = decoded.sorted { $0.finishedAt < $1.finishedAt }
            completedLessonIDs = Set(sessions.map(\.lessonID))
        }
        applyRegenIfNeeded(now: Date())
    }


    // MARK: - Completions

    // Which lesson was finished most recently -- what the Learn hero keys off
    // to decide which unit "Up next" should continue.
    var lastCompletedLessonID: String? {
        sessions.last?.lessonID
    }

    // Wipes all progress. Used by the Profile screen's reset.
    func resetProgress() {
        sessions = []
        persistSessions()
        // Otherwise a reset account would reopen every lesson holding the
        // scenario its previous owner had already worked through.
        ScenarioCache.invalidateAll()
    }

    func applyEntitlement(isPro: Bool) {
        guard isPremium != isPro else { return }
        isPremium = isPro
    }

    var energyCap: Int { isPremium ? Self.premiumEnergyCap : Self.freeEnergyCap }

    var regenInterval: TimeInterval { isPremium ? Self.premiumRegenInterval : Self.freeRegenInterval }

    // For copy that has to name the cadence ("one back every N hours").
    var regenHours: Int { Int(regenInterval / 3600) }

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
        let periods = Int(elapsed / regenInterval)
        guard periods > 0 else { return }
        energyRemaining = min(cap, energyRemaining + periods)
        // Once capped, anchor to `now` rather than carrying the leftover
        // fractional period forward -- unclaimed regen shouldn't accumulate
        // past the cap.
        lastRegenDate = energyRemaining >= cap
            ? now
            : lastRegenDate.addingTimeInterval(TimeInterval(periods) * regenInterval)
        persist()
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(energyRemaining, forKey: Self.energyKey)
        defaults.set(lastRegenDate, forKey: Self.lastRegenKey)
    }

    private func persistSessions() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        UserDefaults.standard.set(data, forKey: Self.sessionsKey)
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

    // Records a finished conversation. A replay appends a second record
    // rather than being discarded: it happened, it cost energy, it produced
    // its own scores, and the calendar should show the day it was practised.
    // `completedLessonIDs` de-duplicates by lesson id, so unit progress still
    // counts a replayed lesson once.
    func recordCompletion(
        lessonID: String,
        skillLevels: [PoiseSkill: SkillLevel],
        criteriaMet: Int,
        criteriaTotal: Int
    ) {
        let content = PoiseLessonLibrary.all.first { $0.id == lessonID }
        let record = SessionRecord(
            lessonID: lessonID,
            unitNumber: content?.unitNumber ?? 0,
            isCheckpoint: content?.isCheckpoint ?? false,
            finishedAt: now,
            skillLevels: skillLevels.reduce(into: [:]) { $0[$1.key.rawValue] = $1.value.rawValue },
            criteriaMet: criteriaMet,
            criteriaTotal: criteriaTotal
        )
        sessions.append(record)
        persistSessions()
        // The scenario you just played is spent. Clearing it here -- and only
        // here -- is what makes "the lesson changes after you finish it" true.
        ScenarioCache.invalidate(lessonID: lessonID)
    }

    // MARK: - Testing helpers
    //
    // Wired to the Testing card at the foot of the Profile screen. Energy
    // regenerates on an 8-hour real-world clock, which makes both ends of the
    // range -- empty and full -- impossible to reach on demand while working
    // on the screens that depend on them. Delete this section and that card
    // together when the app ships.

    func grantEnergy(_ amount: Int = 1) {
        energyRemaining = min(energyCap, energyRemaining + amount)
        // At the cap nothing is pending, so the regen clock restarts from now
        // rather than carrying a stale deadline that would hand out a free
        // unit the moment one is spent.
        if energyRemaining >= energyCap { lastRegenDate = Date() }
        persist()
    }

    // Steps the progress clock back a day, floor -365. There is no forward
    // step past today: the point is to fill in history behind you, and a
    // future-dated session would sit in the calendar as a day you cannot have
    // practised. "Today" returns to the real date.
    func stepBackOneDay() {
        debugDayOffset = max(-365, debugDayOffset - 1)
    }

    func returnToToday() {
        debugDayOffset = 0
    }

    func drainEnergy() {
        energyRemaining = 0
        // Start the 8-hour countdown from the drain, so the popup's "next in"
        // reads like a real depletion rather than resuming a half-run clock.
        lastRegenDate = Date()
        persist()
    }

    // Charged when the conversation starts, because energy stands in for the
    // tokens a generated conversation costs and those are spent as soon as it
    // runs -- whether or not the user sees it through.
    //
    // Completion is deliberately NOT consulted. Replaying a finished lesson
    // generates a fresh scenario from scratch, so it burns exactly as many
    // tokens as the first run did; charging for the first attempt only would
    // have made the most-repeated lessons the free ones.
    //
    // Returns whether it actually charged. The flow now refuses to start a
    // conversation at zero (see LiveLessonFlowView.startRoleplay), so a
    // false here means something bypassed that guard -- the scorecard
    // reports what happened rather than asserting a cost either way.
    @discardableResult
    func spendEnergy() -> Bool {
        guard wouldSpendEnergy else { return false }
        energyRemaining -= 1
        persist()
        return true
    }

    // The single answer to "will this cost anything", used both by the charge
    // itself and by the cost badge shown before starting. Kept in one place so
    // the badge can't advertise a cost the charge then declines.
    var wouldSpendEnergy: Bool {
        energyRemaining > 0
    }

    // When the next unit of energy lands. Nil at full -- nothing is pending.
    var nextEnergyDate: Date? {
        guard energyRemaining < energyCap else { return nil }
        return lastRegenDate.addingTimeInterval(regenInterval)
    }

    // Exact time to the next unit of energy, evaluated against a caller-
    // supplied `now` so a view can tick it every second.
    //
    // This used to round to "about 6 hours" on the grounds that regen is only
    // applied at launch and on foreground, so a countdown would go stale. That
    // was the wrong conclusion: the deadline is a stored date, so the
    // remaining time is computable at any moment -- the fix is to re-render,
    // not to blur the number. EnergyCountdown drives that, and pokes
    // refreshRegen when the clock runs out so the balance actually moves.
    func secondsUntilNextEnergy(asOf now: Date = Date()) -> TimeInterval? {
        guard let nextEnergyDate else { return nil }
        return max(0, nextEnergyDate.timeIntervalSince(now))
    }

    func countdownText(asOf now: Date = Date()) -> String? {
        guard let seconds = secondsUntilNextEnergy(asOf: now) else { return nil }
        let total = Int(seconds.rounded())
        guard total > 0 else { return "Ready now" }
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return String(format: "%dh %02dm", hours, minutes) }
        if minutes > 0 { return String(format: "%dm %02ds", minutes, secs) }
        return "\(secs)s"
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

// MARK: - Derived progress
//
// Everything the Progress page draws. All of it reads `sessions` and nothing
// else, which is what keeps the streak on the Learn header, the streak in the
// popover and the streak on the calendar card from ever showing three numbers.
extension LearnProgressStore {
    private var calendar: Calendar { Calendar.current }

    // Monday-first, matching the calendar grid's header row.
    static let weekdayLetters = ["M", "T", "W", "T", "F", "S", "S"]

    // Distinct days on which at least one conversation was finished.
    var practiceDays: Set<Date> {
        Set(sessions.map { calendar.startOfDay(for: $0.finishedAt) })
    }

    func practised(on day: Date) -> Bool {
        practiceDays.contains(calendar.startOfDay(for: day))
    }

    var practisedToday: Bool { practised(on: now) }

    // Counts back from today, or from yesterday when today isn't done yet: a
    // streak isn't broken until a whole day has been missed.
    var currentStreak: Int {
        let days = practiceDays
        guard !days.isEmpty else { return 0 }
        let today = calendar.startOfDay(for: now)
        var cursor = days.contains(today)
            ? today
            : calendar.date(byAdding: .day, value: -1, to: today)!
        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    // The real calendar month containing today, laid out Monday-first so the
    // grid's columns line up with the M/T/W/T/F/S/S header.
    var currentMonthDays: [PracticeDay] {
        let today = calendar.startOfDay(for: now)
        guard let monthRange = calendar.range(of: .day, in: .month, for: today),
              let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today))
        else { return [] }

        // Calendar.weekday is 1=Sunday; shift so Monday is 0.
        let leading = (calendar.component(.weekday, from: firstOfMonth) + 5) % 7

        let blanks = (0..<leading).map { _ in PracticeDay(day: nil, practiced: false, isToday: false) }
        let days = monthRange.compactMap { day -> PracticeDay? in
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth) else { return nil }
            return PracticeDay(day: day, practiced: practised(on: date), isToday: calendar.isDate(date, inSameDayAs: today))
        }
        return blanks + days
    }

    var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        return formatter.string(from: now)
    }

    // MARK: Weekly goal

    static let weeklyGoal = 5

    // Conversations finished in the last 7 days including today. Counts
    // sessions, not days -- two conversations in an evening are two.
    var conversationsThisWeek: Int {
        guard let cutoff = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) else { return 0 }
        return sessions.filter { $0.finishedAt >= cutoff }.count
    }

    var remainingThisWeek: Int { max(0, Self.weeklyGoal - conversationsThisWeek) }

    // The seven days ending today, for the Learn page's activity strip.
    var weekEndingToday: [PracticeDay] {
        let today = calendar.startOfDay(for: now)
        return (0..<7).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return PracticeDay(
                day: calendar.component(.day, from: date),
                practiced: practised(on: date),
                isToday: offset == 0,
                weekday: Self.weekdayLetters[(calendar.component(.weekday, from: date) + 5) % 7]
            )
        }
    }

    // MARK: Checkpoint results

    // The most recent attempt at each unit's checkpoint, in unit order. A
    // retake replaces the earlier result rather than appending: this card
    // answers "where do I stand", not "what have I tried".
    var checkpointResults: [(unitNumber: Int, record: SessionRecord?)] {
        let unitNumbers = Set(PoiseLessonLibrary.all.map(\.unitNumber)).sorted()
        return unitNumbers.map { unit in
            (unit, sessions.last { $0.isCheckpoint && $0.unitNumber == unit })
        }
    }

    // MARK: Badges

    func hasEarned(_ badge: PoiseBadge) -> Bool {
        let completed = completedLessonIDs
        switch badge.id {
        case "first-words":
            return !sessions.isEmpty
        case "full-circle":
            return completed.count >= PoiseLessonLibrary.all.count
        case "unit-1", "unit-2", "unit-3", "unit-4":
            guard let unit = Int(badge.id.dropFirst("unit-".count)) else { return false }
            let lessons = PoiseLessonLibrary.all.filter { $0.unitNumber == unit }
            return !lessons.isEmpty && lessons.allSatisfy { completed.contains($0.id) }
        case "checkpoint-clarity":
            return hasStrongCheckpoint(in: .clarity)
        case "checkpoint-empathy":
            return hasStrongCheckpoint(in: .empathy)
        case "checkpoint-resolution":
            return hasStrongCheckpoint(in: .resolution)
        case "streak-3":
            return longestStreak >= 3
        case "streak-7":
            return longestStreak >= 7
        case "streak-30":
            return longestStreak >= 30
        default:
            return false
        }
    }

    private func hasStrongCheckpoint(in skill: PoiseSkill) -> Bool {
        sessions.contains { $0.isCheckpoint && $0.level(for: skill) == .strong }
    }

    // Badges are earned, not rented: a streak badge stays won once the run
    // that earned it happened, so this measures the best run in history
    // rather than the one currently alive.
    var longestStreak: Int {
        let days = practiceDays.sorted()
        guard !days.isEmpty else { return 0 }
        var best = 1
        var run = 1
        for index in 1..<days.count {
            let previous = calendar.date(byAdding: .day, value: 1, to: days[index - 1])
            if let previous, calendar.isDate(previous, inSameDayAs: days[index]) {
                run += 1
                best = max(best, run)
            } else {
                run = 1
            }
        }
        return best
    }

    var earnedBadges: [PoiseBadge] { PoiseBadgeCatalogue.all.filter(hasEarned) }
}
