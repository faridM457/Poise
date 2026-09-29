import PoiseVoiceAnalysis
import SwiftUI
import os

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
    // Traces the ad lifecycle around a lesson's completion -- see
    // AdsManager's own logger for why this is os.Logger, not print().
    fileprivate static let adsLogger = Logger(subsystem: "com.sapersolutions.poise", category: "Ads")

    private enum Step {
        case briefing
        case guide
        case roleplay
        case scorecard
    }

    let engineLessonId: String
    let title: String
    // A checkpoint is a test, so it must not open with a screen listing the
    // exact criteria it will be graded against -- which is what this flow did
    // until recently. It still gets a guide step, but one that names the
    // dimensions (PoiseSkill) rather than the answers.
    let isCheckpoint: Bool
    // Bool is whether the lesson was actually completed (reached the
    // scorecard and tapped Continue) vs. exited early via the header's close
    // button.
    let onFinish: (Bool) -> Void

    @StateObject private var viewModel: LiveLessonViewModel
    @State private var step: Step = .briefing
    @State private var showOutOfEnergy = false
    // Lifted out of LiveRoleplayView so the character layer below can be
    // mounted once for the whole flow. Idle except while an NPC line is
    // actively being revealed word-by-word.
    @State private var characterMood: CharacterAnimationView.Mood = .idleNeutral
    // Whether this run actually cost anything -- replays and runs started at
    // zero are free, and the scorecard must not claim otherwise.

    init(engineLessonId: String, title: String, isCheckpoint: Bool, onFinish: @escaping (Bool) -> Void) {
        self.engineLessonId = engineLessonId
        self.title = title
        self.isCheckpoint = isCheckpoint
        self.onFinish = onFinish
        _viewModel = StateObject(wrappedValue: LiveLessonViewModel(lessonId: engineLessonId))
    }

    // For a scenario generated from the user's own prompt (Poise Pro's
    // custom-scenario builder, see CustomScenarioFlowView) -- the lesson and
    // its first scenario already exist by the time this view is reached, so
    // this skips straight to LiveLessonViewModel's custom-lesson init rather
    // than a by-id lookup. Never a checkpoint: checkpoints are curriculum
    // structure, and a custom scenario has none.
    init(customLesson: EngineLessonSummary, scenario: EngineScenario, onFinish: @escaping (Bool) -> Void) {
        self.engineLessonId = customLesson.id
        self.title = customLesson.title
        self.isCheckpoint = false
        self.onFinish = onFinish
        _viewModel = StateObject(wrappedValue: LiveLessonViewModel(customLesson: customLesson, scenario: scenario))
    }

    var body: some View {
        ZStack {
            // Mounted once for the life of the flow rather than inside the
            // roleplay step. The briefing and guide draw an opaque background
            // over it, so it is hidden but still composited -- which means the
            // AVPlayerLayer is created and drawable within the first moments
            // of the flow, long before the roleplay screen uncovers it.
            //
            // This is what removed the start-of-roleplay artefacts. Creating
            // the layer at the moment that screen appeared left ~430ms with
            // nothing to draw, and every attempt to paper over that window --
            // a blank, then a black layer raised too early, then a poster
            // still whose colour could not be matched to the video pipeline --
            // was treating the symptom. With the layer already playing, there
            // is no window to cover.
            // Which of the app's three character models this renders as
            // isn't known until viewModel.character resolves (after
            // start() below) -- until then this defaults to .char1, but
            // that's invisible either way, since `content` (the loading
            // view, then briefing/guide) draws opaquely over this layer
            // the whole time. By the moment the roleplay step actually
            // uncovers it, character has long since resolved and the
            // preload below has had the whole briefing+guide screens to
            // warm the *correct* clip, not just char1's.
            CharacterAnimationView(mood: characterMood, characterSet: viewModel.character?.appearance ?? .char1, fillScreen: true)
                .ignoresSafeArea()

            content
        }
        .task {
            await viewModel.start()
            // Warm the clip assets as early as possible now that the
            // character (and therefore which model to warm) is known; the
            // view above turns that into an already-decoding layer.
            CharacterClipPreloader.preload([.idleNeutral, .talkNeutral], for: viewModel.character?.appearance ?? .char1)
        }
        // Fires when the WHOLE flow closes, on any step -- broader than
        // LiveRoleplayView's own stopSpeaking() (roleplay step only). Cancels
        // any voice-analysis assembly still in flight so it can't finish and
        // populate voicePayload after the user has already left.
        .onDisappear { viewModel.abandonVoiceSession() }
    }

    private var content: some View {
        VStack(spacing: 0) {
            LessonProgressHeader(step: stepIndex, total: stepTotal, label: stepLabel, onExit: { onFinish(false) })
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
                        LiveBriefingView(viewModel: viewModel, title: title, isCheckpoint: isCheckpoint) {
                            step = .guide
                        }
                    case .guide:
                        if isCheckpoint {
                            LiveCheckpointGuideView { startRoleplay() }
                        } else {
                            LiveGuideView(criteria: viewModel.criteria) {
                                startRoleplay()
                            }
                        }
                    case .roleplay:
                        LiveRoleplayView(viewModel: viewModel, characterMood: $characterMood) {
                            step = .scorecard
                        }
                    case .scorecard:
                        LiveScorecardView(viewModel: viewModel, isCheckpoint: isCheckpoint, onContinue: recordAndFinish)
                            .task {
                                // Preload now so the interstitial (if this
                                // user is free-tier) is already sitting in
                                // memory by the time they tap Continue.
                                Self.adsLogger.notice("scorecard reached, isPro=\(SubscriptionStore.shared.isPro), debugSkipRoleplay=\(LearnProgressStore.shared.debugSkipRoleplay)")
                                if !SubscriptionStore.shared.isPro {
                                    AdsManager.shared.preloadInterstitial()
                                }
                            }
                    }
                }
            }
        }
        // Opaque everywhere except roleplay, which is the one step meant to
        // show the character behind its overlays.
        .background(
            (step == .roleplay ? Color.clear : Color.poiseCanvas).ignoresSafeArea()
        )
        .overlay {
            if showOutOfEnergy {
                PoiseModal(
                    icon: "bolt.fill",
                    iconColor: .poiseAmber,
                    title: "Not enough energy",
                    message: "Starting a conversation costs 1 energy, and you have none left.",
                    primaryTitle: "Got it",
                    onPrimary: { withAnimation(.snappy(duration: 0.22)) { showOutOfEnergy = false } }
                ) {
                    // The countdown ticks inside the modal rather than being
                    // baked into the message: a refusal that also says when it
                    // lifts is the difference between a rule and a dead end.
                    if LearnProgressStore.shared.secondsUntilNextEnergy() != nil {
                        Spacer().frame(height: 16)
                        EnergyCountdown()
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.poiseCanvas)
                            .clipShape(Capsule())
                    }
                }
            }
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

    // Both paths have four steps again: the checkpoint no longer skips the
    // guide, it gets a different one.
    // Energy is charged when the conversation STARTS, not when it finishes.
    // It stands in for the tokens a generated conversation costs, and those
    // are spent the moment the roleplay runs -- abandoning it halfway doesn't
    // give them back. Exiting during the roleplay therefore costs energy but
    // records no progress, which is the honest outcome.
    // The session is recorded here rather than in LearnView's completion
    // callback because this is the only place the graded feedback exists. A
    // record carries the three skill levels, so the Progress page's checkpoint
    // results and the skill badges are reading what the engine actually said
    // about this conversation, not a count inferred afterwards.
    private func recordAndFinish() {
        if let feedback = viewModel.feedback {
            LearnProgressStore.shared.recordCompletion(
                lessonID: engineLessonId,
                skillLevels: feedback.skillLevels,
                criteriaMet: feedback.checklist.filter(\.met).count,
                criteriaTotal: feedback.checklist.count
            )
        }
        // Free-tier only. If no ad is ready (still loading, failed, or
        // unconfigured), the completion fires immediately -- see
        // AdsManager.presentInterstitial.
        guard !SubscriptionStore.shared.isPro else {
            Self.adsLogger.notice("Continue tapped, isPro=true -- no ad attempted")
            onFinish(true)
            return
        }
        Self.adsLogger.notice("Continue tapped, isPro=false -- attempting to present")
        AdsManager.shared.presentInterstitial { [onFinish] in
            onFinish(true)
        }
    }

    private func startRoleplay() {
        // Hard gate. Energy stands in for the tokens a generated conversation
        // burns, so at zero there is nothing to spend and the run cannot be
        // allowed to happen. Reading the briefing and the guide stays free --
        // only starting the conversation costs.
        guard LearnProgressStore.shared.wouldSpendEnergy else {
            withAnimation(.snappy(duration: 0.22)) { showOutOfEnergy = true }
            return
        }
        LearnProgressStore.shared.spendEnergy()

        // Energy is spent either way -- the skip stands in for the
        // conversation, not for paying for it, so the cost model stays honest.
        if LearnProgressStore.shared.debugSkipRoleplay {
            viewModel.skipToResults()
            step = .scorecard
            return
        }

        step = .roleplay
    }

    private var stepTotal: Int { 4 }

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
            .buttonStyle(PoiseFlatButtonStyle())
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LiveBriefingView: View {
    @ObservedObject var viewModel: LiveLessonViewModel
    let title: String
    let isCheckpoint: Bool
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    PoiseEyebrow(text: "Live scenario")
                    Text(title)
                        .font(PoiseType.title())
                        .foregroundStyle(Color.poiseNavy)
                }

                ZStack(alignment: .bottomLeading) {
                    // The landscape still, filling the panel edge to edge --
                    // not the looping clip. Those are all 1178x2556 portrait,
                    // so at 210pt tall the animation rendered as a ~97pt
                    // vertical strip floating in the middle of a ~354pt-wide
                    // panel, with flat teal either side.
                    //
                    // GeometryReader + an explicit .frame(width:height:) on
                    // the image itself, not .frame(maxWidth: .infinity) --
                    // .scaledToFill() combined with an *unbounded* maxWidth
                    // lets the image propose an oversized ideal width when
                    // its own aspect ratio is far from this panel's (~1.6:1
                    // at typical device widths), and that oversized
                    // proposal leaks up through the ZStack into the whole
                    // screen's layout, clipping the header on both edges.
                    // CharFullFrame (1.684:1) happened to be close enough to
                    // never expose this; Char3FullFrame's real 2:1 source
                    // render did. Binding both dimensions explicitly avoids
                    // it regardless of the source image's own aspect ratio.
                    GeometryReader { geo in
                        Image(viewModel.character?.appearance.stillImageName ?? "CharFullFrame")
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: 220)
                            .clipped()
                    }
                    .frame(height: 220)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.character?.name ?? "...")
                            .font(PoiseType.caption(.heavy))
                            .foregroundStyle(Color.poiseNavy)
                        Text(viewModel.character?.shortRole ?? "")
                            .font(PoiseType.caption(.semibold))
                            .foregroundStyle(Color.poiseMuted)
                    }
                    .padding(12)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .padding(14)
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                Text(viewModel.briefing)
                    .font(PoiseType.body())
                    .foregroundStyle(Color.poiseMuted)
                    .lineSpacing(5)
            }
            .padding(.horizontal, PoiseLayout.readingMargin)
            .padding(.vertical, 24)
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: onContinue) {
                PrimaryButtonLabel(isCheckpoint ? "What you're scored on" : "See your guide")
            }
            .buttonStyle(PoiseFlatButtonStyle(fullWidth: true))
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Color.poiseCanvas)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.poiseBorder.opacity(0.8)).frame(height: 1)
            }
            .accessibilityLabel(isCheckpoint ? "What you're scored on" : "See your guide")
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
                    PoiseEyebrow(text: "Your conversation compass")
                    Text("Keep these in mind.")
                        .font(PoiseType.title())
                        .foregroundStyle(Color.poiseNavy)
                    Text("Use your own words. These are goals, not a script.")
                        .font(PoiseType.body())
                        .foregroundStyle(Color.poiseMuted)
                }

                // One card with hairline-separated rows and 38pt rounded-square
                // markers -- the same object as the unit sheet's lesson list,
                // rather than three floating cards with circular badges.
                PoiseSurfaceCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(criteria.enumerated()), id: \.offset) { index, criterion in
                            if index > 0 {
                                PoiseDivider().padding(.leading, 68)
                            }
                            // .center, not .top -- with a fixed 38pt badge,
                            // .top left a one-line criterion sitting at the
                            // top of the row (since the badge, not the text,
                            // was setting the row's height) instead of
                            // centered against the badge. Two-line criteria
                            // are close enough to 38pt tall that this makes
                            // no visible difference for them.
                            HStack(alignment: .center, spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 38 * 0.3, style: .continuous)
                                        .fill(Color.poiseBlue.opacity(0.13))
                                    Text("\(index + 1)")
                                        .font(PoiseType.body(.bold))
                                        .foregroundStyle(Color.poiseBlueDark)
                                }
                                .frame(width: 38, height: 38)

                                Text(criterion)
                                    .font(PoiseType.body())
                                    .foregroundStyle(Color.poiseNavy)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                    }
                }
            }
            .padding(.horizontal, PoiseLayout.readingMargin)
            .padding(.vertical, 24)
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: onContinue) {
                StartLabel(title: "Let's practice")
            }
            .buttonStyle(PoiseFlatButtonStyle(fullWidth: true))
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Color.poiseCanvas)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.poiseBorder.opacity(0.8)).frame(height: 1)
            }
            .accessibilityLabel("Start roleplay practice")
        }
    }
}

