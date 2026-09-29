import Combine
import Foundation
import PoiseVoiceAnalysis

// Drives one real, server-generated lesson conversation end to end:
// scenario -> opening line -> per-turn generation+grading -> feedback.
// Talks to conversation-engine over ConversationEngineClient. This is
// intentionally lesson-agnostic (keyed by `lessonId`) even though only one
// lesson is wired to a live `LessonNode` right now.
@MainActor
final class LiveLessonViewModel: ObservableObject {
    // Real generation against conversation-engine (Bedrock/Claude Haiku 4.5
    // behind it) -- Debug builds hit localhost:3000, so the local server
    // needs to be running (`npm start` in conversation-engine/); Release
    // builds hit the deployed engine at api.sapersolutions.com. Set back to
    // true to go back to static canned content for layout/UI iteration
    // without touching the network or spending real Bedrock calls.
    static let useMockDataForUITesting = false

    // Real lesson length -- 3 turns, same as MockLessonContent.turnReplies
    // and the "5 min" estimate on the Learn page. Has no effect while
    // useMockDataForUITesting is false; only relevant if mocking is turned
    // back on for UI iteration.
    static let mockTurnLimit: Int? = nil

    let lessonRef: LessonReference
    var lessonId: String { lessonRef.lessonId }

    // On-device acoustic analysis of the user's own recorded turns (see
    // AGENTS.md's voice-delivery-analysis exception). Assembled into one
    // conversation-level payload at the end of the lesson (finishVoiceSession)
    // and sent alongside the existing turn/feedback data so the scorecard can
    // grade delivery the same way it grades clarity/empathy/resolution.
    let voiceSession = VoiceConversationSession()
    @Published private(set) var voicePayload: Data?
    @Published private(set) var voiceAnalysisError: String?
    private var voiceFinishTask: Task<Void, Never>?
    // True while the user is actively recording their own turn -- NPC
    // playback is suppressed during this window so the mic doesn't pick up
    // the NPC's own voice over the speaker.
    private var suppressNPCPlayback = false
    // Invalidates an in-flight presentNPCMessage() synthesis if suppression
    // or dismissal state changes before it resolves -- same class of
    // check-after-await race as isDismissed, scoped to this one flag pair.
    private var playbackGeneration = UUID()
    // Set once the WHOLE lesson flow (not just the roleplay step) has gone
    // away -- see abandonVoiceSession(). Broader than isDismissed, which
    // only covers the roleplay step's own lifetime; this also cancels a
    // voice-analysis assembly still running after the user has moved on to
    // the scorecard (or backed out) before it settled.
    private var isAbandoned = false

    @Published private(set) var isLoadingScenario = true
    @Published private(set) var isSendingTurn = false
    @Published private(set) var briefing: String = ""
    @Published private(set) var criteria: [String] = []
    @Published private(set) var character: EngineCharacter?
    @Published private(set) var messages: [ConversationMessage] = []
    // Real Pocket TTS clip duration for the most recently appended NPC line,
    // once synthesis completes -- see presentNPCMessage(). Nil while
    // synthesizing (isSynthesizingSpeech) or if synthesis failed, in which
    // case WordRevealText falls back to its WPM estimate.
    @Published private(set) var currentSpeechDuration: Double?
    @Published private(set) var isSynthesizingSpeech = false
    // The real signal that the current NPC line's audio is still audibly
    // playing -- driven by NPCVoiceService's own playback-finished callback,
    // not by WordRevealText's text-reveal timer (which is only an estimate
    // of speech duration, weighted by word length, and can finish before the
    // real clip actually stops sounding). LiveRoleplayView combines this
    // with its own reveal-complete signal so the character only returns to
    // idle once BOTH are true -- see applySpeech() and appendWithoutSpeech()
    // below for where this flips.
    @Published private(set) var isAudioPlaying = false
    @Published private(set) var metCriteria: [String] = []
    @Published private(set) var deductionCount = 0
    @Published private(set) var turnNumber = 0
    @Published private(set) var ended = false
    @Published private(set) var resolution: String?
    @Published private(set) var feedback: FeedbackResponse?
    // Issued by the server on turn 1 when the conversation is charged; must be
    // sent on every later turn and on feedback, or the server refuses them.
    private var conversationToken: String?
    @Published var errorMessage: String?

