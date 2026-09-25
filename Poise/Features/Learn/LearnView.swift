import SwiftUI
import UIKit

// MARK: - Page
//
// Learn/Home is built on three deliberate rules so the page reads as one
// designed surface instead of a stack of unrelated widgets:
//
//  1. ONE type ladder -- everything here uses PoiseType (eyebrow / caption /
//     subhead / body / headline / title). No ad-hoc `.system(size:)` calls.
//  2. ONE surface treatment -- every card is white with a hairline border and
//     the same soft shadow (`poiseCard`). The single exception is the hero,
//     which is the page's only tinted block.
//  3. Color carries MEANING, not decoration -- per-unit accents appear only
//     in a small icon badge and that unit's progress fill. Card backgrounds
//     stay neutral so the units don't read as different components.
//
// Units are a menu, not a ladder: every ordinary lesson is startable at any
// time, in any order. The one exception is a unit's checkpoint, which stays
// locked until that unit's lessons are done -- see LearnProgressStore's
// state(for:) for why the "pick what you need" rule doesn't extend to it.
struct LearnView: View {
    @ObservedObject private var store = LearnProgressStore.shared
    @ObservedObject private var subscriptions = SubscriptionStore.shared
    @State private var activeLesson: LessonNode?
    @State private var showCustomScenario = false
    @State private var showPaywall = false
    // The unit whose lesson list is open. Presented as a sheet rather than a
    // pushed screen: a NavigationStack here would swallow the tab bar's bottom
    // safeAreaInset (see PoiseRootView), and this is a pick-one-and-go detour,
    // not a place to live.
    @State private var detailUnit: LessonUnit?
    // A lesson chosen inside that sheet. It can't be started until the sheet
    // has actually gone away -- setting a fullScreenCover while a sheet is
    // dismissing drops the presentation -- so it waits for onDismiss.
    @State private var pendingLesson: LessonNode?

    private var units: [LessonUnit] { store.units }

    // Unit id is "unit-<n>", which is what the store keys unlock progress on.
    private func unlockProgress(for unit: LessonUnit) -> (done: Int, total: Int) {
        let number = Int(unit.id.dropFirst("unit-".count)) ?? 0
        let progress = store.unlockProgress(forUnit: number)
        return (progress.done, progress.total)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            pageContent
                .padding(.horizontal, 20)
                .padding(.top, 20)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            PoiseTopBar(streak: store.currentStreak, energyText: store.energyDisplayText)
        }
        // Painted as a background rather than a ZStack sibling: a sibling with
        // .ignoresSafeArea() expands the ZStack's bounds, and the ScrollView
        // next to it then loses the root's bottom tab-bar inset entirely.
        .background(Color.poiseCanvas.ignoresSafeArea())
        .sheet(item: $detailUnit, onDismiss: startPendingLesson) { unit in
            UnitDetailSheet(
                unit: unit,
                accent: accentColor(for: units.firstIndex { $0.id == unit.id } ?? 0),
                upNextLessonID: store.upNext?.lesson.id,
                unlockProgress: unlockProgress(for: unit),
                onSelect: { lesson in
                    pendingLesson = lesson
                    detailUnit = nil
                }
            )
        }
        .poiseLessonCover(item: $activeLesson) { lesson in
            LessonFlowView(lesson: lesson) { completed in
                activeLesson = nil
                _ = completed
            }
        }
        .fullScreenCover(isPresented: $showCustomScenario) {
            CustomScenarioFlowView()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallSheet(subscriptions: subscriptions)
                .presentationBackground(Color.poiseCanvas)
        }
    }

    // Split out of `body` -- inline, the whole page was one expression and
    // the Swift type checker gave up on it ("failed to produce diagnostic").
    private var pageContent: some View {
        VStack(alignment: .leading, spacing: 26) {
            GreetingHeader(remainingThisWeek: store.remainingThisWeek)

            UpNextCard(upNext: store.upNext, onStart: attemptStart)

            PoiseSection(title: "Explore units", showsRule: true) { unitGrid }

            PoiseSection(title: "This week", showsRule: true) {
                WeeklyActivityCard(week: store.weekEndingToday, completed: store.conversationsThisWeek, goal: store.weeklyGoal)
            }

            // Its own section, not a bare card tacked on after "This week" --
            // every other block here gets an eyebrow announcing a new
            // section; without one this card had nothing to visually detach
            // it from the weekly card above, and it read as more content
            // under "THIS WEEK" instead of a separate feature.
            PoiseSection(title: "More ways to practice", showsRule: true) {
                CustomScenarioCard(action: openCustomScenario)
            }

            // Small tail of breathing room. The tab bar is a bottom
            // safeAreaInset (see PoiseRootView), so the scroll view already
            // accounts for its height -- this is just air under the last card.
            Color.clear.frame(height: 16)
        }
    }

    private var unitGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            spacing: 12
        ) {
            ForEach(Array(units.enumerated()), id: \.element.id) { index, unit in
                UnitGridCard(
                    unit: unit,
                    accent: accentColor(for: index),
                    action: { detailUnit = unit }
                )
            }
        }
    }

    private func startPendingLesson() {
        guard let lesson = pendingLesson else { return }
        pendingLesson = nil
        attemptStart(lesson)
    }

    // Opening a lesson is free -- the briefing and the guide cost nothing to
    // read. The energy check lives on the start button inside the flow (see
    // LiveLessonFlowView.startRoleplay), which is the moment a conversation
    // is actually generated. This used to block here and offer a "Start
    // anyway" escape, which spent nothing and produced a run the scorecard
    // then had to describe as free.
    private func attemptStart(_ lesson: LessonNode) {
        activeLesson = lesson
    }

    private func openCustomScenario() {
        if subscriptions.isPro {
            showCustomScenario = true
        } else {
            showPaywall = true
        }
    }

    private func accentColor(for index: Int) -> Color {
        // Five units, five accents -- with four the fifth unit wrapped back
        // to Unit 1's colour and the grid read as a repeat.
        let palette: [Color] = [.poiseMintDark, .poisePurple, .poiseOrange, .poiseBlueDark, .poiseGold]
        return palette[index % palette.count]
    }
}

