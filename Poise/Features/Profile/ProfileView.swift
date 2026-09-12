import SwiftUI

struct ProfileView: View {
    let profile: UserProfile

    @State private var voicePractice = false
    @State private var videoRecording = false
    @State private var saveRecordings = false
    @State private var soundEffects = true
    @State private var showPaywall = false

    var body: some View {
        ZStack {
            Color.poiseBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    StatusRow(streak: PoiseMockData.progress.streakDays, xp: PoiseMockData.progress.xp, level: profile.level)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                    VStack(alignment: .leading, spacing: 8) {
                        SectionEyebrow(text: "Your space")
                        Text("Profile")
                            .font(PoiseType.largeTitle())
                            .foregroundStyle(Color.poiseNavy)
                    }

                    ProfileSummary(profile: profile)
                    ProCard { showPaywall = true }
                    PrivacyCard(voicePractice: $voicePractice, videoRecording: $videoRecording, saveRecordings: $saveRecordings)
                    SettingsCard(soundEffects: $soundEffects)
                }
                .padding(20)
            }
        }
        .sheet(isPresented: $showPaywall) {
            MockPaywallSheet()
        }
    }
}

private struct ProfileSummary: View {
    let profile: UserProfile

    var body: some View {
        HStack(spacing: 14) {
            Text(profile.initial)
                .font(PoiseType.title())
                .foregroundStyle(Color.poiseBlueDark)
                .frame(width: 64, height: 64)
                .background(Color.poisePaleBlue)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.poiseBlue.opacity(0.18), lineWidth: 1.5)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name)
                    .font(PoiseType.title())
                    .foregroundStyle(Color.poiseNavy)
                Text("Level \(profile.level) · \(profile.subtitle)")
                    .font(PoiseType.caption(.semibold))
                    .foregroundStyle(Color.poiseMuted)
            }
            Spacer()
        }
    }
}

private struct ProCard: View {
    let onExplore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Free plan".uppercased())
                .font(PoiseType.caption(.heavy))
                .foregroundStyle(Color.poiseBlueDark.opacity(0.72))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.65))
                .clipShape(Capsule())
            Text("More room to practice.")
                .font(PoiseType.title())
                .foregroundStyle(Color.poiseNavy)
            Text("Unlock every unit, unlimited rehearsals, and deeper insights as they become available.")
                .font(PoiseType.body())
                .foregroundStyle(Color.poiseMuted)
                .lineSpacing(4)
            Button(action: onExplore) {
                PrimaryButtonLabel("Explore Poise Pro")
            }
            .buttonStyle(TactileButtonStyle())
            .accessibilityLabel("Explore Poise Pro")
        }
        .padding(22)
        .poiseCard(fill: .poisePaleBlue, stroke: Color.poiseBlue.opacity(0.16), radius: 26)
    }
}

private struct PrivacyCard: View {
    @Binding var voicePractice: Bool
    @Binding var videoRecording: Bool
    @Binding var saveRecordings: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Privacy, by choice")
                .font(PoiseType.headline())
                .foregroundStyle(Color.poiseNavy)
            Text("Voice would be used to transcribe responses and provide feedback. Video analysis is planned for later. Recording is optional, and saving recordings is off by default.")
                .font(PoiseType.body())
                .foregroundStyle(Color.poiseMuted)
                .lineSpacing(4)

            PrivacyToggle(title: "Enable voice practice", subtitle: "Would allow microphone recording during a real session.", isOn: $voicePractice)
            Divider()
            PrivacyToggle(title: "Enable video recording", subtitle: "Post-MVP preview setting. Camera stays off.", isOn: $videoRecording)
            Divider()
            PrivacyToggle(title: "Save recordings", subtitle: "Off by default. Keep recordings only when you choose.", isOn: $saveRecordings)

            Text("Mockup: controls change local demo state only. No recording, uploading, or account changes occur.")
                .font(PoiseType.caption(.semibold))
                .foregroundStyle(Color.poiseMuted)
                .padding(.top, 2)
        }
        .padding(20)
        .poiseCard()
    }
}

private struct PrivacyToggle: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(PoiseType.body(.bold))
                    .foregroundStyle(Color.poiseNavy)
                Text(subtitle)
                    .font(PoiseType.caption(.semibold))
                    .foregroundStyle(Color.poiseMuted)
            }
        }
        .toggleStyle(SwitchToggleStyle(tint: .poiseMintDark))
        .accessibilityLabel(title)
    }
}

private struct SettingsCard: View {
    @Binding var soundEffects: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Account & settings")
                .font(PoiseType.headline())
                .foregroundStyle(Color.poiseNavy)
                .padding(.bottom, 16)

            SettingsRow(title: "Practice language", value: "English")
            Divider().padding(.vertical, 12)
            Toggle(isOn: $soundEffects) {
                Text("Sound effects")
                    .font(PoiseType.body(.bold))
                    .foregroundStyle(Color.poiseNavy)
            }
            .toggleStyle(SwitchToggleStyle(tint: .poiseMintDark))
            .accessibilityLabel("Sound effects")
            Divider().padding(.vertical, 12)
            SettingsRow(title: "Account", value: "Demo profile")
        }
        .padding(20)
        .poiseCard()
    }
}

private struct SettingsRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(PoiseType.body(.bold))
                .foregroundStyle(Color.poiseNavy)
            Spacer()
            Text(value)
                .font(PoiseType.body(.bold))
                .foregroundStyle(Color.poiseMuted)
        }
    }
}

private struct MockPaywallSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(Color.poiseGold)
                Spacer()
                Button("Done") { dismiss() }
                    .font(PoiseType.body(.heavy))
                    .foregroundStyle(Color.poiseBlueDark)
            }
            Text("Poise Pro preview")
                .font(PoiseType.largeTitle())
                .foregroundStyle(Color.poiseNavy)
            Text("A future subscription could include unlimited rehearsals, advanced practice packs, and richer consent-based insights.")
                .font(PoiseType.body())
                .foregroundStyle(Color.poiseMuted)
                .lineSpacing(5)
            VStack(alignment: .leading, spacing: 12) {
                Label("No purchase flow in this prototype", systemImage: "checkmark.circle.fill")
                Label("No StoreKit or RevenueCat integration", systemImage: "checkmark.circle.fill")
                Label("No account or payment information collected", systemImage: "checkmark.circle.fill")
            }
            .font(PoiseType.body(.bold))
            .foregroundStyle(Color.poiseNavy)
            Spacer()
            Button("Close") { dismiss() }
                .buttonStyle(TactileButtonStyle())
                .accessibilityLabel("Close Poise Pro preview")
        }
        .padding(24)
        .background(Color.poiseBackground)
    }
}