    private var scenario: EngineScenario?
    private var history: [HistoryTurn] = []
    private var empathyLevels: [String] = []
    // Opening line, fetched/prepared eagerly in start() but deliberately NOT
    // presented (synthesized+played+appended) until the roleplay screen
    // itself appears -- see presentOpeningLineIfNeeded(). Presenting it at
    // start() time made Jean's audio play while the user was still looking
    // at the briefing/guide screens, long before the message (and its
    // word-reveal) ever became visible.
    private var pendingOpeningLine: ConversationMessage?
    private var openingLineDidPresent = false

    // Set only by the custom-lesson init below -- when present, start()
    // skips the /api/scenario fetch and ScenarioCache entirely and goes
    // straight to the opening line, since the scenario was already
    // generated by the custom-scenario builder screen.
    private let prefetchedCustomScenario: EngineScenario?

    init(lessonId: String) {
        self.lessonRef = .builtIn(lessonId)
        self.prefetchedCustomScenario = nil
    }

    // For a scenario generated from the user's own prompt (see
    // ConversationEngineClient.generateCustomScenario) -- never cached (see
    // ScenarioCache's own doc on why: there's no static lesson behind a
    // custom one to reopen later, each is a one-off).
    init(customLesson: EngineLessonSummary, scenario: EngineScenario) {
        self.lessonRef = .custom(customLesson)
        self.prefetchedCustomScenario = scenario
        self.character = customLesson.character
    }

    // Set once the roleplay screen has left the screen (see stopSpeaking()).
    // Guards presentNPCMessage below against a synthesis call that was
    // still in flight at that exact moment from starting playback anyway
    // afterward: Swift's Task cancellation is cooperative, and the Rust FFI
    // call inside NPCVoiceService.speak() never checks Task.isCancelled, so
    // leaving mid-synthesis does NOT stop it from running to completion --
    // and stopSpeaking()'s own NPCVoiceService.stop() only stops a player
    // that already exists, which one made AFTER the screen closed never
    // did. Once true, this view model's audio work is permanently done --
    // a fresh LiveLessonFlowView/LiveLessonViewModel is created per lesson
    // attempt, so this never needs to reset.
    private var isDismissed = false

    // Kicked off by prefetchOpeningSpeech() the moment the opening line's
    // text (and character/voice) are known -- start(), startCustomLesson(),
    // or applyCached() -- so synthesis runs in the background while the
    // user is still reading briefing/guide, instead of only starting once
    // they reach the roleplay screen. See presentPrefetchedOpeningLine().
    private var openingSpeechTask: Task<NPCVoiceService.Speech?, Never>?

