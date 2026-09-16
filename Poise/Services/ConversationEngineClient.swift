import Foundation

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

struct OpeningResponse: Codable {
    let openingLine: String
    let character: String
}

struct HistoryTurn: Codable {
    let role: String // "npc" or "user"
    let text: String
    let character: String?
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

enum ConversationEngineError: LocalizedError {
    case server(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .server(let message): return message
        case .invalidResponse: return "The server sent back something unexpected."
        }
    }
}

enum ConversationEngineClient {
    static let baseURL = URL(string: "http://localhost:3000")!

    static func fetchScenario(lessonId: String) async throws -> ScenarioResponse {
        try await post("api/scenario", body: ["lessonId": lessonId])
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
        userResponse: String
    ) async throws -> TurnResponse {
        try await post("api/turn", body: [
            "lessonId": lessonId,
            "scenario": scenarioPayload(scenario),
            "history": history.map(historyPayload),
            "metCriteria": metCriteria,
            "turnNumber": turnNumber,
            "userResponse": userResponse,
        ])
    }

    static func fetchFeedback(
        lessonId: String,
        scenario: EngineScenario,
        history: [HistoryTurn],
        metCriteria: [String],
        deductionCount: Int,
        resolution: String,
        empathyLevels: [String]
    ) async throws -> FeedbackResponse {
        try await post("api/feedback", body: [
            "lessonId": lessonId,
            "scenario": scenarioPayload(scenario),
            "history": history.map(historyPayload),
            "metCriteria": metCriteria,
            "deductionCount": deductionCount,
            "resolution": resolution,
            "empathyLevels": empathyLevels,
        ])
    }

    private static func scenarioPayload(_ scenario: EngineScenario) -> [String: Any] {
        ["briefing": scenario.briefing, "criteria": scenario.criteria]
    }

    private static func historyPayload(_ turn: HistoryTurn) -> [String: Any] {
        var dict: [String: Any] = ["role": turn.role, "text": turn.text]
        if let character = turn.character { dict["character"] = character }
        return dict
    }

    private static func post<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ConversationEngineError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
                ?? "Server error (\(http.statusCode))"
            throw ConversationEngineError.server(message)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
