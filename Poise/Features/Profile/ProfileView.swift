import RevenueCat
import SwiftUI

// Rebuilt on the shared system (see PoiseComponents' "Shared page chrome"):
// same top bar, same section eyebrows, same white card surface, same flat
// capsule button as Learn's hero. The upgrade card deliberately echoes the
// Learn hero's construction -- pale tint, eyebrow pill, title, description,
// capsule CTA -- so the app's one promotional surface and its one primary
// action look like the same idea rather than two different designs.
struct ProfileView: View {
    @ObservedObject private var store = LearnProgressStore.shared
    @ObservedObject private var profile = UserProfileStore.shared
    @ObservedObject private var subscriptions = SubscriptionStore.shared

    @State private var voicePractice = false
    @State private var videoRecording = false
    @State private var saveRecordings = false
    @State private var showPaywall = false
    @State private var showResetConfirm = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 26) {
                ProfileIdentity(
                    profile: profile,
                    lessonsDone: store.completedLessonIDs.count,
                    badgesEarned: store.earnedBadges.count
                )

                UpgradeCard(isPremium: subscriptions.isPro) { showPaywall = true }

                PoiseSection(title: "Privacy") {
                    PrivacyCard(
                        voicePractice: $voicePractice,
                        videoRecording: $videoRecording,
                        saveRecordings: $saveRecordings
                    )
                }

                PoiseSection(title: "Account & settings") {
                    SettingsCard(profile: profile, onReset: { showResetConfirm = true })
                }

                PoiseSection(title: "Testing") {
                    VStack(alignment: .leading, spacing: 18) {
                        EnergyCheatCard(store: store)
                        ClockCheatCard(store: store)
                        SkipRoleplayCard(store: store)
                    }
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
        // See ProgressDashboardView: a ZStack sibling that ignores the safe
        // area costs the ScrollView the root's bottom tab-bar inset.
        .background(Color.poiseCanvas.ignoresSafeArea())
        .sheet(isPresented: $showPaywall) {
            PaywallSheet(subscriptions: subscriptions)
        }
        .alert("Reset all progress?", isPresented: $showResetConfirm) {
            Button("Reset", role: .destructive) { store.resetProgress() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every finished conversation, your streak and all badges will be cleared. This can't be undone.")
        }
    }
}

// MARK: - Identity

// Stands in for the page title, so Profile doesn't carry both a heading and a
// name saying the same thing. The initial tile uses PoiseIconBadge's geometry
// (radius = 0.3x size) at a larger size.
private struct ProfileIdentity: View {
    @ObservedObject var profile: UserProfileStore
    let lessonsDone: Int
    let badgesEarned: Int

    @State private var isEditing = false
    @FocusState private var nameFocused: Bool

    private let tileSize: CGFloat = 60

    // Was a fixed "practicing with purpose" for everyone. Now it reports what
    // the user has actually done, which is the only thing this line can say
    // that they can't already see is untrue.
    private var subtitle: String {
        guard lessonsDone > 0 else { return "No conversations yet" }
        let lessons = "\(lessonsDone) lesson\(lessonsDone == 1 ? "" : "s") done"
        guard badgesEarned > 0 else { return lessons }
        return lessons + " · \(badgesEarned) badge\(badgesEarned == 1 ? "" : "s")"
    }

    var body: some View {
        HStack(spacing: 14) {
            Text(profile.initial)
                .font(PoiseType.title())
                .foregroundStyle(Color.poiseBlueDark)
                .frame(width: tileSize, height: tileSize)
                .background(Color.poiseSoftBlue)
                .clipShape(RoundedRectangle(cornerRadius: tileSize * 0.3, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                if isEditing {
                    TextField("Your name", text: $profile.name)
                        .font(PoiseType.title())
                        .foregroundStyle(Color.poiseNavy)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused($nameFocused)
                        .onSubmit { isEditing = false }
                } else {
                    Button {
                        isEditing = true
                        nameFocused = true
                    } label: {
                        HStack(spacing: 6) {
                            Text(profile.hasName ? profile.name : "Add your name")
                                .font(PoiseType.title())
                                .foregroundStyle(profile.hasName ? Color.poiseNavy : Color.poiseMuted)
                            Image(systemName: "pencil")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.poiseMuted)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Text(subtitle)
                    .font(PoiseType.subhead())
                    .foregroundStyle(Color.poiseMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Upgrade

private struct UpgradeCard: View {
    let isPremium: Bool
    let onExplore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PoiseEyebrow(text: isPremium ? "Poise Pro" : "Free plan", color: .poiseBlueDark)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.75))
                .clipShape(Capsule())

            Spacer().frame(height: 12)

            Text(isPremium ? "You're on Poise Pro." : "More room to practice.")
                .font(PoiseType.headline())
                .foregroundStyle(Color.poiseNavy)

            Spacer().frame(height: 5)

            Text(isPremium
                 ? "Twelve energy refilling every 2 hours, voice analysis, and scenarios you write yourself."
                 : "Twelve energy refilling 4x faster, voice analysis, your own scenarios, and no ads.")
                .font(PoiseType.subhead())
                .foregroundStyle(Color.poiseMuted)
                .fixedSize(horizontal: false, vertical: true)

            Spacer().frame(height: 16)

            Button(isPremium ? "Manage plan" : "Explore Poise Pro", action: onExplore)
                .buttonStyle(PoiseFlatButtonStyle())
                .accessibilityLabel(isPremium ? "Manage plan" : "Explore Poise Pro")
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.poiseSoftBlue, Color.poisePaleBlue],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.poiseBlue.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .poiseNavy.opacity(0.07), radius: 12, x: 0, y: 6)
    }
}

// MARK: - Settings cards
//
// All three are the same object: a white card holding rows separated by the
// app's hairline, no internal headline (the section eyebrow above names it).

private struct PrivacyCard: View {
    @Binding var voicePractice: Bool
    @Binding var videoRecording: Bool
    @Binding var saveRecordings: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PoiseSurfaceCard(padding: 0) {
                VStack(spacing: 0) {
                    SettingsToggleRow(
                        title: "Voice practice",
                        subtitle: "Speak your turns instead of typing them.",
                        isOn: $voicePractice
                    )
                    PoiseDivider().padding(.horizontal, 16)
                    SettingsToggleRow(
                        title: "Video recording",
                        subtitle: "Record video alongside a session for your own review.",
                        isOn: $videoRecording
                    )
                    PoiseDivider().padding(.horizontal, 16)
                    SettingsToggleRow(
                        title: "Save recordings",
                        subtitle: "Off by default. Keep a session only when you choose to.",
                        isOn: $saveRecordings
                    )
                }
            }

            FootNote("Nothing is recorded or uploaded. These settings stay on this device.")
        }
    }
}

private struct SettingsCard: View {
    @ObservedObject var profile: UserProfileStore
    let onReset: () -> Void

    var body: some View {
        PoiseSurfaceCard(padding: 0) {
            VStack(spacing: 0) {
                // English is the only language the lesson content exists in,
                // so this is shown as a fact rather than as a picker that
                // would offer choices the app can't honour.
                SettingsValueRow(title: "Practice language", value: profile.practiceLanguage)
                PoiseDivider().padding(.horizontal, 16)
                SettingsToggleRow(title: "Sound effects", subtitle: nil, isOn: $profile.soundEffects)
                PoiseDivider().padding(.horizontal, 16)
                Button(action: onReset) {
                    HStack {
                        Text("Reset progress")
                            .font(PoiseType.body(.bold))
                            .foregroundStyle(SkillLevel.needsWork.tint)
                        Spacer(minLength: 12)
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(SkillLevel.needsWork.tint)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Testing

// Development-only. Energy regenerates on a real-world clock, so without
// this neither end of the range can be reached on demand: you cannot see the
// out-of-energy block without waiting out three real conversations, and you
// cannot get back to full without waiting a day. Delete this card and
// LearnProgressStore's "Testing helpers" section together before shipping.
private struct EnergyCheatCard: View {
    @ObservedObject var store: LearnProgressStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PoiseSurfaceCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        PoiseIconBadge(icon: "bolt.fill", color: .poiseAmber)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.energyDisplayText)
                                .font(PoiseType.headline())
                                .foregroundStyle(Color.poiseNavy)
                            Text(store.countdownText().map { "Next in \($0)" } ?? "Full")
                                .font(PoiseType.subhead())
                                .foregroundStyle(Color.poiseMuted)
                                .monospacedDigit()
                        }
                        Spacer(minLength: 8)
                    }

                    HStack(spacing: 10) {
                        CheatButton(title: "1", icon: "plus") {
                            store.grantEnergy()
                        }
                        .disabled(store.energyRemaining >= store.energyCap)

                        CheatButton(title: "Fill", icon: "bolt.fill") {
                            store.grantEnergy(store.energyCap)
                        }
                        .disabled(store.energyRemaining >= store.energyCap)

                        CheatButton(title: "Empty", icon: "minus") {
                            store.drainEnergy()
                        }
                        .disabled(store.energyRemaining == 0)
                    }
                }
            }

            FootNote("Development shortcuts. Empty is how you reach the out-of-energy block without waiting out the regen clock.")
        }
    }
}

// Development-only, and the loudest thing on this page when it is active:
// with the clock moved, every date the app shows is a lie, and forgetting that
// would make the calendar and streak look broken rather than shifted.
private struct ClockCheatCard: View {
    @ObservedObject var store: LearnProgressStore

    private var simulatedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE d MMMM"
        return formatter.string(from: store.now)
    }

    private var offsetLabel: String {
        let days = -store.debugDayOffset
        guard days > 0 else { return "Real date" }
        return "\(days) day\(days == 1 ? "" : "s") back"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PoiseSurfaceCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        PoiseIconBadge(
                            icon: store.isTimeTravelling ? "clock.badge.exclamationmark.fill" : "calendar",
                            color: store.isTimeTravelling ? .poiseOrange : .poiseBlueDark
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(simulatedDate)
                                .font(PoiseType.headline())
                                .foregroundStyle(Color.poiseNavy)
                            Text(offsetLabel)
                                .font(PoiseType.subhead())
                                .foregroundStyle(store.isTimeTravelling ? Color.poiseOrange : Color.poiseMuted)
                        }
                        Spacer(minLength: 8)
                    }

                    HStack(spacing: 10) {
                        CheatButton(title: "1 day", icon: "chevron.left") {
                            store.stepBackOneDay()
                        }

                        CheatButton(title: "Today", icon: "arrow.uturn.right") {
                            store.returnToToday()
                        }
                        .disabled(!store.isTimeTravelling)
                    }
                }
            }

            FootNote("Moves the app's idea of today backwards so a streak can be built in one sitting: step back a day, finish a lesson, return to today, finish another. Energy keeps the real clock.")
        }
    }
}