// The checkpoint stand-in for LiveGuideView: same shape, but it names the
// three dimensions instead of the lesson's criteria. Telling someone they're
// judged on clarity is fair warning; telling them to "state the concrete
// impact" would be handing over the answer.
// The cost sits on the button that actually commits you to the conversation,
// rather than on the Learn banner where you are still only browsing. White to
// match the label it sits beside -- it is part of the button's own text, not a
// separate badge pinned to it.
private struct StartLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
            // Unconditional. This used to be driven by wouldSpendEnergy, which
            // conflates "this costs energy" with "you can afford it" -- so the
            // price vanished from the button at exactly zero, the one moment
            // the user needs it to understand why the tap gets refused. Every
            // live conversation costs 1; whether you have it is the start
            // gate's question, not the label's.
            HStack(spacing: 3) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("1")
            }
            .foregroundStyle(.white.opacity(0.85))
            .accessibilityLabel("Costs 1 energy")
        }
    }
}

private struct LiveCheckpointGuideView: View {
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    PoiseEyebrow(text: "Checkpoint")
                    Text("No guide this time.")
                        .font(PoiseType.title())
                        .foregroundStyle(Color.poiseNavy)
                    Text("You won't get a checklist for this one. It's scored on how you handle the conversation overall.")
                        .font(PoiseType.body())
                        .foregroundStyle(Color.poiseMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                PoiseSection(title: "Scored on") {
                    PoiseSurfaceCard(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(PoiseSkill.allCases.enumerated()), id: \.element.id) { index, skill in
                                if index > 0 {
                                    PoiseDivider().padding(.leading, 68)
                                }
                                SkillRow(skill: skill)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, PoiseLayout.readingMargin)
            .padding(.vertical, 24)
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: onContinue) {
                StartLabel(title: "Start the conversation")
            }
            .buttonStyle(PoiseFlatButtonStyle(fullWidth: true))
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Color.poiseCanvas)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.poiseBorder.opacity(0.8)).frame(height: 1)
            }
            .accessibilityLabel("Start the conversation")
        }
    }
}

