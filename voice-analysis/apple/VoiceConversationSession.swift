import Combine
import Foundation

public enum VoiceTurnInput: Sendable {
    case recorded(RecordedVoiceClip)
    case typed
    case missingAudio
    case failed(VoiceTurnFailure)
}

/// Shared by the lesson and the offline diagnostic screen. No recording or networking.
@MainActor
public final class VoiceConversationSession: ObservableObject {
    public struct Entry: Identifiable, Sendable {
        public let id: String
        public let role: ConversationVoiceTurn.Role
        public let text: String
        public let speakerName: String?
        public fileprivate(set) var voice: UserVoiceAnalysis?
        public fileprivate(set) var isPending: Bool
    }

    public let conversationID: String
    @Published public private(set) var entries: [Entry] = []
    @Published public private(set) var payload: ConversationVoicePayload?
    @Published public private(set) var isFinishing = false
    @Published public private(set) var isClosed = false
    public var pendingCount: Int { entries.filter(\.isPending).count }

    private struct Job {
        let id: String
        let clip: RecordedVoiceClip
    }
    private var jobs: [Job] = []
    private var worker: Task<Void, Never>?
    private let analyze: @Sendable (URL) async throws -> VoiceAnalysisReport
    private var recordingSeconds = 0.0
    // Retained past analysis so a caller can offer playback of what the user
    // actually said -- otherwise each RecordedVoiceClip's deinit deletes its
    // temp file the moment `drain()`'s loop body releases the last strong
    // reference to it. Cleared by releaseRecordings() once the caller is
    // done (e.g. the scorecard is dismissed); also drops with this object's
    // own deinit if that's never called explicitly.
    private var recordedClips: [String: RecordedVoiceClip] = [:]

    public convenience init(conversationID: String = UUID().uuidString) {
        let analyzer = OnDeviceVoiceAnalyzer()
        self.init(conversationID: conversationID, analyze: { try await analyzer.analyze(fileURL: $0) })
    }

    init(conversationID: String, analyze: @escaping @Sendable (URL) async throws -> VoiceAnalysisReport) {
        self.conversationID = conversationID
        self.analyze = analyze
    }

    public func appendNPC(id: String, text: String, speakerName: String? = nil) throws {
        try validate(id: id, text: text, role: .npc)
        entries.append(Entry(id: id, role: .npc, text: text, speakerName: speakerName, voice: nil, isPending: false))
    }

    public func appendUser(id: String, text: String, input: VoiceTurnInput) throws {
        try validate(id: id, text: text, role: .user)
        let voice: UserVoiceAnalysis
        var pending = false
        switch input {
        case .typed: voice = .typed
        case .missingAudio: voice = .missingAudio
        case .failed(let code): voice = .failed(code)
        case .recorded(let clip):
            // Preserve the dialogue when the recording budget is exhausted.
            if recordingSeconds + clip.durationSeconds > 300.05 {
                voice = .failed(.invalidAudio)
            } else {
                recordingSeconds += clip.durationSeconds
                jobs.append(Job(id: id, clip: clip))
                voice = .missingAudio
                pending = true
            }
        }
        entries.append(Entry(id: id, role: .user, text: text, speakerName: nil, voice: voice, isPending: pending))
        if worker == nil, !jobs.isEmpty {
            worker = Task { [weak self] in await self?.drain() }
        }
    }

    /// Seals accepted dialogue, waits for queued analysis, then assembles exactly once.
    public func finish() async throws -> ConversationVoicePayload {
        if let payload { return payload }
        guard !isClosed else { throw CancellationError() }
        isFinishing = true
        defer { isFinishing = false }
        await worker?.value
        try Task.checkCancellation()
        guard !isClosed else { throw CancellationError() }
        let result = try ConversationVoicePayload.build(conversationID: conversationID, turns: entries.map {
            ConversationVoiceTurn(id: $0.id, role: $0.role, text: $0.text, speakerName: $0.speakerName, voice: $0.voice)
        })
        payload = result
        isClosed = true
        return result
    }

    public func cancel() {
        isClosed = true
        worker?.cancel()
        jobs.removeAll()
        for index in entries.indices where entries[index].isPending {
            entries[index].voice = .failed(.cancelled)
            entries[index].isPending = false
        }
        // The active job owns its clip until the analyzer has finished cleanup.
    }

    /// The turn's recorded audio, still on disk, for playback. Available for
    /// any turn whose recording made it through `drain()` -- regardless of
    /// whether analysis itself succeeded -- until `releaseRecordings()` is
    /// called or this session is deallocated.
    public func recordingURL(forTurnID id: String) -> URL? {
        recordedClips[id]?.fileURL
    }

    /// Deletes every retained recording's temp file (via each RecordedVoiceClip's
    /// own deinit) and drops this session's references to them. Call once the
    /// caller no longer needs playback -- e.g. the scorecard has been dismissed.
    /// Idempotent; safe to call even if nothing was ever retained.
    public func releaseRecordings() {
        recordedClips.removeAll()
    }

    private func validate(id: String, text: String, role: ConversationVoiceTurn.Role) throws {
        guard !isClosed, !isFinishing else { throw VoicePayloadError.invalid("session.closed") }
        guard !entries.contains(where: { $0.id == id }), entries.count < 100,
              role != .user || entries.filter({ $0.role == .user }).count < 20,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.utf8.count <= 20_000,
              entries.reduce(text.utf8.count, { $0 + $1.text.utf8.count }) <= 200_000,
              !id.isEmpty, id.utf8.count <= 128,
              id.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }) else {
            throw VoicePayloadError.invalid("session.turn")
        }
    }

    private func drain() async {
        defer { worker = nil }
        while !jobs.isEmpty, !isClosed {
            let job = jobs.removeFirst()
            recordedClips[job.id] = job.clip
            let result: UserVoiceAnalysis
            do {
                try Task.checkCancellation()
                result = .analyzed(try await analyze(job.clip.fileURL))
            } catch is CancellationError {
                result = .failed(.cancelled)
            } catch VoiceAnalysisError.timedOut {
                result = .failed(.timedOut)
            } catch let error as VoiceAnalysisFailure {
                result = .failed(error.stage == .decoding ? .invalidAudio : error.stage == .transcription ? .transcriptionUnavailable : .analysisFailed)
            } catch {
                result = .failed(.analysisFailed)
            }
            guard !isClosed, let index = entries.firstIndex(where: { $0.id == job.id }) else { continue }
            entries[index].voice = result
            entries[index].isPending = false
        }
    }
}
