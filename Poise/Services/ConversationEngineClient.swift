import Foundation
import RevenueCat

// Talks to the local conversation-engine Node server (see
// conversation-engine/server/index.js) over plain HTTP, for lessons wired
// live (see `LessonNode.engineLessonId`). Dev/verification-only for now:
// points at localhost, no auth, no production endpoint yet.

struct EngineScenario: Codable, Hashable {
    // `var`, not `let`: the custom-scenario builder lets the user hand-edit
    // a generated scenario before starting practice (see
    // CustomScenarioFlowView). Confirmed safe -- this type is never used as
    // a Set/Dictionary key anywhere.
    var briefing: String
    var criteria: [String]
}

struct EngineLessonSummary: Codable, Hashable {
    let id: String
    let unit: String
    // `var`, not `let`, for the same hand-edit reason as EngineScenario above.
    var title: String
    let isCheckpoint: Bool
    var character: EngineCharacter
    // Only present for a custom scenario (see LessonReference.custom below) --
    // a built-in lesson's persona notes and criteria live server-side in
    // lessons.js and never need to round-trip through the client. A custom
    // lesson isn't in that static list, so the server hands both back once,
    // at generation time, and the client carries them on every later call.
    var personaNotes: String? = nil
    var criteria: [String]? = nil
}

struct ScenarioResponse: Codable {
    let lesson: EngineLessonSummary
    let scenario: EngineScenario
}

// Identifies which lesson a request is about: a built-in lesson (looked up
// server-side by id, same as always) or a custom one generated on the fly
// from a user's own prompt (see generateCustomScenario below), which isn't
// in the server's static list, so the client resends the full lesson object
// on every call instead of just an id.
enum LessonReference {
    case builtIn(String)
    case custom(EngineLessonSummary)

    var lessonId: String {
        switch self {
        case .builtIn(let id): return id
        case .custom(let summary): return summary.id
        }
    }
}

struct RedeemResponse: Codable {
    let energy: ServerEnergy
}

struct OpeningResponse: Codable {
    let openingLine: String
    let character: String
}

struct HistoryTurn: Codable {
    let role: String // "npc" or "user"
    let text: String
    let character: String?
}

// The server's view of the user's energy, attached to every response that
// touches it. Once the app is on the live path this is the number that is
// true; the client's own bookkeeping remains for mock mode and instant
// display but adopts this whenever it arrives.
struct ServerEnergy: Codable {
    let remaining: Int
    let cap: Int
    let nextRegenAt: String?

    var nextRegenDate: Date? {
        nextRegenAt.flatMap { ISO8601DateFormatter.withFractionalSeconds.date(from: $0) }
    }
}

private extension ISO8601DateFormatter {
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

struct TurnResponse: Codable {
    let npc_reply: String
    let appropriateness: String
    let respect_and_empathy: String
    let newly_met_criteria: [String]
    let updated_met_criteria: [String]
    let deduction: Bool
    let ended: Bool
    let resolution: String?
    let character: String
    // Issued on turn 1 when the conversation is paid for; must be sent back on
    // every later turn and on feedback. Absent on turns after the first.
    var conversationToken: String? = nil
    var energy: ServerEnergy? = nil
}

struct ChecklistEntry: Codable, Identifiable {
    var id: String { criterion }
    let criterion: String
    let met: Bool
}

struct EmpathySummary: Codable {
    let strong: Int
    let adequate: Int
    let minimal: Int
}

struct SkillScore: Codable {
    let level: String
    let note: String

    var skillLevel: SkillLevel {
        switch level {
        case "needs_work": return .needsWork
        case "developing": return .developing
        case "solid": return .solid
        case "strong": return .strong
        default: return .developing
        }
    }
}

struct SkillScores: Codable {
    let clarity: SkillScore
    let empathy: SkillScore
    let resolution: SkillScore
    // Nil whenever no turn in the conversation had usable recorded audio --
    // absent, not a low score, since there's nothing to grade delivery from.
    // Optional (with a decode default) so a response from an engine that
    // doesn't send it yet still decodes.
    var delivery: SkillScore? = nil

    subscript(skill: PoiseSkill) -> SkillScore? {
        switch skill {
        case .clarity: return clarity
        case .empathy: return empathy
        case .resolution: return resolution
        case .delivery: return delivery
        }
    }
}

struct FeedbackResponse: Codable {
    let checklist: [ChecklistEntry]
    let deductionCount: Int
    let empathySummary: EmpathySummary
    let resolution: String?
    let feedbackLine: String
    // Optional so a response from an older engine still decodes.
    var skills: SkillScores? = nil
    var energy: ServerEnergy? = nil