private struct SkillRow: View {
    let skill: PoiseSkill

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            PoiseIconBadge(icon: skill.icon, color: skill.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(skill.title)
                    .font(PoiseType.body(.bold))
                    .foregroundStyle(Color.poiseNavy)
                Text(skill.blurb)
                    .font(PoiseType.caption())
                    .foregroundStyle(Color.poiseMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct LiveRoleplayView: View {
    @ObservedObject var viewModel: LiveLessonViewModel
    // Owned by LiveLessonFlowView, which mounts the character layer once for
    // the whole flow; this step only drives which clip is showing.
    @Binding var characterMood: CharacterAnimationView.Mood
    let onReview: () -> Void

    // Type or speak, never both for the same turn -- picking one starts that
    // turn over clean (switchMode discards whatever the other mode had),
    // rather than trying to keep a single composer consistent across a
    // typed edit landing on top of a live dictation draft. That hybrid used
    // to exist and was a real source of state bugs (stale recordings
    // attaching to unrelated edited text); this removes the combination
    // entirely instead of continuing to patch it.
    enum InputMode { case text, voice }
    @State private var inputMode: InputMode = .voice
    @State private var response = ""
    @FocusState private var isWriting: Bool
    @StateObject private var speech = SpeechRecognitionService()
    // True from the moment Send is tapped until sendUserResponse settles --
    // covers the gap between tapping and speech.finalizedInput() actually
    // resolving, which composerLocked's other flags don't (isSendingTurn
    // only flips true once the network call itself starts).
    @State private var isSubmitting = false
    // Set only once the FINAL npc_reply has finished its word-by-word
    // reveal (and, by extension, finished playing) -- see the onReview
    // transition below for why this exists instead of reacting to
    // viewModel.ended directly.
    @State private var finalMessageRevealed = false
    @State private var showTranscript = false
    // True by default (not false) -- covers the window between this screen
    // appearing and the opening line's reveal actually starting (the
    // deliberate pre-dialogue delay plus voice synthesis time in
    // presentOpeningLineIfNeeded), during which viewModel.isSendingTurn is
    // never true (that flag only ever covers sendUserResponse's own round
    // trip) and viewModel.messages is still empty, so nothing else was
    // blocking the composer. Flips true again on every later reveal too --
    // see composerLocked below for why sending mid-reply must not be
    // allowed.
    @State private var npcIsSpeaking = true
    // Whether the CURRENT line's word-by-word reveal has finished. Distinct
    // from npcIsSpeaking -- that one no longer flips false the instant the
    // reveal completes; both it and characterMood only flip once this AND
    // viewModel.isAudioPlaying are both settled (see updateCharacterMoodIfIdle
    // below), reset to false on every new line's onRevealStart so a stale
    // true left over from the previous line can't fire it early.
    @State private var revealComplete = false

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
                    // The character itself is drawn by LiveLessonFlowView,
                    // underneath this whole step -- only the scrim and chrome
                    // live here now.

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
                        Text(viewModel.character?.name ?? "NPC")
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
        // Deliberately NOT keyed off viewModel.ended directly -- that flips
        // true the instant sendUserResponse's network call returns, which is
        // BEFORE the final npc_reply has even started its word-by-word
        // reveal (let alone finished being read or spoken). Reacting to it
        // immediately cut straight to the scorecard mid-line. Instead this
        // waits for the reveal to actually finish (finalMessageRevealed,
        // set from bottomDialoguePanel's onRevealComplete below), then adds
        // one more deliberate beat so the user has time to actually read the
        // NPC's last line before the screen changes out from under it.
        .onChange(of: finalMessageRevealed) { _, revealed in
            guard revealed else { return }
            Task {
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                onReview()
            }
        }
        // The other half of updateCharacterMoodIfIdle's two signals -- see
        // its doc below. Audio can keep playing after the text reveal has
        // already finished (WordRevealText's timer is only an estimate), so
        // this catches the moment real playback ends and re-checks whether
        // it's now safe to show idle.
        .onChange(of: viewModel.isAudioPlaying) { _, playing in
            if !playing { updateCharacterMoodIfIdle() }
        }
    }

    // The character (and the composer lock, via npcIsSpeaking) should only
    // treat the NPC as done talking once BOTH the text has finished
    // revealing AND the real audio has actually finished playing -- not
    // just whichever of the two happens to finish first. WordRevealText's
    // reveal timer is only an estimate of the real Pocket TTS clip's
    // duration (see its own doc), so relying on it alone could (and did)
    // show the character smiling/idle -- and unlock the composer -- while
    // dialogue was still audibly playing. Called from both onRevealComplete
    // below and the isAudioPlaying onChange above, whichever fires second.
    private func updateCharacterMoodIfIdle() {
        guard revealComplete, !viewModel.isAudioPlaying else { return }
        characterMood = .idleNeutral
        npcIsSpeaking = false
        if viewModel.ended { finalMessageRevealed = true }
    }

    // Shows only the MOST RECENT line (not a scrolling transcript) so this
    // panel's height is always just "one short message + a compact input
    // row" -- small and predictable, instead of growing with conversation
    // length and risking covering more of the scene the longer you talk.
    // Past lines are still reachable, just not inline: the small button
    // below opens the full transcript in a sheet on demand instead.
    private var bottomDialoguePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if viewModel.messages.count > 1 {
                HStack {
                    Spacer()
                    Button {
                        showTranscript = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "clock.arrow.circlepath")
                            Text("View past dialogue")
                        }
                        .font(PoiseType.caption(.semibold))
                        .foregroundStyle(.white.opacity(composerLocked ? 0.4 : 0.85))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.3))
                        .clipShape(Capsule())
                    }
                    // Locked for the same whole window the composer is --
                    // npcIsSpeaking alone only covers once the reply has
                    // actually started revealing, leaving the gap between
                    // pressing Send and the reply arriving (the network
                    // round trip plus synthesis) wide open, during which
                    // opening the transcript to replay a recording could
                    // still end up overlapping the NPC's line the instant
                    // it starts. composerLocked already covers that whole
                    // window (isSendingTurn/isSynthesizingSpeech/
                    // npcIsSpeaking/isSubmitting).
                    .disabled(composerLocked)
                    .accessibilityLabel("View past dialogue")
                }
            }

            if let latest = viewModel.messages.last {
                // Content-sized -- MessageBubble itself caps to 6 lines
                // (see its own doc) instead of this call site trying to
                // bound its height with a frame modifier, which in
                // practice did not shrink to short content the way a
                // plain Text does, and instead reserved a much taller
                // block with the visible bubble pinned to one edge of it.
                MessageBubble(
                    message: latest,
                    animateReveal: latest.speaker != .user,
                    speechDuration: viewModel.currentSpeechDuration,
                    onRevealStart: {
                        revealComplete = false
                        characterMood = .talkNeutral
                        npcIsSpeaking = true
                    },
                    onRevealComplete: {
                        revealComplete = true
                        // Only actually flips mood/npcIsSpeaking to idle if
                        // audio has also finished by now -- see
                        // updateCharacterMoodIfIdle. If audio is still
                        // playing, this is a no-op until the isAudioPlaying
                        // onChange above fires.
                        updateCharacterMoodIfIdle()
                    }
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

            ComposerModeToggle(mode: $inputMode, disabled: composerLocked, onSwitch: switchMode)

            HStack(alignment: .bottom, spacing: 10) {
                if inputMode == .text {
                    TextField("Type your response...", text: $response, axis: .vertical)
                        .font(PoiseType.body())
                        .foregroundStyle(Color.poiseNavy)
                        .lineLimit(1...3)
                        .padding(12)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .focused($isWriting)
                        .disabled(composerLocked)
                        .accessibilityLabel("Typed response")
                } else {
                    // Read-only, deliberately -- see InputMode's own doc.
                    // The only way to change what this holds is to
                    // re-record (tap the mic again, which discards and
                    // starts over) or switch back to Text mode.
                    VoiceTranscriptDisplay(speech: speech, response: response)

                    // Fills `response` as the user speaks, live -- never
                    // sends automatically. Also suppresses NPC playback for
                    // the duration (setUserRecording) so the mic doesn't
                    // pick up the NPC's own voice over the speaker.
                    Button {
                        viewModel.setUserRecording(true)
                        speech.toggleListening()
                        viewModel.setUserRecording(speech.isCapturing)
                    } label: {
                        Image(systemName: speech.isListening ? "mic.fill" : "mic")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(speech.isListening ? .white : .white.opacity(0.85))
                            .frame(width: 44, height: 44)
                            .background(speech.isListening ? Color.red.opacity(0.85) : .white.opacity(0.18))
                            .clipShape(Circle())
                    }
                    .disabled(composerLocked || speech.isFinalizing || speech.isFinishingTranscript)
                    .accessibilityLabel(speech.isListening ? "Stop dictating" : "Speak your response")
                }

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
            guard !isSubmitting, !newValue.isEmpty else { return }
            response = newValue
        }
        .onChange(of: speech.isListening) { _, listening in
            if listening { response = "" }
        }
        // Matches the server's own MAX_USER_RESPONSE_LENGTH (server/index.js)
        // -- typed input had no length limit anywhere, client or server,
        // before this. Truncating here (rather than only rejecting server
        // side after a real network round trip) keeps a pasted wall of text
        // from ever being sent in the first place.
        .onChange(of: response) { _, newValue in
            guard newValue.count > 1500 else { return }
            response = String(newValue.prefix(1500))
        }
        .onChange(of: speech.isCapturing) { _, recording in viewModel.setUserRecording(recording) }
        .onDisappear {
            speech.discardDraft()
            viewModel.setUserRecording(false)
        }
        .sheet(isPresented: $showTranscript) {
            ConversationTranscriptSheet(messages: viewModel.messages, characterName: viewModel.character?.name, voiceSession: viewModel.voiceSession)
        }
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

    // Locked for the whole time the NPC is "talking" -- voice synthesis,
    // audio playback, and the word-by-word reveal all read as one
    // uninterruptible turn from the user's side. Without this, the composer
    // was only ever disabled by isSendingTurn, which covers the network
    // round trip but not synthesis (isSynthesizingSpeech) or the reveal
    // itself (npcIsSpeaking) -- both real windows where a fast typist could
    // otherwise send a reply the NPC hadn't finished delivering yet, talking
    // over them mid-sentence.
    private var composerLocked: Bool {
        // viewModel.ended, not just the three in-flight-turn flags above --
        // once the conversation has concluded (all criteria met, a severe
        // flag, or the turn cap), there's a real window between the final
        // reply finishing its reveal and onReview() actually transitioning
        // to the scorecard (the deliberate 2.2s beat below, so the user has
        // time to read that last line) where none of the other three flags
        // are true any more, leaving the mic/send/mode buttons live for a
        // conversation that's already over.
        viewModel.isSendingTurn || viewModel.isSynthesizingSpeech || npcIsSpeaking || isSubmitting || viewModel.ended
    }

    private var sendDisabled: Bool {
        // Not while recording or while the transcriber is still finalizing
        // the last stretch of speech -- until then the end of the text can
        // be a half-word guess, and that's what would get sent.
        response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || composerLocked || speech.isStarting
            || speech.isListening || speech.isFinishingTranscript
    }

    // Discards whatever the OTHER mode was holding -- a typed draft, or a
    // dictated one -- so each mode always starts clean rather than trying
    // to reconcile leftover state from the one just left.
    private func switchMode(_ mode: InputMode) {
        guard mode != inputMode else { return }
        speech.discardDraft()
        viewModel.setUserRecording(false)
        response = ""
        inputMode = mode
    }

    private func sendResponse() {
        let trimmed = response
        isSubmitting = true
        isWriting = false
        // Cleared synchronously, before the round trip -- the user should
        // see the field empty the instant they tap Send, not after
        // sendUserResponse's network call resolves. Restored in the else
        // branch below if the send actually fails, so a failure doesn't
        // silently lose what they typed.
        response = ""
        Task {
            // Seals whatever recording was in progress (or already
            // finished) into a VoiceTurnInput -- .typed if none was ever
            // started. Awaiting this also naturally stops any active
            // dictation, so the mic can't keep listening into the next turn.
            let input = await speech.finalizedInput()
            viewModel.setUserRecording(false)
            if await viewModel.sendUserResponse(trimmed, voiceInput: input) {
                speech.discardDraft()
            } else {
                response = trimmed
            }
            isSubmitting = false
        }
    }
}

// Two mutually exclusive ways to answer -- type, or speak -- rather than one
// composer that tries to accept both at once (see LiveRoleplayView.InputMode).
private struct ComposerModeToggle: View {
    @Binding var mode: LiveRoleplayView.InputMode
    let disabled: Bool
    let onSwitch: (LiveRoleplayView.InputMode) -> Void

    var body: some View {
        HStack(spacing: 8) {
            modeButton(.text, title: "Type", icon: "keyboard")
            modeButton(.voice, title: "Speak", icon: "mic.fill")
        }
    }

    private func modeButton(_ target: LiveRoleplayView.InputMode, title: String, icon: String) -> some View {
        let isSelected = mode == target
        return Button {
            onSwitch(target)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                Text(title).font(PoiseType.caption(.semibold))
            }
            .foregroundStyle(isSelected ? Color.poiseNavy : .white.opacity(0.85))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.white : .white.opacity(0.18))
            .clipShape(Capsule())
        }
        .disabled(disabled)
        .accessibilityLabel("\(title) response")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// The Speak-mode transcript, read-only -- see LiveRoleplayView.InputMode's
// own doc for why this never accepts manual edits: the only way to change
// what it holds is to re-record or switch to Type mode.
private struct VoiceTranscriptDisplay: View {
    @ObservedObject var speech: SpeechRecognitionService
    let response: String

    private var placeholder: String {
        if speech.isListening { return "Listening..." }
        if speech.isFinalizing { return "Finishing up..." }
        return "Tap the mic to speak..."
    }

    var body: some View {
        Text(response.isEmpty ? placeholder : response)
            .font(PoiseType.body())
            .foregroundStyle(response.isEmpty ? Color.poiseMuted : Color.poiseNavy)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityLabel(response.isEmpty ? placeholder : "Transcribed response: \(response)")
    }
}

// The on-demand full history that bottomDialoguePanel's "View past dialogue"
// button opens. Every past line at once, statically (no word reveal -- these
// were already read/heard live), so this is just a plain scroll-back, not a
// second live conversation surface.
private struct ConversationTranscriptSheet: View {
    let messages: [ConversationMessage]
    let characterName: String?
    // Passed in rather than looked up globally -- recordings are only
    // retained for the lesson currently in progress (see
    // VoiceConversationSession.recordedClips), and this sheet always opens
    // from within that same lesson's flow.
    let voiceSession: VoiceConversationSession
    @Environment(\.dismiss) private var dismiss
    @StateObject private var player = VoiceClipPlayer()

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(messages) { message in
                            VStack(alignment: message.speaker == .user ? .trailing : .leading, spacing: 6) {
                                MessageBubble(message: message)
                                // Only ever set for the user's own turns (see
                                // VoiceConversationSession.recordingURL) --
                                // this naturally never shows on NPC lines.
                                if let url = voiceSession.recordingURL(forTurnID: message.id.uuidString) {
                                    ReplayRecordingButton(url: url, player: player)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: message.speaker == .user ? .trailing : .leading)
                            .id(message.id)
                        }
                    }
                    .padding(20)
                }
                .background(Color.poiseCanvas)
                .onAppear {
                    if let lastId = messages.last?.id {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
            .navigationTitle(characterName.map { "Conversation with \($0)" } ?? "Conversation so far")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        // The sheet, not the whole lesson, owns this player's lifetime --
        // stop on dismiss so audio never keeps playing behind a closed sheet.
        .onDisappear { player.stop() }
    }
}

// "Hear it back" for one of the user's own recorded turns -- addresses the
// otherwise reasonable assumption that recording your voice for delivery
// analysis would let you replay it, which it didn't until this button
// existed (see VoiceRecordingWriter/VoiceConversationSession's retention).
private struct ReplayRecordingButton: View {
    let url: URL
    @ObservedObject var player: VoiceClipPlayer

    private var isPlaying: Bool { player.playingURL == url }

    // "0:13 / 0:59" while playing, ticking every quarter second (see
    // VoiceClipPlayer.tick) -- the normal transport readout, not a bare
    // play/stop toggle with no sense of how far along or how long it is.
    private var label: String {
        guard isPlaying else { return "Play your recording" }
        return "\(player.currentTime.voiceClipTimestamp) / \(player.duration.voiceClipTimestamp)"
    }

    var body: some View {
        Button {
            player.toggle(url)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 10, weight: .bold))
                Text(label)
                    // Digits reflow at a fixed width each tick otherwise --
                    // "0:9" is narrower than "0:10" -- which visibly jitters
                    // the pill's width once a second.
                    .monospacedDigit()
            }
            .font(PoiseType.caption(.semibold))
            .foregroundStyle(Color.poiseBlueDark)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.poiseBlueDark.opacity(0.13))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Stop playback, \(label) elapsed" : "Play back your recorded response")
    }
}