private extension View {
    @ViewBuilder
    func poiseLessonCover<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        #if os(iOS)
        fullScreenCover(item: item, content: content)
        #else
        sheet(item: item, content: content)
        #endif
    }
}

// MARK: - Header

// "Good afternoon, Farid" -- no emoji (the user was explicit: never use
// literal emoji characters in this app; SF Symbols elsewhere are fine,
// this is specifically about the greeting text).
private struct GreetingHeader: View {
    let remainingThisWeek: Int

    // Observed, not read once: the name is editable on the Profile tab and
    // the greeting has to follow it. Reading UserProfileStore.shared.name
    // inline left this frozen at whatever it was when the view first built.
    @ObservedObject private var profile = UserProfileStore.shared

    private var timeOfDayGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    private var weeklyNudge: String {
        let left = remainingThisWeek
        guard left > 0 else { return "You've hit this week's goal." }
        return "\(left) more conversation\(left == 1 ? "" : "s") to hit this week's goal."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(timeOfDayGreeting)\(profile.displayNameSuffix)")
                .font(PoiseType.title())
                .foregroundStyle(Color.poiseNavy)
            // Was "One conversation at a time." -- the only line on the page
            // that told the user nothing. Deliberately says what's LEFT rather
            // than what's done: the weekly card at the foot of the page
            // already reports the count and the day-by-day shape, so a second
            // "4 of 5" here would restate it. Both read from the same
            // LearnProgressStore week, so they can't disagree.
            Text(weeklyNudge)
                .font(PoiseType.subhead())
                .foregroundStyle(Color.poiseMuted)
        }
    }
}

// MARK: - Hero

