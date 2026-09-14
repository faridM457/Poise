import SwiftUI

// Rebuilt on the shared system (see PoiseComponents' "Shared page chrome"):
// same top bar, same section eyebrows, same white card surface, same flat
// capsule button as Learn's hero. The upgrade card deliberately echoes the
// Learn hero's construction -- pale tint, eyebrow pill, title, description,
// capsule CTA -- so the app's one promotional surface and its one primary
// action look like the same idea rather than two different designs.
struct ProfileView: View {
    let profile: UserProfile

    @ObservedObject private var store = LearnProgressStore.shared
    @State private var voicePractice = false
    @State private var videoRecording = false
    @State private var saveRecordings = false
    @State private var soundEffects = true
    @State private var showPaywall = false

    var body: some View {
        ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {
                    ProfileIdentity(profile: profile, energyText: store.energyDisplayText)

                    UpgradeCard(plan: profile.plan) { showPaywall = true }

                    PoiseSection(title: "Privacy") {
                        PrivacyCard(
                            voicePractice: $voicePractice,
                            videoRecording: $videoRecording,
                            saveRecordings: $saveRecordings
                        )
                    }

                    PoiseSection(title: "Account & settings") {
                        SettingsCard(soundEffects: $soundEffects)
                    }

                    PoiseSection(title: "Testing") {
                        DebugCard(isPremium: $store.isPremium)
                    }

                    // The tab bar is a bottom safeAreaInset (see PoiseRootView),
                    // so the scroll view already accounts for its height --
                    // this is just air under the last card.
                    Color.clear.frame(height: 16)
                }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            PoiseTopBar(streak: PoiseMockData.progress.streakDays, energyText: store.energyDisplayText)
        }
        // See ProgressDashboardView: a ZStack sibling that ignores the safe
        // area costs the ScrollView the root's bottom tab-bar inset.
        .background(Color.poiseCanvas.ignoresSafeArea())
        .sheet(isPresented: $showPaywall) {
            MockPaywallSheet()
        }
    }
}

// MARK: - Identity

// Stands in for the page title, so Profile doesn't carry both a heading and a
// name saying the same thing. The initial tile uses PoiseIconBadge's geometry
// (radius = 0.3x size) at a larger size.
private struct ProfileIdentity: View {
    let profile: UserProfile
    let energyText: String

    private let tileSize: CGFloat = 60

    var body: some View {
        HStack(spacing: 14) {
            Text(profile.initial)
                .font(PoiseType.title())
                .foregroundStyle(Color.poiseBlueDark)
                .frame(width: tileSize, height: tileSize)
                .background(Color.poiseSoftBlue)
                .clipShape(RoundedRectangle(cornerRadius: tileSize * 0.3, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(profile.name)
                    .font(PoiseType.title())
                    .foregroundStyle(Color.poiseNavy)
                Text(profile.subtitle)
                    .font(PoiseType.subhead())
                    .foregroundStyle(Color.poiseMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Upgrade

private struct UpgradeCard: View {
    let plan: String
    let onExplore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PoiseEyebrow(text: plan, color: .poiseBlueDark)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.75))
                .clipShape(Capsule())

            Spacer().frame(height: 12)

            Text("More room to practice.")
                .font(PoiseType.headline())
                .foregroundStyle(Color.poiseNavy)

            Spacer().frame(height: 5)

            Text("Unlock unlimited rehearsals and deeper insights as they become available.")
                .font(PoiseType.subhead())
                .foregroundStyle(Color.poiseMuted)
                .fixedSize(horizontal: false, vertical: true)

            Spacer().frame(height: 16)

            Button("Explore Poise Pro", action: onExplore)
                .buttonStyle(PoiseFlatButtonStyle())
                .accessibilityLabel("Explore Poise Pro")
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
                        subtitle: "Would allow microphone recording during a session.",
                        isOn: $voicePractice
                    )
                    PoiseDivider().padding(.horizontal, 16)
                    SettingsToggleRow(
                        title: "Video recording",
                        subtitle: "Post-MVP preview setting. Camera stays off.",
                        isOn: $videoRecording
                    )
                    PoiseDivider().padding(.horizontal, 16)
                    SettingsToggleRow(
                        title: "Save recordings",
                        subtitle: "Off by default. Keep recordings only when you choose.",
                        isOn: $saveRecordings
                    )
                }
            }

            FootNote("Controls change local demo state only. No recording, uploading, or account changes occur.")
        }
    }
}

private struct SettingsCard: View {
    @Binding var soundEffects: Bool

    var body: some View {
        PoiseSurfaceCard(padding: 0) {
            VStack(spacing: 0) {
                SettingsValueRow(title: "Practice language", value: "English")
                PoiseDivider().padding(.horizontal, 16)
                SettingsToggleRow(title: "Sound effects", subtitle: nil, isOn: $soundEffects)
                PoiseDivider().padding(.horizontal, 16)
                SettingsValueRow(title: "Account", value: "Demo profile")
            }
        }
    }
}

// Testing-only toggle for the mocked premium tier -- there's no real
// subscription/IAP integration yet, this just flips which energy cap
// LearnProgressStore uses (3 free / 10 premium) so both can be tested.
private struct DebugCard: View {
    @Binding var isPremium: Bool

    var body: some View {
        PoiseSurfaceCard(padding: 0) {
            SettingsToggleRow(
                title: "Premium (mock)",
                subtitle: "Raises the energy cap from 3 to 10. No real subscription is involved.",
                isOn: $isPremium
            )
        }
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

private struct MockPaywallSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let disclaimers = [
        "No purchase flow in this prototype",
        "No StoreKit or RevenueCat integration",
        "No account or payment information collected"
    ]

    var body: some View {
        ZStack {
            Color.poiseCanvas.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    PoiseIconBadge(icon: "sparkles", color: .poiseGold, size: 44)
                    Spacer()
                    Button("Done") { dismiss() }
                        .font(PoiseType.body(.bold))
                        .foregroundStyle(Color.poiseBlueDark)
                }

                Spacer().frame(height: 20)

                Text("Poise Pro preview")
                    .font(PoiseType.title())
                    .foregroundStyle(Color.poiseNavy)

                Spacer().frame(height: 6)

                Text("A future subscription could include unlimited rehearsals, advanced practice packs, and richer consent-based insights.")
                    .font(PoiseType.subhead())
                    .foregroundStyle(Color.poiseMuted)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer().frame(height: 22)

                PoiseSurfaceCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(disclaimers.enumerated()), id: \.element) { index, line in
                            if index > 0 {
                                PoiseDivider().padding(.horizontal, 16)
                            }
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Color.poiseMintDark)
                                Text(line)
                                    .font(PoiseType.subhead(.semibold))
                                    .foregroundStyle(Color.poiseNavy)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                    }
                }

                Spacer(minLength: 24)

                Button("Close") { dismiss() }
                    .buttonStyle(PoiseFlatButtonStyle(fullWidth: true))
                    .accessibilityLabel("Close Poise Pro preview")
            }
            .padding(24)
        }
    }
}
