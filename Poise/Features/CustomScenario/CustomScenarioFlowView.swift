import SwiftUI

@MainActor
struct CustomScenarioFlowView: View {
    private enum Route: Hashable {
        case preview(EngineLessonSummary, EngineScenario)
    }

    @Environment(\.dismiss) private var dismiss
    @State private var path: [Route] = []
    // Set once the preview screen's "Start Practice" is tapped -- presents
    // the real live lesson flow full-screen (same as every other lesson in
    // the app), rather than pushed as a NavigationStack destination, since
    // LiveLessonFlowView already manages its own full-screen chrome.
    //
    // Lesson and scenario travel together as the cover's single item. They
    // used to be two separate @State values, with the cover's closure
    // reading practiceScenario on its own -- but that closure was evaluated
    // once with practiceScenario still nil, and LiveLessonFlowView's
    // @StateObject view model is only ever built from that first
    // evaluation, so every custom lesson started with an empty briefing and
    // no goals. Bundling them means the closure can only ever see both.
    private struct Practice: Identifiable {
        let lesson: EngineLessonSummary
        let scenario: EngineScenario
        var id: String { lesson.id }
    }
    @State private var practice: Practice?

    var body: some View {
        NavigationStack(path: $path) {
            CustomScenarioBuilderView { lesson, scenario in
                path.append(.preview(lesson, scenario))
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .preview(let lesson, let scenario):
                    CustomScenarioPreviewView(lesson: lesson, scenario: scenario) { editedLesson, editedScenario in
                        practice = Practice(lesson: editedLesson, scenario: editedScenario)
                        OneSignalNotificationService.shared.recordCustomScenarioStarted(id: editedLesson.id)
                    }
                }
            }
        }
        .tint(.poiseBlueDark)
        .fullScreenCover(item: $practice) { practice in
            LiveLessonFlowView(customLesson: practice.lesson, scenario: practice.scenario) { completed in
                // Only a real finish (reached the scorecard), not an early
                // exit via the close button, counts as "completed" here --
                // matches this Bool's meaning everywhere else it's used.
                if completed {
                    OneSignalNotificationService.shared.recordCustomScenarioCompleted(id: practice.lesson.id)
                }
                self.practice = nil
                dismiss()
            }
        }
    }
}

extension EngineLessonSummary: Identifiable {}

private struct CustomScenarioBuilderView: View {
    private enum BuilderState: Equatable {
        case idle
        case generating
        case error(String)
    }

    private struct Example: Identifiable {
        let title: String
        let prompt: String
        var id: String { title }
    }

    private static let characterLimit = 500
    private static let examples = [
        Example(title: "Ask for a raise", prompt: "Ask my manager for a raise after leading a successful project."),
        Example(title: "Give feedback", prompt: "Give a colleague difficult feedback about missed project handoffs."),
        Example(title: "Upset customer", prompt: "Calm an upset customer whose delivery arrived late."),
        Example(title: "Job interview", prompt: "Practice a job interview for a collaborative leadership role.")
    ]

    let onGenerated: (EngineLessonSummary, EngineScenario) -> Void

    @State private var prompt = ""
    @State private var state: BuilderState = .idle
    @FocusState private var promptIsFocused: Bool

    private var trimmedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isGenerating: Bool {
        state == .generating
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    PoiseIconBadge(icon: "ellipsis.message.fill", color: .poiseBlueDark, size: 72)
                        .accessibilityHidden(true)

                    Text("What do you want\nto practice?")
                        .font(PoiseType.largeTitle())
                        .foregroundStyle(Color.poiseNavy)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 12)