// "Up next" is a single, definite lesson -- the one LearnProgressStore.upNext
// resolves from where the user actually left off (next unfinished lesson in
// the unit they last worked in; the following unit's first lesson once that
// unit is done). It is NOT tied to the grid below: tapping a unit card opens
// that unit's lesson list, it doesn't retarget this card.
//
// Layout follows NewHomePage.png -- pale tinted card, eyebrow pill, headline,
// one detail line, an inline pill CTA, and the character bleeding to the
// trailing edge -- at a fixed compact height so the unit grid stays visible
// without scrolling.
private struct UpNextCard: View {
    let upNext: (unit: LessonUnit, lesson: LessonNode, lessonNumber: Int)?
    let onStart: (LessonNode) -> Void

    // Narrowed from 126pt. At that width the text column was 200pt and
    // "Repeated Interruptions" measured 194.3pt -- 5.7pt of headroom, so any
    // longer lesson name wrapped. 110pt gives the column 216pt.
    // Fixed, not a floor -- the banner is a flat "video tile," not something
    // that grows with its neighboring text the way the old side-by-side
    // layout's photo panel did. The text block below it just sizes to its
    // own content now, with no matching-height concern to solve.
    private static let bannerHeight: CGFloat = 175

    private var headlineText: String {
        upNext?.lesson.displayTitle ?? "You're all caught up"
    }

    private var detailText: String {
        guard let upNext else { return "Open any unit below to practice a conversation again." }
        // "Lesson N", not "Lesson N of 5" -- the count is already visible in
        // the unit grid below, and dropping it here was part of a bigger fix:
        // see the eyebrow's own comment for the rest of it.
        return "\(UnitLabelFormatter.unitName(upNext.unit)) · Lesson \(upNext.lessonNumber)"
    }

    // Stacked layout: wide character banner on top with the "Up next" pill
    // rendered inside it (over the image, not as a separate container above
    // it -- keeps the banner reading as one preview tile), then a condensed
    // title/detail/button row below. The button moved into that row's
    // trailing edge and shrank, so the bottom strip is a thin info bar
    // rather than a second stacked block the way it was when the button
    // sat full-width below the text.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                HeroCharacterBanner()
                    .frame(height: Self.bannerHeight)
                    .clipped()

                Text(upNext == nil ? "All done" : "Up next")
                    .font(PoiseType.caption(.bold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.32))
                    .clipShape(Capsule())
                    .padding(12)
            }

            bottomContent
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
        }
        .background(Color.poiseBlue)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .poiseBlueDark.opacity(0.25), radius: 14, x: 0, y: 8)
    }

    // The unit/lesson line stays quiet (muted opacity) against the loud
    // title, same hierarchy this card already settled on -- only the layout
    // moved, not that decision.
    private static let metaOpacity: Double = 0.75

    private var bottomContent: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(headlineText)
                    // 17pt -- smaller than the 20pt this ran at when the
                    // button sat full-width below it; with Start now a
                    // small trailing pill on the same row, a loud title
                    // isn't needed to carry the row on its own.
                    .font(PoiseType.headline(size: 17))
                    .foregroundStyle(Color.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer().frame(height: 3)

                Text(detailText)
                    .font(PoiseType.caption())
                    .foregroundStyle(Color.white.opacity(Self.metaOpacity))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let upNext {
                Spacer(minLength: 0)

                // Thin, compact -- a bottom-right corner action rather than
                // the full-height 44pt pill it was when it sat below the
                // text on its own line. Still a real tap target, just not
                // a block-level one.
                Button(action: { onStart(upNext.lesson) }) {
                    HStack(spacing: 5) {
                        Text("Start")
                            .font(PoiseType.caption(.bold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(Color.poiseBlueDark)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 32)
                    .background(Color.white)
                    .clipShape(Capsule())
                }
                .buttonStyle(PoisePressableStyle())
                .accessibilityLabel("Start \(upNext.lesson.title)")
            }
        }
    }
}

// The card's new banner: a wide, short strip spanning the card's full
// width, clipped only by the card's own corner radius (top corners; the
// bottom edge butts against bottomContent, no rounding needed there).
private struct HeroCharacterBanner: View {
    var body: some View {
        Color.clear
            .overlay {
                Image(uiImage: CharacterCrops.heroBanner ?? UIImage())
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
            .accessibilityHidden(true)
    }
}

// MARK: - Unit detail

// Opened by tapping a unit card. Lists every lesson in the unit so the user
// can pick one directly instead of being routed through "up next" -- nothing
// is locked, so any row is startable in any order.
private struct UnitDetailSheet: View {
    let unit: LessonUnit
    let accent: Color
    let upNextLessonID: String?
    let unlockProgress: (done: Int, total: Int)
    let onSelect: (LessonNode) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var lockedLesson: LessonNode?