    // The engine grades these over the whole transcript and explains each one.
    // The derived fallbacks below cover a response without them -- an older
    // engine, or the offline mock path -- in which case there is no note,
    // because inventing an explanation would be worse than showing none.
    var skillLevels: [PoiseSkill: SkillLevel] {
        if let skills {
            var levels: [PoiseSkill: SkillLevel] = [
                .clarity: skills.clarity.skillLevel,
                .empathy: skills.empathy.skillLevel,
                .resolution: skills.resolution.skillLevel,
            ]
            // Absent, not defaulted -- see SkillScores.delivery's doc. A
            // missing key here (not a synthesized level) is what tells
            // SkillScoreCard to leave the chip off entirely.
            if let delivery = skills.delivery { levels[.delivery] = delivery.skillLevel }
            return levels
        }
        return [.clarity: clarityLevel, .empathy: empathyLevel, .resolution: resolutionLevel]
    }

    // Only the engine writes these. There is no derived fallback: a note has
    // to point at something that actually happened in the conversation, and
    // nothing the app can compute locally does that. An earlier version
    // rendered "1 of 3 things this scenario was looking for came through" --
    // a count dressed up as an explanation, and on a checkpoint it dangled
    // two criteria the screen deliberately withholds. Better to show the
    // level alone than to imply an explanation that isn't there.
    func note(for skill: PoiseSkill) -> String? {
        skills?[skill]?.note
    }

    // Coarse levels are still derivable from signals the engine returns even
    // when it sends no `skills` block. A level is a rough judgement and these
    // inputs genuinely support one; that is why the fallback survives here and
    // not for the notes.
    private var clarityLevel: SkillLevel {
        guard !checklist.isEmpty else { return .developing }
        let ratio = Double(checklist.filter(\.met).count) / Double(checklist.count)
        switch ratio {
        case 1: return .strong
        case 0.6...: return .solid
        case 0.3...: return .developing
        default: return .needsWork
        }
    }

    private var empathyLevel: SkillLevel {
        let total = empathySummary.strong + empathySummary.adequate + empathySummary.minimal
        guard total > 0 else { return .developing }
        if empathySummary.minimal > empathySummary.strong { return .needsWork }
        if empathySummary.minimal > 0 { return .developing }
        return empathySummary.strong >= empathySummary.adequate ? .strong : .solid
    }

    private var resolutionLevel: SkillLevel {
        switch resolution {
        case "approving": return .strong
        case "scaled": return .solid
        case "negative": return .needsWork
        default: return .developing
        }
    }
}

// The body of a non-2xx engine response. `energy` rides along on a 402 so
// the out-of-energy message can say when the next unit lands.
private struct EngineErrorBody: Decodable {
    let error: String?
    let energy: ServerEnergy?
}

private struct EnergyResponse: Decodable {
    let energy: ServerEnergy
}

enum ConversationEngineError: LocalizedError {
    case server(String)
    case invalidResponse
    // 401: app key or conversation token rejected.
    case unauthorized(String)
    // 402: the server's ledger says zero energy. Carries the state so the
    // message can say when the next unit lands, matching the in-app modal.
    case outOfEnergy(ServerEnergy?)
    // 429: too many generation requests.
    case rateLimited(String)

    var errorDescription: String? {
        switch self {
        case .server(let message): return message
        case .invalidResponse: return "The server sent back something unexpected."
        case .unauthorized(let message): return message
        case .outOfEnergy(let energy):
            var text = "Starting a conversation costs 1 energy, and you have none left."
            if let date = energy?.nextRegenDate {
                let remaining = max(0, date.timeIntervalSinceNow)
                let h = Int(remaining) / 3600, m = (Int(remaining) % 3600) / 60
                text += h > 0 ? " Next one in \(h)h \(m)m." : " Next one in \(max(1, m))m."
            }
            return text
        case .rateLimited(let message): return message
        }
    }
}

enum ConversationEngineClient {
    // Debug points at a local server (`npm start` in conversation-engine/)
    // for iterating without touching production. Release talks to the real
    // deployed engine -- AWS Lightsail, same account as Bedrock, HTTPS via
    // Let's Encrypt (see conversation-engine's deployment notes).
    static let baseURL: URL = {
        #if DEBUG
        return URL(string: "http://localhost:3000")!
        #else
        return URL(string: "https://api.sapersolutions.com")!
        #endif
    }()

    static func fetchScenario(lessonId: String) async throws -> ScenarioResponse {
        try await post("api/scenario", body: ["lessonId": lessonId])
    }

    // Read-only: the server's real number, so the app can show it correctly
    // on launch/foreground instead of only ever finding out via a 402 from
    // actually trying to spend a unit (see server/index.js's own comment on
    // GET /api/energy -- this call existed on the server from the start;
    // nothing on the client was ever calling it). Callers should treat
    // failure as best-effort and silently keep whatever was last known --
    // this is a background sync, not something to surface as an error.
    static func fetchEnergy() async throws -> ServerEnergy {
        let response: EnergyResponse = try await get("api/energy")
        return response.energy
    }

    // Shipaton-judge code redemption (see conversation-engine/server/energy.js:
    // redeemJudgeCode). On success the account gets a large standing energy
    // cap; the caller should immediately adopt the returned energy state.
    static func redeemCode(_ code: String) async throws -> RedeemResponse {
        try await post("api/redeem", body: ["code": code])
    }