    // Synthesizes the NPC line's voice (in this character's own voice -- see
    // CharacterAppearance.voiceIndex) BEFORE appending it to `messages`, so
    // that by the time the message (and its word-by-word WordRevealText)
    // becomes visible, the real clip duration is already known and audio
    // playback starts in the same instant the reveal does -- rather than
    // text appearing first on a guessed pace while audio is still catching
    // up. A brief "getting voice ready" moment is the correct trade-off
    // here, not a bug. Used for every turn's reply; the opening line instead
    // goes through presentPrefetchedOpeningLine() below, which only falls
    // back to this when no prefetch was kicked off.
    @available(iOS 17.0, *)
    private func presentNPCMessage(_ message: ConversationMessage) async {
        guard !isAbandoned else { return }
        do {
            try voiceSession.appendNPC(id: message.id.uuidString, text: message.text, speakerName: message.characterName)
        } catch {
            voiceAnalysisError = error.localizedDescription
        }
        // The user is actively recording their own turn -- don't play the
        // NPC back over the mic, just show the line silently.
        if suppressNPCPlayback {
            appendWithoutSpeech(message)
            return
        }
        isSynthesizingSpeech = true
        currentSpeechDuration = nil
        let voice = character?.appearance.voiceIndex ?? CharacterAppearance.char1.voiceIndex
        let generation = playbackGeneration
        do {
            let speech = try await NPCVoiceService.shared.speak(message.text, voice: voice)
            isSynthesizingSpeech = false
            guard !isAbandoned else { return }
            // Suppression kicked in, or this generation was invalidated,
            // while synthesis was in flight -- show the text, skip playback.
            if suppressNPCPlayback || playbackGeneration != generation {
                appendWithoutSpeech(message)
                return
            }
            await applySpeech(speech, to: message)
        } catch {
            isSynthesizingSpeech = false
            guard !isAbandoned else { return }
            // TTS is additive, not load-bearing -- a failure here should
            // never block the conversation. The message still appears;
            // WordRevealText just falls back to its WPM estimate.
            print("[LiveLessonViewModel] NPC speech synthesis failed, falling back to timed-estimate reveal: \(error)")
            appendWithoutSpeech(message)
        }
    }

    // Fire-and-forget: starts synthesizing the opening line's audio right
    // away rather than waiting for the roleplay screen to appear. By the
    // time the user has actually read through briefing and guide (real
    // seconds, not something this can shortcut), synthesis -- 2-7+ seconds
    // measured on-device, worse on a cold model load -- has usually already
    // finished, so presentPrefetchedOpeningLine() just awaits an
    // already-done Task instead of starting synthesis from scratch at the
    // moment the user taps "Let's Practice".
    @available(iOS 17.0, *)
    private func prefetchOpeningSpeech(text: String, voice: UInt32) {
        openingSpeechTask = Task {
            do {
                return try await NPCVoiceService.shared.speak(text, voice: voice)
            } catch {
                print("[LiveLessonViewModel] Opening-line pre-synthesis failed, will fall back to timed-estimate reveal: \(error)")
                return nil
            }
        }
    }

    // Call once, from presentOpeningLineIfNeeded(), instead of
    // presentNPCMessage() directly -- awaits the Task prefetchOpeningSpeech()
    // already started (typically already finished by now) rather than
    // kicking off synthesis fresh. Falls back to a live presentNPCMessage()
    // call if no prefetch is in flight, which covers the mock-data UI-testing
    // path (loadMockScenario() never calls prefetchOpeningSpeech) and guards
    // against a future call site that sets pendingOpeningLine without
    // prefetching.
    @available(iOS 17.0, *)
    private func presentPrefetchedOpeningLine(_ message: ConversationMessage) async {
        guard let task = openingSpeechTask else {
            await presentNPCMessage(message)
            return
        }
        openingSpeechTask = nil
        isSynthesizingSpeech = true
        currentSpeechDuration = nil
        if let speech = await task.value {
            isSynthesizingSpeech = false
            await applySpeech(speech, to: message)
        } else {
            isSynthesizingSpeech = false
            appendWithoutSpeech(message)
        }
    }

