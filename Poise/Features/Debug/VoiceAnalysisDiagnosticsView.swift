#if DEBUG
import SwiftUI
import UniformTypeIdentifiers
import PoiseVoiceAnalysis

struct VoiceAnalysisDiagnosticsButton: View {
    @State private var isPresented = false

    var body: some View {
        Button { isPresented = true } label: {
            Label("Voice analysis", systemImage: "waveform")
                .font(PoiseType.body())
                .foregroundStyle(Color.poiseBlue)
        }
        .sheet(isPresented: $isPresented) {
            NavigationStack { VoiceAnalysisDiagnosticsView() }
        }
    }
}

private struct VoiceJSONDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct VoiceAnalysisDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var sessionID = UUID()

    var body: some View {
        VoiceAnalysisDiagnosticSession()
            .id(sessionID)
            .navigationTitle("Voice analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("New", systemImage: "arrow.counterclockwise") { sessionID = UUID() }
                }
            }
    }
}

private struct VoiceAnalysisDiagnosticSession: View {
    @StateObject private var speech = SpeechRecognitionService()
    @StateObject private var session = VoiceConversationSession()
    @State private var response = ""
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var exporting = false
    @State private var operation: Task<Void, Never>?

    private var sealed: Bool { session.isClosed || session.isFinishing }

    var body: some View {
        Form {
            Section("Local conversation") {
                ForEach(session.entries) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.role == .npc ? "NPC" : "You").font(.caption.bold())
                        Text(entry.text)
                        if entry.role == .user {
                            Text(status(entry)).font(.caption).foregroundStyle(.secondary)
                            if case .analyzed(let report) = entry.voice {
                                DisclosureGroup("Analysis JSON") { jsonText(report.json) }
                            }
                        }
                    }
                }
            }

            if !sealed {
                Section("Your turn") {
                    TextField("Response", text: $response, axis: .vertical)
                        .lineLimit(3...8)
                        .disabled(busy)
                    HStack {
                        Button {
                            speech.toggleListening()
                        } label: {
                            Label(speech.isListening ? "Stop" : "Record", systemImage: speech.isListening ? "stop.fill" : "mic.fill")
                        }
                        .disabled(busy || speech.isFinalizing)
                        Spacer()
                        Button("Accept turn", systemImage: "arrow.up") { acceptTurn() }
                            .disabled(busy || speech.isStarting || response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .buttonStyle(.borderless)
                    if speech.isStarting || speech.isFinalizing { ProgressView() }
                    if let message = speech.errorMessage { Text(message).foregroundStyle(.red) }
                }
                Section {
                    Button("Build payload", systemImage: "doc.badge.gearshape") { finish() }
                        .disabled(busy || speech.isCapturing || !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !session.entries.contains(where: { $0.role == .user }))
                }
            }

            Section("Pipeline") {
                LabeledContent("Accepted user turns", value: "\(session.entries.filter { $0.role == .user }.count)")
                LabeledContent("Pending analysis", value: "\(session.pendingCount)")
                if busy || session.isFinishing { ProgressView("Processing") }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                if let payload = session.payload {
                    Button("Export JSON", systemImage: "square.and.arrow.up") { exporting = true }
                    DisclosureGroup("Conversation payload") { jsonText(payload.json) }
                }
            }
        }
        .tint(Color.poiseBlue)
        .task {
            guard session.entries.isEmpty else { return }
            do { try session.appendNPC(id: UUID().uuidString, text: "Tell me about something you enjoyed this week.", speakerName: "Practice partner") }
            catch { errorMessage = error.localizedDescription }
        }
        .onChange(of: speech.transcript) { _, value in if !busy { response = value } }
        .onChange(of: speech.isListening) { _, value in if value { response = "" } }
        .onDisappear {
            operation?.cancel()
            speech.discardDraft()
            session.cancel()
        }
        .fileExporter(isPresented: $exporting,
                      document: VoiceJSONDocument(data: session.payload?.json ?? Data()),
                      contentType: .json, defaultFilename: "voice-analysis-\(session.conversationID)") { result in
            if case .failure(let error) = result { errorMessage = error.localizedDescription }
        }
    }

    private func status(_ entry: VoiceConversationSession.Entry) -> String {
        if entry.isPending { return "Analyzing" }
        switch entry.voice {
        case .analyzed: return "Analyzed"
        case .typed: return "Typed - no audio"
        case .missingAudio: return "Missing audio"
        case .failed(let reason): return "Unavailable: \(reason.rawValue)"
        case nil: return ""
        }
    }

    private func jsonText(_ data: Data) -> some View {
        Text(String(decoding: data, as: UTF8.self))
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func acceptTurn() {
        let text = response.trimmingCharacters(in: .whitespacesAndNewlines)
        busy = true
        errorMessage = nil
        operation = Task {
            defer { busy = false }
            let input = await speech.finalizedInput()
            guard !Task.isCancelled else { return }
            do {
                try session.appendUser(id: UUID().uuidString, text: text, input: input)
                response = ""
                speech.discardDraft()
                try session.appendNPC(id: UUID().uuidString, text: "Thanks for sharing. What else would you like to add?", speakerName: "Practice partner")
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func finish() {
        busy = true
        errorMessage = nil
        operation = Task {
            defer { busy = false }
            do { _ = try await session.finish() }
            catch is CancellationError { }
            catch { errorMessage = error.localizedDescription }
        }
    }
}
#endif
