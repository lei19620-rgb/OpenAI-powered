import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct StudyWorkspaceView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var actionEngine: TodoActionEngine
    @EnvironmentObject private var settings: AppSettings
    @Query(sort: \StudyAssetRecord.importedAt) private var allAssets: [StudyAssetRecord]
    @Query(sort: \StudyNoteRecord.createdAt) private var allNotes: [StudyNoteRecord]
    @Query(sort: \NoteTemplateRecord.name) private var templates: [NoteTemplateRecord]
    @Query(sort: \CourseRecord.createdAt) private var courses: [CourseRecord]
    @Query(sort: \HomeworkDefinitionRecord.importedAt) private var homeworks: [HomeworkDefinitionRecord]
    @Query(sort: \TodoRecord.createdAt) private var todos: [TodoRecord]

    let workspace: StudyWorkspaceRecord

    @State private var selectedAssetID: UUID?
    @State private var showsNote = false
    @State private var showsQuestions = false
    @State private var isOCRRunning = false
    @State private var ocrProgress = 0.0
    @State private var ocrTask: Task<Void, Never>?
    @State private var ocrError: String?
    @State private var ocrGeneration = UUID()
    @State private var aiSource: AIStudySource?

    private var assets: [StudyAssetRecord] {
        allAssets.filter { $0.workspaceID == workspace.id }
    }

    private var activeAsset: StudyAssetRecord? {
        assets.first(where: { $0.id == selectedAssetID }) ?? assets.first
    }

    private var mainNote: StudyNoteRecord? {
        allNotes.first { $0.id == workspace.mainNoteID }
            ?? allNotes.first { $0.workspaceID == workspace.id }
    }

    private var linkedHomework: HomeworkDefinitionRecord? {
        homeworks.first { $0.workspaceID == workspace.id }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let asset = activeAsset {
                        PDFStudyView(
                            asset: asset,
                            onOCR: { runOCR(asset) },
                            onCancelOCR: cancelOCR,
                            isOCRRunning: isOCRRunning,
                            ocrProgress: ocrProgress,
                            onExplain: { source in
                                showsNote = false
                                if mainNote == nil { createMainNote() }
                                aiSource = source
                            }
                        )
                        .id(asset.id)
                    } else {
                        ContentUnavailableView {
                            Label("No materials for this lesson", systemImage: "doc")
                        } description: {
                            Text("Import a PDF from the course page.")
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let note = mainNote {
                    FloatingNotePanel(note: note, workspaceID: workspace.id, containerSize: geometry.size, isVisible: showsNote) {
                        showsNote = false
                    }
                    .opacity(showsNote ? 1 : 0)
                    .allowsHitTesting(showsNote)
                    .accessibilityHidden(!showsNote)
                }

                Button {
                    openMainNote()
                } label: {
                    Label(showsNote ? "Close notes" : "Notes", systemImage: showsNote ? "xmark" : "note.text")
                        .font(.headline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .shadow(radius: 8, y: 3)
                .padding(18)
                .opacity(showsNote ? 0 : 1)
            }
        }
        .navigationTitle(workspace.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showsNote = false
                    if mainNote == nil { createMainNote() }
                    aiSource = AIStudySource(text: "", title: activeAsset?.displayName ?? workspace.title,
                        workspaceID: workspace.id, assetID: activeAsset?.id)
                } label: { Image(systemName: "sparkles") }
                    .accessibilityLabel("AI study assistant: type or paste source text")
                if assets.count > 1 {
                    Menu {
                        ForEach(assets) { asset in
                            Button(asset.displayName) { cancelOCR(); selectedAssetID = asset.id }
                        }
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .accessibilityLabel("Switch material")
                }

                Button { showsQuestions = true } label: {
                    Image(systemName: "questionmark.text.page")
                }
                .disabled(activeAsset?.extractedQuestions.isEmpty != false)
                .accessibilityLabel("Extracted questions")

                if let linkedHomework {
                    NavigationLink(value: StudyRoute.homework(linkedHomework.id)) {
                        Image(systemName: "pencil.and.list.clipboard")
                    }
                    .accessibilityLabel("Lesson assignment")
                }

                if !workspace.isCompleted {
                    Button("Finish lesson") { completeLesson() }
                } else {
                    Label("Completed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
        .sheet(isPresented: $showsQuestions) {
            NavigationStack {
                List(activeAsset?.extractedQuestions ?? [], id: \.self) { question in
                    Text(question).textSelection(.enabled)
                }
                .navigationTitle("Extracted questions")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showsQuestions = false }
                    }
                }
            }
        }
        .modifier(AIStudyPresentation(source: $aiSource))
        .alert("Action failed", isPresented: Binding(get: { ocrError != nil }, set: { if !$0 { ocrError = nil } })) {
            Button("OK", role: .cancel) { ocrError = nil }
        } message: {
            Text(ocrError ?? "")
        }
        .onAppear {
            selectedAssetID = selectedAssetID ?? assets.first?.id
            #if DEBUG && targetEnvironment(simulator)
            if AppPreviewSupport.isPreview && ProcessInfo.processInfo.arguments.contains("-SimpleStudyPreviewNote") { showsNote = true }
            if AppPreviewSupport.isPreview && ProcessInfo.processInfo.arguments.contains("-StudyAIPreviewAssistant") {
                aiSource = AIStudySource(text: "I am happy because I received a gift yesterday.",
                    title: "UI preview sample", workspaceID: workspace.id)
            }
            #endif
        }
        .onDisappear(perform: cancelOCR)
    }

    private func openMainNote() {
        if mainNote == nil { createMainNote() }
        withAnimation(.snappy) { showsNote.toggle() }
    }

    private func createMainNote() {
        let template = settings.defaultTemplateID.flatMap { id in templates.first(where: { $0.id == id }) }
            ?? templates.first(where: { $0.name == "Sentence study" })
            ?? templates.first
        guard let template else { return }
        let courseTitle = courses.first(where: { $0.id == workspace.courseID })?.title ?? workspace.title
        let content = NoteRenderingService.render(
            template: template,
            courseTitle: courseTitle,
            day: workspace.sequence,
            materialName: activeAsset?.displayName
        )
        let note = StudyNoteRecord(
            workspaceID: workspace.id,
            title: workspace.title,
            content: content,
            template: template.snapshot
        )
        modelContext.insert(note)
        workspace.mainNoteID = note.id
        do { try modelContext.save() } catch {
            modelContext.rollback()
            ocrError = "Note not saved: \(error.localizedDescription)"
        }
    }

    private func runOCR(_ asset: StudyAssetRecord) {
        guard !isOCRRunning else { return }
        isOCRRunning = true
        ocrProgress = 0
        let generation = UUID()
        ocrGeneration = generation
        let progressUpdate: @Sendable (Double) -> Void = { value in
            Task { @MainActor in
                guard ocrGeneration == generation else { return }
                ocrProgress = value
            }
        }
        ocrTask = Task {
            do {
                let text = try await PDFTextService.recognize(data: asset.fileData, progress: progressUpdate)
                try Task.checkCancellation()
                guard ocrGeneration == generation, !asset.isDeleted else { return }
                asset.ocrText = text
                let combined = PDFTextService.embeddedText(data: asset.fileData) + "\n" + text
                asset.extractedQuestions = PDFTextService.extractQuestions(from: combined)
                try modelContext.save()
            } catch is CancellationError {
                // Keep the original PDF and completed OCR results when canceled.
            } catch {
                guard ocrGeneration == generation else { return }
                modelContext.rollback()
                ocrError = error.localizedDescription
            }
            guard ocrGeneration == generation else { return }
            isOCRRunning = false
            ocrTask = nil
        }
    }

    private func cancelOCR() {
        ocrGeneration = UUID()
        ocrTask?.cancel()
        ocrTask = nil
        isOCRRunning = false
    }

    private func completeLesson() {
        let currentSequence = courses.first { $0.id == workspace.courseID }?.currentSequence
        do {
            try CourseProgressService.complete(workspace, context: modelContext)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            ocrError = "Progress not saved: \(error.localizedDescription)"
            return
        }

        let linkedTodos = todos.filter {
            $0.storedState != .completed &&
            $0.completionRule == .lessonCompletion &&
            ($0.workspaceID == workspace.id || ($0.workspaceID == nil && $0.courseID == workspace.courseID && workspace.sequence == currentSequence))
        }
        Task {
            for todo in linkedTodos {
                todo.workspaceID = workspace.id
                await actionEngine.complete(todo: todo, context: modelContext)
            }
        }
    }
}

private enum PhoneNoteSize: String, CaseIterable {
    case compact
    case half
    case full

    var title: String {
        switch self {
        case .compact: "Compact"
        case .half: "Half screen"
        case .full: "Full screen"
        }
    }
}

private enum MarkdownNoteMode: String, CaseIterable {
    case edit
    case preview

    var title: String {
        switch self {
        case .edit: "Edit"
        case .preview: "Preview"
        }
    }
}

private struct FloatingNotePanel: View {
    @Environment(\.modelContext) private var modelContext
    let note: StudyNoteRecord
    @State private var draft = ""
    @State private var lastSavedContent = ""
    @State private var isLoaded = false
    @State private var saveTask: Task<Void, Never>?
    let workspaceID: UUID
    let containerSize: CGSize
    let isVisible: Bool
    let close: () -> Void
    @FocusState private var isEditing: Bool

    @State private var offset: CGSize = .zero
    @State private var panelSize = CGSize(width: 520, height: 560)
    @State private var isFullScreen = false
    @State private var phoneSize: PhoneNoteSize = .half
    @State private var resizeStart: CGSize?
    @State private var mode: MarkdownNoteMode = .edit
    @State private var selection: TextSelection?
    @State private var showsMarkdownImporter = false
    @State private var showsMarkdownExporter = false
    @State private var pendingImportedMarkdown: String?
    @State private var showsImportConfirmation = false
    @State private var markdownError: String?
    @State private var dictionaryQuery = ""
    @State private var showsDictionary = false
    @State private var dictionarySelectionTask: Task<Void, Never>?
    @GestureState private var dragTranslation: CGSize = .zero

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private var effectiveSize: CGSize {
        if isFullScreen || (!isPad && phoneSize == .full) {
            return CGSize(width: max(1, containerSize.width - 16), height: max(1, containerSize.height - 16))
        }
        if !isPad {
            let height = phoneSize == .compact ? min(280, containerSize.height * 0.38) : containerSize.height * 0.58
            return CGSize(width: max(1, containerSize.width - 24), height: height)
        }
        return CGSize(
            width: min(max(320, panelSize.width), max(1, containerSize.width - 24)),
            height: min(max(280, panelSize.height), max(1, containerSize.height - 24))
        )
    }

    private var selectedText: String? {
        guard let selection, case .selection(let range) = selection.indices else { return nil }
        let value = String(draft[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private var effectivePosition: CGPoint {
        if isFullScreen || (!isPad && phoneSize == .full) {
            return CGPoint(x: containerSize.width / 2, y: containerSize.height / 2)
        }
        if !isPad {
            return CGPoint(x: containerSize.width / 2, y: containerSize.height - effectiveSize.height / 2 - 12)
        }
        let proposed = CGPoint(
            x: containerSize.width / 2 + offset.width + dragTranslation.width,
            y: containerSize.height / 2 + offset.height + dragTranslation.height
        )
        return CGPoint(
            x: min(max(effectiveSize.width / 2, proposed.x), containerSize.width - effectiveSize.width / 2),
            y: min(max(effectiveSize.height / 2, proposed.y), containerSize.height - effectiveSize.height / 2)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.secondary)
                Text(note.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()

                if let selectedText,
                   let selectedDictionaryQuery = DictionarySelectionQuery.normalized(from: selectedText) {
                    Button {
                        presentDictionary(for: selectedDictionaryQuery)
                    } label: {
                        Image(systemName: "character.book.closed")
                    }
                    .accessibilityLabel("Look up the selected word or phrase in this note")
                    .accessibilityHint("Uses only offline dictionaries")
                }

                if !isPad {
                    Menu {
                        ForEach(PhoneNoteSize.allCases, id: \.rawValue) { size in
                            Button(size.title) { phoneSize = size }
                        }
                    } label: {
                        Image(systemName: "rectangle.compress.vertical")
                    }
                }

                Button { isFullScreen.toggle() } label: {
                    Image(systemName: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                }
                .accessibilityLabel(isFullScreen ? "Minimize notes" : "Full-screen notes")
                Button { if saveNote() { close() } } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .accessibilityLabel("Hide notes")
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(.bar)
            .contentShape(Rectangle())
            .gesture(isPad && !isFullScreen ? dragGesture : nil)

            HStack(spacing: 10) {
                Picker("Note display", selection: $mode) {
                    ForEach(MarkdownNoteMode.allCases, id: \.rawValue) { value in
                        Text(value.title).tag(value)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)

                Spacer()

                Menu {
                    Button {
                        showsMarkdownImporter = true
                    } label: {
                        Label("Import Markdown", systemImage: "square.and.arrow.down")
                    }

                    Button {
                        showsMarkdownExporter = true
                    } label: {
                        Label("Export Markdown", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
                .accessibilityLabel("Note files")
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(.bar)

            if mode == .edit {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(MarkdownFormat.allCases) { format in
                            Button {
                                apply(format)
                            } label: {
                                Label(format.title, systemImage: format.systemImage)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .background(.bar)

                TextEditor(text: $draft, selection: $selection)
                    .focused($isEditing)
                    .font(.system(.body, design: .monospaced))
                    .padding(10)
                    .scrollContentBackground(.hidden)
                    .background(.background)
                    .onChange(of: draft) { _, _ in
                        guard isLoaded else { return }
                        saveTask?.cancel()
                        saveTask = Task {
                            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
                            saveNote()
                        }
                    }
            } else {
                MarkdownPreviewView(markdown: draft)
            }

            if isPad && !isFullScreen {
                HStack {
                    Spacer()
                    Image(systemName: "arrow.down.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .contentShape(Rectangle())
                        .gesture(resizeGesture)
                }
                .frame(height: 24)
                .background(.bar)
            }
        }
        .frame(width: effectiveSize.width, height: effectiveSize.height)
        .background(.background, in: RoundedRectangle(cornerRadius: isFullScreen ? 8 : 18))
        .clipShape(RoundedRectangle(cornerRadius: isFullScreen ? 8 : 18))
        .shadow(color: .black.opacity(0.22), radius: 20, y: 8)
        .position(effectivePosition)
        .popover(isPresented: $showsDictionary, arrowEdge: .top) {
            LocalDictionaryLookupView(query: dictionaryQuery)
        }
        .onAppear {
            restoreGeometry()
            if !isLoaded {
                draft = note.content
                lastSavedContent = draft
                isLoaded = true
            }
        }
        .onChange(of: note.content) { _, content in
            if draft == lastSavedContent {
                selection = nil
                draft = content
                lastSavedContent = content
            }
        }
        .onChange(of: isVisible) { _, visible in
            if !visible { saveTask?.cancel(); saveNote(); isEditing = false; saveGeometry() }
        }
        .onDisappear {
            saveTask?.cancel()
            saveNote()
            dictionarySelectionTask?.cancel()
            dictionarySelectionTask = nil
            saveGeometry()
        }
        .onChange(of: selectedText) { _, value in
            scheduleDictionaryLookup(for: value)
        }
        .fileImporter(
            isPresented: $showsMarkdownImporter,
            allowedContentTypes: [ProductFileType.markdown, .plainText],
            allowsMultipleSelection: false,
            onCompletion: importMarkdown
        )
        .fileExporter(
            isPresented: $showsMarkdownExporter,
            document: MarkdownNoteDocument(content: draft),
            contentType: ProductFileType.markdown,
            defaultFilename: NoteMarkdownService.safeFileName(note.title)
        ) { result in
            if case .failure(let error) = result {
                markdownError = error.localizedDescription
            }
        }
        .confirmationDialog(
            "Importing replaces the current note body",
            isPresented: $showsImportConfirmation,
            titleVisibility: .visible
        ) {
            Button("Replace current body", role: .destructive) {
                if let pendingImportedMarkdown {
                    replaceContent(with: pendingImportedMarkdown)
                }
                pendingImportedMarkdown = nil
            }
            Button("Cancel", role: .cancel) {
                pendingImportedMarkdown = nil
            }
        } message: {
            Text("The course, lesson, note title, and template snapshot will stay unchanged.")
        }
        .alert("Could not save or import note", isPresented: Binding(
            get: { markdownError != nil },
            set: { if !$0 { markdownError = nil } }
        )) {
            Button("OK", role: .cancel) { markdownError = nil }
        } message: {
            Text(markdownError ?? "")
        }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .updating($dragTranslation) { value, state, _ in state = value.translation }
            .onEnded { value in
                offset.width += value.translation.width
                offset.height += value.translation.height
                saveGeometry()
            }
    }

    private var resizeGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let start = resizeStart ?? panelSize
                resizeStart = start
                panelSize = CGSize(
                    width: start.width + value.translation.width,
                    height: start.height + value.translation.height
                )
            }
            .onEnded { _ in
                resizeStart = nil
                saveGeometry()
            }
    }

    private var geometryKey: String { "notePanel.\(workspaceID.uuidString).\(DeviceIdentity.id)" }

    private func restoreGeometry() {
        let defaults = UserDefaults.standard
        let values = defaults.dictionary(forKey: geometryKey) as? [String: Double]
        offset = CGSize(width: values?["x"] ?? 0, height: values?["y"] ?? 0)
        panelSize = CGSize(width: values?["width"] ?? 520, height: values?["height"] ?? 560)
    }

    private func saveGeometry() {
        UserDefaults.standard.set([
            "x": offset.width,
            "y": offset.height,
            "width": panelSize.width,
            "height": panelSize.height
        ], forKey: geometryKey)
    }

    private func apply(_ format: MarkdownFormat) {
        let selectedRange: Range<Int>?
        if let selection, case .selection(let range) = selection.indices {
            selectedRange = draft.distance(from: draft.startIndex, to: range.lowerBound)..<draft.distance(
                from: draft.startIndex,
                to: range.upperBound
            )
        } else {
            selectedRange = nil
        }

        let result = NoteMarkdownService.apply(
            format,
            to: draft,
            selectedCharacterRange: selectedRange
        )
        draft = result.content
        let lower = draft.index(draft.startIndex, offsetBy: result.selectedCharacterRange.lowerBound)
        let upper = draft.index(draft.startIndex, offsetBy: result.selectedCharacterRange.upperBound)
        selection = TextSelection(range: lower..<upper)
        saveNote()
    }

    private func importMarkdown(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               size > NoteMarkdownService.maximumFileSize {
                throw NoteMarkdownError.fileTooLarge
            }
            let imported = try NoteMarkdownService.decode(Data(contentsOf: url))
            if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                replaceContent(with: imported)
            } else {
                pendingImportedMarkdown = imported
                showsImportConfirmation = true
            }
        } catch let error as CocoaError where error.code == .userCancelled {
            return
        } catch {
            markdownError = error.localizedDescription
        }
    }

    private func replaceContent(with content: String) {
        draft = content
        selection = nil
        mode = .edit
        saveNote()
    }

    private func scheduleDictionaryLookup(for selection: String?) {
        dictionarySelectionTask?.cancel()
        dictionarySelectionTask = nil

        guard let query = DictionarySelectionQuery.normalized(from: selection) else {
            dictionaryQuery = ""
            showsDictionary = false
            return
        }

        dictionaryQuery = query
        dictionarySelectionTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(350))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            showsDictionary = true
            dictionarySelectionTask = nil
        }
    }

    private func presentDictionary(for query: String) {
        dictionarySelectionTask?.cancel()
        dictionarySelectionTask = nil
        dictionaryQuery = query
        showsDictionary = true
    }

    @discardableResult
    private func saveNote() -> Bool {
        guard isLoaded, draft != lastSavedContent else { return true }
        note.content = draft
        note.updatedAt = Date()
        do {
            try modelContext.save()
            lastSavedContent = draft
            return true
        } catch {
            modelContext.rollback()
            // The independent editor buffer survives a failed persistence save.
            markdownError = "Your text is still on this page. Try saving again or export Markdown. \(error.localizedDescription)"
            return false
        }
    }
}
