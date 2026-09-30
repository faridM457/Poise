import AuthenticationServices
import RevenueCat
import SwiftUI
import UIKit

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
    @ObservedObject private var account = AccountStore.shared
    @ObservedObject private var notifications = OneSignalNotificationService.shared

    @State private var showPaywall = false
    @State private var showResetConfirm = false

    #if DEBUG
    // Compiled out of Release, same as the Testing section below that's
    // this closure's only caller.
    var onDebugReplayFirstLaunch: () -> Void = {}
    #endif

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 26) {
                ProfileIdentity(
                    profile: profile,
                    lessonsDone: store.completedLessonIDs.count,
                    badgesEarned: store.earnedBadges.count
                )

                UpgradeCard(isPremium: subscriptions.isPro) { showPaywall = true }

                PoiseSection(title: "Account") {
                    VStack(alignment: .leading, spacing: 14) {
                        AccountCard(account: account)
                        RedeemCodeCard(store: store)
                    }
                }

                PoiseSection(title: "Privacy") {
                    PrivacyCard()
                }

                PoiseSection(title: "Notifications") {
                    NotificationPreferencesCard(service: notifications)
                }

                PoiseSection(title: "Account & settings") {
                    SettingsCard(profile: profile, store: store, onReset: { showResetConfirm = true })
                }

                #if DEBUG
                // Compiled out of Release entirely -- not just hidden -- so a
                // real App Store build carries neither the cheat UI nor a way
                // to reach it. See EnergyCheatCard's header comment.
                PoiseSection(title: "Testing") {
                    VStack(alignment: .leading, spacing: 18) {
                        EnergyCheatCard(store: store)
                        ClockCheatCard(store: store)
                        SkipRoleplayCard(store: store)
                        VoiceAnalysisDiagnosticsButton()
                        ReplayFirstLaunchCard(action: onDebugReplayFirstLaunch)
                    }
                }
                #endif

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
                // Matches the fix already used on the app's other sheets --
                // without it, a sheet's default backing on this iOS version
                // is the translucent Liquid Glass material, which doesn't
                // match this app's one surface treatment.
                .presentationBackground(Color.poiseCanvas)
        }
        .alert("Reset all progress?", isPresented: $showResetConfirm) {
            Button("Reset", role: .destructive) { store.resetProgress() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every finished conversation, your streak and all badges will be cleared. This can't be undone.")
        }
    }
}

private struct NotificationPreferencesCard: View {
    @ObservedObject var service: OneSignalNotificationService
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PoiseSurfaceCard(padding: 0) {
                VStack(spacing: 0) {
                    notificationToggle(
                        title: "Practice reminders",
                        subtitle: "A gentle prompt when you're ready for today's communication practice.",
                        isOn: service.preferences.practiceReminders,
                        update: service.setPracticeReminders
                    )
                    PoiseDivider().padding(.horizontal, 16)
                    notificationToggle(
                        title: "Streak expiration alerts",
                        subtitle: "A heads-up before an active practice streak expires.",
                        isOn: service.preferences.streakExpirationAlerts,
                        update: service.setStreakExpirationAlerts
                    )
                    PoiseDivider().padding(.horizontal, 16)
                    notificationToggle(
                        title: "Weekly progress summary",
                        subtitle: "A weekly recap of practice, XP and streak progress.",
                        isOn: service.preferences.weeklyProgressSummary,
                        update: service.setWeeklyProgressSummary
                    )
                    PoiseDivider().padding(.horizontal, 16)
                    notificationToggle(
                        title: "Custom-scenario reminders",
                        subtitle: "A nudge to try the custom scenario builder if it's been a while.",
                        isOn: service.preferences.customScenarioReminders,
                        update: service.setCustomScenarioReminders
                    )
                }
            }

