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
    let snapshot: ProgressSnapshot

    @ObservedObject private var store = LearnProgressStore.shared

    var body: some View {
        ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {
                    PoisePageHeader(title: "Your progress", subtitle: "You showed up. That counts.")

                    PoiseSection(title: "Practice days") {
                        StreakCalendarCard(days: snapshot.calendarDays, streak: snapshot.streakDays)
                    }

                    PoiseSection(title: "Energy") {
                        EnergyCard(remaining: store.energyRemaining, cap: store.energyCap)
                    }

                    PoiseSection(title: "Weekly goal") {
                        WeeklyGoalCard(snapshot: snapshot)
                    }

                    PoiseSection(title: "Skills over time") {
                        SkillTrendCard(rates: snapshot.skillRates)
                    }

                    PoiseSection(title: "Badges") {
                        BadgeCard(badges: snapshot.badges)
                    }

                    FutureMetricsNote()

                    // The tab bar is a bottom safeAreaInset (see PoiseRootView),
                    // so the scroll view already accounts for its height --
                    // this is just air under the last card.
                    Color.clear.frame(height: 16)
                }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            PoiseTopBar(streak: snapshot.streakDays, energyText: store.energyDisplayText)
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

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        PoiseSurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                StatLine(value: "\(streak)-day", unit: "streak", trailing: "September · sample")

                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, dayLabel in
                        PoiseEyebrow(text: dayLabel)
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(days) { day in
                        DayTile(day: day)
                    }
                }
            }
        }
    }
}

// Matches the Learn page's weekly activity marks exactly: blue fill for a
// practiced day, poiseTrack for an empty one, a blueDark ring for today.
private struct DayTile: View {
    let day: PracticeDay

    var body: some View {
        Text("\(day.day)")
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
            .accessibilityLabel("Day \(day.day)\(day.practiced ? ", practiced" : "")")
    }
}

// MARK: - Energy & goal

private struct EnergyCard: View {
    let remaining: Int
    let cap: Int

    var body: some View {
        PoiseSurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                StatLine(value: "\(remaining) of \(cap)", unit: "left today")
                SegmentedMeter(total: cap, filled: remaining, tint: .poiseAmber)
                Text("Each lesson spends one. Energy regenerates on its own over time.")
                    .font(PoiseType.subhead())
                    .foregroundStyle(Color.poiseMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct WeeklyGoalCard: View {
    let snapshot: ProgressSnapshot

    private var remaining: Int { max(0, snapshot.weeklyGoal - snapshot.weeklyCompleted) }

    var body: some View {
        PoiseSurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                StatLine(value: "\(snapshot.weeklyCompleted) of \(snapshot.weeklyGoal)", unit: "conversations")
                SegmentedMeter(total: snapshot.weeklyGoal, filled: snapshot.weeklyCompleted, tint: .poiseBlue)
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

// MARK: - Skills

private struct SkillTrendCard: View {
    let rates: [SkillRate]

    private var latest: Int { Int((rates.last?.rate ?? 0) * 100) }

    var body: some View {
        PoiseSurfaceCard {
            VStack(alignment: .leading, spacing: 16) {
                StatLine(value: "\(latest)%", unit: "criteria hit, last session")

                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(Array(rates.enumerated()), id: \.element.id) { index, rate in
                        SkillBar(rate: rate, isLatest: index == rates.count - 1)
                    }
                }
                .frame(height: 148)
            }
        }
    }
}

private struct SkillBar: View {
    let rate: SkillRate
    let isLatest: Bool

    var body: some View {
        VStack(spacing: 8) {
            Text("\(Int(rate.rate * 100))%")
                .font(PoiseType.caption(.bold))
                .foregroundStyle(isLatest ? Color.poiseBlueDark : Color.poiseMuted)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                // Only the most recent bar carries full accent -- the earlier
                // ones are context, not the headline.
                .fill(isLatest ? Color.poiseBlue : Color.poiseBlue.opacity(0.28))
                .frame(height: max(6, 108 * rate.rate))
            PoiseEyebrow(text: rate.label)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Badges

private struct BadgeCard: View {
    let badges: [String]

    var body: some View {
        PoiseSurfaceCard(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(badges.enumerated()), id: \.element) { index, badge in
                    if index > 0 {
                        PoiseDivider().padding(.leading, 68)
                    }
                    HStack(spacing: 14) {
                        PoiseIconBadge(icon: "seal.fill", color: .poiseGold)
                        Text(badge)
                            .font(PoiseType.body(.bold))
                            .foregroundStyle(Color.poiseNavy)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
            }
        }
    }
}

// MARK: - Note

private struct FutureMetricsNote: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.poiseMuted)
            Text("Voice analysis isn't implemented in this prototype. A later version could summarize pace, clarity and tone, with consent.")
                .font(PoiseType.caption())
                .foregroundStyle(Color.poiseMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
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