    private var completedCount: Int {
        unit.lessons.filter { $0.state == .completed }.count
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                header

                PoiseSection(title: "Lessons") {
                    PoiseSurfaceCard(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(unit.lessons.enumerated()), id: \.element.id) { index, lesson in
                                if index > 0 {
                                    PoiseDivider().padding(.leading, 68)
                                }
                                LessonRow(
                                    lesson: lesson,
                                    number: index + 1,
                                    accent: accent,
                                    isUpNext: lesson.id == upNextLessonID,
                                    unlockProgress: lesson.state == .locked ? unlockProgress : nil,
                                    action: { select(lesson) }
                                )
                            }
                        }
                    }
                }

                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
        .background(Color.poiseCanvas.ignoresSafeArea())
        .overlay {
            if let lockedLesson {
                PoiseModal(
                    icon: "lock.fill",
                    iconColor: .poiseBlueDark,
                    title: "Finish the unit first",
                    message: lockedMessage(for: lockedLesson),
                    primaryTitle: "Got it",
                    onPrimary: { withAnimation(.snappy(duration: 0.22)) { self.lockedLesson = nil } }
                )
            }
        }
    }

    // A locked checkpoint never reaches onSelect, so it can never open the
    // flow or spend energy -- it explains itself instead of failing silently.
    private func select(_ lesson: LessonNode) {
        guard lesson.state != .locked else {
            withAnimation(.snappy(duration: 0.22)) { lockedLesson = lesson }
            return
        }
        onSelect(lesson)
    }

    // Says why rather than just that. The checkpoint withholds its criteria on
    // purpose, so taking it early isn't a shortcut -- it's a worse version of
    // the exercise, and that's the part worth explaining.
    private func lockedMessage(for lesson: LessonNode) -> String {
        let remaining = max(0, unlockProgress.total - unlockProgress.done)
        let countLine = remaining == 1
            ? "One lesson to go."
            : "\(remaining) lessons to go."
        return "This checkpoint combines what the unit's lessons teach, and it doesn't show you its criteria — so it only works once you've practised them. \(countLine)"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Icon beside the eyebrow, not stacked above it -- matches
            // UnitGridCard's badge+"UNIT N" row on the main Learn page
            // instead of a different layout for the same pairing.
            HStack(alignment: .center) {
                HStack(spacing: 10) {
                    PoiseIconBadge(icon: unit.lessons.first?.icon ?? "book.fill", color: accent, size: 44)
                    // 15pt, not the default 11 -- next to a 44pt icon badge,
                    // the standard eyebrow size read as an afterthought
                    // rather than the icon's actual label.
                    PoiseEyebrow(text: UnitLabelFormatter.eyebrow(unit), size: 15)
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.poiseMuted)
                        .frame(width: 32, height: 32)
                        .background(Color.white)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.poiseBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(UnitLabelFormatter.topic(unit))
                    .font(PoiseType.title())
                    .foregroundStyle(Color.poiseNavy)
                Text(unit.subtitle)
                    .font(PoiseType.subhead())
                    .foregroundStyle(Color.poiseMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                SegmentedProgressBar(total: unit.lessons.count, completed: completedCount, tint: accent)
                Text("\(completedCount) of \(unit.lessons.count) lessons complete")
                    .font(PoiseType.caption())
                    .foregroundStyle(Color.poiseMuted)
            }
        }
    }
}

private struct LessonRow: View {
    let lesson: LessonNode
    let number: Int
    let accent: Color
    let isUpNext: Bool
    // Only set for a locked checkpoint: how many of the unit's lessons are
    // done, so the row can say what remains rather than just refusing.
    let unlockProgress: (done: Int, total: Int)?
    let action: () -> Void

