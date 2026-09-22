import Combine
import Foundation

// Single shared source of truth for the things that used to be hardcoded
// literals scattered across LearnView/ProgressDashboardView/ProfileView:
// streak, energy, and which lessons are completed.
// In-memory + iCloud key-value storage (see CloudStore) for the real data,
// plain UserDefaults for the two debug-only toggles -- still no custom
// server-side backend or user database, just Apple's own per-Apple-ID sync,
// which is what lets this survive a reinstall or follow the user to a new
// device once they've signed in with Apple (see AccountStore).
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

    // Badges newly crossed into "earned" by a completion, queued for the UI
    // to announce -- separate from `earnedBadges` below, which only ever
    // answers "is this earned right now" and has no memory of when. Never
    // persisted: missing an announcement across a relaunch (the app was
    // killed mid-banner) is a shrug, not a bug worth a stored flag for, and
    // the badge itself is still there, unannounced, the next time it's
    // computed. Appended to, not replaced, so two completions finished in
    // quick succession both get their moment rather than the second
    // clobbering the first. The UI never mutates this directly -- see
    // `dismissCurrentBadgeAnnouncement()`.
    @Published var pendingBadgeAnnouncements: [PoiseBadge] = []
    @Published private(set) var energyRemaining: Int
    // Whether the user is on Poise Pro. Owned by RevenueCat and pushed down
    // here by SubscriptionStore.applyEntitlement -- never set directly, or the
    // app could believe someone is subscribed when the store disagrees.
    //
    // Cached in iCloud key-value storage (see CloudStore), not just
    // UserDefaults, for two reasons: the correct cap and regen interval are
    // in place on the very first frame after launch, before the entitlement
    // check returns (that check then confirms or corrects it); and on a
    // fresh install on a second device, this cache -- like sessions, energy
    // and lastRegenDate below -- is already right before RevenueCat's own
    // async lookup even completes.
    @Published private(set) var isPremium: Bool {
        didSet {
            CloudStore.store.set(isPremium, forKey: Self.premiumKey)
            // The cap just changed -- reconcile immediately (e.g. clamp down
            // if energy was sitting above the new, lower free cap) rather
            // than waiting for the next regen tick.
            energyRemaining = min(energyRemaining, energyCap)
            // Same reasoning as energyRemaining just above: a lapsed Pro
            // subscription can drop maxWeeklyGoal below whatever the user
            // had set it to, so clamp it down right away rather than
            // leaving a goal the current tier can't support.
            weeklyGoal = min(weeklyGoal, maxWeeklyGoal)
            // The regen interval changed with the tier, so the pending
            // deadline was computed against the wrong one -- catch up now
            // rather than leaving a countdown that is off by hours.
            applyRegenIfNeeded(now: Date())
            persist()
        }
    }

    // Set only by redeeming a Shipaton-judge code (see
    // ConversationEngineClient.redeemCode / energy.js: redeemJudgeCode).
    // Deliberately independent of isPremium/RevenueCat: a judge account isn't
    // "purchased," and tying it to isPremium would have it overwritten the
    // next time SubscriptionStore syncs the real (non-)entitlement. It only
    // ever widens the energy cap -- lessons themselves were never Pro-gated,
    // just energy-gated, so that's the one lever a judge actually needs.
    @Published private(set) var isJudge: Bool {
        didSet {
            CloudStore.store.set(isJudge, forKey: Self.judgeKey)
            // Losing judge status (rare, but possible) can shrink the cap
            // just like a lapsed Pro subscription -- catch the weekly goal
            // the same way, immediately rather than on next regen tick.
            weeklyGoal = min(weeklyGoal, maxWeeklyGoal)
        }
    }
    @Published private(set) var judgeEnergyCap: Int {
        didSet {
            CloudStore.store.set(judgeEnergyCap, forKey: Self.judgeCapKey)
            weeklyGoal = min(weeklyGoal, maxWeeklyGoal)
        }
    }

    // The user's own target for conversations per week, shown on the Learn
    // header and the Progress dashboard. Bounded by maxWeeklyGoal below so
    // it can't be pushed past what the current energy tier can actually
    // support. Defaults to 5, matching the constant this replaced, so
    // nothing changes for an existing user until they open the new
    // setting themselves.
    //
    // Persisted through CloudStore for the same reasons as isPremium
    // above: correct on the very first frame after launch, and already
    // right on a second device before any async lookup completes.
    @Published private(set) var weeklyGoal: Int {
        didSet { CloudStore.store.set(weeklyGoal, forKey: Self.weeklyGoalKey) }
    }

    private static let sessionsKey = "poise.sessions"
    private static let dayOffsetKey = "poise.debugDayOffset"
    private static let skipRoleplayKey = "poise.debugSkipRoleplay"
    private static let energyKey = "poise.energyRemaining"
    private static let lastRegenKey = "poise.lastEnergyRegenDate"
    private static let premiumKey = "poise.isPremium"
    private static let judgeKey = "poise.isJudge"
    private static let judgeCapKey = "poise.judgeEnergyCap"
    private static let weeklyGoalKey = "poise.weeklyGoal"
    private static let defaultWeeklyGoal = 5

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

    private var changeObserver: NSObjectProtocol?

    private init() {
        let defaults = UserDefaults.standard
        // Only the four real-data keys migrate -- the debug toggles below
        // stay local, deliberately (see their own comments).
        CloudStore.migrateIfNeeded(Self.premiumKey)
        CloudStore.migrateIfNeeded(Self.energyKey)
        CloudStore.migrateIfNeeded(Self.lastRegenKey)
        CloudStore.migrateIfNeeded(Self.sessionsKey)
        CloudStore.migrateIfNeeded(Self.weeklyGoalKey)
        let cloud = CloudStore.store

        isPremium = cloud.bool(forKey: Self.premiumKey)
        isJudge = cloud.bool(forKey: Self.judgeKey)
        judgeEnergyCap = cloud.object(forKey: Self.judgeCapKey) != nil
            ? Int(cloud.longLong(forKey: Self.judgeCapKey)) : Self.premiumEnergyCap
        weeklyGoal = cloud.object(forKey: Self.weeklyGoalKey) != nil
            ? Int(cloud.longLong(forKey: Self.weeklyGoalKey)) : Self.defaultWeeklyGoal
        #if DEBUG
        debugDayOffset = defaults.integer(forKey: Self.dayOffsetKey)
        // Defaults on: this was added because the roleplay is the slow part of
        // every trip to the results screen. Flip it off to exercise the real flow.
        debugSkipRoleplay = defaults.object(forKey: Self.skipRoleplayKey) as? Bool ?? true
        #else
        // Release must never read either debug key back out of UserDefaults.
        // A device that was ever used for Debug testing (including a TestFlight
        // build built with Debug config, or a device that ran this app in the
        // simulator during development) would otherwise carry a persisted `true`
        // for debugSkipRoleplay straight into a real user's App Store install --
        // silently skipping every roleplay while still charging energy for it.
        // Both toggles are testing-only and unreachable in Release anyway (see
        // ProfileView's Testing section), so Release always starts them clean
        // rather than trusting anything already on disk.
        debugDayOffset = 0
        debugSkipRoleplay = false
        #endif
        if cloud.object(forKey: Self.energyKey) != nil {
            energyRemaining = Int(cloud.longLong(forKey: Self.energyKey))
        } else {
            energyRemaining = Self.freeEnergyCap
        }
        lastRegenDate = cloud.object(forKey: Self.lastRegenKey) as? Date ?? Date()
        if let data = cloud.data(forKey: Self.sessionsKey),
           let decoded = try? JSONDecoder().decode([SessionRecord].self, from: data) {
            sessions = decoded.sorted { $0.finishedAt < $1.finishedAt }
            completedLessonIDs = Set(sessions.map(\.lessonID))
        }

        changeObserver = CloudStore.observeChanges { [weak self] changedKeys in
            self?.applyExternalChanges(changedKeys)
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

    // Adopts the server's ledger. On the live path the server is the one
    // counting -- it is what actually bounds billable calls -- so whenever a
    // response carries its state, the local copy is overwritten rather than
    // reconciled. Cap is derived from the tier the server verified, which is
    // also more trustworthy than the cached isPremium.
    func applyServerEnergy(_ energy: ServerEnergy) {
        // A cap above Pro's can only mean the server has this account marked
        // as a judge (see energy.js: JUDGE_CAP) -- isPremium is left alone so
        // a later RevenueCat sync doesn't fight this over Pro status, which
        // redeeming a judge code was never meant to claim.
        if energy.cap > Self.premiumEnergyCap {
            isJudge = true
            judgeEnergyCap = energy.cap
        } else if energy.cap != energyCap {
            isPremium = energy.cap == Self.premiumEnergyCap
        }
        energyRemaining = max(0, min(energy.cap, energy.remaining))
        // Back-derive the anchor so the local countdown matches the server's
        // nextRegenAt; at cap the server sends nil and the clock is idle.
        if let next = energy.nextRegenDate {
            lastRegenDate = next.addingTimeInterval(-regenInterval)
        } else {
            lastRegenDate = Date()
        }
        persist()
    }

    func applyEntitlement(isPro: Bool) {
        guard isPremium != isPro else { return }
        isPremium = isPro
    }

    var energyCap: Int {
        if isJudge { return judgeEnergyCap }
        return isPremium ? Self.premiumEnergyCap : Self.freeEnergyCap
    }

    var regenInterval: TimeInterval { (isPremium || isJudge) ? Self.premiumRegenInterval : Self.freeRegenInterval }

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
        let cloud = CloudStore.store
        cloud.set(energyRemaining, forKey: Self.energyKey)
        cloud.set(lastRegenDate, forKey: Self.lastRegenKey)
    }

    private func persistSessions() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        CloudStore.store.set(data, forKey: Self.sessionsKey)
    }

    // Another device changed one of the four real-data keys (session
    // history, energy, its regen clock, or the cached Pro flag) -- pull the
    // new value in rather than waiting for a relaunch to notice. The debug
    // keys are never in `changedKeys`: they were never migrated to iCloud in
    // the first place (see init), so they never change externally.
    private func applyExternalChanges(_ changedKeys: [String]) {
        let cloud = CloudStore.store
        if changedKeys.contains(Self.sessionsKey),
           let data = cloud.data(forKey: Self.sessionsKey),
           let decoded = try? JSONDecoder().decode([SessionRecord].self, from: data) {
            sessions = decoded.sorted { $0.finishedAt < $1.finishedAt }
        }
        if changedKeys.contains(Self.energyKey) {
            energyRemaining = Int(cloud.longLong(forKey: Self.energyKey))
        }
        if changedKeys.contains(Self.lastRegenKey) {
            lastRegenDate = cloud.object(forKey: Self.lastRegenKey) as? Date ?? lastRegenDate
        }
        if changedKeys.contains(Self.premiumKey) {
            isPremium = cloud.bool(forKey: Self.premiumKey)
        }
        if changedKeys.contains(Self.judgeKey) {
            isJudge = cloud.bool(forKey: Self.judgeKey)
        }
        if changedKeys.contains(Self.judgeCapKey) {
            judgeEnergyCap = Int(cloud.longLong(forKey: Self.judgeCapKey))
        }
        if changedKeys.contains(Self.weeklyGoalKey) {
            weeklyGoal = Int(cloud.longLong(forKey: Self.weeklyGoalKey))
        }
    }

    // Ordinary lessons are never gated: they are workplace scenarios a manager
    // picks by what they're facing this week, not a language course where
    // lesson 4 presumes lesson 3.
    //
    // A checkpoint is the exception, because it is not a scenario you're
    // facing -- it's the unit's assessment, synthesized from two specific
    // lessons in it, and it deliberately withholds its criteria (no guide
    // screen, skill tiers instead of a checklist). That design only works if
    // you've done the lessons. Someone who jumps straight in gets an unguided
    // conversation scored on three dimensions nobody ever explained, and
    // concludes the app is vague rather than that they skipped ahead.
    //
    // Completion is checked first and deliberately: a checkpoint that has been
    // passed stays unlocked forever, even if a lesson is later added to the
    // unit. Re-locking something already earned would read as losing it.
    func state(for lessonID: String) -> LessonNodeState {
        if completedLessonIDs.contains(lessonID) { return .completed }
        guard let content = PoiseLessonLibrary.all.first(where: { $0.id == lessonID }),
              content.isCheckpoint
        else { return .available }
        return unlockProgress(forUnit: content.unitNumber).isUnlocked ? .available : .locked
    }

    // How close a unit's checkpoint is to unlocking. Returned rather than a
    // bare Bool so the locked row can say what remains ("2 of 4 done") instead
    // of showing a padlock with no way to read it.
    func unlockProgress(forUnit unitNumber: Int) -> (done: Int, total: Int, isUnlocked: Bool) {
        let lessons = PoiseLessonLibrary.all.filter { $0.unitNumber == unitNumber && !$0.isCheckpoint }
        let done = lessons.filter { completedLessonIDs.contains($0.id) }.count
        // An empty unit would otherwise report locked forever with nothing the
        // user could do about it.
        return (done, lessons.count, lessons.isEmpty || done == lessons.count)
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
        // Snapshot what's earned before this session lands, so afterwards a
        // plain diff tells us which badges this exact completion crossed --
        // never a single Optional, because one completion can finish a unit
        // AND extend a streak in the same call, and both deserve their
        // banner.
        let earnedBefore = Set(earnedBadges.map(\.id))
        sessions.append(record)
        persistSessions()
        // The scenario you just played is spent. Clearing it here -- and only
        // here -- is what makes "the lesson changes after you finish it" true.
        ScenarioCache.invalidate(lessonID: lessonID)
        // They just practised, so today's streak reminder (if one was
        // pending from an earlier backgrounding) is now moot -- cancel it
        // rather than let it fire later and nag about something already
        // done. The come-back reminder is untouched: it isn't about today,
        // it's about the days after this one if the app goes untouched.
        NotificationService.shared.cancelStreakReminder()
        let newlyEarned = earnedBadges.filter { !earnedBefore.contains($0.id) }
        if !newlyEarned.isEmpty {
            pendingBadgeAnnouncements.append(contentsOf: newlyEarned)
        }
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

    // What the Learn page's "Up next" offers: literally the next lesson
    // after the one most recently finished, in curriculum order -- NOT the
    // first unfinished lesson in that lesson's unit. Those differ the moment
    // someone skips ahead on purpose (ordinary lessons are never gated, see
    // state(for:) -- "a menu, not a ladder", per LearnView.swift), which used
    // to pull Up Next backward to whatever earlier lesson they'd
    // deliberately passed over instead of acknowledging what they just did.
    // Wraps around the whole curriculum, so finishing the last lesson lands
    // back on the first. Nil once everything is done. With nothing completed
    // yet this is simply Unit 1, Lesson 1.
    var upNext: (unit: LessonUnit, lesson: LessonNode, lessonNumber: Int)? {
        let flat = units.flatMap { unit in
            unit.lessons.enumerated().map { index, lesson in (unit: unit, lesson: lesson, lessonNumber: index + 1) }
        }
        guard !flat.isEmpty else { return nil }

        let startIndex = lastCompletedLessonID
            .flatMap { id in flat.firstIndex { $0.lesson.id == id } }
            .map { $0 + 1 } ?? 0

        for offset in 0..<flat.count {
            let candidate = flat[(startIndex + offset) % flat.count]
            // `.available`, not merely "not completed" -- a locked checkpoint
            // must never be offered as the next thing to do. Skipping past
            // one here (rather than stopping) is what correctly falls
            // through to the next unit once a locked checkpoint is the only
            // thing standing between "last completed" and real content.
            if candidate.lesson.state == .available {
                return candidate
            }
        }
        return nil
    }

    // All units with their lessons in curriculum order, states
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
            return LessonUnit(id: "unit-\(unitNumber)", label: info.label, title: info.title, shortTitle: info.shortTitle, subtitle: info.subtitle, lessons: lessons)
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

    // The ceiling on the user-configurable weeklyGoal above, tied to the
    // energy tier's real cap rather than a made-up number: free (cap 3)
    // tops out at 6, Pro (cap 12) at 24, and a judge account (cap 999) at
    // 1998 -- a ceiling no judge account will ever actually reach. Always
    // computed fresh from energyCap, never cached, so it reflects a tier
    // change (e.g. a lapsed Pro subscription) the moment it happens.
    var maxWeeklyGoal: Int { energyCap * 2 }

    // The only way to change weeklyGoal -- clamps to 1...maxWeeklyGoal so
    // a caller can never push it out of bounds even by mistake.
    func setWeeklyGoal(_ value: Int) {
        weeklyGoal = min(max(1, value), maxWeeklyGoal)
    }

    // Conversations finished in the last 7 days including today. Counts
    // sessions, not days -- two conversations in an evening are two.
    var conversationsThisWeek: Int {
        guard let cutoff = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) else { return 0 }
        return sessions.filter { $0.finishedAt >= cutoff }.count
    }

    var remainingThisWeek: Int { max(0, weeklyGoal - conversationsThisWeek) }

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
        case "unit-1", "unit-2", "unit-3", "unit-4", "unit-5":
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

    // The only way the announcement queue shrinks -- pops the front rather
    // than letting the UI splice the array itself, so there's exactly one
    // place that can get "which one just finished showing" wrong. Called once
    // a banner's auto-dismiss timer fires or the user taps it away; safe to
    // call on an empty queue (e.g. a duplicate tap racing the timer).
    func dismissCurrentBadgeAnnouncement() {
        guard !pendingBadgeAnnouncements.isEmpty else { return }
        pendingBadgeAnnouncements.removeFirst()
    }
}
