import SwiftUI

struct ProgressDashboardView: View {
    let snapshot: ProgressSnapshot

    var body: some View {
        ZStack {
            Color.poiseBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    StatusRow(streak: snapshot.streakDays, xp: snapshot.xp, level: snapshot.level)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                    VStack(alignment: .leading, spacing: 8) {
                        SectionEyebrow(text: "Small wins add up")
                        Text("Your progress")
                            .font(PoiseType.largeTitle())
                            .foregroundStyle(Color.poiseNavy)
                        Text("You showed up. That counts.")
                            .font(PoiseType.body())
                            .foregroundStyle(Color.poiseMuted)
                    }

                    StreakCalendarView(days: snapshot.calendarDays, streak: snapshot.streakDays)
                    LevelProgressCard(snapshot: snapshot)
                    SkillTrendCard(rates: snapshot.skillRates)
                    BadgeCard(badges: snapshot.badges)
                    DeliveryFutureCard()
                }
                .padding(20)
            }
        }
    }
}

private struct StreakCalendarView: View {
    let days: [PracticeDay]
    let streak: Int

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("\(streak)-day streak")
                    .font(PoiseType.headline())
                    .foregroundStyle(Color.poiseNavy)
                Spacer()
                Text("September · sample")
                    .font(PoiseType.caption(.semibold))
                    .foregroundStyle(Color.poiseMuted)
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, dayLabel in
                    Text(dayLabel)
                        .font(PoiseType.caption(.bold))
                        .foregroundStyle(Color.poiseMuted)
                }
                ForEach(days) { day in
                    Text("\(day.day)")
                        .font(PoiseType.caption(.heavy))
                        .foregroundStyle(day.practiced ? Color.poiseMintDark : Color.poiseNavy)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(day.practiced ? Color.poiseMint.opacity(0.24) : Color.poiseSoftGray)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(day.isToday ? Color.poiseBlue : .clear, lineWidth: 1.8)
                        )
                        .accessibilityLabel("Day \(day.day)\(day.practiced ? ", practiced" : "")")
                }
            }
        }
        .padding(20)
        .poiseCard()
    }
}

private struct LevelProgressCard: View {
    let snapshot: ProgressSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Level \(snapshot.level)")
                    .font(PoiseType.headline())
                    .foregroundStyle(Color.poiseNavy)
                Spacer()
                Text("420 / 600 XP")
                    .font(PoiseType.body(.heavy))
                    .foregroundStyle(Color.poiseNavy)
            }
            ProgressBar(value: snapshot.levelProgress)
            Text("XP history · " + snapshot.xpHistory.map(String.init).joined(separator: " → "))
                .font(PoiseType.caption(.semibold))
                .foregroundStyle(Color.poiseMuted)

            Divider()

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Weekly goal")
                        .font(PoiseType.headline())
                        .foregroundStyle(Color.poiseNavy)
                    ProgressBar(value: Double(snapshot.weeklyCompleted) / Double(snapshot.weeklyGoal), height: 9)
                    Text("Two more conversations this week.")
                        .font(PoiseType.caption(.semibold))
                        .foregroundStyle(Color.poiseMuted)
                }
                Spacer()
                Text("\(snapshot.weeklyCompleted) / \(snapshot.weeklyGoal)")
                    .font(PoiseType.body(.heavy))
                    .foregroundStyle(Color.poiseNavy)
            }
        }
        .padding(20)
        .poiseCard()
    }
}

private struct SkillTrendCard: View {
    let rates: [SkillRate]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Skills over time")
                .font(PoiseType.headline())
                .foregroundStyle(Color.poiseNavy)

            HStack {
                Text("Content criteria hit rate")
                    .font(PoiseType.body(.heavy))
                    .foregroundStyle(Color.poiseNavy)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.poiseMuted)
            }
            .padding(14)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.poiseBorder, lineWidth: 1.3)
            )

            HStack(alignment: .bottom, spacing: 10) {
                ForEach(rates) { rate in
                    VStack(spacing: 8) {
                        Text("\(Int(rate.rate * 100))%")
                            .font(PoiseType.caption(.heavy))
                            .foregroundStyle(Color.poiseBlueDark)
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.poiseBlue.opacity(0.72))
                            .frame(height: 120 * rate.rate)
                        Text(rate.label)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.poiseMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 170)
        }
        .padding(20)
        .poiseCard()
    }
}

private struct BadgeCard: View {
    let badges: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Completed units & badges")
                .font(PoiseType.headline())
                .foregroundStyle(Color.poiseNavy)
            ForEach(badges, id: \.self) { badge in
                HStack(spacing: 12) {
                    Image(systemName: "seal.fill")
                        .foregroundStyle(Color.poiseGold)
                        .font(.system(size: 24, weight: .bold))
                    Text(badge)
                        .font(PoiseType.body(.bold))
                        .foregroundStyle(Color.poiseNavy)
                    Spacer()
                }
                .padding(14)
                .background(Color.poiseGold.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .padding(20)
        .poiseCard()
    }
}

private struct DeliveryFutureCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(text: "Future delivery metrics")
            Text("Voice analysis is not implemented in this prototype.")
                .font(PoiseType.body(.bold))
                .foregroundStyle(Color.poiseNavy)
            Text("When enabled in a later version, delivery insights can summarize pace, clarity, and tone with consent.")
                .font(PoiseType.caption(.semibold))
                .foregroundStyle(Color.poiseMuted)
        }
        .padding(20)
        .poiseCard(fill: .poisePaleBlue, stroke: Color.poiseBlue.opacity(0.12))
    }
}