    // Shared tail of both presentation paths above. The user left while
    // synthesis was in flight -- see isDismissed's doc above. Don't append
    // (nothing is watching `messages` anymore) and, above all, don't start
    // playback of a line for a screen that already closed.
    private func applySpeech(_ speech: NPCVoiceService.Speech, to message: ConversationMessage) async {
        guard !isDismissed else { return }
        currentSpeechDuration = speech.durationSeconds
        // Prepare (pre-buffer) playback BEFORE appending the message --
        // appending is what starts WordRevealText's reveal timer, so
        // warming up AVAudioPlayer ahead of that moment (rather than
        // constructing it and calling .play() afterward) tightens the
        // gap between the reveal starting and audio actually sounding.
        // The completion closure is the REAL "audio finished" signal
        // (fired by NPCVoiceService on natural completion or an
        // interrupting stop()) -- see isAudioPlaying's own doc above.
        let prepared = NPCVoiceService.shared.prepare(speech.audioData) { [weak self] in
            Task { @MainActor in self?.isAudioPlaying = false }
        }
        messages.append(message)
        guard prepared else { return }
        // `messages.append` above only SCHEDULES a SwiftUI update -- the
        // actual reveal starting, and the character switching to its Talk
        // clip because of it, both happen on a later run-loop tick, not
        // synchronously with this call. playPrepared() below, on an
        // already-buffered player, starts producing audible sound almost
        // immediately. Without this gap the voice was reliably audible
        // before the mouth visibly started moving, even though this
        // function calls things in the "right" order -- a short, deliberate
        // head start closes that real (not just source-order) gap.
        try? await Task.sleep(nanoseconds: 150_000_000)
        guard !isDismissed else { return }
        isAudioPlaying = true
        let generation = playbackGeneration
        NPCVoiceService.shared.playPrepared()
        // Safety net -- isAudioPlaying is meant to always resolve via the
        // completion closure above (natural finish or an interrupting
        // stop()), but if that signal is ever missed for any reason, this
        // flag staying stuck true would permanently jam the character in
        // its Talk animation and keep the composer/"View past dialogue"
        // locked with no way out. Comfortably longer than the clip itself;
        // only fires if the real signal never showed up, and does nothing
        // if a later line has already started (a new playbackGeneration).
        let duration = speech.durationSeconds
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((duration + 5) * 1_000_000_000))
            await MainActor.run {
                guard let self, self.playbackGeneration == generation, self.isAudioPlaying else { return }
                self.isAudioPlaying = false
            }
        }
    }

    private func appendWithoutSpeech(_ message: ConversationMessage) {
        guard !isDismissed else { return }
        // No audio ever plays for this line (suppressed, or synthesis
        // failed) -- isAudioPlaying was never set true for it, so the
        // reveal-complete signal alone is enough to return the character
        // to idle.
        isAudioPlaying = false
        messages.append(message)
    }

    func start() async {
        isLoadingScenario = true
        errorMessage = nil

        if Self.useMockDataForUITesting {
            loadMockScenario()
            isLoadingScenario = false
            return
        }

        if let prefetchedCustomScenario {
            await startCustomLesson(scenario: prefetchedCustomScenario)
            isLoadingScenario = false
            return
        }

        // A lesson keeps the scenario it was given until it is completed, so
        // reopening one shows the same situation you were already reading
        // rather than generating a replacement (and paying for it). See
        // ScenarioCache.
        if let cached = ScenarioCache.scenario(for: lessonId) {
            applyCached(cached)
            isLoadingScenario = false
            return
        }

        do {
            let scenarioResponse = try await ConversationEngineClient.fetchScenario(lessonId: lessonId)
            scenario = scenarioResponse.scenario
            briefing = scenarioResponse.scenario.briefing
            criteria = scenarioResponse.scenario.criteria
            character = scenarioResponse.lesson.character

            let opening = try await ConversationEngineClient.fetchOpening(
                lessonRef,
                scenario: scenarioResponse.scenario
            )

            ScenarioCache.store(
                CachedScenario(
                    scenario: scenarioResponse.scenario,
                    character: scenarioResponse.lesson.character,
                    openingLine: opening.openingLine,
                    openingCharacterName: opening.character,
                    generatedAt: Date()
                ),
                for: lessonId
            )
            // Text is fetched eagerly (good for latency), but NOT presented
            // (synthesized/played/appended) yet -- see presentOpeningLineIfNeeded().
            pendingOpeningLine = ConversationMessage(speaker: .npc, text: opening.openingLine, characterName: opening.character)
            history = [HistoryTurn(role: "npc", text: opening.openingLine, character: opening.character)]
            // Audio, unlike the text above, starts synthesizing right now --
            // see prefetchOpeningSpeech's doc.
            prefetchOpeningSpeech(
                text: opening.openingLine,
                voice: character?.appearance.voiceIndex ?? CharacterAppearance.char1.voiceIndex
            )
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
        isLoadingScenario = false
    }

    // Custom scenarios skip the /api/scenario fetch entirely -- the builder
    // screen already generated this lesson+scenario from the user's prompt
    // (see ConversationEngineClient.generateCustomScenario) -- and are never
    // written to ScenarioCache, since there's no static lesson to reopen
    // later; each one is a one-off. This otherwise mirrors start()'s
    // built-in-lesson tail: fetch the opening line, stash it unpresented.
    private func startCustomLesson(scenario customScenario: EngineScenario) async {
        scenario = customScenario
        briefing = customScenario.briefing
        criteria = customScenario.criteria

        do {
            let opening = try await ConversationEngineClient.fetchOpening(lessonRef, scenario: customScenario)
            pendingOpeningLine = ConversationMessage(speaker: .npc, text: opening.openingLine, characterName: opening.character)
            history = [HistoryTurn(role: "npc", text: opening.openingLine, character: opening.character)]
            prefetchOpeningSpeech(
                text: opening.openingLine,
                voice: character?.appearance.voiceIndex ?? CharacterAppearance.char1.voiceIndex
            )
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }

    // Restores a scenario from the cache into exactly the state a fresh fetch
    // would have left behind, including the un-presented opening line -- the
    // roleplay screen still reveals it on its own schedule.
    private func applyCached(_ cached: CachedScenario) {
        scenario = cached.scenario
        briefing = cached.scenario.briefing
        criteria = cached.scenario.criteria
        character = cached.character
        pendingOpeningLine = ConversationMessage(
            speaker: .npc,
            text: cached.openingLine,
            characterName: cached.openingCharacterName
        )
        history = [HistoryTurn(role: "npc", text: cached.openingLine, character: cached.openingCharacterName)]
        // Only the text is cached, not the synthesized audio -- still worth
        // prefetching here rather than falling through to a live synthesize
        // at roleplay time, same reasoning as the fresh-fetch path above.
        prefetchOpeningSpeech(
            text: cached.openingLine,
            voice: cached.character.appearance.voiceIndex
        )
    }

    /// Call once, when the roleplay screen itself actually appears. Presents
    /// (synthesizes Jean's audio for, plays, and reveals) the opening line
    /// that start() already fetched the text for -- deliberately deferred so
    /// audio doesn't start while the user is still on the briefing/guide
    /// screens. Safe to call more than once; only the first call does anything.
    @available(iOS 17.0, *)
    func presentOpeningLineIfNeeded() async {
        guard !openingLineDidPresent, let opening = pendingOpeningLine else { return }
        openingLineDidPresent = true
        pendingOpeningLine = nil
        // Deliberate 2-second beat so the user actually sees the scene/
        // character first, rather than being hit with dialogue the instant
        // the roleplay screen appears -- this is now effectively the WHOLE
        // delay before she starts talking, since prefetchOpeningSpeech()
        // already started synthesis back in start()/startCustomLesson()/
        // applyCached(), well before the user tapped through briefing and
        // guide to get here. A real `try` (not `try?`) matters here:
        // SwiftUI cancels this .task's underlying Task when the roleplay
        // view disappears, which makes Task.sleep throw CancellationError --
        // `try?` was silently swallowing that and falling through to
        // presentPrefetchedOpeningLine() (and thus playing audio) even
        // after the user had already left. Letting the throw propagate
        // aborts here instead.
        do {
            try await Task.sleep(nanoseconds: 2_000_000_000)
        } catch {
            return
        }
        await presentPrefetchedOpeningLine(opening)
    }

    /// Immediately halts any currently-playing NPC speech, and permanently
    /// latches isDismissed so a synthesis call already in flight at this
    /// moment can't start playback later, after the fact. Call when the
    /// roleplay screen disappears -- audio must never keep playing (or
    /// start) once the user has left, regardless of how far into the
    /// pipeline (pre-delay, synthesis, or active playback) things had
    /// gotten. The pre-delay case is separately handled by
    /// presentOpeningLineIfNeeded()'s cancellation above; NPCVoiceService's
    /// own stop() covers playback that had already started; isDismissed
    /// covers the gap between those two -- synthesis in progress, with
    /// nothing yet to stop.
    @available(iOS 17.0, *)
    func stopSpeaking() {
        isDismissed = true
        NPCVoiceService.shared.stop()
    }

    // Toggled around the mic button: true while the user is recording (or
    // about to), so any in-flight/future NPC playback stays suppressed until
    // they're done. Also stops any currently-playing NPC line immediately,
    // same reasoning as stopSpeaking() -- the user talking over the NPC on
    // purpose is not a case to keep playing through.
    func setUserRecording(_ recording: Bool) {
        suppressNPCPlayback = recording
        if recording { stopSpeaking2() }
    }

    // Distinct from stopSpeaking(): that one also latches isDismissed
    // (roleplay screen gone for good). Recording toggles on and off
    // repeatedly within one still-open roleplay screen, so it needs its own
    // "stop whatever's playing right now" that doesn't permanently disable
    // future playback -- just invalidates this one in-flight generation.
    private func stopSpeaking2() {
        playbackGeneration = UUID()
        NPCVoiceService.shared.stop()
    }

    /// Call when the WHOLE lesson flow is going away (not just the roleplay
    /// step) -- see isAbandoned's doc. Cancels any voice-analysis work still
    /// in flight so it can't finish and do anything after the user has left.
    func abandonVoiceSession() {
        isAbandoned = true
        stopSpeaking()
        voiceFinishTask?.cancel()
        voiceSession.cancel()
        // Whole flow (including the scorecard) is going away for good --
        // nothing can ask for playback after this, so release the retained
        // recordings' temp files now rather than leaving that to whenever
        // this view model happens to deinit.
        voiceSession.releaseRecordings()
    }

    // Awaits the conversation-level voice-analysis assembly (bounded by the
    // analyzer's own cooperative deadline, see the package's docs) and
    // reduces it to just `coverage` + `aggregates` -- the per-turn evidence
    // and full word lists are real but far too large for an LLM prompt, and
    // aren't needed for a holistic delivery judgment. Best-effort throughout:
    // any failure here (or an accumulated per-turn voiceAnalysisError) just
    // means no delivery grading this run, never a blocked feedback call --
    // delivery is additive on top of the existing content grading.
    private func finishVoiceSessionAndSummarize() async -> [String: Any]? {
        guard !isAbandoned, voiceAnalysisError == nil else {
            voiceSession.cancel()
            return nil
        }
        let task = Task { try await voiceSession.finish() }
        voiceFinishTask = Task { _ = try? await task.value }
        do {
            let payload = try await task.value
            voicePayload = payload.json
            guard let object = try JSONSerialization.jsonObject(with: payload.json) as? [String: Any] else { return nil }
            var summary: [String: Any] = [:]
            if let coverage = object["coverage"] { summary["coverage"] = coverage }
            if let aggregates = object["aggregates"] { summary["aggregates"] = aggregates }
            return summary.isEmpty ? nil : summary
        } catch is CancellationError {
            return nil
        } catch {
            voiceAnalysisError = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func sendUserResponse(_ text: String, voiceInput: VoiceTurnInput = .typed) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSendingTurn, !ended, !isAbandoned else { return false }
        guard Self.useMockDataForUITesting || scenario != nil else { return false }

        let userMessage = ConversationMessage(speaker: .user, text: trimmed)
        messages.append(userMessage)
        let historyBeforeThisTurn = history
        history.append(HistoryTurn(role: "user", text: trimmed, character: nil))
        turnNumber += 1
        isSendingTurn = true
        errorMessage = nil

        if Self.useMockDataForUITesting {
            do {
                try voiceSession.appendUser(id: userMessage.id.uuidString, text: trimmed, input: voiceInput)
            } catch {
                voiceAnalysisError = error.localizedDescription
            }
            await mockSendUserResponse()
            isSendingTurn = false
            return true
        }

        guard let scenario else { isSendingTurn = false; return false }

        do {
            let result = try await ConversationEngineClient.fetchTurn(
                lessonRef,
                scenario: scenario,
                history: historyBeforeThisTurn,
                metCriteria: metCriteria,
                turnNumber: turnNumber,
                userResponse: trimmed,
                conversationToken: conversationToken
            )
            guard !isAbandoned else { isSendingTurn = false; return false }
            // Accept the recording only after the text turn succeeds --
            // a failed send below rolls back the turn entirely, and a voice
            // clip for a turn that never happened shouldn't count either.
            do {
                try voiceSession.appendUser(id: userMessage.id.uuidString, text: trimmed, input: voiceInput)
            } catch {
                voiceAnalysisError = error.localizedDescription
            }
            if let token = result.conversationToken { conversationToken = token }
            if let energy = result.energy { LearnProgressStore.shared.applyServerEnergy(energy) }
            await presentNPCMessage(ConversationMessage(speaker: .npc, text: result.npc_reply, characterName: result.character))
            history.append(HistoryTurn(role: "npc", text: result.npc_reply, character: result.character))
            metCriteria = result.updated_met_criteria
            if result.deduction { deductionCount += 1 }
            empathyLevels.append(result.respect_and_empathy)

            if result.ended {
                ended = true
                resolution = result.resolution
                await loadFeedback()
            }
        } catch {
            errorMessage = friendlyMessage(for: error)
            // Roll back the optimistic user turn/counters so a retry is possible.
            if messages.last?.speaker == .user { messages.removeLast() }
            history = historyBeforeThisTurn
            turnNumber -= 1
            isSendingTurn = false
            return false
        }
        isSendingTurn = false
        return true
    }

    private func loadFeedback() async {
        guard let scenario, let resolution else { return }
        let voiceSummary = await finishVoiceSessionAndSummarize()
        do {
            feedback = try await ConversationEngineClient.fetchFeedback(
                lessonRef,
                scenario: scenario,
                history: history,
                metCriteria: metCriteria,
                deductionCount: deductionCount,
                resolution: resolution,
                empathyLevels: empathyLevels,
                conversationToken: conversationToken,
                voiceSummary: voiceSummary
            )
            if let energy = feedback?.energy { LearnProgressStore.shared.applyServerEnergy(energy) }
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }

    // MARK: - Mock content (UI testing only, see useMockDataForUITesting)

    // Looked up by lessonId so every lesson gets its own
    // mocked content instead of all sharing this one Sam/Meridian scenario --
    // falls back to it only if `lessonId` doesn't match any known lesson,
    // which shouldn't normally happen.
    private var mockContent: MockLessonContent {
        PoiseLessonLibrary.content(for: lessonId) ?? PoiseLessonLibrary.all[0]
    }

    private func loadMockScenario() {
        let content = mockContent
        let mockScenario = EngineScenario(briefing: content.briefing, criteria: content.criteria)
        scenario = mockScenario
        briefing = mockScenario.briefing
        criteria = mockScenario.criteria
        character = content.character

        // Same deferred-presentation rule as the live path: text is ready
        // now, but presentOpeningLineIfNeeded() (called from the roleplay
        // screen) is what actually synthesizes/plays/reveals it.
        pendingOpeningLine = ConversationMessage(speaker: .npc, text: content.openingLine, characterName: content.character.name)
        history = [HistoryTurn(role: "npc", text: content.openingLine, character: content.character.name)]
    }

    private func mockSendUserResponse() async {
        // Small artificial delay so the "is responding..." state is actually
        // visible while testing, instead of resolving instantly.
        try? await Task.sleep(nanoseconds: 500_000_000)

        let mockReplies = mockContent.turnReplies
        let turnsThisRun = min(Self.mockTurnLimit ?? mockReplies.count, mockReplies.count)
        let reply = mockReplies[min(turnNumber - 1, mockReplies.count - 1)]

        await presentNPCMessage(ConversationMessage(speaker: .npc, text: reply, characterName: character?.name ?? mockContent.character.name))
        history.append(HistoryTurn(role: "npc", text: reply, character: character?.name))

        if turnNumber - 1 < criteria.count {
            let newlyMet = criteria[turnNumber - 1]
            if !metCriteria.contains(newlyMet) { metCriteria.append(newlyMet) }
        }

        if turnNumber >= turnsThisRun {
            ended = true
            resolution = "approving"
            loadMockFeedback()
        }
    }

    // TESTING ONLY -- jumps straight to the scorecard without running a
    // conversation, so the results screen can be worked on without playing
    // three turns first. Driven by the Skip roleplay switch on Profile.
    //
    // Builds the feedback locally rather than asking the engine for it: a
    // grading call with no transcript would either fail or invent a reading
    // of a conversation that never happened, and paying tokens to be lied to
    // is worse than an obviously synthetic card. The feedback line says so on
    // its face, so this can never be mistaken for a real result.
    func skipToResults() {
        ended = true
        resolution = "approving"
        // One criterion left unmet so the checklist shows both states.
        metCriteria = criteria.count > 1 ? Array(criteria.dropLast()) : criteria
        feedback = FeedbackResponse(
            checklist: criteria.map { ChecklistEntry(criterion: $0, met: metCriteria.contains($0)) },
            deductionCount: 0,
            empathySummary: EmpathySummary(strong: 1, adequate: 1, minimal: 0),
            resolution: resolution,
            feedbackLine: "Roleplay skipped for testing. No conversation happened, so nothing here is a real assessment.",
            // Spread across three tiers so the checkpoint scorecard and the
            // Progress chart both have something to draw.
            skills: SkillScores(
                clarity: SkillScore(level: "strong", note: "Placeholder note — the roleplay was skipped."),
                empathy: SkillScore(level: "solid", note: "Placeholder note — the roleplay was skipped."),
                resolution: SkillScore(level: "developing", note: "Placeholder note — the roleplay was skipped.")
            )
        )
    }

    private func loadMockFeedback() {
        feedback = FeedbackResponse(
            checklist: criteria.map { ChecklistEntry(criterion: $0, met: metCriteria.contains($0)) },
            deductionCount: deductionCount,
            empathySummary: EmpathySummary(strong: 2, adequate: 1, minimal: 0),
            resolution: resolution,
            feedbackLine: mockContent.feedbackLine,
            // SAMPLE TEXT, mock path only -- written to show the shape and
            // quality the engine's notes are meant to have, so the scorecard
            // can be judged without a server. Deliberately spread across three
            // levels so every chip colour is visible. Never shown once
            // useMockDataForUITesting is false.
            skills: SkillScores(
                clarity: SkillScore(
                    level: "developing",
                    note: "You raised the pattern but never said what it was costing the team."
                ),
                empathy: SkillScore(
                    level: "needs_work",
                    note: "They mentioned being stretched thin and you moved straight past it."
                ),
                resolution: SkillScore(
                    level: "solid",
                    note: "You agreed it should change, but not who does what next."
                )
            )
        )
    }

    private func friendlyMessage(for error: Error) -> String {
        if let engineError = error as? ConversationEngineError {
            switch engineError {
            case .outOfEnergy, .rateLimited:
                // Already worded for the user by the error itself.
                return engineError.localizedDescription
            case .unauthorized(let message):
                // A rejected conversation token means the server no longer
                // recognises this run -- say what to do rather than echo the
                // status.
                return message.contains("Conversation token")
                    ? "This conversation has expired. Start it again from the lesson."
                    : "This build isn't authorised to use the conversation engine. (\(message))"
            case .server, .invalidResponse:
                return engineError.localizedDescription
            }
        }
        return "Couldn't reach the local conversation-engine server at \(ConversationEngineClient.baseURL.absoluteString). " +
            "Make sure it's running (`npm start` in conversation-engine/). (\(error.localizedDescription))"
    }
}