private struct SkipRoleplayCard: View {
    @ObservedObject var store: LearnProgressStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PoiseSurfaceCard(padding: 0) {
                SettingsToggleRow(
                    title: "Skip roleplay",
                    subtitle: "\"Let's practice\" jumps straight to the results screen.",
                    isOn: $store.debugSkipRoleplay
                )
            }

            FootNote("Energy is still spent, so the cost and the out-of-energy block behave normally. The scorecard is synthetic — nothing on it is a real assessment.")
        }
    }
}

private struct CheatButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                Text(title)
                    .font(PoiseType.subhead(.bold))
            }
            .foregroundStyle(isEnabled ? Color.poiseBlueDark : Color.poiseMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(isEnabled ? Color.poiseSoftBlue : Color.poiseSoftGray)
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) energy")
    }
}

// MARK: - Rows

private struct SettingsToggleRow: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(PoiseType.body(.bold))
                    .foregroundStyle(Color.poiseNavy)
                if let subtitle {
                    Text(subtitle)
                        .font(PoiseType.caption())
                        .foregroundStyle(Color.poiseMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        // The app's primary accent, not the system green -- switches are the
        // only interactive control on this page and should match the CTA.
        .tint(.poiseBlueDark)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityLabel(title)
    }
}

private struct SettingsValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(PoiseType.body(.bold))
                .foregroundStyle(Color.poiseNavy)
            Spacer(minLength: 12)
            Text(value)
                .font(PoiseType.subhead(.semibold))
                .foregroundStyle(Color.poiseMuted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }
}