            if service.permissionState == .denied {
                Button("Open iOS notification settings") { service.openSystemSettings() }
                    .font(PoiseType.subhead(.bold))
                    .foregroundStyle(Color.poiseBlueDark)
                    .accessibilityLabel("Open Poise notification settings")
            } else if service.permissionState == .provisional {
                FootNote("Notifications are currently delivered quietly. You can change delivery in iOS Settings.")
            } else {
                FootNote("Preferences stay on this device and are used by OneSignal Journeys. Poise never asks at launch.")
            }
        }
        .task { await service.refreshPermissionState() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await service.refreshPermissionState() } }
        }
    }

    private func notificationToggle(
        title: String,
        subtitle: String,
        isOn: Bool,
        update: @escaping (Bool) async -> Void
    ) -> some View {
        SettingsToggleRow(
            title: title,
            subtitle: subtitle,
            isOn: Binding(
                get: { isOn },
                set: { newValue in Task { await update(newValue) } }
            )
        )
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

// The only account the app has: Sign in with Apple exists purely to give
// RevenueCat a stable id, so a subscription and its energy ledger (both
// keyed server-side on that id -- see AccountStore) survive a reinstall or a
// new device instead of resetting with a fresh anonymous user every time.
// Using the app signed out is fully supported; this card just offers the
// option, it never gates anything.
private struct AccountCard: View {
    @ObservedObject var account: AccountStore

    var body: some View {
        PoiseSurfaceCard {
            if account.isSignedIn {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Signed in with Apple")
                            .font(PoiseType.subhead(.bold))
                            .foregroundStyle(Color.poiseNavy)
                        Text("Your streak, energy, and Pro subscription sync across devices.")
                            .font(PoiseType.caption())
                            .foregroundStyle(Color.poiseMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Button("Sign out") { account.signOut() }
                        .font(PoiseType.subhead(.bold))
                        .foregroundStyle(Color.poiseBlueDark)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Keep your progress")
                        .font(PoiseType.subhead(.bold))
                        .foregroundStyle(Color.poiseNavy)
                    Text("Sign in with Apple so your streak, energy, and Pro subscription survive a reinstall or a new device.")
                        .font(PoiseType.caption())
                        .foregroundStyle(Color.poiseMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    // Only the name, and only to pre-fill Profile's editable
                    // name field if it's still blank (see
                    // AccountStore.handleAuthorization) -- no email scope,
                    // since nothing here has a use for it: no backend user
                    // table, no communications.
                    SignInWithAppleButton(.signIn, onRequest: { request in
                        request.requestedScopes = [.fullName]
                    }, onCompletion: { result in
                        switch result {
                        case .success(let authorization):
                            account.handleAuthorization(authorization)
                        case .failure(let error):
                            print("AccountCard: Sign in with Apple failed: \(error.localizedDescription)")
                        }
                    })
                    .frame(height: 44)
                }
            }
        }
    }
}

// A code redeemed here goes straight to the server (POST /api/redeem, see
// conversation-engine/server/energy.js: redeemJudgeCode) -- there is no
// client-side notion of a valid code, so a wrong one always round-trips
// before it's rejected. Built for Shipaton judges: it grants a large
// standing energy cap so a judging session isn't bounded by Pro's normal
// 12-a-day reserve. Anyone can try; an unset or wrong code just fails.
private struct RedeemCodeCard: View {
    @ObservedObject var store: LearnProgressStore

    @State private var code = ""
    @State private var isSubmitting = false
    @State private var feedback: String?
    @State private var feedbackIsError = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        PoiseSurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Have a code?")
                    .font(PoiseType.subhead(.bold))
                    .foregroundStyle(Color.poiseNavy)
                HStack(spacing: 10) {
                    TextField("Enter code", text: $code)
                        .focused($fieldFocused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(PoiseType.body())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.poiseCanvas)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Button(isSubmitting ? "…" : "Redeem") { redeem() }
                        .font(PoiseType.subhead(.bold))
                        .foregroundStyle(Color.poiseBlueDark)
                        .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
                }
                if let feedback {
                    Text(feedback)
                        .font(PoiseType.caption())
                        .foregroundStyle(feedbackIsError ? SkillLevel.needsWork.tint : Color.poiseMuted)
                }
            }
        }
    }

    private func redeem() {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        fieldFocused = false
        isSubmitting = true
        feedback = nil
        Task {
            do {
                let response = try await ConversationEngineClient.redeemCode(trimmed)
                store.applyServerEnergy(response.energy)
                feedback = "Code redeemed."
                feedbackIsError = false
                code = ""
            } catch {
                feedback = error.localizedDescription
                feedbackIsError = true
            }
            isSubmitting = false
        }
    }
}

// MARK: - Settings cards
//
// All three are the same object: a white card holding rows separated by the
// app's hairline, no internal headline (the section eyebrow above names it).

