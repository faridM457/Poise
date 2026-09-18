import Foundation
import RevenueCat

// Talks to the local conversation-engine Node server (see
// conversation-engine/server/index.js) over plain HTTP, for lessons wired
// live (see `LessonNode.engineLessonId`). Dev/verification-only for now:
// points at localhost, no auth, no production endpoint yet.

struct EngineScenario: Codable, Hashable {
    let briefing: String
    let criteria: [String]
}

struct EngineLessonSummary: Codable {
    let id: String
    let unit: String
    let title: String
    let isCheckpoint: Bool
    let character: EngineCharacter
}

struct ScenarioResponse: Codable {
    let lesson: EngineLessonSummary
    let scenario: EngineScenario
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

    subscript(skill: PoiseSkill) -> SkillScore {
        switch skill {
        case .clarity: return clarity
        case .empathy: return empathy
        case .resolution: return resolution
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
            return [
                .clarity: skills.clarity.skillLevel,
                .empathy: skills.empathy.skillLevel,
                .resolution: skills.resolution.skillLevel,
            ]
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
        skills?[skill].note
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

    // Shipaton-judge code redemption (see conversation-engine/server/energy.js:
    // redeemJudgeCode). On success the account gets a large standing energy
    // cap; the caller should immediately adopt the returned energy state.
    static func redeemCode(_ code: String) async throws -> RedeemResponse {
        try await post("api/redeem", body: ["code": code])
    }

    static func fetchOpening(lessonId: String, scenario: EngineScenario) async throws -> OpeningResponse {
        try await post("api/opening", body: [
            "lessonId": lessonId,
            "scenario": scenarioPayload(scenario),
        ])
    }

    static func fetchTurn(
        lessonId: String,
        scenario: EngineScenario,
        history: [HistoryTurn],
        metCriteria: [String],
        turnNumber: Int,
        userResponse: String,
        conversationToken: String?
    ) async throws -> TurnResponse {
        try await post("api/turn", body: [
            "lessonId": lessonId,
            "scenario": scenarioPayload(scenario),
            "history": history.map(historyPayload),
            "metCriteria": metCriteria,
            "turnNumber": turnNumber,
            "userResponse": userResponse,
        ], conversationToken: conversationToken)
    }

    static func fetchFeedback(
        lessonId: String,
        scenario: EngineScenario,
        history: [HistoryTurn],
        metCriteria: [String],
        deductionCount: Int,
        resolution: String,
        empathyLevels: [String],
        conversationToken: String?
    ) async throws -> FeedbackResponse {
        try await post("api/feedback", body: [
            "lessonId": lessonId,
            "scenario": scenarioPayload(scenario),
            "history": history.map(historyPayload),
            "metCriteria": metCriteria,
            "deductionCount": deductionCount,
            "resolution": resolution,
            "empathyLevels": empathyLevels,
        ], conversationToken: conversationToken)
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