private struct FootNote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(PoiseType.caption())
            .foregroundStyle(Color.poiseMuted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }
}

// MARK: - Paywall

// The app's own paywall, driven by RevenueCat. The prebuilt RevenueCatUI
// PaywallView was the obvious alternative and was deliberately not used: it
// brings its own typography, spacing and button treatment, which is the exact
// mismatch this screen was just rebuilt to remove. What RevenueCat owns here
// is the commerce -- offerings, localized prices, the purchase, restore and
// the entitlement -- while the presentation stays on the app's own ladder.
private struct PaywallSheet: View {
    @ObservedObject var subscriptions: SubscriptionStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPackageID: String?

    private let benefits: [(icon: String, title: String, detail: String)] = [
        ("bolt.fill", "12 energy, refilling 4x faster",
         "One back every 2 hours instead of every 8 — a full reserve a day, against three on Free."),
        // Marked because neither is built yet -- the paywall should not read
        // as if paying today unlocks them.
        ("waveform", "Voice analysis",
         "Practice out loud and get read back on pace, clarity and tone, not just on what you said. (Coming Soon)"),
        ("wand.and.stars", "Build your own scenarios",
         "Describe the conversation you're actually dreading and practice that one, in your own words. (Coming Soon)"),
        ("hand.raised.slash.fill", "No ads",
         "Free shows one ad after each lesson. Pro never interrupts a debrief."),
    ]