// Microphone access and practice reminders, plus "Ad privacy choices" for
// users Google's consent message applies to. No separate "voice practice"
// toggle --
// speaking your turns instead of typing already works today (see
// LiveLessonFlowView's mic button, backed by SpeechRecognitionService),
// it's a plain button, not a mode to opt into.
private struct PrivacyCard: View {
    // This can't flip the OS permission itself -- no app can. It mirrors the
    // real state (SFSpeechRecognizer + AVAudioApplication, read fresh on
    // every foreground) and, on tap, either fires the one-time system
    // prompt (first use, .notDetermined -- same prompt the lesson's mic
    // button itself would trigger) or hands off to Settings (already
    // decided, either direction -- iOS won't re-prompt, Settings is the
    // only place left that can change it). If the user taps "Don't Allow"
    // on that system prompt, this snaps back to off on its own, because
    // it's reading truth, not holding a separate stored preference.
    @State private var micAuthorized = SpeechRecognitionService.isAuthorized
    // Seeded false, then corrected as soon as the view appears -- unlike
    // SFSpeechRecognizer.authorizationStatus(), UNUserNotificationCenter's
    // settings only come back through an async call (see
    // NotificationService.isAuthorized), so there's no synchronous truth to
    // seed this @State with the way micAuthorized above is seeded.
    @State private var notificationsAuthorized = false
    // Only users Google's consent message applies to (EEA, UK, Switzerland)
    // get the "Ad privacy choices" row -- Google requires a way to change the
    // choice later.
    @ObservedObject private var adConsent = AdConsentManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PoiseSurfaceCard(padding: 0) {
                VStack(spacing: 0) {
                    SettingsToggleRow(
                        title: "Microphone access",
                        subtitle: "Needed to speak your turns instead of typing them. With Pro, your delivery is also analyzed on this device.",
                        isOn: Binding(get: { micAuthorized }, set: { _ in handleMicToggle() })
                    )
                    PoiseDivider().padding(.horizontal, 16)
                    SettingsToggleRow(
                        title: "Practice reminders",
                        subtitle: "A nudge to keep a streak alive, or a heads-up that your next lesson's ready.",
                        isOn: Binding(get: { notificationsAuthorized }, set: { _ in handleNotificationToggle() })
                    )
                    if adConsent.privacyOptionsRequired {
                        PoiseDivider().padding(.horizontal, 16)
                        SettingsActionRow(
                            title: "Ad privacy choices",
                            subtitle: "Change what you agreed to for ads."
                        ) {
                            Task { await adConsent.presentPrivacyOptions() }
                        }
                    }
                }
            }