                VStack(alignment: .trailing, spacing: 7) {
                    ZStack(alignment: .topLeading) {
                        if prompt.isEmpty {
                            Text("Describe the conversation you want to practice")
                                .font(PoiseType.body())
                                .foregroundStyle(Color.poiseMuted)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 18)
                                .allowsHitTesting(false)
                        }

                        TextEditor(text: $prompt)
                            .font(PoiseType.body())
                            .foregroundStyle(Color.poiseNavy)
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .frame(minHeight: 172)
                            .focused($promptIsFocused)
                            .accessibilityLabel("Practice scenario description")
                    }
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(promptIsFocused ? Color.poiseBlue : Color.poiseBorder, lineWidth: 1.5)
                    )

                    Text("\(prompt.count)/\(Self.characterLimit)")
                        .font(PoiseType.caption())
                        .foregroundStyle(Color.poiseMuted)
                        .accessibilityLabel("\(prompt.count) of \(Self.characterLimit) characters")
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Try an example")
                        .font(PoiseType.body(.bold))
                        .foregroundStyle(Color.poiseNavy)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(Self.examples) { example in
                            Button {
                                prompt = example.prompt
                                promptIsFocused = true
                            } label: {
                                Text(example.title)
                                    .font(PoiseType.subhead(.bold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.82)
                                    .allowsTightening(true)
                                    .frame(maxWidth: .infinity, minHeight: 48)
                            }
                            .foregroundStyle(Color.poiseNavy)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.poiseBorder, lineWidth: 1.5)
                            )
                            .buttonStyle(PoisePressableStyle())
                            .accessibilityHint("Fills the scenario description")
                        }
                    }
                }

                if case .error(let message) = state {
                    PoiseSurfaceCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Scenario couldn't be created", systemImage: "exclamationmark.triangle.fill")
                                .font(PoiseType.body(.bold))
                                .foregroundStyle(Color.poiseOrange)
                            Text(message)
                                .font(PoiseType.subhead())
                                .foregroundStyle(Color.poiseMuted)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Try again", action: createScenario)
                                .buttonStyle(PoiseFlatButtonStyle())
                        }
                    }
                    .accessibilityElement(children: .contain)
                }

                Button(action: createScenario) {
                    if isGenerating {
                        HStack(spacing: 9) {
                            ProgressView().tint(.white)
                            Text("Creating scenario")
                        }
                    } else {
                        Text("Create Scenario")
                    }
                }
                .buttonStyle(PoiseFlatButtonStyle(fullWidth: true))
                .disabled(trimmedPrompt.isEmpty || isGenerating)
                .opacity(trimmedPrompt.isEmpty ? 0.45 : 1)
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.poiseCanvas.ignoresSafeArea())
        .navigationTitle("Create a scenario")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: prompt) { _, newValue in
            if newValue.count > Self.characterLimit {
                prompt = String(newValue.prefix(Self.characterLimit))
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { promptIsFocused = false }
            }
        }
    }

    private func createScenario() {
        guard !trimmedPrompt.isEmpty, !isGenerating else { return }
        let submittedPrompt = trimmedPrompt
        promptIsFocused = false
        state = .generating

        Task { @MainActor in
            do {
                let response = try await ConversationEngineClient.generateCustomScenario(prompt: submittedPrompt)
                state = .idle
                onGenerated(response.lesson, response.scenario)
            } catch {
                state = .error(friendlyMessage(for: error))
            }
        }
    }

    private func friendlyMessage(for error: Error) -> String {
        if let engineError = error as? ConversationEngineError {
            return engineError.localizedDescription
        }
        return "Couldn't reach the conversation engine. Check your connection and try again."
    }
}

private struct CustomScenarioPreviewView: View {
    @State private var lesson: EngineLessonSummary
    @State private var scenario: EngineScenario
    let onStart: (EngineLessonSummary, EngineScenario) -> Void

    @State private var showEditor = false
    @State private var showValidation = false

    init(lesson: EngineLessonSummary, scenario: EngineScenario, onStart: @escaping (EngineLessonSummary, EngineScenario) -> Void) {
        _lesson = State(initialValue: lesson)
        _scenario = State(initialValue: scenario)
        self.onStart = onStart
    }

