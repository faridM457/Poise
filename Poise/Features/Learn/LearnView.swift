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
//     stay neutral so four units don't read as four different components.
//
// Nothing on this page is ever locked (see LearnProgressStore.state(for:)):
// units are a menu, not a ladder, so every state here is either "not started
// yet", "in progress" or "complete".
struct LearnView: View {
    @ObservedObject private var store = LearnProgressStore.shared
    @State private var activeLesson: LessonNode?
    // The unit whose lesson list is open. Presented as a sheet rather than a
    // pushed screen: a NavigationStack here would swallow the tab bar's bottom
    // safeAreaInset (see PoiseRootView), and this is a pick-one-and-go detour,
    // not a place to live.
    @State private var detailUnit: LessonUnit?
    // A lesson chosen inside that sheet. It can't be started until the sheet
    // has actually gone away -- setting a fullScreenCover while a sheet is
    // dismissing drops the presentation -- so it waits for onDismiss.
    @State private var pendingLesson: LessonNode?
    // Set when the user taps the continue button at 0 energy -- surfaces a
    // dismissable warning (testing purposes only, never a hard gate; see
    // LearnProgressStore.markCompleted) rather than blocking the tap.
    @State private var lowEnergyLesson: LessonNode?

    private var units: [LessonUnit] { store.units }

