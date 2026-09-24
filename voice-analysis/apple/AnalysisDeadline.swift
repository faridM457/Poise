import Foundation

enum AnalysisDeadline {
    /// Cooperative cancellation: structured concurrency keeps ownership until
    /// child work stops. It never abandons a live analyzer in the background.
    static func run<T: Sendable>(seconds: Double, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        guard seconds.isFinite, seconds > 0, seconds <= 1800 else { throw VoiceAnalysisError.invalidTimeout }
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw VoiceAnalysisError.timedOut
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }
}
