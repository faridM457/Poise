import SwiftUI

// Real, server-generated version of LessonFlowView's step machine (briefing
// -> guide -> roleplay -> scorecard), used when a LessonNode has an
// `engineLessonId`. Talks to the local conversation-engine server via
// LiveLessonViewModel instead of PoiseMockData/MockEvaluationService.
//
// Character art: there's no real character model with per-person artwork
// yet, so MarcusAvatar is reused as a placeholder visual for whichever NPC
// the server actually generates (e.g. lesson "feedback-small-pattern"'s
// character is "Sam", not Marcus) -- the name/role text shown is the real
// one, only the avatar art is a stand-in.
struct LiveLessonFlowView: View {
    private enum Step {
        case briefing
        case guide
        case roleplay
        case scorecard
    }

    let engineLessonId: String
    let onFinish: () -> Void

    @StateObject private var viewModel: LiveLessonViewModel
    @State private var step: Step = .briefing

    init(engineLessonId: String, onFinish: @escaping () -> Void) {
        self.engineLessonId = engineLessonId
        self.onFinish = onFinish
        _viewModel = StateObject(wrappedValue: LiveLessonViewModel(lessonId: engineLessonId))
    }

    var body: some View {
        VStack(spacing: 0) {
            LessonProgressHeader(step: stepIndex, total: 4, label: stepLabel, onExit: onFinish)
            Group {
                if viewModel.isLoadingScenario {
                    LiveLoadingView(text: "Generating your scenario...")
                } else if let error = viewModel.errorMessage, viewModel.messages.isEmpty {
                    LiveErrorView(message: error) {
                        Task { await viewModel.start() }
                    }
                } else {
                    switch step {
                    case .briefing:
                        LiveBriefingView(viewModel: viewModel) { step = .guide }
                    case .guide:
                        LiveGuideView(criteria: viewModel.criteria) { step = .roleplay }
                    case .roleplay:
                        LiveRoleplayView(viewModel: viewModel) { step = .scorecard }
                    case .scorecard:
                        LiveScorecardView(viewModel: viewModel, onContinue: onFinish)
                    }
                }
            }
        }
        .background(Color.poiseBackground.ignoresSafeArea())
        .task {
            await viewModel.start()
        }
    }

    private var stepLabel: String {
        switch step {
        case .briefing: return "Briefing"
        case .guide: return "Guide"
        case .roleplay: return "Roleplay"
        case .scorecard: return "Complete"
        }
    }

    private var stepIndex: Int {
        switch step {
        case .briefing: return 1
        case .guide: return 2
        case .roleplay: return 3
        case .scorecard: return 4
        }
    }
}

private struct LiveLoadingView: View {
    let text: String

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.3)
            Text(text)
                .font(PoiseType.body(.medium))
                .foregroundStyle(Color.poiseMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LiveErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(Color.poiseGold)
            Text(message)
                .font(PoiseType.body(.medium))
                .foregroundStyle(Color.poiseNavy)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button(action: onRetry) {
                PrimaryButtonLabel("Try again")
            }
            .buttonStyle(TactileButtonStyle())
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LiveBriefingView: View {
    @ObservedObject var viewModel: LiveLessonViewModel
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionEyebrow(text: "Live scenario")
                    Text("Naming a Small Pattern")
                        .font(PoiseType.largeTitle())
                        .foregroundStyle(Color.poiseNavy)
                }

                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color(red: 0.80, green: 0.90, blue: 0.92))
                        .frame(height: 220)
                    HStack {
                        Spacer()
                        CharacterAnimationView(mood: .idleNeutral, height: 210)
                        Spacer()
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.character?.name ?? "...")
                            .font(PoiseType.caption(.heavy))
                            .foregroundStyle(Color.poiseNavy)
                        Text(viewModel.character?.role ?? "")
                            .font(PoiseType.caption(.semibold))
                            .foregroundStyle(Color.poiseMuted)
                    }
                    .padding(12)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .padding(14)
                }
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

                Text(viewModel.briefing)
                    .font(PoiseType.body())
                    .foregroundStyle(Color.poiseMuted)
                    .lineSpacing(5)

                Text("This scenario and conversation are generated fresh each time by Claude, not scripted.")
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

private struct LiveGuideView: View {
    let criteria: [String]
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
                    ForEach(Array(criteria.enumerated()), id: \.offset) { index, criterion in
                        HStack(spacing: 14) {
                            Text("\(index + 1)")
                                .font(PoiseType.caption(.heavy))
                                .foregroundStyle(Color.poiseBlueDark)
                                .frame(width: 30, height: 30)
                                .background(Color.poiseSoftBlue)
                                .clipShape(Circle())
                            Text(criterion)
                                .font(PoiseType.body(.bold))
                                .foregroundStyle(Color.poiseNavy)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(18)
                        .poiseCard(radius: 18)
                    }
                }
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

private struct LiveRoleplayView: View {
    @ObservedObject var viewModel: LiveLessonViewModel
    let onReview: () -> Void