    private var isCompleted: Bool { lesson.state == .completed }
    private var isLocked: Bool { lesson.state == .locked }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                marker

                VStack(alignment: .leading, spacing: 3) {
                    Text(lesson.displayTitle)
                        .font(PoiseType.body(.bold))
                        // Locked rows drain to muted rather than going
                        // half-opacity: the app's other unavailable states
                        // (locked badges) do the same, and a dimmed row reads
                        // as broken rendering rather than as a state.
                        .foregroundStyle(isLocked ? Color.poiseMuted : Color.poiseNavy)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if isLocked {
                        Text(unlockHint)
                            .font(PoiseType.caption())
                            .foregroundStyle(Color.poiseMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if isUpNext {
                        PoiseEyebrow(text: "Up next", color: .poiseBlueDark)
                    } else if isCompleted {
                        Text("Completed")
                            .font(PoiseType.caption())
                            .foregroundStyle(Color.poiseMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Dropped for the same reason it came off the Up Next hero
                // card: every one of the 26 lessons is 5 minutes (see
                // MockLessonContent.estimatedMinutes), so it never told you
                // anything a lesson-to-lesson comparison would use.
                Image(systemName: isLocked ? "lock.fill" : "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.poiseMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(PoisePressableStyle())
        .accessibilityLabel(accessibilityText)
    }

    // Names the requirement and the progress toward it. A bare padlock tells
    // the user they can't do something without telling them how to fix it.
    private var unlockHint: String {
        guard let unlockProgress, unlockProgress.total > 0 else {
            return "Finish this unit's lessons to unlock"
        }
        // At zero done, "Finish the N lessons in this unit" already says
        // everything -- appending "0 of N done" just repeats the same N with
        // no new information. Once something's actually been done, the count
        // starts saying something the first clause didn't (how far along).
        guard unlockProgress.done > 0 else {
            return "Finish the \(unlockProgress.total) lessons in this unit to unlock"
        }
        return "Finish the \(unlockProgress.total) lessons in this unit · \(unlockProgress.done) of \(unlockProgress.total) done"
    }

    private var accessibilityText: String {
        if isLocked { return "Lesson \(number), \(lesson.title), locked. \(unlockHint)" }
        return "Lesson \(number), \(lesson.title)\(isCompleted ? ", completed" : "")"
    }

    // The row's leading slot is always the same 38pt square: a checkmark once
    // the lesson is done, a padlock while it's gated, its position otherwise.
    private var marker: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 38 * 0.3, style: .continuous)
                .fill(markerFill)
            if isCompleted {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.poiseMintDark)
            } else if isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.poiseMuted)
            } else {
                Text("\(number)")
                    .font(PoiseType.body(.bold))
                    .foregroundStyle(accent)
            }
        }
        .frame(width: 38, height: 38)
    }

    private var markerFill: Color {
        if isCompleted { return Color.poiseMintDark.opacity(0.13) }
        if isLocked { return Color.poiseTrack.opacity(0.7) }
        return accent.opacity(0.13)
    }
}

// MARK: - Units

private struct UnitGridCard: View {
    let unit: LessonUnit
    let accent: Color
    let action: () -> Void

    private var completedCount: Int {
        unit.lessons.filter { $0.state == .completed }.count
    }

    private var isComplete: Bool { completedCount == unit.lessons.count }

    // The accent tint marks a FINISHED unit -- earned state, not a selection.
    // Every card keeps its chevron either way, since a completed unit is still
    // open for revisiting. Split out of `body` because the inline ternaries
    // pushed the whole view past the type checker's budget.
    private var surfaceFill: Color { isComplete ? accent.opacity(0.06) : .white }
    private var surfaceStroke: Color { isComplete ? accent.opacity(0.5) : .poiseBorder }
    private var surfaceStrokeWidth: CGFloat { isComplete ? 1.75 : 1 }

