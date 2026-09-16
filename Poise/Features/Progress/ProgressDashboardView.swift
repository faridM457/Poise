import SwiftUI

// Rebuilt on the same rules as Learn (see LearnView's header comment): one
// type ladder, one card surface, color only where it carries meaning, and
// every group introduced by the same quiet section eyebrow.
//
// The structural change from the previous version: cards no longer each carry
// their own headline. A stack of boxes that each open with an 18pt title reads
// as a stack of mini-pages; naming the group outside the card and letting the
// card lead with its actual number gives the page one hierarchy instead of six.
struct ProgressDashboardView: View {
    @ObservedObject private var store = LearnProgressStore.shared

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 26) {
                PoisePageHeader(title: "Your progress", subtitle: "You showed up. That counts.")

                PoiseSection(title: "Practice days") {
                    StreakCalendarCard(
                        days: store.currentMonthDays,
                        streak: store.currentStreak,
                        month: store.monthTitle,
                        practisedToday: store.practisedToday
                    )
                }

                PoiseSection(title: "Weekly goal") {
                    WeeklyGoalCard(
                        completed: store.conversationsThisWeek,
                        goal: LearnProgressStore.weeklyGoal,
                        remaining: store.remainingThisWeek
                    )
                }

                PoiseSection(title: "Checkpoint results") {
                    CheckpointResultsCard(results: store.checkpointResults)
                }

                PoiseSection(title: "Badges") {
                    BadgeSection(store: store)
                }

                // The tab bar is a bottom safeAreaInset (see PoiseRootView),
                // so the scroll view already accounts for its height --
                // this is just air under the last card.
                Color.clear.frame(height: 16)
            }
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
    }
}

// MARK: - Practice days

private struct StreakCalendarCard: View {
    let days: [PracticeDay]
    let streak: Int
    let month: String
    let practisedToday: Bool

    var body: some View {
        PoiseSurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                // The streak used to float above the grid as a bare "4-day
                // streak" line with a right-aligned caption, reading as a
                // caption that had come loose. It is the headline of this card,
                // so it gets the flame, the count and the state of today on one
                // committed row.
                HStack(spacing: 10) {
                    PoiseIconBadge(icon: "flame.fill", color: .poiseOrange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(streak == 0 ? "No streak yet" : "\(streak)-day streak")
                            .font(PoiseType.headline())
                            .foregroundStyle(Color.poiseNavy)
                        Text(streakDetail)
                            .font(PoiseType.subhead())
                            .foregroundStyle(Color.poiseMuted)
                    }
                    Spacer(minLength: 8)
                }

                PoiseDivider()

                Text(month)
                    .font(PoiseType.eyebrow())
                    .tracking(PoiseType.eyebrowTracking)
                    .foregroundStyle(Color.poiseMuted)

                // Explicit rows rather than a LazyVGrid. The lazy grid
                // under-reported its height inside the card's clipShape and
                // the final week rendered sliced in half by the card's
                // bottom edge. A month is 5 rows -- there is nothing here
                // worth being lazy about.
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        ForEach(Array(LearnProgressStore.weekdayLetters.enumerated()), id: \.offset) { _, dayLabel in
                            PoiseEyebrow(text: dayLabel)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                        HStack(spacing: 6) {
                            ForEach(week) { day in
                                DayTile(day: day)
                            }
                        }
                    }
                }
            }
        }
    }

    // Padded out to whole weeks so every row has seven cells and the columns
    // stay aligned with the header.
    private var weeks: [[PracticeDay]] {
        var padded = days
        while padded.count % 7 != 0 {
            padded.append(PracticeDay(day: nil, practiced: false, isToday: false))
        }
        return stride(from: 0, to: padded.count, by: 7).map { Array(padded[$0..<$0 + 7]) }
    }

    private var streakDetail: String {
        if streak == 0 { return "One conversation starts it." }
        return practisedToday ? "Done for today." : "Practice today to keep it."
    }
}

// Matches the Learn page's weekly activity marks exactly: blue fill for a
// practiced day, poiseTrack for an empty one, a blueDark ring for today.
private struct DayTile: View {
    let day: PracticeDay