    private var isValid: Bool {
        !lesson.title.trimmed.isEmpty
            && !lesson.character.name.trimmed.isEmpty
            && !lesson.character.role.trimmed.isEmpty
            && !scenario.briefing.trimmed.isEmpty
            && !scenario.criteria.isEmpty
            && scenario.criteria.allSatisfy { !$0.trimmed.isEmpty }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                previewHeader
                ScenarioDetailCard(icon: "doc.text.fill", title: "Situation", value: scenario.briefing)
                ScenarioDetailCard(
                    icon: "person.2.fill",
                    title: "Who you're talking to",
                    value: lesson.character.relationship.map { "\(lesson.character.name) — \(lesson.character.role) (\($0))" }
                        ?? "\(lesson.character.name) — \(lesson.character.role)"
                )
                goalsCard

                Button("Edit") { showEditor = true }
                    .buttonStyle(PoiseFlatButtonStyle(fill: .poiseSoftBlue, foreground: .poiseBlueDark, fullWidth: true))

                Button("Start Practice") {
                    if isValid { onStart(lesson, scenario) } else { showValidation = true }
                }
                .buttonStyle(PoiseFlatButtonStyle(fullWidth: true))
            }
            .padding(20)
        }
        .background(Color.poiseCanvas.ignoresSafeArea())
        .navigationTitle("Scenario preview")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEditor) {
            CustomScenarioEditorView(lesson: $lesson, scenario: $scenario)
                .presentationBackground(Color.poiseCanvas)
        }
        .alert("Finish the scenario", isPresented: $showValidation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Add a title, the situation, who you're talking to, and every goal before starting practice.")
        }
    }

    private var previewHeader: some View {
        HStack(spacing: 14) {
            PoiseIconBadge(icon: "briefcase.fill", color: .poiseBlueDark, size: 54)
            Text(lesson.title)
                .font(PoiseType.title())
                .foregroundStyle(Color.poiseNavy)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(18)
        .poiseCard(fill: .poisePaleBlue, stroke: .poiseSoftBlue, radius: 20)
        .accessibilityElement(children: .combine)
    }

    private var goalsCard: some View {
        PoiseSurfaceCard {
            HStack(alignment: .top, spacing: 13) {
                PoiseIconBadge(icon: "target", color: .poiseBlueDark, size: 42)
                VStack(alignment: .leading, spacing: 9) {
                    Text("Your goals")
                        .font(PoiseType.body(.bold))
                        .foregroundStyle(Color.poiseNavy)
                    ForEach(scenario.criteria, id: \.self) { goal in
                        Label(goal, systemImage: "checkmark.circle.fill")
                            .font(PoiseType.subhead())
                            .foregroundStyle(Color.poiseNavy)
                            .labelStyle(CustomGoalLabelStyle())
                    }
                }
            }
        }
    }
}

private struct ScenarioDetailCard: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        PoiseSurfaceCard {
            HStack(alignment: .top, spacing: 13) {
                PoiseIconBadge(icon: icon, color: .poiseBlueDark, size: 42)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(PoiseType.body(.bold))
                        .foregroundStyle(Color.poiseNavy)
                    Text(value)
                        .font(PoiseType.subhead())
                        .foregroundStyle(Color.poiseMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct CustomGoalLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            configuration.icon.foregroundStyle(Color.poiseBlueDark)
            configuration.title
        }
    }
}

private struct CustomScenarioEditorView: View {
    @Binding var lesson: EngineLessonSummary
    @Binding var scenario: EngineScenario
    @Environment(\.dismiss) private var dismiss
    @State private var draftLesson: EngineLessonSummary
    @State private var draftScenario: EngineScenario

    init(lesson: Binding<EngineLessonSummary>, scenario: Binding<EngineScenario>) {
        _lesson = lesson
        _scenario = scenario
        _draftLesson = State(initialValue: lesson.wrappedValue)
        _draftScenario = State(initialValue: scenario.wrappedValue)
    }

    private var isValid: Bool {
        !draftLesson.title.trimmed.isEmpty
            && !draftLesson.character.name.trimmed.isEmpty
            && !draftLesson.character.role.trimmed.isEmpty
            && !draftScenario.briefing.trimmed.isEmpty
            && draftScenario.criteria.allSatisfy { !$0.trimmed.isEmpty }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    ScenarioEditField(title: "Title", text: $draftLesson.title)
                    ScenarioEditField(title: "Situation", text: $draftScenario.briefing, axis: .vertical)
                    ScenarioEditField(title: "Their name", text: $draftLesson.character.name)
                    ScenarioEditField(title: "Their role", text: $draftLesson.character.role)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Goals")
                            .font(PoiseType.body(.bold))
                            .foregroundStyle(Color.poiseNavy)
                        ForEach(draftScenario.criteria.indices, id: \.self) { index in
                            TextField("Goal \(index + 1)", text: $draftScenario.criteria[index], axis: .vertical)
                                .font(PoiseType.body())
                                .padding(14)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.poiseBorder, lineWidth: 1.5))
                                .accessibilityLabel("Goal \(index + 1)")
                        }
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.poiseCanvas.ignoresSafeArea())
            .navigationTitle("Edit scenario")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        draftLesson.criteria = draftScenario.criteria
                        lesson = draftLesson
                        scenario = draftScenario
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}

private struct ScenarioEditField: View {
    let title: String
    @Binding var text: String
    var axis: Axis = .horizontal

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(PoiseType.body(.bold))
                .foregroundStyle(Color.poiseNavy)
            TextField(title, text: $text, axis: axis)
                .font(PoiseType.body())
                .lineLimit(axis == .vertical ? 3...7 : 1...1)
                .padding(14)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.poiseBorder, lineWidth: 1.5))
        }
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