    var body: some View {
        ScrollView(showsIndicators: false) {
            pageContent
                .padding(.horizontal, 20)
                .padding(.top, 10)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            PoiseTopBar(streak: store.streak, energyText: store.energyDisplayText)
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
                onSelect: { lesson in
                    pendingLesson = lesson
                    detailUnit = nil
                }
            )
        }
        .poiseLessonCover(item: $activeLesson) { lesson in
            LessonFlowView(lesson: lesson) { completed in
                activeLesson = nil
                if completed { store.markCompleted(lesson.id) }
            }
        }
        .alert(
            "You're out of energy",
            isPresented: Binding(
                get: { lowEnergyLesson != nil },
                set: { if !$0 { lowEnergyLesson = nil } }
            ),
            presenting: lowEnergyLesson
        ) { lesson in
            Button("Start anyway") {
                activeLesson = lesson
                lowEnergyLesson = nil
            }
            Button("Cancel", role: .cancel) {
                lowEnergyLesson = nil
            }
        } message: { _ in
            Text("You don't have any energy left, but you can still practice this lesson.")
        }
    }

    // Split out of `body` -- inline, the whole page was one expression and
    // the Swift type checker gave up on it ("failed to produce diagnostic").
    private var pageContent: some View {
        VStack(alignment: .leading, spacing: 26) {
            GreetingHeader(name: PoiseMockData.profile.name, snapshot: PoiseMockData.progress)

            UpNextCard(upNext: store.upNext, onStart: attemptStart)

            PoiseSection(title: "Explore units") { unitGrid }

            PoiseSection(title: "This week") {
                WeeklyActivityCard(snapshot: PoiseMockData.progress)
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

    // No state check: every lesson is startable, including replaying one
    // that's already completed (markCompleted is idempotent, so a replay
    // neither double-counts progress nor spends energy twice).
    private func attemptStart(_ lesson: LessonNode) {
        if store.energyRemaining <= 0 {
            lowEnergyLesson = lesson
        } else {
            activeLesson = lesson
        }
    }

    private func accentColor(for index: Int) -> Color {
        let palette: [Color] = [.poiseMintDark, .poisePurple, .poiseOrange, .poiseBlueDark]
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
    let name: String
    let snapshot: ProgressSnapshot

    private var timeOfDayGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    private var weeklyNudge: String {
        let left = snapshot.remainingThisWeek
        guard left > 0 else { return "You've hit this week's goal." }
        return "\(left) more conversation\(left == 1 ? "" : "s") to hit this week's goal."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(timeOfDayGreeting), \(name)")
                .font(PoiseType.title())
                .foregroundStyle(Color.poiseNavy)
            // Was "One conversation at a time." -- the only line on the page
            // that told the user nothing. Deliberately says what's LEFT rather
            // than what's done: the weekly card at the foot of the page
            // already reports the count and the day-by-day shape, so a second
            // "4 of 5" here would restate it. Both read from the same
            // ProgressSnapshot week, so they can't disagree.
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

    private static let photoWidth: CGFloat = 126
    // A floor, not a fixed height. At 184 fixed, a one-line headline left a
    // 32.7pt void between the detail line and the button -- the same reserved
    // whitespace removed from the unit cards, and the largest unstructured
    // gap on the page. The card now sizes to its content and only stops
    // shrinking here, so two-line headlines still grow to fit.
    private static let minCardHeight: CGFloat = 176

    private var headlineText: String {
        upNext?.lesson.displayTitle ?? "You're all caught up"
    }

    private var detailText: String {
        guard let upNext else { return "Open any unit below to practice a conversation again." }
        return "\(UnitLabelFormatter.unitName(upNext.unit)) · Lesson \(upNext.lessonNumber) of \(upNext.unit.lessons.count)"
    }

    var body: some View {
        HStack(spacing: 0) {
            // The flexible half of an HStack that also holds a fixed-width
            // sibling must claim its width explicitly, or it sizes to its own
            // unwrapped ideal width and runs under the image instead of
            // wrapping. Keep this `maxWidth: .infinity`.
            textColumn
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)

            HeroCharacterPanel()
                .frame(width: Self.photoWidth)
        }
        .frame(minHeight: Self.minCardHeight)
        .background(heroBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.poiseBlue.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .poiseNavy.opacity(0.07), radius: 12, x: 0, y: 6)
    }

    private var textColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The estimate rides beside the pill, not inside the detail line
            // below: that line already measures ~134pt of a ~200pt column, and
            // appending the time would push it back into wrapping.
            HStack(spacing: 9) {
                PoiseEyebrow(text: upNext == nil ? "All done" : "Up next", color: .poiseBlueDark)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.75))
                    .clipShape(Capsule())

                if let upNext {
                    DurationLabel(minutes: upNext.lesson.estimatedMinutes)
                }
            }

            Spacer().frame(height: 10)

            Text(headlineText)
                .font(PoiseType.headline())
                .foregroundStyle(Color.poiseNavy)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer().frame(height: 4)

            Text(detailText)
                .font(PoiseType.subhead())
                .foregroundStyle(Color.poiseMuted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 12)

            if let upNext {
                Button(action: { onStart(upNext.lesson) }) {
                    HStack(spacing: 7) {
                        Text("Start")
                            .font(PoiseType.body(.bold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Color.poiseBlueDark)
                    .clipShape(Capsule())
                }
                .buttonStyle(PoisePressableStyle())
                .accessibilityLabel("Start \(upNext.lesson.title)")
            }
        }
    }

    // Pale tint plus the soft light disc the character sits against in the
    // mockup -- the photo panel covers the disc's right half, so only the arc
    // beside the text shows.
    private var heroBackground: some View {
        ZStack(alignment: .trailing) {
            LinearGradient(
                colors: [Color.poiseSoftBlue, Color.poisePaleBlue],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            // Radial, not a flat fill: a solid circle left a hard arc cutting
            // across the description text.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.6), Color.white.opacity(0)],
                        center: .center,
                        startRadius: 30,
                        endRadius: 118
                    )
                )
                .frame(width: 236, height: 236)
                .offset(x: -16)
        }
    }
}

// The trailing slice of the hero card: fills its full height edge-to-edge,
// clipped only by the card's own corner radius.
private struct HeroCharacterPanel: View {
    var body: some View {
        Color.clear
            .overlay {
                Image(uiImage: CharacterCrops.heroPanel ?? UIImage())
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
            .accessibilityHidden(true)
    }
}

// How long a lesson takes, shown wherever one can be started. The number is
// derived from the lesson's turn count (see MockLessonContent), not hand-set.
private struct DurationLabel: View {
    let minutes: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
                .font(.system(size: 11, weight: .semibold))
            Text("\(minutes) min")
                .font(PoiseType.caption())
        }
        .foregroundStyle(Color.poiseMuted)
        .accessibilityLabel("About \(minutes) minutes")
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
    let onSelect: (LessonNode) -> Void

