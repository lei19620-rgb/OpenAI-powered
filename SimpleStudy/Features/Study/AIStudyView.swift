import SwiftData
import SwiftUI

struct AIStudyView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \AIStudyRecord.createdAt, order: .reverse) private var history: [AIStudyRecord]
    @Query private var notes: [StudyNoteRecord]
    @Query private var homeworks: [HomeworkDefinitionRecord]
    @State var source: AIStudySource
    var onClose: (() -> Void)? = nil
    @State private var record: AIStudyRecord?
    @State private var result: AIStudyResult?
    @State private var chosenSections: Set<Int> = []
    @State private var running = false
    @State private var task: Task<Void, Never>?
    @State private var issue: String?
    @State private var showsConsent = false
    @State private var showsSettings = false
    @State private var showsHistory = false
    @State private var savedMessage: String?
    @State private var deleteTarget: AIStudyRecord?
    @State private var consentConfiguration = AIServiceConfiguration.saved
    @State private var consentSource: AIStudySource?

    private var mainNote: StudyNoteRecord? { notes.first { $0.workspaceID == source.workspaceID } }
    private var visibleHistory: [AIStudyRecord] { history.filter { $0.workspaceID == source.workspaceID } }
    private var savedHomework: HomeworkDefinitionRecord? { homeworks.first { $0.id == record?.homeworkID } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    AIIdentityHeader(title: source.operation.title, subtitle: "Understand it. Put it into practice.")
                    if result == nil {
                        inputCard
                    }
                    if running {
                        HStack(spacing: 14) {
                            ProgressView()
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Putting it together…").font(.headline)
                                Text("You can stop waiting or close this page. Sent requests may still be billed.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Stop") { task?.cancel() }
                        }.appCard()
                    }
                    if let issue {
                        Label(issue, systemImage: "exclamationmark.circle")
                            .font(.subheadline).foregroundStyle(.orange).appCard()
                    }
                    if let result { resultCards(result) }
                    if let savedMessage {
                        Label(savedMessage, systemImage: "checkmark.circle.fill")
                            .font(.subheadline).foregroundStyle(AppTheme.accent)
                    }
                }
                .frame(maxWidth: 740)
                .padding(AppTheme.pagePadding)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppTheme.pageBackground)
            .navigationTitle("Study assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") {
                    if let onClose { onClose() } else { dismiss() }
                } }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { showsHistory = true } label: { Image(systemName: "clock.arrow.circlepath") }
                        .accessibilityLabel("Explanation history")
                    Button { showsSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("AI service settings")
                }
            }
            .sheet(isPresented: $showsSettings) { NavigationStack { AISettingsView() } }
            .sheet(isPresented: $showsHistory) { historyView }
            .sheet(isPresented: $showsConsent) { consentView }
            .confirmationDialog("Delete this AI record? Saved notes and assignments will be kept.", isPresented: Binding(
                get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }
            ), titleVisibility: .visible) {
                Button("Delete record", role: .destructive) { deleteRecord() }
            }
            .onDisappear { task?.cancel() }
            .onAppear {
                #if DEBUG && targetEnvironment(simulator)
                if AppPreviewSupport.isPreview && ProcessInfo.processInfo.arguments.contains("-StudyAIPreviewAssistant") && result == nil {
                    let preview = AIStudyResult(title: "State first, reason next", summary: "I am happy because I received a gift yesterday.", sections: [
                        .init(title: "Sentence structure", body: "I is the subject, am is the linking verb, and happy is the subject complement. This describes a state, not an action.", quote: "I am happy"),
                        .init(title: "Read from left to right", body: "I am happy → the main statement\nbecause → introduces the reason\nI received a gift yesterday → explains the reason\n\nRead the main clause, then the reason. There is no need to read backwards.", quote: ""),
                        .init(title: "Another example", body: "I am tired because I worked today.\nThe main clause describes a state; the because-clause explains why.", quote: "")
                    ], questions: [])
                    result = preview; chosenSections = Set(preview.sections.indices)
                    savedMessage = "UI preview sample · Not generated by the API"
                }
                #endif
            }
        }
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(source.title, systemImage: "text.quote").lineLimit(2)
                Spacer()
                if let page = source.page { Text("Page \(page)").foregroundStyle(.secondary) }
            }.font(.subheadline)
            TextEditor(text: $source.text)
                .frame(minHeight: 180, maxHeight: 300)
                .scrollContentBackground(.hidden)
                .accessibilityLabel("Source text. You can correct recognized text here.")
            HStack {
                Text("\(source.text.count) / 6000 characters").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { prepareConsent() } label: {
                    Label(source.operation.title, systemImage: "sparkles")
                }.buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(running || source.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || source.text.count > 6000)
            }
            Text("Only the text you confirm is sent, not the entire document.")
                .font(.footnote).foregroundStyle(.secondary)
        }.appCard(padding: 20)
        .disabled(running)
    }

    @ViewBuilder private func resultCards(_ result: AIStudyResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(result.title).font(.title2.weight(.semibold))
            DisclosureGroup("Source · \(source.title)") {
                Text(source.text).font(.subheadline).textSelection(.enabled).padding(.vertical, 8)
            }.font(.subheadline).foregroundStyle(.secondary)
            Text(result.summary).font(.body).textSelection(.enabled)
            Label("AI-assisted content. Check against the source.", systemImage: "sparkles")
                .font(.footnote).foregroundStyle(.secondary)
            if let record, record.tokenCount > 0 {
                Text("\(record.model) · \(record.tokenCount) tokens")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.appCard(padding: 22)
        if record?.result == nil {
            Button("Save this result again") {
                guard let record else { return }
                record.resultData = JSONCoding.encode(result); record.state = "completed"
                do { try context.save(); issue = nil; savedMessage = "Result saved." }
                catch { context.rollback(); issue = "Still not saved. Export the content to keep a copy." }
            }.buttonStyle(.bordered)
        }
        ForEach(Array(result.sections.enumerated()), id: \.offset) { index, section in
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: Binding(get: { chosenSections.contains(index) }, set: { selected in
                    if selected { chosenSections.insert(index) } else { chosenSections.remove(index) }
                })) { Text(section.title).font(.headline) }
                .toggleStyle(.switch)
                .accessibilityHint("Include this section when saving to notes")
                if !section.quote.isEmpty {
                    Text(section.quote).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Text(section.body).lineSpacing(5).textSelection(.enabled)
            }.appCard(padding: 20)
        }
        if !result.questions.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text("Practice preview").font(.headline)
                ForEach(Array(result.questions.enumerated()), id: \.offset) { index, item in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(index + 1). \(item.prompt)")
                        Text(item.type.title).font(.caption).foregroundStyle(.secondary)
                        ForEach(item.options) { option in Text("\(option.id). \(option.text)").font(.subheadline) }
                    }
                }
                Text("Save to begin. Answers appear after submission. AI-generated questions are not original textbook questions.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let savedHomework {
                    NavigationLink("Start practice") { HomeworkDetailView(homework: savedHomework) }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Save as assignment") { saveHomework(result) }.buttonStyle(.borderedProminent)
                }
            }.appCard(padding: 20)
        }
        ViewThatFits(in: .horizontal) {
            HStack { resultActions(result) }
            VStack(alignment: .leading, spacing: 12) { resultActions(result) }
        }
        Button("Explain another passage") {
            self.result = nil; record = nil; savedMessage = nil; issue = nil
            source.operation = .explain
        }.disabled(running)
    }

    @ViewBuilder private func resultActions(_ result: AIStudyResult) -> some View {
        if let mainNote, !result.sections.isEmpty {
            Button(record?.appendedNoteID == nil ? "Add to main note" : "Added to note") { appendNote(result, to: mainNote) }
                .buttonStyle(.borderedProminent).disabled(record?.appendedNoteID != nil)
        }
        ShareLink(item: result.markdown(source: source, selectedSections: chosenSections)) {
            Label("Export content", systemImage: "square.and.arrow.up")
        }.buttonStyle(.bordered)
        if source.operation == .explain {
            Button { prepareConsent(operation: .practice) } label: { Label("Practice this", systemImage: "pencil.and.list.clipboard") }
                .buttonStyle(.bordered).disabled(running)
        }
    }

    private var consentView: some View {
        NavigationStack {
            List {
                Section("Text to send") {
                    Text(consentSource?.text ?? "").textSelection(.enabled)
                }
                Section("Service and cost") {
                    LabeledContent("Service", value: (try? consentConfiguration.endpoint().host) ?? "Not set")
                    LabeledContent("Model", value: consentConfiguration.model)
                    LabeledContent("Output limit", value: "\(consentConfiguration.outputLimit) tokens")
                    Text("Uses your own API quota. The output limit is not a spending cap. Sent requests may be billed even if canceled. No automatic retries.")
                    Text("Only the text above and fixed teaching instructions are sent. The provider may retain requests under its policy; disabling storage does not mean zero retention.")
                }.font(.subheadline)
                Button("Confirm and generate") { showsConsent = false; start() }
                    .buttonStyle(.borderedProminent).disabled(running)
            }
            .navigationTitle("Review before sending")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showsConsent = false } } }
        }
    }

    private var historyView: some View {
        NavigationStack {
            List {
                if visibleHistory.isEmpty { ContentUnavailableView("No explanations yet", systemImage: "clock") }
                ForEach(visibleHistory) { item in
                    Button {
                        guard let savedSource = item.source else { return }
                        source = savedSource; record = item; result = item.result
                        chosenSections = Set(item.result?.sections.indices ?? 0..<0)
                        issue = item.result == nil ? "The previous request returned no valid result and may have been billed. It will not be resent automatically." : nil
                        savedMessage = nil; showsHistory = false
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.result?.title ?? item.title).foregroundStyle(.primary)
                            Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                            if item.result == nil { Text("Incomplete").font(.caption).foregroundStyle(.orange) }
                        }
                    }.disabled(running)
                    .swipeActions { Button("Delete", role: .destructive) { deleteTarget = item; showsHistory = false }.disabled(running) }
                }
            }.navigationTitle("Explanation history")
                .toolbar { Button("Done") { showsHistory = false } }
        }
    }

    private func prepareConsent(operation: AIStudyOperation? = nil) {
        do {
            let config = AIServiceConfiguration.saved
            _ = try config.endpoint()
            guard !(try AIKeychain.read(host: config.credentialScope)).isEmpty else { throw AIServiceError.missingKey }
            consentConfiguration = config
            var draft = source
            if let operation { draft.operation = operation }
            consentSource = draft
            issue = nil; showsConsent = true
        } catch { issue = error.localizedDescription; showsSettings = true }
    }

    private func start() {
        guard !running, let snapshot = consentSource else { return }
        do {
            let key = try AIKeychain.read(host: consentConfiguration.credentialScope)
            let configuration = consentConfiguration
            _ = try AIStudyService.request(source: snapshot, configuration: configuration, key: key)
            let entry = AIStudyRecord(source: snapshot, model: configuration.model, serviceHost: configuration.baseURL)
            context.insert(entry)
            entry.state = "sending"
            try context.save()
            source = snapshot; record = entry; result = nil; savedMessage = nil; issue = nil; running = true
            task = Task { @MainActor in
                defer { running = false; task = nil }
                do {
                    let (answer, tokens) = try await AIStudyService.generate(source: snapshot, configuration: configuration, key: key)
                    try Task.checkCancellation()
                    entry.resultData = JSONCoding.encode(answer); entry.tokenCount = tokens
                    entry.state = "completed"; entry.title = answer.title
                    do { try context.save() }
                    catch {
                        context.rollback()
                        result = answer; chosenSections = Set(answer.sections.indices)
                        issue = "The result was generated but could not be saved. Export it to avoid losing it."
                        return
                    }
                    result = answer; chosenSections = Set(answer.sections.indices)
                } catch {
                    entry.state = "unresolved"
                    do { try context.save() } catch { context.rollback() }
                    issue = Task.isCancelled ? "Stopped waiting. The service may still process the request. It will not be retried automatically." : "\(error.localizedDescription) The request may have been billed. No automatic retry will be made."
                }
            }
        } catch { context.rollback(); issue = error.localizedDescription }
    }

    private func appendNote(_ result: AIStudyResult, to note: StudyNoteRecord) {
        guard let record, record.appendedNoteID == nil else { return }
        note.content += "\n\n" + result.markdown(source: source, selectedSections: chosenSections)
        note.updatedAt = Date(); record.appendedNoteID = note.id
        do { try context.save(); savedMessage = "Added to the main note. Existing content was kept." }
        catch { context.rollback(); issue = "The note could not be saved. Try again." }
    }

    private func saveHomework(_ result: AIStudyResult) {
        guard let record, record.homeworkID == nil else { return }
        do {
            let package = try result.homework(id: record.id.uuidString)
            let homework = HomeworkDefinitionRecord(package: package, sourceFileName: "AI-generated-\(record.id).json", workspaceID: source.workspaceID)
            context.insert(homework); record.homeworkID = homework.id
            try context.save(); savedMessage = "Assignment saved. You can start practicing."
        } catch { context.rollback(); issue = error.localizedDescription }
    }

    private func deleteRecord() {
        guard let target = deleteTarget else { return }
        let selected = record?.id == target.id
        context.delete(target)
        do {
            try context.save()
            if selected { record = nil; result = nil }
        } catch { context.rollback(); issue = "Could not delete. Try again." }
        deleteTarget = nil
    }
}

struct AIStudyPresentation: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Binding var source: AIStudySource?
    func body(content: Content) -> some View {
        content
            .inspector(isPresented: Binding(
                get: { source != nil && sizeClass == .regular },
                set: { if !$0 && sizeClass == .regular { source = nil } }
            )) {
                if let source {
                    AIStudyView(source: source, onClose: { self.source = nil })
                        .id(source.id)
                        .inspectorColumnWidth(min: 340, ideal: 420, max: 600)
                }
            }
            .sheet(item: Binding(
                get: { sizeClass != .regular ? source : nil },
                set: { if sizeClass != .regular { source = $0 } }
            )) { source in
                AIStudyView(source: source)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
    }
}

struct AIIdentityHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "sparkles").font(.title2.weight(.medium))
                .foregroundStyle(AppTheme.accent).frame(width: 54, height: 54)
                .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.title2.weight(.semibold))
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 8)
    }
}