private struct LiveScorecardView: View {
    @ObservedObject var viewModel: LiveLessonViewModel
    let isCheckpoint: Bool
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Landscape still in a panel, matching the briefing screen --
                // the looping clips are all portrait, so at 150pt tall this
                // rendered as a ~69pt vertical strip floating in the middle.
                // GeometryReader + explicit width -- see the briefing
                // screen's identical fix for why .frame(maxWidth: .infinity)
                // isn't safe here regardless of the source image's aspect
                // ratio.
                GeometryReader { geo in
                    Image(viewModel.character?.appearance.stillImageName ?? "CharFullFrame")
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: 150)
                        .clipped()
                }
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                if let feedback = viewModel.feedback {
                    VStack(spacing: 10) {
                        Text("One conversation stronger.")
                            .font(PoiseType.title())
                            .foregroundStyle(Color.poiseNavy)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // A checkpoint's criteria stay hidden at the END as well as
                    // the start. Showing the checklist here would hand back the
                    // exact answer key the guide screen withheld, and "3 of 3
                    // criteria met" would give it away by itself.
                    if isCheckpoint {
                        SkillScoreCard(feedback: feedback)
                    } else {
                        ChecklistResultCard(feedback: feedback)
                    }

                    // Specific measured numbers behind the Delivery
                    // level/note above -- reads voicePayload directly
                    // (on-device, conversation-level aggregates) rather than
                    // anything the server sent, since the server only ever
                    // returns one coarse level + note for delivery, never
                    // the underlying pace/pitch/filler measurements.
                    if feedback.skillLevels[.delivery] != nil,
                       let rows = VoiceDeliveryMetrics.rows(from: viewModel.voicePayload) {
                        DeliveryMetricsCard(rows: rows)
                    }

                    // Was the last block on this screen still wearing the
                    // pre-redesign treatment: a pale-blue card with a blue
                    // stroke, prose at .regular surrounded by bold labels, and
                    // no line spacing. Now the same PoiseSection +
                    // PoiseSurfaceCard as everything above it.
                    PoiseSection(title: "Feedback") {
                        PoiseSurfaceCard {
                            // Same treatment as the per-skill notes above --
                            // both are supporting explanation, so they should
                            // read as the same kind of text rather than the
                            // feedback being a second, larger voice. That
                            // means matching poiseMuted too, not just the
                            // font: navy next to the categories' muted notes
                            // read as a heavier, second voice despite being
                            // the same point size.
                            Text(feedback.feedbackLine)
                                .font(PoiseType.caption())
                                .foregroundStyle(Color.poiseMuted)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
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
            .padding(.horizontal, PoiseLayout.readingMargin)
            .padding(.vertical, 24)
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: onContinue) {
                PrimaryButtonLabel("Continue")
            }
            .buttonStyle(PoiseFlatButtonStyle(fullWidth: true))
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Color.poiseCanvas)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.poiseBorder.opacity(0.8)).frame(height: 1)
            }
            .accessibilityLabel("Continue to Learn")
        }
    }
}