    @State private var response = ""
    @FocusState private var isWriting: Bool
    @StateObject private var speech = SpeechRecognitionService()
    // Idle the rest of the time, Talk_Neutral only while the latest NPC
    // line is actively being revealed word-by-word below.
    @State private var characterMood: CharacterAnimationView.Mood = .idleNeutral

    // Measured directly from an extracted frame of Idle_Neutral.mp4 (frame
    // 30, via ffmpeg) -- not a guess. Face occupies roughly 27%-51% of frame
    // height (hair ~27%, chin ~51%); shoulders/desk start ~52%-63%. Anything
    // at or below this fraction of screen height is safe to cover with UI
    // chrome. Same character/framing is assumed for Talk_Neutral (mouth
    // movement only), not re-measured.
    private static let faceSafeZoneFraction: CGFloat = 0.52

    var body: some View {
        GeometryReader { geo in
            // A plain ZStack overlay, NOT .safeAreaInset -- safeAreaInset
            // actively RESERVES space by shrinking its main content's
            // available layout height to make room for the inset view. That
            // was quietly starving the video of vertical space (it was only
            // being laid out in whatever was left after reserving room for
            // the bottom panel), which is what cut off the bottom of the
            // animation. A ZStack overlay just draws on top without taking
            // space away from its siblings, so the video always gets the
            // full frame.
            ZStack(alignment: .bottom) {
                // Only the BACKGROUND goes full-bleed (edge-to-edge,
                // including under the notch/home-indicator) -- the "you're
                // in the room" treatment. The UI chrome layered on top
                // (badge, panel) deliberately does NOT ignore the safe area,
                // so it sits at standard, native-feeling margins instead of
                // crowding the physical edges -- same pattern as Photos/
                // Camera: full-bleed media, normally-inset controls.
                Group {
                    CharacterAnimationView(mood: characterMood, fillScreen: true)

                    // Scrim stays fully transparent through the measured face
                    // band, only starting to darken right at the safe boundary.
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .clear, location: Self.faceSafeZoneFraction),
                            .init(color: .black.opacity(0.42), location: Self.faceSafeZoneFraction + 0.16),
                            .init(color: .black.opacity(0.55), location: 1.0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)
                }
                .ignoresSafeArea(.container)

                VStack {
                    HStack {
                        Text("\(viewModel.character?.name ?? "NPC") · Turn \(viewModel.turnNumber) / 5")
                            .font(PoiseType.caption(.heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)
                            .background(.black.opacity(0.4))
                            .clipShape(Capsule())
                        Spacer()
                    }
                    // Safe area is respected here (not ignored), plus a
                    // small standard amount of extra breathing room below it.
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    Spacer()
                }

                // Hard cap, derived from the measured safe zone, not content
                // size -- guarantees the panel can never creep up into the
                // 0-52% band regardless of how much text it ends up holding.
                // Safe area is respected here too, so it sits above the
                // home indicator with standard clearance, not flush against it.
                bottomDialoguePanel
                    .frame(maxHeight: geo.size.height * (1 - Self.faceSafeZoneFraction), alignment: .bottom)
            }
        }
        .task {
            // The opening line's text is already fetched (from start(), back
            // on the briefing screen) -- this is what actually speaks/reveals
            // it, now that the roleplay screen is the thing on screen.
            // Idempotent: safe even if this view re-appears.
            await viewModel.presentOpeningLineIfNeeded()
        }
        .onDisappear {
            // Audio must never keep playing once this screen is gone --
            // covers leaving mid-playback (the .task cancellation above only
            // covers leaving during the pre-dialogue delay, before playback
            // ever started).
            viewModel.stopSpeaking()
        }
        .onChange(of: viewModel.ended) { _, ended in
            if ended { onReview() }
        }
    }

    // Shows only the MOST RECENT line (not a scrolling transcript) so this
    // panel's height is always just "one short message + a compact input
    // row" -- small and predictable, instead of growing with conversation
    // length and risking covering more of the scene the longer you talk.
    private var bottomDialoguePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let latest = viewModel.messages.last {
                MessageBubble(
                    message: latest,
                    animateReveal: latest.speaker != .user,
                    speechDuration: viewModel.currentSpeechDuration,
                    onRevealStart: { characterMood = .talkNeutral },
                    onRevealComplete: { characterMood = .idleNeutral }
                )
            }

