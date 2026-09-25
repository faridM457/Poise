import SwiftUI

struct CustomScenarioPracticeFlowView: View {
    private enum Step: Int {
        case briefing
        case guide
        case roleplay
        case scorecard

        var title: String {
            switch self {
            case .briefing: "Briefing"
            case .guide: "Guide"
            case .roleplay: "Roleplay"
            case .scorecard: "Complete"
            }
        }
    }

    let scenario: CustomScenario
    let onFinish: () -> Void

    @State private var step: Step = .briefing
    @State private var messages: [ConversationMessage] = []
    @State private var response = ""
    @State private var turn = 0
    @State private var isResponding = false
    @FocusState private var composerIsFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header

            switch step {
            case .briefing:
                briefing
            case .guide:
                guide
            case .roleplay:
                roleplay
            case .scorecard:
                scorecard
            }
        }
        .background(Color.poiseCanvas.ignoresSafeArea())
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onFinish) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 38, height: 38)
                    .background(Color.white)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Exit practice")

            VStack(alignment: .leading, spacing: 5) {
                Text(step.title)
                    .font(PoiseType.caption(.bold))
                    .foregroundStyle(Color.poiseMuted)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.poiseTrack)
                        Capsule()
                            .fill(Color.poiseBlueDark)
                            .frame(width: geometry.size.width * CGFloat(step.rawValue + 1) / 4)
                    }
                }
                .frame(height: 7)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.poiseCanvas)
        .overlay(alignment: .bottom) { PoiseDivider() }
    }

    private var briefing: some View {
        FlowPage {
            PoiseIconBadge(icon: "briefcase.fill", color: .poiseBlueDark, size: 64)
            Text(scenario.title)
                .font(PoiseType.largeTitle())
                .foregroundStyle(Color.poiseNavy)
                .multilineTextAlignment(.center)
            Text(scenario.situation)
                .font(PoiseType.body())
                .foregroundStyle(Color.poiseMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            PoiseSurfaceCard {
                VStack(spacing: 14) {
                    roleRow(label: "You", value: scenario.userRole, icon: "person.fill")
                    PoiseDivider()
                    roleRow(label: "Them", value: scenario.counterpartRole, icon: "person.2.fill")
                }
            }

            Button("Continue") { step = .guide }
                .buttonStyle(PoiseFlatButtonStyle(fullWidth: true))
        }
    }

    private var guide: some View {
        FlowPage {
            PoiseIconBadge(icon: "target", color: .poiseMintDark, size: 64)
            Text("Your goals")
                .font(PoiseType.largeTitle())
                .foregroundStyle(Color.poiseNavy)
            Text("Keep these three outcomes in mind during the conversation.")
                .font(PoiseType.body())
                .foregroundStyle(Color.poiseMuted)
                .multilineTextAlignment(.center)

            PoiseSurfaceCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(scenario.goals.enumerated()), id: \.offset) { index, goal in
                        if index > 0 { PoiseDivider().padding(.leading, 64) }
                        HStack(spacing: 13) {
                            PoiseIconBadge(icon: "checkmark", color: .poiseMintDark, size: 38)
                            Text(goal)
                                .font(PoiseType.body(.bold))
                                .foregroundStyle(Color.poiseNavy)
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                    }
                }
            }

            Button("Start Roleplay") {
                messages = [ConversationMessage(speaker: .npc, text: scenario.openingLine, characterName: scenario.counterpartRole)]
                step = .roleplay
            }
            .buttonStyle(PoiseFlatButtonStyle(fullWidth: true))
        }
    }

    private var roleplay: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        Text("Practice conversation")
                            .font(PoiseType.caption(.bold))
                            .foregroundStyle(Color.poiseMuted)
                            .padding(.vertical, 4)

                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }

                        if isResponding {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("\(scenario.counterpartRole) is responding…")
                                    .font(PoiseType.subhead())
                                    .foregroundStyle(Color.poiseMuted)
                                Spacer()
                            }
                            .padding(14)
                        }
                    }
                    .padding(20)
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Type your response", text: $response, axis: .vertical)
                    .font(PoiseType.body())
                    .lineLimit(1...4)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.poiseBorder, lineWidth: 1.5))
                    .focused($composerIsFocused)
                    .accessibilityLabel("Your response")

                Button(action: sendResponse) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 46, height: 46)
                        .background(Color.poiseBlueDark)
                        .clipShape(Circle())
                }
                .disabled(response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isResponding)
                .opacity(response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                .accessibilityLabel("Send response")
            }
            .padding(14)
            .background(Color.poiseCanvas)
            .overlay(alignment: .top) { PoiseDivider() }
        }
    }

    private var scorecard: some View {
        FlowPage {
            PoiseIconBadge(icon: "checkmark.seal.fill", color: .poiseMintDark, size: 68)
            Text("Practice complete")
                .font(PoiseType.largeTitle())
                .foregroundStyle(Color.poiseNavy)
            Text("You completed all three parts of this guided practice.")
                .font(PoiseType.body())
                .foregroundStyle(Color.poiseMuted)
                .multilineTextAlignment(.center)

            PoiseSurfaceCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(scenario.goals.enumerated()), id: \.offset) { index, goal in
                        if index > 0 { PoiseDivider().padding(.leading, 64) }
                        HStack(spacing: 13) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 25, weight: .semibold))
                                .foregroundStyle(Color.poiseMintDark)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(goal)
                                    .font(PoiseType.body(.bold))
                                    .foregroundStyle(Color.poiseNavy)
                                Text("Practiced")
                                    .font(PoiseType.caption())
                                    .foregroundStyle(Color.poiseMuted)
                            }
                            Spacer()
                        }
                        .padding(14)
                    }
                }
            }

            Text("This MVP scorecard records completion of the guided goals; it does not assess the quality of your words.")
                .font(PoiseType.caption())
                .foregroundStyle(Color.poiseMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button("Continue", action: onFinish)
                .buttonStyle(PoiseFlatButtonStyle(fullWidth: true))
        }
    }

    private func roleRow(label: String, value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            PoiseIconBadge(icon: icon, color: .poiseBlueDark, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(PoiseType.caption(.bold))
                    .foregroundStyle(Color.poiseMuted)
                Text(value)
                    .font(PoiseType.body(.bold))
                    .foregroundStyle(Color.poiseNavy)
            }
            Spacer()
        }
    }

    private func sendResponse() {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isResponding else { return }
        response = ""
        composerIsFocused = false
        messages.append(ConversationMessage(speaker: .user, text: trimmed))
        isResponding = true

        Task {
            try? await Task.sleep(for: .milliseconds(550))
            let replyIndex = min(turn, scenario.counterpartReplies.count - 1)
            messages.append(
                ConversationMessage(
                    speaker: .npc,
                    text: scenario.counterpartReplies[replyIndex],
                    characterName: scenario.counterpartRole
                )
            )
            turn += 1
            isResponding = false
            if turn >= scenario.counterpartReplies.count {
                try? await Task.sleep(for: .milliseconds(450))
                step = .scorecard
            }
        }
    }
}

private struct FlowPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                content
            }
            .padding(20)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
    }
}