    var body: some View {
        Group {
            if let number = day.day {
                Text("\(number)")
                    .font(PoiseType.caption(.bold))
                    .foregroundStyle(day.practiced ? .white : Color.poiseMuted)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(day.practiced ? Color.poiseBlue : Color.poiseTrack)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        if day.isToday {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.poiseBlueDark, lineWidth: 2)
                        }
                    }
                    .accessibilityLabel("Day \(number)\(day.practiced ? ", practiced" : "")")
            } else {
                // Padding for the first week -- no tile, so the month starts
                // in the correct weekday column.
                Color.clear.frame(minHeight: 36)
            }
        }
    }
}

// MARK: - Weekly goal

private struct WeeklyGoalCard: View {
    let completed: Int
    let goal: Int
    let remaining: Int

    var body: some View {
        PoiseSurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                // Past the goal this used to read "6 of 5", which looks like
                // an arithmetic bug rather than an achievement. Once the goal
                // is met the count stands on its own.
                StatLine(
                    value: completed >= goal ? "\(completed)" : "\(completed) of \(goal)",
                    unit: completed >= goal ? "conversations this week" : "conversations"
                )
                SegmentedMeter(total: goal, filled: min(completed, goal), tint: .poiseBlue)
                Text(remaining == 0
                     ? "Goal met for this week."
                     : "\(remaining) more conversation\(remaining == 1 ? "" : "s") to hit this week's goal.")
                    .font(PoiseType.subhead())
                    .foregroundStyle(Color.poiseMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Checkpoint results

// Four checkpoints, one bar each, in curriculum order. The bar plots the
// rounded mean of that checkpoint's three skill tiers, so the ladder is a
// quarter per tier: empty when untaken, then 25 / 50 / 75 / 100.
//
// The previous version of this was a list of four rows each carrying three
// labelled pills -- twelve pieces of text to say what four bars say at a
// glance. The per-skill breakdown still exists where it belongs, on the
// scorecard at the end of the checkpoint itself.
private struct CheckpointResultsCard: View {
    let results: [(unitNumber: Int, record: SessionRecord?)]

    private var taken: Int { results.filter { $0.record != nil }.count }

    var body: some View {
        PoiseSurfaceCard {
            VStack(alignment: .leading, spacing: 18) {
                StatLine(value: "\(taken) of \(results.count)", unit: "checkpoints taken")

                HStack(alignment: .bottom, spacing: 12) {
                    ForEach(Array(results.enumerated()), id: \.element.unitNumber) { _, result in
                        CheckpointBar(unitNumber: result.unitNumber, level: result.record?.overallLevel)
                    }
                }
            }
        }
    }
}

private struct CheckpointBar: View {
    let unitNumber: Int
    let level: SkillLevel?

    // Tall enough that a quarter-step is an obvious difference in height. The
    // old chart capped bars at 108pt while each was ~78pt wide, so they read
    // as squat blocks and a 60-to-80% gap looked flat.
    private let trackHeight: CGFloat = 132

    var body: some View {
        VStack(spacing: 8) {
            // The empty track is drawn full height so an untaken checkpoint
            // reads as a column waiting to be filled rather than as nothing.
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.poiseTrack)
                    .frame(height: trackHeight)

                if let level {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(level.tint)
                        .frame(height: trackHeight * level.barFraction)
                }
            }
            // Bars, not blocks: the column is ~78pt wide on a phone, so the
            // fill is held to a bar's proportions and centred in it.
            .frame(maxWidth: 46)
            .frame(maxWidth: .infinity)

            Text("UNIT \(unitNumber)")
                .font(PoiseType.eyebrow())
                .tracking(PoiseType.eyebrowTracking)
                .foregroundStyle(Color.poiseMuted)

            Text(level?.title ?? "Not taken")
                .font(PoiseType.caption(.bold))
                .foregroundStyle(level?.tint ?? Color.poiseMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Unit \(unitNumber) checkpoint: \(level?.title ?? "not taken")")
    }
}

// MARK: - Badges

// Locked badges are shown alongside earned ones. The previous version listed
// three hardcoded strings, all of them already "won", which gave the user
// nothing to aim at and told them nothing about how any of it was earned.
private struct BadgeSection: View {
    @ObservedObject var store: LearnProgressStore

    // Collapsed by default. Twelve badges in four groups is a tall list, and
    // fully expanded it occupied more of this page than the progress it was
    // meant to decorate. The summary row is the part that belongs on the
    // page; the catalogue is what you open when you want to go looking.
    @State private var isExpanded = false

    private var earned: Int {
        PoiseBadgeCatalogue.all.filter(store.hasEarned).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PoiseSurfaceCard {
                Button {
                    withAnimation(.snappy(duration: 0.26)) { isExpanded.toggle() }
                } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(earned) of \(PoiseBadgeCatalogue.all.count)")
                                .font(PoiseType.headline())
                                .foregroundStyle(Color.poiseNavy)
                            Text("earned")
                                .font(PoiseType.subhead(.semibold))
                                .foregroundStyle(Color.poiseMuted)
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.poiseMuted)
                                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        }
                        SegmentedMeter(total: PoiseBadgeCatalogue.all.count, filled: earned, tint: .poiseGold)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .accessibilityLabel("\(earned) of \(PoiseBadgeCatalogue.all.count) badges earned")
            .accessibilityHint(isExpanded ? "Collapse badge list" : "Expand badge list")

            if isExpanded {
                ForEach(PoiseBadge.Group.allCases, id: \.self) { group in
                    let badges = PoiseBadgeCatalogue.all.filter { $0.group == group }
                    if !badges.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.title)
                                .font(PoiseType.eyebrow())
                                .tracking(PoiseType.eyebrowTracking)
                                .foregroundStyle(Color.poiseMuted)

                            PoiseSurfaceCard(padding: 0) {
                                VStack(spacing: 0) {
                                    ForEach(Array(badges.enumerated()), id: \.element.id) { index, badge in
                                        if index > 0 {
                                            PoiseDivider().padding(.leading, 68)
                                        }
                                        BadgeRow(badge: badge, earned: store.hasEarned(badge))
                                    }
                                }
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

private struct BadgeRow: View {
    let badge: PoiseBadge
    let earned: Bool

    var body: some View {
        HStack(spacing: 14) {
            PoiseIconBadge(icon: badge.icon, color: earned ? .poiseGold : .poiseMuted)
                // Locked badges read as absent rather than as a second style
                // of badge -- the shape stays, the colour drains out.
                .opacity(earned ? 1 : 0.45)

            VStack(alignment: .leading, spacing: 2) {
                Text(badge.title)
                    .font(PoiseType.body(.bold))
                    .foregroundStyle(earned ? Color.poiseNavy : Color.poiseMuted)
                // The requirement is the payload for a locked badge, so it
                // stays visible once earned too rather than swapping to a
                // "done" label that says less.
                Text(badge.requirement)
                    .font(PoiseType.caption())
                    .foregroundStyle(Color.poiseMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if earned {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.poiseMintDark)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(badge.title). \(earned ? "Earned" : "Locked") -- \(badge.requirement)")
    }
}

// MARK: - Shared bits

// The card's lead line: the number at headline size, its unit beside it at
// subhead, optionally a caption pinned right. Replaces the per-card titles --
// every card on this page opens the same way, with its own actual figure.
private struct StatLine: View {
    let value: String
    let unit: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value)
                .font(PoiseType.headline())
                .foregroundStyle(Color.poiseNavy)
            Text(unit)
                .font(PoiseType.subhead(.semibold))
                .foregroundStyle(Color.poiseMuted)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(PoiseType.caption())
                    .foregroundStyle(Color.poiseMuted)
            }
        }
    }
}

// Discrete segments rather than a continuous fill, matching the unit progress
// bars on Learn -- energy and weekly goals are both small whole numbers, so a
// percentage bar was always overstating the precision.
private struct SegmentedMeter: View {
    let total: Int
    let filled: Int
    var tint: Color = .poiseBlue
    var height: CGFloat = 8

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<max(total, 1), id: \.self) { index in
                Capsule()
                    .fill(index < filled ? tint : Color.poiseTrack)
                    .frame(height: height)
            }
        }
        .accessibilityLabel("\(filled) of \(total)")
    }
}
