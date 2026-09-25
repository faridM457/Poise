import SwiftUI

// Whether PoiseRootView should show the first-run onboarding flow at launch.
// Same reasoning as AccountStore.shouldShowSignInPrompt (see that file):
// deliberately plain UserDefaults, not CloudStore. A fresh install or
// reinstall is exactly when a first-run flow should fire again, and a
// synced flag would silently suppress that on the very device it matters
// most for.
enum OnboardingStore {
    private static let hasShownKey = "poise.hasShownOnboarding"

    static var shouldShow: Bool {
        !UserDefaults.standard.bool(forKey: hasShownKey)
    }

    static func markShown() {
        UserDefaults.standard.set(true, forKey: hasShownKey)
    }

    // Debug-only escape hatch (see ProfileView's Testing section) -- lets
    // onboarding be replayed without a real uninstall/reinstall.
    static func reset() {
        UserDefaults.standard.removeObject(forKey: hasShownKey)
    }
}

// Shown once, ever, at first launch, before the sign-in prompt (see
// PoiseRootView, which owns the one-time gate via OnboardingStore.shouldShow
// and marks it shown in the fullScreenCover's onDismiss -- the same pattern
// SignInPromptSheet uses one layer up). A brand-new user otherwise lands
// straight in the Learn tab with no idea what the app is, what energy means,
// or that a weekly goal exists at all.
//
// Three steps, enum-driven rather than TabView paging: LiveLessonFlowView's
// Step enum is this app's only other multi-step flow, and matching it (plain
// @State step + a segmented progress rail) keeps onboarding feeling like the
// same app instead of introducing a second paging idiom nothing else uses.
struct OnboardingView: View {
    let onFinish: () -> Void

    @ObservedObject private var progressStore = LearnProgressStore.shared
    @State private var step: OnboardingStep = .welcome

    var body: some View {
        VStack(spacing: 0) {
            OnboardingProgressRail(step: step.rawValue, total: OnboardingStep.allCases.count)

            // GeometryReader + a Spacer on each side (rather than just
            // top-aligning stepContent) centers the step's content in
            // whatever room is left above the buttons -- these steps are
            // short (an icon, a title, one or two lines), so top-aligned
            // left a large dead gap above the buttons. Still scrolls
            // normally if a step's content ever grows past one screen.
            GeometryReader { proxy in
                ScrollView {
                    VStack {
                        Spacer(minLength: 24)
                        stepContent
                            .padding(.horizontal, PoiseLayout.readingMargin)
                        Spacer(minLength: 24)
                    }
                    .frame(minHeight: proxy.size.height)
                }
            }

            VStack(spacing: 14) {
                Button(primaryTitle, action: advance)
                    .buttonStyle(PoiseFlatButtonStyle(fullWidth: true))
                    .padding(.horizontal, 24)

                // Step 1 has nowhere to go back to.
                if step != .welcome {
                    Button("Back", action: goBack)
                        .font(PoiseType.subhead(.bold))
                        .foregroundStyle(Color.poiseMuted)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color.poiseCanvas.ignoresSafeArea())
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            OnboardingWelcomeStep()
        case .energy:
            OnboardingEnergyStep()
        case .weeklyGoal:
            OnboardingWeeklyGoalStep(store: progressStore)
        }
    }

    private var primaryTitle: String {
        step == OnboardingStep.allCases.last ? "Get started" : "Next"
    }

    private func advance() {
        if let next = OnboardingStep(rawValue: step.rawValue + 1) {
            withAnimation(.snappy(duration: 0.22)) { step = next }
        } else {
            // Marking OnboardingStore shown happens once, in PoiseRootView's
            // fullScreenCover onDismiss -- same single-place-to-set-the-flag
            // reasoning as SignInPromptSheet. This just ends the flow.
            onFinish()
        }
    }

    private func goBack() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        withAnimation(.snappy(duration: 0.22)) { step = previous }
    }
}

private enum OnboardingStep: Int, CaseIterable {
    case welcome, energy, weeklyGoal
}

// Same segmented-capsule rail LessonProgressHeader uses for the live lesson
// flow, minus its exit button -- onboarding has nothing to exit to early.
private struct OnboardingProgressRail: View {
    let step: Int
    let total: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index <= step ? Color.poiseBlue : Color.poiseTrack)
                    .frame(height: 6)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step + 1) of \(total)")
    }
}