    // Designs a one-off lesson + first scenario from the user's own
    // plain-language prompt (Poise Pro's custom-scenario builder). The
    // returned lesson isn't in the server's static list -- callers carry it
    // forward via LessonReference.custom on every later opening/turn/
    // feedback call for this conversation.
    static func generateCustomScenario(prompt: String) async throws -> ScenarioResponse {
        try await post("api/custom-scenario", body: ["prompt": prompt])
    }

    static func fetchOpening(_ lesson: LessonReference, scenario: EngineScenario) async throws -> OpeningResponse {
        try await post("api/opening", body: lessonPayload(lesson).merging([
            "scenario": scenarioPayload(scenario),
        ]) { _, new in new })
    }

    static func fetchTurn(
        _ lesson: LessonReference,
        scenario: EngineScenario,
        history: [HistoryTurn],
        metCriteria: [String],
        turnNumber: Int,
        userResponse: String,
        conversationToken: String?
    ) async throws -> TurnResponse {
        try await post("api/turn", body: lessonPayload(lesson).merging([
            "scenario": scenarioPayload(scenario),
            "history": history.map(historyPayload),
            "metCriteria": metCriteria,
            "turnNumber": turnNumber,
            "userResponse": userResponse,
        ]) { _, new in new }, conversationToken: conversationToken)
    }

    static func fetchFeedback(
        _ lesson: LessonReference,
        scenario: EngineScenario,
        history: [HistoryTurn],
        metCriteria: [String],
        deductionCount: Int,
        resolution: String,
        empathyLevels: [String],
        conversationToken: String?,
        // Reduced on-device voice-analysis output (coverage + aggregates
        // only -- see LiveLessonViewModel.finishVoiceSessionAndSummarize).
        // Nil whenever no user turn had usable audio, analysis failed, or
        // the feature is unavailable; delivery grading is additive, never
        // required for feedback to work.
        voiceSummary: [String: Any]? = nil
    ) async throws -> FeedbackResponse {
        var body = lessonPayload(lesson).merging([
            "scenario": scenarioPayload(scenario),
            "history": history.map(historyPayload),
            "metCriteria": metCriteria,
            "deductionCount": deductionCount,
            "resolution": resolution,
            "empathyLevels": empathyLevels,
        ]) { _, new in new }
        if let voiceSummary { body["voiceSummary"] = voiceSummary }
        return try await post("api/feedback", body: body, conversationToken: conversationToken)
    }

    // Built-in lessons send just an id, looked up server-side. A custom
    // lesson isn't in that static list, so its full shape rides along
    // instead -- matching isValidCustomLesson's expectations in index.js.
    private static func lessonPayload(_ lesson: LessonReference) -> [String: Any] {
        switch lesson {
        case .builtIn(let id):
            return ["lessonId": id]
        case .custom(let summary):
            var character: [String: Any] = ["name": summary.character.name, "role": summary.character.role]
            if let relationship = summary.character.relationship { character["relationship"] = relationship }
            if let gender = summary.character.gender { character["gender"] = gender }
            return ["lesson": [
                "id": summary.id,
                "title": summary.title,
                "personaNotes": summary.personaNotes ?? "",
                "criteria": summary.criteria ?? [],
                "character": character,
            ]]
        }
    }

    private static func scenarioPayload(_ scenario: EngineScenario) -> [String: Any] {
        ["briefing": scenario.briefing, "criteria": scenario.criteria]
    }

    private static func historyPayload(_ turn: HistoryTurn) -> [String: Any] {
        var dict: [String: Any] = ["role": turn.role, "text": turn.text]
        if let character = turn.character { dict["character"] = character }
        return dict
    }

    private static func post<T: Decodable>(
        _ path: String,
        body: [String: Any],
        conversationToken: String? = nil
    ) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Both required by the server on every route except the lesson list.
        // The user id is RevenueCat's, so the server can verify Pro itself
        // rather than take the client's word for it.
        request.setValue(EngineConfig.appKey, forHTTPHeaderField: "X-Poise-App-Key")
        request.setValue(Purchases.shared.appUserID, forHTTPHeaderField: "X-Poise-User")
        if let conversationToken {
            request.setValue(conversationToken, forHTTPHeaderField: "X-Poise-Conversation")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await perform(request)
    }

    private static func get<T: Decodable>(_ path: String) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "GET"
        request.setValue(EngineConfig.appKey, forHTTPHeaderField: "X-Poise-App-Key")
        request.setValue(Purchases.shared.appUserID, forHTTPHeaderField: "X-Poise-User")
        return try await perform(request)
    }

    private static func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ConversationEngineError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let parsed = try? JSONDecoder().decode(EngineErrorBody.self, from: data)
            let message = parsed?.error ?? "Server error (\(http.statusCode))"
            switch http.statusCode {
            case 401: throw ConversationEngineError.unauthorized(message)
            case 402:
                if let energy = parsed?.energy { await LearnProgressStore.shared.applyServerEnergy(energy) }
                throw ConversationEngineError.outOfEnergy(parsed?.energy)
            case 429: throw ConversationEngineError.rateLimited(message)
            default: throw ConversationEngineError.server(message)
            }
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