    private var selectedPackage: Package? {
        subscriptions.sortedPackages.first { $0.identifier == selectedPackageID }
            ?? subscriptions.sortedPackages.first
    }

    var body: some View {
        ZStack {
            Color.poiseCanvas.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    Spacer().frame(height: 22)

                    PoiseSurfaceCard(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(benefits.enumerated()), id: \.element.title) { index, benefit in
                                if index > 0 {
                                    PoiseDivider().padding(.leading, 68)
                                }
                                BenefitRow(icon: benefit.icon, title: benefit.title, detail: benefit.detail)
                            }
                        }
                    }

                    if !subscriptions.isPro {
                        Spacer().frame(height: 22)
                        planSection
                    }
                }
                .padding(24)
            }
        }
        .safeAreaInset(edge: .bottom) { footer }
        .task {
            await subscriptions.loadOfferings()
            if selectedPackageID == nil {
                selectedPackageID = subscriptions.sortedPackages.first?.identifier
            }
        }
        .overlay {
            if let message = subscriptions.errorMessage {
                PoiseModal(
                    icon: "exclamationmark.triangle.fill",
                    iconColor: .poiseOrange,
                    title: "Something went wrong",
                    message: message,
                    primaryTitle: "OK",
                    onPrimary: { subscriptions.errorMessage = nil }
                )
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                PoiseIconBadge(icon: "sparkles", color: .poiseGold, size: 44)
                Spacer()
                Button("Done") { dismiss() }
                    .font(PoiseType.body(.bold))
                    .foregroundStyle(Color.poiseBlueDark)
            }

            Spacer().frame(height: 20)

            Text(subscriptions.isPro ? "You're on Poise Pro." : "Practice more, and on your own terms.")
                .font(PoiseType.title())
                .foregroundStyle(Color.poiseNavy)

            Spacer().frame(height: 6)

            Text(subscriptions.isPro
                 ? "Your plan is active. Manage or cancel it any time from the App Store."
                 : "More practice, spoken feedback, your own scenarios, and nothing interrupting them.")
                .font(PoiseType.subhead())
                .foregroundStyle(Color.poiseMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var planSection: some View {
        Text("Choose a plan")
            .font(PoiseType.eyebrow())
            .tracking(PoiseType.eyebrowTracking)
            .foregroundStyle(Color.poiseMuted)

        Spacer().frame(height: 10)

        switch subscriptions.loadState {
        case .idle, .loading:
            PoiseSurfaceCard {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading plans")
                        .font(PoiseType.subhead())
                        .foregroundStyle(Color.poiseMuted)
                    Spacer(minLength: 0)
                }
            }
        case .unavailable(let reason):
            // Says so plainly instead of showing an empty list above a button
            // that cannot do anything.
            PoiseSurfaceCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(reason)
                        .font(PoiseType.subhead())
                        .foregroundStyle(Color.poiseMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Try again") {
                        Task { await subscriptions.loadOfferings() }
                    }
                    .buttonStyle(PoiseFlatButtonStyle())
                }
            }
        case .loaded:
            VStack(spacing: 10) {
                ForEach(subscriptions.sortedPackages, id: \.identifier) { package in
                    PlanRow(
                        package: package,
                        isSelected: selectedPackage?.identifier == package.identifier,
                        onSelect: { selectedPackageID = package.identifier }
                    )
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button(action: primaryAction) {
                if subscriptions.isPurchasing {
                    ProgressView().tint(.white)
                } else {
                    Text(primaryTitle)
                }
            }
            .buttonStyle(PoiseFlatButtonStyle(fullWidth: true))
            .disabled(subscriptions.isPurchasing || (!subscriptions.isPro && selectedPackage == nil))

            if !subscriptions.isPro {
                // Required by App Review, and the only way a returning user on
                // a new device gets their subscription back.
                Button("Restore purchases") {
                    Task {
                        if await subscriptions.restorePurchases() { dismiss() }
                    }
                }
                .font(PoiseType.caption(.bold))
                .foregroundStyle(Color.poiseBlueDark)
                .disabled(subscriptions.isPurchasing)
            }

            Text("Cancel any time. Renews automatically until cancelled.")
                .font(PoiseType.caption())
                .foregroundStyle(Color.poiseMuted)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .background(Color.poiseCanvas)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.poiseBorder.opacity(0.8))
                .frame(height: 1)
        }
    }

    private var primaryTitle: String {
        if subscriptions.isPro { return "Manage subscription" }
        guard let package = selectedPackage else { return "Start Poise Pro" }
        return "Start Poise Pro — \(package.storeProduct.localizedPriceString)"
    }

    private func primaryAction() {
        guard !subscriptions.isPro else {
            dismiss()
            return
        }
        guard let package = selectedPackage else { return }
        Task {
            if await subscriptions.purchase(package) { dismiss() }
        }
    }
}