    @Environment(\.dismiss) private var dismiss

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
                                    action: { onSelect(lesson) }
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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                PoiseIconBadge(icon: unit.lessons.first?.icon ?? "book.fill", color: accent, size: 44)
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
                PoiseEyebrow(text: UnitLabelFormatter.eyebrow(unit))
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
    let action: () -> Void

    private var isCompleted: Bool { lesson.state == .completed }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                marker

                VStack(alignment: .leading, spacing: 3) {
                    Text(lesson.displayTitle)
                        .font(PoiseType.body(.bold))
                        .foregroundStyle(Color.poiseNavy)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if isUpNext {
                        PoiseEyebrow(text: "Up next", color: .poiseBlueDark)
                    } else if isCompleted {
                        Text("Completed")
                            .font(PoiseType.caption())
                            .foregroundStyle(Color.poiseMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                DurationLabel(minutes: lesson.estimatedMinutes)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.poiseMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(PoisePressableStyle())
        .accessibilityLabel("Lesson \(number), \(lesson.title)\(isCompleted ? ", completed" : "")")
    }

    // The row's leading slot is always the same 38pt square: a checkmark once
    // the lesson is done, its position in the unit otherwise.
    private var marker: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 38 * 0.3, style: .continuous)
                .fill(isCompleted ? Color.poiseMintDark.opacity(0.13) : accent.opacity(0.13))
            if isCompleted {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.poiseMintDark)
            } else {
                Text("\(number)")
                    .font(PoiseType.body(.bold))
                    .foregroundStyle(accent)
            }
        }
        .frame(width: 38, height: 38)
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
                HStack(alignment: .top) {
                    PoiseIconBadge(icon: unit.lessons.first?.icon ?? "book.fill", color: accent)
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

                Spacer().frame(height: 12)

                PoiseEyebrow(text: UnitLabelFormatter.eyebrow(unit))

                Spacer().frame(height: 3)

                // One rung down the ladder (14pt, not 16) so every unit name
                // fits on a single line: at 16pt "Hard Conversations" measured
                // 148.4pt against 147pt of content width -- over by 1.4pt, and
                // that single wrap was what made its row taller than the other
                // (the grid equalizes heights WITHIN a row, not between rows).
                // At 14pt it needs ~130pt, leaving real margin. One line
                // everywhere means all four cards match with no reserved
                // whitespace. minimumScaleFactor is a safety net for any
                // future unit name longer than these four -- it shrinks rather
                // than truncating, and never fires for the current set.
                Text(UnitLabelFormatter.topic(unit))
                    .font(PoiseType.subhead(.bold))
                    .foregroundStyle(Color.poiseNavy)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
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
    let snapshot: ProgressSnapshot

    // Both of these live on ProgressSnapshot now -- the greeting at the top of
    // the page quotes the same numbers.
    private var week: [PracticeDay] { snapshot.weekEndingToday }
    private var practicedThisWeek: Int { snapshot.practicedThisWeek }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(practicedThisWeek) of \(snapshot.weeklyGoal)")
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
        .accessibilityLabel("\(practicedThisWeek) of \(snapshot.weeklyGoal) sessions practiced this week")
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
                .font(PoiseType.eyebrow(day.isToday ? .heavy : .bold))
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

    // Portrait slice for the hero card's trailing panel: head high in the
    // frame with the skyline behind him, cut just above the desk (whose top
    // edge measures at y = 81.3%) so the bottom is torso, not a tan sliver of
    // desktop. Width is derived from the panel's own aspect ratio so nothing
    // is re-cropped at display time.
    static var heroPanel: UIImage? {
        crop(key: "hero", top: 0.05, bottom: 0.805, aspect: 126.0 / 184.0)
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