// One header shape shared by every step: icon badge, title, one or two
// sentences of plain copy underneath. Keeps the three screens reading as one
// flow instead of three separately designed ones.
private struct OnboardingStepHeader: View {
    let icon: String
    let iconColor: Color
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 20) {
            PoiseIconBadge(icon: icon, color: iconColor, size: 80)

            VStack(spacing: 8) {
                Text(title)
                    .font(PoiseType.title())
                    .foregroundStyle(Color.poiseNavy)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(PoiseType.body())
                    .foregroundStyle(Color.poiseMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Step 1: Welcome

private struct OnboardingWelcomeStep: View {
    var body: some View {
        OnboardingStepHeader(
            icon: "bubble.left.and.bubble.right.fill",
            iconColor: .poiseBlueDark,
            title: "Welcome to Poise",
            message: "Poise is a place to practice hard work conversations before you have them for real. Pick a scenario, talk it through with an AI character, and see how you did."
        )
    }
}

// MARK: - Step 2: Energy

private struct OnboardingEnergyStep: View {
    // Read straight from the real constants rather than writing numbers by
    // hand, so this copy can't quietly drift from what the app actually
    // does. freeRegenInterval/premiumRegenInterval are static because they
    // don't depend on the current user's tier -- unlike LearnProgressStore's
    // instance `regenHours`, which only ever answers for whichever tier is
    // active right now.
    private var freeHours: Int { Int(LearnProgressStore.freeRegenInterval / 3600) }
    private var premiumHours: Int { Int(LearnProgressStore.premiumRegenInterval / 3600) }

    var body: some View {
        VStack(spacing: 24) {
            OnboardingStepHeader(
                icon: "bolt.fill",
                iconColor: .poiseAmber,
                title: "How energy works",
                message: "Starting a conversation costs 1 energy. It refills on its own, so there's always more coming."
            )

            VStack(spacing: 12) {
                OnboardingEnergyTierRow(
                    icon: "bolt.fill",
                    iconColor: .poiseAmber,
                    title: "Free",
                    detail: "\(LearnProgressStore.freeEnergyCap) energy. One comes back every \(freeHours) hours."
                )
                OnboardingEnergyTierRow(
                    icon: "crown.fill",
                    iconColor: .poiseGold,
                    title: "Poise Pro",
                    detail: "\(LearnProgressStore.premiumEnergyCap) energy. One comes back every \(premiumHours) hours."
                )
            }
        }
    }
}

private struct OnboardingEnergyTierRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            PoiseIconBadge(icon: icon, color: iconColor, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(PoiseType.body(.bold))
                    .foregroundStyle(Color.poiseNavy)
                Text(detail)
                    .font(PoiseType.caption())
                    .foregroundStyle(Color.poiseMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .poiseCard(radius: 18)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Step 3: Weekly goal

private struct OnboardingWeeklyGoalStep: View {
    @ObservedObject var store: LearnProgressStore

    var body: some View {
        VStack(spacing: 24) {
            OnboardingStepHeader(
                icon: "target",
                iconColor: .poiseBlue,
                title: "Set your weekly goal",
                // Reworded so the trailing clause has enough words to fill a
                // line on its own instead of leaving a short, orphan-looking
                // wrap -- "in Profile." alone read as too short even with
                // the two words kept together. The non-breaking space is
                // still a safety net for whichever two words end up last.
                message: "This is how many conversations you're aiming for each week. It shows up on the Learn tab and your Progress dashboard, and you can always change it later from your Profile\u{00A0}tab."
            )

            OnboardingWeeklyGoalStepper(store: store)
        }
    }
}

// Matches ProfileView's SettingsStepperRow treatment (same layout, same
// Stepper-driving-a-Binding pattern), so this control looks and behaves
// exactly like the one in Profile the user will find it again as.
private struct OnboardingWeeklyGoalStepper: View {
    @ObservedObject var store: LearnProgressStore

    private var valueText: String {
        "\(store.weeklyGoal) conversation\(store.weeklyGoal == 1 ? "" : "s") per week"
    }

    var body: some View {
        HStack {
            Text("Weekly goal")
                .font(PoiseType.body(.bold))
                .foregroundStyle(Color.poiseNavy)
            Spacer(minLength: 12)
            Text(valueText)
                .font(PoiseType.subhead(.semibold))
                .foregroundStyle(Color.poiseMuted)
            // The only way weeklyGoal changes -- see
            // LearnProgressStore.setWeeklyGoal, which clamps to
            // 1...maxWeeklyGoal so this can never push it out of bounds.
            Stepper(
                "",
                value: Binding(
                    get: { store.weeklyGoal },
                    set: { store.setWeeklyGoal($0) }
                ),
                in: 1...store.maxWeeklyGoal
            )
            .labelsHidden()
            .tint(.poiseBlueDark)
            .accessibilityLabel("Weekly goal")
            .accessibilityValue(valueText)
        }
        .padding(16)
        .poiseCard(radius: 18)
    }
}

#Preview {
    OnboardingView(onFinish: {})
}