// The checkpoint's result: the three dimensions it was judged on, in the same
// order the guide screen promised them.
// The one place the cost of a lesson is stated plainly. Energy was charged
// when the conversation ended, so this reports a balance that has already
// moved rather than predicting one.

private struct SkillScoreCard: View {
    let feedback: FeedbackResponse

    // Delivery is additive, not guaranteed -- only shown when the
    // conversation actually had a graded delivery score (i.e. at least one
    // turn had usable recorded audio). The original three are always graded.
    private var shownSkills: [PoiseSkill] {
        var skills: [PoiseSkill] = [.clarity, .empathy, .resolution]
        if feedback.skillLevels[.delivery] != nil { skills.append(.delivery) }
        return skills
    }

    var body: some View {
        PoiseSection(title: "How it went") {
            PoiseSurfaceCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(shownSkills.enumerated()), id: \.element.id) { index, skill in
                        if index > 0 {
                            PoiseDivider().padding(.leading, 68)
                        }
                        SkillResultRow(
                            skill: skill,
                            level: feedback.skillLevels[skill] ?? .developing,
                            note: feedback.note(for: skill)
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SkillResultRow: View {
    let skill: PoiseSkill
    let level: SkillLevel
    // The line that actually explains the level. A bare "Strong" says nothing
    // the user can act on, so the level is the label and this is the payload.
    let note: String?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            PoiseIconBadge(icon: skill.icon, color: skill.accent)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(skill.title)
                        .font(PoiseType.body(.bold))
                        .foregroundStyle(Color.poiseNavy)
                    Spacer(minLength: 8)
                    // Small labels are one treatment app-wide: uppercase,
                    // tracked, 11pt. A 12pt bold chip sitting beside a 12pt
                    // semibold note was two weights one step apart, which
                    // reads as a mistake rather than a distinction.
                    PoiseEyebrow(text: level.title, color: level.tint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(level.tint.opacity(0.13))
                        .clipShape(Capsule())
                }

                if let note {
                    Text(note)
                        .font(PoiseType.caption())
                        .foregroundStyle(Color.poiseMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// The specific measurements behind the Delivery grade -- pace, pitch
// variation, filler rate -- each with the same provisional target band the
// per-turn scorer already states in its own feedback strings (see
// voice-analysis/src/scoring.js). Deliberately plain, measured language, not
// coaching copy: this is supporting evidence for the level/note above it,
// not a second verdict, and (per the voice-analysis payload's own trusted
// guidance) never implies anything about confidence, emotion, or ability
// from pitch.
private struct DeliveryMetricsCard: View {
    let rows: [VoiceDeliveryMetricRow]

    var body: some View {
        PoiseSection(title: "Delivery, measured") {
            PoiseSurfaceCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            PoiseDivider().padding(.leading, 68)
                        }
                        DeliveryMetricRowView(row: row)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DeliveryMetricRowView: View {
    let row: VoiceDeliveryMetricRow

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            PoiseIconBadge(icon: row.icon, color: .poiseGold)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(PoiseType.body(.bold))
                    .foregroundStyle(Color.poiseNavy)
                Text(row.valueText)
                    .font(PoiseType.caption(.semibold))
                    .foregroundStyle(row.isAvailable ? Color.poiseNavy.opacity(0.85) : Color.poiseMuted)
                Text(row.detailText)
                    .font(PoiseType.caption())
                    .foregroundStyle(Color.poiseMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // Full width, leading -- the card's VStack centers any row narrower
        // than itself, so a row with shorter text sat visibly further right.
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// A regular lesson's result, built from exactly the same parts as
// SkillScoreCard -- same section eyebrow, same surface, same hairline rows,
// same chip -- so the two scorecards read as one screen rather than two
// designs. It replaces a pair of tinted score tiles (30pt off-ladder numerals,
// 1.5pt strokes) and an inline 18pt headline above a bare list.
//
// The numbered markers deliberately match the guide screen's: the same three
// criteria, in the same order, now carrying a result.
private struct ChecklistResultCard: View {
    let feedback: FeedbackResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PoiseSection(title: "How it went") {
                VStack(spacing: 10) {
                    PoiseSurfaceCard(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(feedback.checklist.enumerated()), id: \.element.id) { index, item in
                                if index > 0 {
                                    PoiseDivider().padding(.leading, 68)
                                }
                                ChecklistResultRow(number: index + 1, item: item)
                            }
                        }
                    }

                    // A regular lesson's checklist has no room for a fourth,
                    // differently-shaped criterion, so Delivery (when graded)
                    // gets its own card here instead of a row in the list
                    // above -- same SkillResultRow a checkpoint's
                    // SkillScoreCard uses, so it reads as the same kind of
                    // judgment as it does there.
                    if let deliveryLevel = feedback.skillLevels[.delivery] {
                        PoiseSurfaceCard(padding: 0) {
                            SkillResultRow(skill: .delivery, level: deliveryLevel, note: feedback.note(for: .delivery))
                        }
                    }
                }
            }

            if feedback.deductionCount > 0 {
                Text("\(feedback.deductionCount) tone deduction\(feedback.deductionCount == 1 ? "" : "s") along the way.")
                    .font(PoiseType.caption())
                    .foregroundStyle(Color.poiseMuted)
                    .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ChecklistResultRow: View {
    let number: Int
    let item: ChecklistEntry

    private var tint: Color { item.met ? .poiseMintDark : .poiseGold }

    var body: some View {
        // .top, matching DeliveryMetricRowView's own shape -- the criterion
        // moved from a single bold line next to the badge into a
        // heading ("Criteria N") + body-text pair, the same
        // heading-then-detail pattern the Delivery section already uses,
        // so the two cards read as one consistent format rather than two
        // different ones on the same scorecard.
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 38 * 0.3, style: .continuous)
                    .fill(tint.opacity(0.13))
                // Always the numeral, never a checkmark in its place. Swapping
                // the glyph for met items broke the sequence -- the list read
                // "check, 2, 3" -- and the numbers stop meaning anything once
                // some of them are missing. Colour and the trailing pill carry
                // the state instead; the number stays a number.
                Text("\(number)")
                    .font(PoiseType.body(.bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 4) {
                Text("Criteria \(number)")
                    .font(PoiseType.body(.bold))
                    .foregroundStyle(Color.poiseNavy)
                Text(item.criterion)
                    .font(PoiseType.caption())
                    .foregroundStyle(Color.poiseMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            PoiseEyebrow(text: item.met ? "Met" : "Not yet", color: tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(tint.opacity(0.13))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}