            // Recordings stay on this device and are deleted once the lesson closes;
            // what does leave the device is the conversation text (and, for Pro,
            // the delivery numbers), sent to Poise's server for replies and grading.
            FootNote("Your voice recordings never leave this device and are deleted when the lesson ends. What you say, as text, is sent to Poise's server to write replies and grade the conversation.")
        }
        .task {
            notificationsAuthorized = await NotificationService.isAuthorized
        }
        // Catches a change made in Settings while this screen was
        // backgrounded -- there's no push notification for permission
        // changes, foregrounding is the only reliable moment to re-check.
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                micAuthorized = SpeechRecognitionService.isAuthorized
                Task { notificationsAuthorized = await NotificationService.isAuthorized }
            }
        }
    }

    private func handleMicToggle() {
        if SpeechRecognitionService.isUndetermined {
            Task {
                _ = await SpeechRecognitionService.requestAuthorization()
                micAuthorized = SpeechRecognitionService.isAuthorized
            }
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func handleNotificationToggle() {
        Task {
            if await NotificationService.isUndetermined {
                _ = await NotificationService.requestAuthorization()
                notificationsAuthorized = await NotificationService.isAuthorized
            } else if let url = URL(string: UIApplication.openSettingsURLString) {
                // Inside this Task's async context, UIApplication.open's
                // completion-handler variant surfaces its generated async
                // overload instead of the fire-and-forget sync one
                // handleMicToggle uses in its own (synchronous) branch --
                // so this awaits it explicitly rather than fighting that.
                _ = await UIApplication.shared.open(url)
            }
        }
    }
}

private struct SettingsCard: View {
    @ObservedObject var profile: UserProfileStore
    @ObservedObject var store: LearnProgressStore
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
                // Range is 1...store.maxWeeklyGoal rather than a cached
                // value, so a Pro downgrade (or a judge redemption) is
                // reflected the moment it happens, not just after relaunch.
                SettingsStepperRow(
                    title: "Weekly goal",
                    value: "\(store.weeklyGoal) conversation\(store.weeklyGoal == 1 ? "" : "s")",
                    count: Binding(
                        get: { store.weeklyGoal },
                        set: { store.setWeeklyGoal($0) }
                    ),
                    range: 1...store.maxWeeklyGoal
                )
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
// cannot get back to full without waiting a day. Compiled out of Release
// along with the rest of the Testing section above (see body's #if DEBUG)
// and LearnProgressStore's "Testing helpers" section, so there is nothing
// left to remember to delete before shipping.
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

private struct ReplayFirstLaunchCard: View {
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PoiseSurfaceCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        PoiseIconBadge(icon: "arrow.counterclockwise", color: .poisePurple)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("First-launch flow")
                                .font(PoiseType.headline())
                                .foregroundStyle(Color.poiseNavy)
                            Text("Onboarding, then the sign-in prompt")
                                .font(PoiseType.subhead())
                                .foregroundStyle(Color.poiseMuted)
                        }
                        Spacer(minLength: 8)
                    }

                    Button(action: action) {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text("Replay")
                                .font(PoiseType.subhead(.bold))
                        }
                        .foregroundStyle(Color.poiseBlueDark)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color.poiseSoftBlue)
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Replay the first-launch flow")
                }
            }

            FootNote("Resets the one-time onboarding and sign-in-prompt flags and shows both again, onboarding first. Also signs you out if you were signed in, since the sign-in prompt only shows to a signed-out account -- your progress itself is untouched.")
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

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(PoiseType.body(.bold))
                    .foregroundStyle(isEnabled ? Color.poiseNavy : Color.poiseMuted)
                if let subtitle {
                    Text(subtitle)
                        .font(PoiseType.caption())
                        .foregroundStyle(Color.poiseMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(PoiseSwitchToggleStyle())
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityLabel(title)
    }
}

// A custom switch, not `.toggleStyle(.switch)` with `.tint()` -- the native
// switch style only lets you customize the ON color; its OFF track is a
// fixed system gray with no exposed API to darken, which read as too low
// contrast against this app's light backgrounds.
private struct PoiseSwitchToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: ToggleStyleConfiguration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 12)
            Capsule()
                .fill(configuration.isOn ? Color.poiseBlueDark : Color.poiseMuted.opacity(0.4))
                .frame(width: 51, height: 31)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .padding(2)
                        .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                }
                .opacity(isEnabled ? 1 : 0.5)
                .animation(.easeInOut(duration: 0.2), value: configuration.isOn)
                .onTapGesture {
                    guard isEnabled else { return }
                    configuration.isOn.toggle()
                }
        }
    }
}

// A settings row that opens something rather than toggling -- same type
// ladder and padding as SettingsToggleRow, with a chevron in the switch's place.
private struct SettingsActionRow: View {
    let title: String
    let subtitle: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
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
                Spacer(minLength: 12)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.poiseMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle ?? "")
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