    private var statusText: String {
        // The empty bar already says "not started"; what the user doesn't
        // know about an untouched unit is how long it is.
        if isComplete { return "Completed" }
        if completedCount == 0 { return "\(unit.lessons.count) lessons" }
        return "\(completedCount) of \(unit.lessons.count) lessons"
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                // Icon, unit number and chevron share one row rather than the
                // icon getting a line to itself. The topic title can't join
                // them -- beside a 34pt badge it would have 89pt to work in
                // and "Hard Conversations" needs 132.7pt, so it would wrap
                // again -- but pairing the badge with the "UNIT 1" label
                // still takes a whole row out of every card.
                HStack(spacing: 10) {
                    // Solid fill, not PoiseIconBadge's usual light tint --
                    // scoped to this card only; the shared badge (used
                    // elsewhere) is untouched. Each unit's own accent, not
                    // one shared color: on an otherwise-identical white card,
                    // this is what lets four units be told apart at a
                    // glance without reading the title.
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(accent)
                        Image(systemName: unit.lessons.first?.icon ?? "book.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.white)
                    }
                    .frame(width: 34, height: 34)
                    PoiseEyebrow(text: UnitLabelFormatter.eyebrow(unit))
                    Spacer(minLength: 4)
                    // Always the chevron: this slot is the affordance, and
                    // every card opens. Completion belongs down in the
                    // progress row with the rest of the progress information.
                    // Full-strength, not 60%: this chevron is the only thing
                    // signalling the card opens, and at 0.6 it measured
                    // 2.09:1 -- under the 3:1 WCAG minimum for non-text UI.
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.poiseMuted)
                }

                Spacer().frame(height: 10)

                // One rung down the ladder (14pt, not 16) so unit names have
                // the best chance of fitting on a single line. `shortTitle`
                // (LessonUnit.shortTitle) does the rest of the work: the grid
                // equalizes card heights WITHIN a row, so a unit whose full
                // name wraps to two lines was forcing its one-line neighbor to
                // carry the same blank second line -- a shorter phrasing for
                // units that need it (set in PoiseLessonLibrary.unitInfo)
                // means every card in the row is actually the same height for
                // the same reason, not padded to match the longest wrap.
                // lineLimit/minimumScaleFactor stay on as a safety net, not
                // the primary fix -- they'll still catch a future unit name
                // that's long even in its short form, just by shrinking
                // rather than truncating.
                Text(unit.shortTitle ?? UnitLabelFormatter.topic(unit))
                    .font(PoiseType.subhead(.bold))
                    .foregroundStyle(Color.poiseNavy)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                Spacer(minLength: 12)

                SegmentedProgressBar(total: unit.lessons.count, completed: completedCount, tint: accent)

                Spacer().frame(height: 9)

                Text(statusText)
                    .font(PoiseType.caption())
                    .foregroundStyle(Color.poiseMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(surfaceFill)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(surfaceStroke, lineWidth: surfaceStrokeWidth)
            )
            .shadow(color: .poiseNavy.opacity(0.05), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PoisePressableStyle())
        .accessibilityLabel("\(UnitLabelFormatter.topic(unit)), \(completedCount) of \(unit.lessons.count) lessons complete")
        .accessibilityHint("Opens this unit's lessons")
    }
}

// A row of `total` capsule segments (5 segments / 4 gaps for our real
// 5-lessons-per-unit data) instead of one continuous fill bar -- each
// completed lesson lights up its own segment, so progress reads as
// discrete steps rather than an ambiguous percentage.
private struct SegmentedProgressBar: View {
    let total: Int
    let completed: Int
    var tint: Color = .poiseBlue
    var height: CGFloat = 6

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<max(total, 1), id: \.self) { index in
                Capsule()
                    .fill(index < completed ? tint : Color.poiseTrack)
                    .frame(height: height)
            }
        }
        .accessibilityLabel("\(completed) of \(total) lessons complete")
    }
}

// MARK: - Weekly activity

