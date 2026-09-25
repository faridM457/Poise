import Foundation

@MainActor
protocol ScenarioGenerating {
    func generate(from prompt: String) async throws -> CustomScenario
}

@MainActor
struct LocalMockScenarioGenerator: ScenarioGenerating {
    func generate(from prompt: String) async throws -> CustomScenario {
        let normalized = prompt.lowercased()

        if normalized.contains("raise") || normalized.contains("salary") || normalized.contains("pay") {
            return Self.raiseScenario
        }
        if normalized.contains("feedback") || normalized.contains("performance") || normalized.contains("critique") {
            return Self.feedbackScenario
        }
        if normalized.contains("customer") || normalized.contains("client") || normalized.contains("complaint") || normalized.contains("upset") {
            return Self.customerScenario
        }
        if normalized.contains("interview") || normalized.contains("job") || normalized.contains("hiring") {
            return Self.interviewScenario
        }
        return Self.genericScenario
    }

    private static let raiseScenario = CustomScenario(
        id: "custom-salary-negotiation",
        title: "Salary negotiation",
        situation: "You are meeting with your manager after successfully leading a major project.",
        userRole: "Team member",
        counterpartRole: "Manager",
        goals: ["Explain your impact", "Make a clear request", "Respond professionally"],
        openingLine: "Thanks for meeting with me. What would you like to discuss?",
        counterpartReplies: [
            "I appreciate the context. What outcomes from the project best show your impact?",
            "That's helpful. What adjustment are you asking us to consider?",
            "I can't promise an answer today, but you've made a clear case. I'll review it with leadership."
        ]
    )

    private static let feedbackScenario = CustomScenario(
        id: "custom-difficult-feedback",
        title: "Difficult feedback",
        situation: "A colleague's missed handoffs have affected the team's work, and you need to address the pattern constructively.",
        userRole: "Project teammate",
        counterpartRole: "Colleague",
        goals: ["Describe specific behavior", "Explain the impact", "Agree on a next step"],
        openingLine: "You wanted to talk about how the project has been going?",
        counterpartReplies: [
            "I didn't realize the handoffs were creating that much extra work. Can you give me an example?",
            "I understand the impact now. What would make the next handoff work better?",
            "That sounds fair. I'll use the checklist and flag delays earlier."
        ]
    )

    private static let customerScenario = CustomScenario(
        id: "custom-upset-customer",
        title: "Upset customer",
        situation: "A customer is frustrated because a delivery arrived late and disrupted an important deadline.",
        userRole: "Customer support specialist",
        counterpartRole: "Customer",
        goals: ["Acknowledge the frustration", "Clarify the problem", "Offer a practical resolution"],
        openingLine: "This delivery was late, and it put my whole deadline at risk.",
        counterpartReplies: [
            "I appreciate you acknowledging it, but I need to know what happened.",
            "That's clearer. What can you do to fix this for me now?",
            "That resolution works for me. Please send the confirmation today."
        ]
    )

    private static let interviewScenario = CustomScenario(
        id: "custom-job-interview",
        title: "Job interview",
        situation: "You are interviewing for a role that requires collaboration, sound judgment, and clear communication.",
        userRole: "Candidate",
        counterpartRole: "Hiring manager",
        goals: ["Give a concise example", "Connect experience to the role", "Ask a thoughtful question"],
        openingLine: "Tell me about a time you handled a difficult problem with a team.",
        counterpartReplies: [
            "What was your specific contribution to that outcome?",
            "How would that experience help you succeed in this role?",
            "Thank you. What would you like to know about the team?"
        ]
    )

    private static let genericScenario = CustomScenario(
        id: "custom-professional-conversation",
        title: "Professional conversation",
        situation: "You are preparing for an important workplace conversation where clarity and composure matter.",
        userRole: "Team member",
        counterpartRole: "Colleague",
        goals: ["State the purpose clearly", "Listen and respond", "Agree on a next step"],
        openingLine: "Thanks for reaching out. What would you like us to work through?",
        counterpartReplies: [
            "I understand the main concern. Can you share a specific example?",
            "That makes sense. What outcome would you like from this conversation?",
            "I can support that next step. Let's follow up after we've tried it."
        ]
    )
}
