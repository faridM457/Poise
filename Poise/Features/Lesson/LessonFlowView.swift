import SwiftUI

struct LessonFlowView: View {
    enum Step: Int, CaseIterable {
        case briefing = 1
        case guide
        case roleplay
        case scorecard

        var label: String {
            switch self {
            case .briefing: return "Briefing"
            case .guide: return "Guide"
            case .roleplay: return "Roleplay"
            case .scorecard: return "Complete"
            }
        }
    }

    let lesson: LessonNode
    let onFinish: () -> Void

    @State private var step: Step = .briefing
    @State private var messages: [ConversationMessage] = [PoiseMockData.openingMessage]

    private let evaluator = MockEvaluationService()

    var body: some View {
        VStack(spacing: 0) {
            LessonProgressHeader(step: visibleStepIndex, total: visibleStepTotal, label: step.label, onExit: onFinish)
            Group {
                switch step {
                case .briefing:
                    BriefingView {
                        step = lesson.skipGuide ? .roleplay : .guide
                    }
                case .guide:
                    GuideView {
                        step = .roleplay
                    }
                case .roleplay:
                    RoleplayView(lesson: lesson, messages: $messages) {
                        step = .scorecard
                    }
                case .scorecard:
                    ScorecardView(score: evaluator.evaluate(messages: messages), onContinue: onFinish)
                }
            }
        }
        .background(Color.poiseBackground.ignoresSafeArea())
    }

    private var visibleStepTotal: Int { lesson.skipGuide ? 3 : 4 }

    private var visibleStepIndex: Int {
        if lesson.skipGuide {
            switch step {
            case .briefing: return 1
            case .guide: return 1
            case .roleplay: return 2
            case .scorecard: return 3
            }
        }
        return step.rawValue
    }
}

private struct BriefingView: View {
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionEyebrow(text: "Managing down · Lesson 3")
                    Text("Mediating a conflict")
                        .font(PoiseType.largeTitle())
                        .foregroundStyle(Color.poiseNavy)
                }

                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color(red: 0.80, green: 0.90, blue: 0.92))
                        .frame(height: 220)
                    HStack {
                        Spacer()
                        MarcusAvatar(size: 190)
                            .offset(y: 38)
                        Spacer()
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Marcus")
                            .font(PoiseType.caption(.heavy))
                            .foregroundStyle(Color.poiseNavy)
                        Text("Your direct report")
                            .font(PoiseType.caption(.semibold))
                            .foregroundStyle(Color.poiseMuted)
                    }
                    .padding(12)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .padding(14)
                }
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

                Text("Marcus and Priya co-own the Miller account. The delivery was late. Marcus says Priya sent her section late; Priya says Marcus never confirmed receipt. You're meeting to help them work it out.")
                    .font(PoiseType.body())
                    .foregroundStyle(Color.poiseMuted)
                    .lineSpacing(5)

                VStack(alignment: .leading, spacing: 10) {
                    SectionEyebrow(text: "The data point")
                    Text("2 days late · client noticed · both dispute responsibility")
                        .font(PoiseType.body(.medium))
                        .foregroundStyle(Color.poiseNavy)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.poisePaleBlue)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Text("Character artwork placeholder. Conversations in this prototype are simulated.")
                    .font(PoiseType.caption(.semibold))
                    .foregroundStyle(Color.poiseMuted)
            }
            .padding(24)
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: onContinue) {
                PrimaryButtonLabel("See your guide")
            }
            .buttonStyle(TactileButtonStyle())
            .padding(20)
            .background(.white)
            .accessibilityLabel("See your guide")
        }
    }
}