// Real per-day data (already tracked for the Progress tab) rather than a
// single summary number -- seven marks make the week's shape legible at a
// glance and give the page a quiet visual anchor at the bottom.
private struct WeeklyActivityCard: View {
    let week: [PracticeDay]
    let completed: Int
    let goal: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(completed) of \(goal)")
                    .font(PoiseType.headline())
                    .foregroundStyle(Color.poiseNavy)
                Text("sessions practiced")
                    .font(PoiseType.subhead(.semibold))
                    .foregroundStyle(Color.poiseMuted)
                Spacer(minLength: 0)
            }

            HStack(spacing: 7) {
                ForEach(week) { day in
                    DayMark(day: day)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .poiseCard(radius: 20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(completed) of \(goal) sessions practiced this week")
    }
}

private struct DayMark: View {
    let day: PracticeDay

    var body: some View {
        VStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(day.practiced ? Color.poiseBlue : Color.poiseTrack)
                .frame(height: 36)
                .overlay {
                    if day.practiced {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                }
                .overlay {
                    if day.isToday {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.poiseBlueDark, lineWidth: 2)
                    }
                }

            Text(day.weekday)
                .font(PoiseType.eyebrow())
                .foregroundStyle(day.isToday ? Color.poiseNavy : Color.poiseMuted)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Character

// Still frames of the character (not the looping video -- see
// CharacterAnimationView), cropped once and cached.
//
// Measured directly against the source asset (3537x2100) rather than eyeballed:
// a hair mask puts the face's horizontal center at x = 49.69%, the hair top at
// y = 22.8% and the chin around y = 50%; the desk edge cuts in around y = 82%.
// Every crop below is centered on that measured face center, which is what
// keeps him from sitting off to one side of the frame.
private enum CharacterCrops {
    private static var cache: [String: UIImage] = [:]

    private static let faceCenterX: CGFloat = 0.4969

    // Wide, short slice for the hero card's banner (a "video call tile"
    // treatment -- see UpNextCard): face and shoulders centered in a band
    // from just above the hair to mid-torso, giving a webcam-style framing
    // rather than the old portrait panel's head-to-torso crop. Shifted down
    // from an earlier top: 0.10/bottom: 0.62 pass, which left too much bare
    // ceiling above the hair (22.8%) and cut off too soon above the chin
    // (50%) -- top: 0.17 trims most of that headroom and bottom: 0.71 shows
    // shoulders/chest instead of stopping right at the chin.
    static var heroBanner: UIImage? {
        crop(key: "heroBanner", top: 0.17, bottom: 0.71, aspect: 350.0 / 175.0)
    }

    private static func crop(key: String, top: CGFloat, bottom: CGFloat, aspect: CGFloat) -> UIImage? {
        if let cached = cache[key] { return cached }
        guard let source = UIImage(named: "CharFullFrame"), let cgImage = source.cgImage else { return nil }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let cropHeight = (bottom - top) * height
        let cropWidth = cropHeight * aspect
        let cropRect = CGRect(
            x: faceCenterX * width - cropWidth / 2,
            y: top * height,
            width: cropWidth,
            height: cropHeight
        )
        guard let cropped = cgImage.cropping(to: cropRect.integral) else { return nil }
        let image = UIImage(cgImage: cropped, scale: source.scale, orientation: source.imageOrientation)
        cache[key] = image
        return image
    }
}

// MARK: - Formatting

// `LessonUnit.label` is a combined "Unit 1 · Giving Feedback" string --
// split it once here into the small "UNIT 1" eyebrow and the "Giving
// Feedback" topic name shown as titles, instead of adding new fields to
// the model for what's really just formatting.
private enum UnitLabelFormatter {
    private static func parts(_ unit: LessonUnit) -> [String] {
        unit.label.split(separator: "\u{00B7}").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // "UNIT 1" for the tracked uppercase eyebrow treatment.
    static func eyebrow(_ unit: LessonUnit) -> String {
        unitName(unit).uppercased()
    }

    // "Unit 1" as written, for running text. The Up Next card pairs this with
    // the lesson position so its detail line speaks the same vocabulary as the
    // grid's eyebrows -- that line is the only link between the two sections
    // now that no unit card is highlighted.
    static func unitName(_ unit: LessonUnit) -> String {
        parts(unit).first ?? unit.label
    }

    static func topic(_ unit: LessonUnit) -> String {
        let split = parts(unit)
        return split.count > 1 ? split[1] : unit.title
    }
}

#Preview {
    LearnView()
}