            if viewModel.isSendingTurn {
                HStack(spacing: 8) {
                    ProgressView().tint(.white)
                    Text("\(viewModel.character?.name ?? "NPC") is responding...")
                        .font(PoiseType.caption(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(PoiseType.caption(.semibold))
                    .foregroundStyle(Color.red)
            }

            if let speechError = speech.errorMessage {
                Text(speechError)
                    .font(PoiseType.caption(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Type or tap the mic to speak...", text: $response, axis: .vertical)
                    .font(PoiseType.body())
                    .foregroundStyle(Color.poiseNavy)
                    .lineLimit(1...3)
                    .padding(12)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .focused($isWriting)
                    .disabled(viewModel.isSendingTurn)
                    .accessibilityLabel("Typed response")

                // Fills the text field as the user speaks, live -- never
                // sends automatically. The user reviews/edits before tapping
                // send, same non-destructive pattern as the browser mic
                // button in conversation-engine.
                Button(action: speech.toggleListening) {
                    Image(systemName: speech.isListening ? "mic.fill" : "mic")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(speech.isListening ? .white : .white.opacity(0.85))
                        .frame(width: 44, height: 44)
                        .background(speech.isListening ? Color.red.opacity(0.85) : .white.opacity(0.18))
                        .clipShape(Circle())
                }
                .disabled(viewModel.isSendingTurn)
                .accessibilityLabel(speech.isListening ? "Stop dictating" : "Speak your response")

                Button(action: sendResponse) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(sendDisabled ? .white.opacity(0.35) : Color.poiseGold)
                }
                .disabled(sendDisabled)
                .accessibilityLabel("Send response")
            }
        }
        .onChange(of: speech.transcript) { _, newValue in
            guard !newValue.isEmpty else { return }
            response = newValue
        }
        .onDisappear { speech.stopListening() }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        // Safe area (home-indicator clearance) is respected here, not
        // ignored -- this is just the small standard bit of extra breathing
        // room below that, matching the top badge's spacing.
        //
        // No local background gradient here anymore -- there used to be a
        // second, smaller darkening gradient behind just this panel, but
        // since this panel respects the safe area (by design, for proper
        // margins) while the ONE real scrim behind everything ignores it
        // (by design, to stay full-bleed), the two don't share a bottom
        // edge -- the local one stopped short of the true bottom, creating
        // a visible seam. The single full-bleed scrim in the background
        // Group above already provides enough contrast on its own.
        .padding(.bottom, 8)
    }

    private var sendDisabled: Bool {
        response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSendingTurn
    }

    private func sendResponse() {
        let trimmed = response
        response = ""
        isWriting = false
        Task { await viewModel.sendUserResponse(trimmed) }
    }
}

private struct LiveScorecardView: View {
    @ObservedObject var viewModel: LiveLessonViewModel
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                CharacterAnimationView(mood: .idleNeutral, height: 150)
                    .padding(.top, 24)

                if let feedback = viewModel.feedback {
                    VStack(spacing: 10) {
                        Text("One conversation stronger.")
                            .font(PoiseType.largeTitle())
                            .foregroundStyle(Color.poiseBlueDark)
                            .multilineTextAlignment(.center)
                    }

                    let metCount = feedback.checklist.filter(\.met).count
                    HStack(spacing: 14) {
                        ScoreTileLive(label: "Deductions", value: "\(feedback.deductionCount)", tint: .poiseGold)
                        ScoreTileLive(label: "Criteria met", value: "\(metCount) / \(feedback.checklist.count)", tint: .poiseBlueDark)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Your conversation checklist")
                            .font(PoiseType.headline())
                            .foregroundStyle(Color.poiseNavy)
                        ForEach(feedback.checklist) { item in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: item.met ? "checkmark" : "arrow.right")
                                    .font(.system(size: 16, weight: .heavy))
                                    .foregroundStyle(item.met ? Color.poiseMintDark : Color.poiseGold)
                                    .frame(width: 22)
                                Text(item.criterion)
                                    .font(PoiseType.body(.bold))
                                    .foregroundStyle(Color.poiseNavy)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 10) {
                        SectionEyebrow(text: "Feedback")
                        Text(feedback.feedbackLine)
                            .font(PoiseType.body())
                            .foregroundStyle(Color.poiseNavy)
                    }
                    .padding(18)
                    .poiseCard(fill: .poisePaleBlue, stroke: Color.poiseBlue.opacity(0.12), radius: 20)
                } else if let error = viewModel.errorMessage {
                    Text(error)
                        .font(PoiseType.body(.medium))
                        .foregroundStyle(Color.poiseNavy)
                        .multilineTextAlignment(.center)
                } else {
                    ProgressView()
                    Text("Grading your conversation...")
                        .font(PoiseType.body(.medium))
                        .foregroundStyle(Color.poiseMuted)
                }
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

private struct ScoreTileLive: View {
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