private struct GuideView: View {
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionEyebrow(text: "Your conversation compass")
                    Text("Keep these in mind.")
                        .font(PoiseType.largeTitle())
                        .foregroundStyle(Color.poiseNavy)
                    Text("Use your own words. These are goals, not a script.")
                        .font(PoiseType.body())
                        .foregroundStyle(Color.poiseMuted)
                }

                VStack(spacing: 14) {
                    ForEach(PoiseMockData.criteria) { criterion in
                        HStack(spacing: 14) {
                            Text("\(criterion.id)")
                                .font(PoiseType.caption(.heavy))
                                .foregroundStyle(Color.poiseBlueDark)
                                .frame(width: 30, height: 30)
                                .background(Color.poiseSoftBlue)
                                .clipShape(Circle())
                            Text(criterion.text)
                                .font(PoiseType.body(.bold))
                                .foregroundStyle(Color.poiseNavy)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(18)
                        .poiseCard(radius: 18)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("There's no perfect opening.")
                        .font(PoiseType.caption(.heavy))
                        .foregroundStyle(Color.poiseBlueDark.opacity(0.75))
                    Text("Speak naturally. You can cover the goals in any order.")
                        .font(PoiseType.body(.medium))
                        .foregroundStyle(Color.poiseNavy)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.poisePaleBlue)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Text("A hint becomes available after a 5-second pause. Using it won't lower your score.")
                    .font(PoiseType.caption(.semibold))
                    .foregroundStyle(Color.poiseMuted)
            }
            .padding(24)
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: onContinue) {
                PrimaryButtonLabel("Let's practice")
            }
            .buttonStyle(TactileButtonStyle())
            .padding(20)
            .background(.white)
            .accessibilityLabel("Start roleplay practice")
        }
    }
}

private struct RoleplayView: View {
    let lesson: LessonNode
    @Binding var messages: [ConversationMessage]
    let onReview: () -> Void

    @State private var response = ""
    @State private var replyIndex = 0
    @State private var showHint = false
    @FocusState private var isWriting: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 18) {
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(Color(red: 0.80, green: 0.90, blue: 0.92))
                            .frame(height: 230)
                        HStack {
                            Spacer()
                            MarcusAvatar(size: 210)
                                .offset(y: 34)
                            Spacer()
                        }
                        Text("Marcus · Turn \(min(replyIndex + 1, 8)) / 8")
                            .font(PoiseType.caption(.heavy))
                            .foregroundStyle(Color.poiseNavy)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)
                            .background(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .padding(14)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                    VStack(spacing: 12) {
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Your turn")
                                .font(PoiseType.headline())
                                .foregroundStyle(Color.poiseNavy)
                            Spacer()
                            Text("Scripted demo")
                                .font(PoiseType.caption(.semibold))
                                .foregroundStyle(Color.poiseMuted)
                        }

                        if showHint, lesson.hintsEnabled {
                            HStack(spacing: 8) {
                                Image(systemName: "lightbulb.fill")
                                    .foregroundStyle(Color.poiseGold)
                                Text("Try starting with what each person experienced before choosing a fix.")
                                    .font(PoiseType.caption(.bold))
                                    .foregroundStyle(Color.poiseNavy)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.poiseGold.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        } else if lesson.hintsEnabled {
                            HStack(spacing: 8) {
                                Image(systemName: "sun.max.fill")
                                    .foregroundStyle(Color.poiseGold)
                                Text("Need a nudge?")
                                    .font(PoiseType.caption(.bold))
                                    .foregroundStyle(Color.poiseNavy.opacity(0.75))
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.poiseGold.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }

                        TextEditor(text: $response)
                            .font(PoiseType.body())
                            .foregroundStyle(Color.poiseNavy)
                            .frame(minHeight: 104)
                            .padding(10)
                            .background(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.poiseBorder, lineWidth: 1.5)
                            )
                            .focused($isWriting)
                            .overlay(alignment: .topLeading) {
                                if response.isEmpty {
                                    Text("Type what you would say...")
                                        .font(PoiseType.body())
                                        .foregroundStyle(Color.poiseMuted)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 18)
                                        .allowsHitTesting(false)
                                }
                            }
                            .accessibilityLabel("Typed response")

                        HStack(spacing: 10) {
                            Button {
                                showHint = true
                            } label: {
                                Image(systemName: "mic.slash.fill")
                                    .font(.system(size: 20, weight: .bold))
                                    .frame(width: 54, height: 54)
                            }
                            .buttonStyle(TactileButtonStyle(fill: .poiseBlue, lowerEdge: .poiseBlueDark))
                            .accessibilityLabel("Voice practice simulated")

                            Button(action: sendResponse) {
                                PrimaryButtonLabel("Send response")
                            }
                            .buttonStyle(TactileButtonStyle(disabled: response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                            .disabled(response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityLabel("Send response")
                        }

                        Text("Voice demo only. No microphone or camera is accessed.")
                            .font(PoiseType.caption(.semibold))
                            .foregroundStyle(Color.poiseMuted)

                        Button(action: onReview) {
                            PrimaryButtonLabel("End & review")
                        }
                        .buttonStyle(SecondaryPoiseButtonStyle())
                        .accessibilityLabel("End and review")
                    }
                    .id("composer")
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 4) }
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last?.id {
                    withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
        .task(id: response + "\(messages.count)") {
            showHint = false
            guard lesson.hintsEnabled else { return }
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                showHint = true
            }
        }
    }

    private func sendResponse() {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages.append(ConversationMessage(speaker: .user, text: trimmed))
        response = ""
        isWriting = false

        if replyIndex < PoiseMockData.scriptedReplies.count {
            let reply = PoiseMockData.scriptedReplies[replyIndex]
            replyIndex += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                messages.append(ConversationMessage(speaker: .marcus, text: reply.text))
            }
        }
    }
}

