import Combine
import Foundation

// Drives one real, server-generated lesson conversation end to end:
// scenario -> opening line -> per-turn generation+grading -> feedback.
// Talks to conversation-engine over ConversationEngineClient. This is
// intentionally lesson-agnostic (keyed by `lessonId`) even though only one
// lesson is wired to a live `LessonNode` right now.
@MainActor
final class LiveLessonViewModel: ObservableObject {
    // Set to false to go back to real generation against the local
    // conversation-engine server. While true, `start()`/`sendUserResponse()`
    // use static canned content and never touch the network -- for iterating
    // on layout/UI without waiting on (or re-triggering) a fresh generation
    // every time the screen reloads.
    static let useMockDataForUITesting = true

    let lessonId: String

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
    @Published private(set) var metCriteria: [String] = []
    @Published private(set) var deductionCount = 0
    @Published private(set) var turnNumber = 0
    @Published private(set) var ended = false
    @Published private(set) var resolution: String?
    @Published private(set) var feedback: FeedbackResponse?
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

    init(lessonId: String) {
        self.lessonId = lessonId
    }

    // Synthesizes the NPC line's voice (Jean) BEFORE appending it to
    // `messages`, so that by the time the message (and its word-by-word
    // WordRevealText) becomes visible, the real clip duration is already
    // known and audio playback starts in the same instant the reveal does --
    // rather than text appearing first on a guessed pace while audio is
    // still catching up. A brief "getting voice ready" moment is the correct
    // trade-off here, not a bug.
    @available(iOS 17.0, *)
    private func presentNPCMessage(_ message: ConversationMessage) async {
        isSynthesizingSpeech = true
        currentSpeechDuration = nil
        do {
            let speech = try await NPCVoiceService.shared.speak(message.text)
            currentSpeechDuration = speech.durationSeconds
            // Prepare (pre-buffer) playback BEFORE appending the message --
            // appending is what starts WordRevealText's reveal timer, so
            // warming up AVAudioPlayer ahead of that moment (rather than
            // constructing it and calling .play() afterward) tightens the
            // gap between the reveal starting and audio actually sounding.
            let prepared = NPCVoiceService.shared.prepare(speech.audioData)
            messages.append(message)
            if prepared { NPCVoiceService.shared.playPrepared() }
        } catch {
            // TTS is additive, not load-bearing -- a failure here should
            // never block the conversation. The message still appears;
            // WordRevealText just falls back to its WPM estimate.
            print("[LiveLessonViewModel] NPC speech synthesis failed, falling back to timed-estimate reveal: \(error)")
            messages.append(message)
        }
        isSynthesizingSpeech = false
    }

    func start() async {
        isLoadingScenario = true
        errorMessage = nil

        if Self.useMockDataForUITesting {
            loadMockScenario()
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
                lessonId: lessonId,
                scenario: scenarioResponse.scenario
            )
            // Text is fetched eagerly (good for latency), but NOT presented
            // (synthesized/played/appended) yet -- see presentOpeningLineIfNeeded().
            pendingOpeningLine = ConversationMessage(speaker: .npc, text: opening.openingLine, characterName: opening.character)
            history = [HistoryTurn(role: "npc", text: opening.openingLine, character: opening.character)]
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
        isLoadingScenario = false
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
        // Deliberate beat so the user actually sees the scene/character
        // first, rather than being hit with dialogue the instant the
        // roleplay screen appears. A real `try` (not `try?`) matters here:
        // SwiftUI cancels this .task's underlying Task when the roleplay
        // view disappears, which makes Task.sleep throw CancellationError --
        // `try?` was silently swallowing that and falling through to
        // presentNPCMessage() (and thus playing audio) even after the user
        // had already left. Letting the throw propagate aborts here instead.
        do {
            try await Task.sleep(nanoseconds: 1_000_000_000)
        } catch {
            return
        }
        await presentNPCMessage(opening)
    }

    /// Immediately halts any currently-playing NPC speech. Call when the
    /// roleplay screen disappears -- audio must never keep playing once the
    /// user has left, regardless of how far into the pipeline (pre-delay,
    /// synthesis, or active playback) things had gotten. The pre-delay case
    /// is separately handled by presentOpeningLineIfNeeded()'s cancellation
    /// above; this covers the case where playback had already started.
    @available(iOS 17.0, *)
    func stopSpeaking() {
        NPCVoiceService.shared.stop()
    }

    func sendUserResponse(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSendingTurn, !ended else { return }
        guard Self.useMockDataForUITesting || scenario != nil else { return }

        messages.append(ConversationMessage(speaker: .user, text: trimmed))
        let historyBeforeThisTurn = history
        history.append(HistoryTurn(role: "user", text: trimmed, character: nil))
        turnNumber += 1
        isSendingTurn = true
        errorMessage = nil

        if Self.useMockDataForUITesting {
            await mockSendUserResponse()
            isSendingTurn = false
            return
        }

        guard let scenario else { isSendingTurn = false; return }

        do {
            let result = try await ConversationEngineClient.fetchTurn(
                lessonId: lessonId,
                scenario: scenario,
                history: historyBeforeThisTurn,
                metCriteria: metCriteria,
                turnNumber: turnNumber,
                userResponse: trimmed
            )
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
        }
        isSendingTurn = false
    }

    private func loadFeedback() async {
        guard let scenario, let resolution else { return }
        do {
            feedback = try await ConversationEngineClient.fetchFeedback(
                lessonId: lessonId,
                scenario: scenario,
                history: history,
                metCriteria: metCriteria,
                deductionCount: deductionCount,
                resolution: resolution,
                empathyLevels: empathyLevels
            )
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }

    // MARK: - Mock content (UI testing only, see useMockDataForUITesting)

    // Looked up by lessonId so every one of the 20 lessons gets its own
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
        let reply = mockReplies[min(turnNumber - 1, mockReplies.count - 1)]

        await presentNPCMessage(ConversationMessage(speaker: .npc, text: reply, characterName: character?.name ?? mockContent.character.name))
        history.append(HistoryTurn(role: "npc", text: reply, character: character?.name))

        if turnNumber - 1 < criteria.count {
            let newlyMet = criteria[turnNumber - 1]
            if !metCriteria.contains(newlyMet) { metCriteria.append(newlyMet) }
        }

        if turnNumber >= mockReplies.count {
            ended = true
            resolution = "approving"
            loadMockFeedback()
        }
    }

    private func loadMockFeedback() {
        feedback = FeedbackResponse(
            checklist: criteria.map { ChecklistEntry(criterion: $0, met: metCriteria.contains($0)) },
            deductionCount: deductionCount,
            empathySummary: EmpathySummary(strong: 2, adequate: 1, minimal: 0),
            resolution: resolution,
            feedbackLine: mockContent.feedbackLine
        )
    }

    private func friendlyMessage(for error: Error) -> String {
        if let engineError = error as? ConversationEngineError {
            return engineError.localizedDescription
        }
        return "Couldn't reach the local conversation-engine server at \(ConversationEngineClient.baseURL.absoluteString). " +
            "Make sure it's running (`npm start` in conversation-engine/). (\(error.localizedDescription))"
    }
}