// Visually identical to SettingsValueRow -- same title/value type ladder and
// padding -- but with a native Stepper standing in for the reset button's
// static text, since the value here is something the user actually sets.
private struct SettingsStepperRow: View {
    let title: String
    let value: String
    @Binding var count: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack {
            Text(title)
                .font(PoiseType.body(.bold))
                .foregroundStyle(Color.poiseNavy)
            Spacer(minLength: 12)
            Text(value)
                .font(PoiseType.subhead(.semibold))
                .foregroundStyle(Color.poiseMuted)
            Stepper("", value: $count, in: range)
                .labelsHidden()
                // Matches SettingsToggleRow's tint -- the -/+ control is
                // interactive chrome, same as a switch, so it should match
                // the app's one accent rather than the system default.
                .tint(.poiseBlueDark)
                // Left as its own accessibility element (not combined into
                // the row) so VoiceOver keeps the Stepper's increment/
                // decrement actions; this just gives it a clearer label
                // and the current value to read out.
                .accessibilityLabel(title)
                .accessibilityValue(value)
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
// UNVERIFIED (2026-09-17): written against the documented shape of
// StoreProductDiscount/SubscriptionPeriod, but never screenshot-checked
// end to end. RevenueCat's Test Store can't carry an introductory offer at
// all (confirmed directly with RevenueCat support this session), and no
// production or TestFlight-sandbox build with a real trial-eligible
// subscription exists yet either -- so there has been no environment able
// to actually exercise this branch. The 1-week Free intro offer already
// added to Poise Pro Annual in App Store Connect should make
// `introductoryDiscount` non-nil with `paymentMode == .freeTrial` once a
// build can reach real or sandboxed App Store data. Confirm this with a
// screenshot the first time that's possible, per this session's
// visual-verification rule, before treating it as done.
//
// `eligible` gates on the specific account, not just the product: Apple
// restricts a trial to first-time subscribers, and showing "free trial" to
// someone who'd actually be charged immediately would be wrong. See
// SubscriptionStore.isEligibleForTrial.
fileprivate func trialPeriodText(for package: Package, eligible: Bool) -> String? {
    guard eligible,
          let discount = package.storeProduct.introductoryDiscount,
          discount.paymentMode == .freeTrial
    else { return nil }
    let period = discount.subscriptionPeriod
    let unit: String
    switch period.unit {
    case .day: unit = "day"
    case .week: unit = "week"
    case .month: unit = "month"
    case .year: unit = "year"
    @unknown default: unit = "period"
    }
    return "\(period.value) \(unit)\(period.value == 1 ? "" : "s")"
}

struct PaywallSheet: View {
    @ObservedObject var subscriptions: SubscriptionStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPackageID: String?

    // Detail lines trimmed to one line each -- this screen no longer
    // scrolls, so every row has to earn its height.
    private let benefits: [(icon: String, title: String, detail: String)] = [
        ("bolt.fill", "12 energy, refilling 4x faster",
         "One back every 2 hours instead of every 8."),
        ("waveform", "Voice analysis", "Pace, pitch and filler words, graded."),
        ("wand.and.stars", "Build your own scenarios", "Practice the conversation you're dreading."),
        ("hand.raised.slash.fill", "No ads", "Pro never interrupts a debrief."),
    ]

    private var selectedPackage: Package? {
        subscriptions.sortedPackages.first { $0.identifier == selectedPackageID }
            ?? subscriptions.sortedPackages.first
    }

    var body: some View {
        ZStack {
            Color.poiseCanvas.ignoresSafeArea()

            // Plain VStack, not a ScrollView -- this screen should read in
            // one glance, not require scrolling to see the plan and price.
            VStack(alignment: .leading, spacing: 0) {
                header

                Spacer().frame(height: 14)

                PoiseSurfaceCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(benefits.enumerated()), id: \.element.title) { index, benefit in
                            if index > 0 {
                                PoiseDivider().padding(.leading, 60)
                            }
                            BenefitRow(icon: benefit.icon, title: benefit.title, detail: benefit.detail)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .safeAreaInset(edge: .bottom) { footer }
        .task {
            // Prefetched at launch now (see PoiseRootView) so this is
            // normally a no-op -- kept as a fallback for the rare case
            // someone opens the paywall before that prefetch has finished.
            if subscriptions.loadState == .idle {
                await subscriptions.loadOfferings()
            }
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
                PoiseIconBadge(icon: "sparkles", color: .poiseGold, size: 36)
                Spacer()
                Button("Done") { dismiss() }
                    .font(PoiseType.body(.bold))
                    .foregroundStyle(Color.poiseBlueDark)
            }

            Spacer().frame(height: 14)

            Text(subscriptions.isPro ? "You're on Poise Pro." : "Practice more, and on your own terms.")
                .font(PoiseType.title())
                .foregroundStyle(Color.poiseNavy)
                .fixedSize(horizontal: false, vertical: true)

            Spacer().frame(height: 4)

            Text(subscriptions.isPro
                 ? "Your plan is active. Manage or cancel it any time from the App Store."
                 : "More practice, spoken feedback, your own scenarios, and nothing interrupting them.")
                .font(PoiseType.subhead())
                .foregroundStyle(Color.poiseMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            // Moved here from the scrollable content above -- that spot
            // reliably failed to render ANY content placed in it (confirmed
            // with a plain solid-color rectangle, no logic involved), while
            // this footer has rendered correctly in every test. Root cause
            // of the original spot's failure is still unknown; this sidesteps
            // it rather than fixes it.
            if !subscriptions.isPro {
                Text("Choose a plan")
                    .font(PoiseType.eyebrow())
                    .tracking(PoiseType.eyebrowTracking)
                    .foregroundStyle(Color.poiseMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if subscriptions.loadState == .loaded {
                    VStack(spacing: 10) {
                        ForEach(subscriptions.sortedPackages, id: \.identifier) { package in
                            PlanRow(
                                package: package,
                                isSelected: selectedPackage?.identifier == package.identifier,
                                isEligibleForTrial: subscriptions.isEligibleForTrial(package),
                                onSelect: { selectedPackageID = package.identifier }
                            )
                        }
                    }
                } else if case .unavailable(let reason) = subscriptions.loadState {
                    // Says so plainly instead of showing an empty list above a
                    // button that cannot do anything.
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
                } else {
                    PoiseSurfaceCard {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Loading plans")
                                .font(PoiseType.subhead())
                                .foregroundStyle(Color.poiseMuted)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }

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

            // Apple requires the paywall to state the subscription's name,
            // its length and its price per period, and to link Terms and
            // Privacy. The previous line said only "Cancel any time. Renews
            // automatically until cancelled." -- true, but missing the three
            // facts Review checks for.
            Text(disclosureText)
                .font(PoiseType.caption())
                .foregroundStyle(Color.poiseMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Link("Terms of Use", destination: PoiseLegal.termsURL)
                Text("·").foregroundStyle(Color.poiseMuted)
                Link("Privacy Policy", destination: PoiseLegal.privacyURL)
            }
            .font(PoiseType.caption(.bold))
            .tint(Color.poiseBlueDark)
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

    // Trimmed from a longer sentence ("...billed through your Apple account
    // and renewing automatically until cancelled. Cancel any time in your
    // App Store settings.") -- still states what Review requires (name,
    // price, length, auto-renewal, where to cancel), just fewer words per
    // fact.
    private var disclosureText: String {
        guard !subscriptions.isPro, let package = selectedPackage else {
            return "Manage or cancel anytime in App Store settings."
        }
        let price = package.storeProduct.localizedPriceString
        let period: String
        switch package.packageType {
        case .annual: period = "year"
        case .monthly: period = "month"
        case .weekly: period = "week"
        default: period = "period"
        }
        // See trialPeriodText's header comment -- this branch is unverified.
        if let trial = trialPeriodText(for: package, eligible: subscriptions.isEligibleForTrial(package)) {
            return "Free for \(trial), then \(price)/\(period). Auto-renews. Cancel anytime in App Store settings."
        }
        return "Poise Pro is \(price)/\(period), auto-renews until cancelled. Cancel anytime in App Store settings."
    }

    private var primaryTitle: String {
        if subscriptions.isPro { return "Manage subscription" }
        guard let package = selectedPackage else { return "Start Poise Pro" }
        // See trialPeriodText's header comment -- this branch is unverified.
        if let trial = trialPeriodText(for: package, eligible: subscriptions.isEligibleForTrial(package)) {
            return "Try free for \(trial)"
        }
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
        HStack(alignment: .center, spacing: 12) {
            PoiseIconBadge(icon: icon, color: .poiseBlueDark, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(PoiseType.subhead(.bold))
                    .foregroundStyle(Color.poiseNavy)
                Text(detail)
                    .font(PoiseType.caption())
                    .foregroundStyle(Color.poiseMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

private struct PlanRow: View {
    let package: Package
    let isSelected: Bool
    let isEligibleForTrial: Bool
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

    // A trial outranks the per-month breakdown when both are available --
    // it's the more persuasive fact at the decision point, and the full
    // price is already stated elsewhere (the footer's disclosure text).
    // See trialPeriodText's header comment: unverified.
    //
    // Otherwise, only shown when StoreKit actually gives us a per-month
    // figure, rather than dividing the price ourselves -- a hand-computed
    // "$4.17 a month" goes wrong on tax-inclusive storefronts and odd
    // currencies.
    private var detail: String? {
        if let trial = trialPeriodText(for: package, eligible: isEligibleForTrial) {
            return "\(trial) free trial"
        }
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