private struct BenefitRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            PoiseIconBadge(icon: icon, color: .poiseBlueDark)
            VStack(alignment: .leading, spacing: 3) {
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
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct PlanRow: View {
    let package: Package
    let isSelected: Bool
    let onSelect: () -> Void

    private var title: String {
        switch package.packageType {
        case .annual: return "Annual"
        case .monthly: return "Monthly"
        case .weekly: return "Weekly"
        case .lifetime: return "Lifetime"
        default: return package.storeProduct.localizedTitle
        }
    }

    private var cadence: String {
        switch package.packageType {
        case .annual: return "per year"
        case .monthly: return "per month"
        case .weekly: return "per week"
        case .lifetime: return "one time"
        default: return ""
        }
    }

    // Only shown when StoreKit actually gives us a per-month figure, rather
    // than dividing the price ourselves -- a hand-computed "$4.17 a month"
    // goes wrong on tax-inclusive storefronts and odd currencies.
    private var detail: String? {
        guard package.packageType == .annual,
              let monthly = package.storeProduct.localizedPricePerMonth
        else { return nil }
        return "\(monthly) a month"
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.poiseBlueDark : Color.poiseTrack)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(PoiseType.body(.bold))
                        .foregroundStyle(Color.poiseNavy)
                    if let detail {
                        Text(detail)
                            .font(PoiseType.caption())
                            .foregroundStyle(Color.poiseMintDark)
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(package.storeProduct.localizedPriceString)
                        .font(PoiseType.headline())
                        .foregroundStyle(Color.poiseNavy)
                    Text(cadence)
                        .font(PoiseType.caption())
                        .foregroundStyle(Color.poiseMuted)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            // Matches PoiseSurfaceCard's geometry -- radius 20, hairline, one
            // soft shadow -- rather than inventing a second card treatment on
            // the one screen a new user is most likely to scrutinise. Only the
            // selected row thickens its stroke, which is the selection itself.
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(isSelected ? Color.poiseBlueDark : Color.poiseBorder, lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: .poiseNavy.opacity(0.05), radius: 8, x: 0, y: 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(package.storeProduct.localizedPriceString) \(cadence)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