private struct MessageBubble: View {
    let message: ConversationMessage

    var body: some View {
        HStack {
            if message.speaker == .user { Spacer(minLength: 34) }
            Text(message.text)
                .font(PoiseType.body(.bold))
                .foregroundStyle(message.speaker == .user ? Color.white : Color.poiseNavy)
                .padding(18)
                .background(message.speaker == .user ? Color.poiseBlue : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(message.speaker == .user ? Color.poiseBlueDark.opacity(0.2) : Color.poiseBorder, lineWidth: 1.5)
                )
            if message.speaker == .marcus { Spacer(minLength: 34) }
        }
        .accessibilityLabel(message.speaker == .user ? "Your message" : "Marcus says")
    }
}

private struct ScorecardView: View {
    let score: ScoreResult
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                MarcusAvatar(size: 132)
                    .padding(.top, 24)

                VStack(spacing: 10) {
                    Text("One conversation stronger.")
                        .font(PoiseType.largeTitle())
                        .foregroundStyle(Color.poiseBlueDark)
                        .multilineTextAlignment(.center)
                    Text("Small steps today.\nMore prepared tomorrow.")
                        .font(PoiseType.body())
                        .foregroundStyle(Color.poiseMuted)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 14) {
                    ScoreTile(label: "Practice XP", value: "+\(score.xpEarned)", tint: .poiseGold)
                    ScoreTile(label: "Criteria met · sample", value: "\(score.criteriaMet) / \(score.totalCriteria)", tint: .poiseBlueDark)
                }

                VStack(alignment: .leading, spacing: 16) {
                    Text("Your conversation checklist")
                        .font(PoiseType.headline())
                        .foregroundStyle(Color.poiseNavy)
                    ForEach(score.checklist) { item in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: item.state == .met ? "checkmark" : "arrow.right")
                                .font(.system(size: 16, weight: .heavy))
                                .foregroundStyle(item.state == .met ? Color.poiseMintDark : Color.poiseGold)
                                .frame(width: 22)
                            Text(item.title)
                                .font(PoiseType.body(.bold))
                                .foregroundStyle(Color.poiseNavy)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 10) {
                    SectionEyebrow(text: "Feedback")
                    Text(score.feedback)
                        .font(PoiseType.body())
                        .foregroundStyle(Color.poiseNavy)
                    Divider()
                    Text("Delivery insights")
                        .font(PoiseType.headline())
                        .foregroundStyle(Color.poiseNavy)
                    Text("Voice and video analysis are future features. This prototype does not record or analyze delivery.")
                        .font(PoiseType.caption(.semibold))
                        .foregroundStyle(Color.poiseMuted)
                }
                .padding(18)
                .poiseCard(fill: .poisePaleBlue, stroke: Color.poiseBlue.opacity(0.12), radius: 20)
            }
            .padding(24)
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: onContinue) {
                PrimaryButtonLabel("Continue")
            }
            .buttonStyle(TactileButtonStyle())
            .padding(20)
            .background(.white)
            .accessibilityLabel("Continue to Learn")
        }
    }
}

private struct ScoreTile: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(spacing: 12) {
            Text(label.uppercased())
                .font(PoiseType.caption(.heavy))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, minHeight: 104)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(tint.opacity(0.25), lineWidth: 1.5)
        )
    }
}
