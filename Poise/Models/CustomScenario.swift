import Foundation

struct CustomScenario: Identifiable, Hashable {
    let id: String
    var title: String
    var situation: String
    var userRole: String
    var counterpartRole: String
    var goals: [String]
    let openingLine: String
    let counterpartReplies: [String]

    var isValid: Bool {
        !title.trimmed.isEmpty
            && !situation.trimmed.isEmpty
            && !userRole.trimmed.isEmpty
            && !counterpartRole.trimmed.isEmpty
            && goals.count == 3
            && goals.allSatisfy { !$0.trimmed.isEmpty }
    }
}

extension String {
    fileprivate var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
