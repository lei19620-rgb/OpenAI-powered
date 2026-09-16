import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum StudyRoute: Hashable {
    case course(UUID)
    case workspace(UUID)
    case homework(UUID)
    case homeworkLibrary
    case templates
}

struct StudyHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var router: AppRouter
    @Query(sort: \CourseRecord.createdAt) private var courses: [CourseRecord]
    @Query(sort: \StudyWorkspaceRecord.sequence) private var workspaces: [StudyWorkspaceRecord]
    @Query(sort: \HomeworkDefinitionRecord.importedAt) private var homeworks: [HomeworkDefinitionRecord]

    @State private var path: [StudyRoute] = []
    @State private var showsCourseEditor = false
    @State private var showsAI = false

    private var nextWorkspace: StudyWorkspaceRecord? {
        workspaces.first { workspace in
            !workspace.isCompleted && courses.contains { $0.id == workspace.courseID && $0.currentSequence == workspace.sequence }
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    Button { showsAI = true } label: {
                        VStack(alignment: .leading, spacing: 18) {
                            HStack {
                                Label("OPENAI · STUDY ASSISTANT", systemImage: "sparkles")
                                    .font(.caption.weight(.semibold)).tracking(1)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                            }.foregroundStyle(AppTheme.accent)
                            Text("Turn questions into understanding.")
                                .font(.system(.title2, design: .rounded).weight(.semibold)).foregroundStyle(.primary)
                            HStack(spacing: 8) {
                                Text("Understand"); Image(systemName: "chevron.right")
                                Text("Take notes"); Image(systemName: "chevron.right"); Text("Practice")
                            }.font(.subheadline).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .appCard(padding: 24, radius: AppTheme.heroRadius)
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(AppTheme.accent).frame(width: 3, height: 40)
                        }
                    }.buttonStyle(.plain)
                    if let workspace = nextWorkspace {
                        Button { path.append(.workspace(workspace.id)) } label: {
                            HStack(spacing: 16) {
                                Image(systemName: "book.pages.fill")
                                    .font(.title2)
                                    .appIconBadge(size: 56, radius: 18)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Continue learning").font(.subheadline).foregroundStyle(.secondary)
                                    Text(workspace.title).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                                }
                                Spacer()
                                Image(systemName: "arrow.right.circle.fill").font(.title2)
                            }
                            .appCard(padding: 20, radius: AppTheme.heroRadius)
                        }
                        .buttonStyle(.plain)
                    }

                    if courses.isEmpty {
                        ContentUnavailableView {
                            Label("No courses yet", systemImage: "books.vertical")
                        } description: {
                            Text("Create a course, then import your PDFs.")
                        } actions: {
                            Button("New course") { showsCourseEditor = true }
                                .buttonStyle(.borderedProminent)
                        }
                        .frame(minHeight: 260)
                    } else {
                        Text("Your courses").font(.title3.weight(.semibold)).padding(.top, 8)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)], spacing: 14) {
                          ForEach(courses) { course in
                            Button {
                                path.append(.course(course.id))
                            } label: {
                                CourseCard(
                                    course: course,
                                    workspaceCount: workspaces.filter { $0.courseID == course.id }.count
                                )
                            }
                            .buttonStyle(.plain)
                          }
                        }
                    }

                    VStack(spacing: 0) {
                        StudyToolRow(icon: "pencil.and.list.clipboard", title: "Practice", subtitle: "") {
                            path.append(.homeworkLibrary)
                        }
                        Divider().padding(.leading, 54)
                        StudyToolRow(icon: "rectangle.stack.badge.plus", title: "Note templates", subtitle: "") {
                            path.append(.templates)
                        }
                    }
                    .appCard(padding: 4)
                }
                .frame(maxWidth: 1000)
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity)
            }
            .background(AppTheme.pageBackground)
            .navigationTitle("Study")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showsCourseEditor = true } label: {
                        Label("New course", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showsCourseEditor) {
                CourseEditorView()
            }
            .sheet(isPresented: $showsAI) {
                AIStudyView(source: AIStudySource(text: ""))
            }
            .navigationDestination(for: StudyRoute.self) { route in
                destination(route)
            }
            .onChange(of: router.requestedWorkspaceID) { _, id in
                guard let id else { return }
                path = [.workspace(id)]
                router.requestedWorkspaceID = nil
            }
            .onChange(of: router.studyHomeRequest) { _, value in
                guard value > 0 else { return }
                path = []
                router.studyHomeRequest = 0
            }
            .onChange(of: router.requestedHomeworkID) { _, id in
                if let id { path = [.homework(id)] }
                router.requestedHomeworkID = nil
            }
            .onChange(of: router.homeworkLibraryRequest) { _, value in
                guard value > 0 else { return }
                path = [.homeworkLibrary]
                router.homeworkLibraryRequest = 0
            }
            .onAppear {
                if router.studyHomeRequest > 0 {
                    path = []
                    router.studyHomeRequest = 0
                } else if let workspaceID = router.requestedWorkspaceID {
                    path = [.workspace(workspaceID)]
                    router.requestedWorkspaceID = nil
                } else if let homeworkID = router.requestedHomeworkID {
                    path = [.homework(homeworkID)]
                    router.requestedHomeworkID = nil
                } else if router.homeworkLibraryRequest > 0 {
                    path = [.homeworkLibrary]
                    router.homeworkLibraryRequest = 0
                }
                #if DEBUG && targetEnvironment(simulator)
                if AppPreviewSupport.isPreview,
                   ProcessInfo.processInfo.arguments.contains("-StudyAIPreviewAssistant") {
                    showsAI = true
                }
                #endif
            }
            .onChange(of: workspaces.count) { _, _ in
                #if DEBUG && targetEnvironment(simulator)
                if AppPreviewSupport.isPreview,
                   ProcessInfo.processInfo.arguments.contains("-SimpleStudyPreviewWorkspace"),
                   let workspace = workspaces.first {
                    path = [.workspace(workspace.id)]
                }
                #endif
            }
            .task(id: workspaces.count) {
                #if DEBUG && targetEnvironment(simulator)
                if AppPreviewSupport.isPreview,
                   ProcessInfo.processInfo.arguments.contains("-SimpleStudyPreviewWorkspace"),
                   let workspace = workspaces.first, path.isEmpty {
                    // Wait for the initial navigation stack to finish mounting.
                    try? await Task.sleep(for: .milliseconds(800))
                    guard !Task.isCancelled else { return }
                    path = [.workspace(workspace.id)]
                }
                #endif
            }
        }
    }

    @ViewBuilder
    private func destination(_ route: StudyRoute) -> some View {
        switch route {
        case .course(let id):
            if let course = courses.first(where: { $0.id == id }) {
                CourseDetailView(course: course)
            } else {
                ContentUnavailableView("Course not found", systemImage: "exclamationmark.triangle")
            }
        case .workspace(let id):
            if let workspace = workspaces.first(where: { $0.id == id }) {
                StudyWorkspaceView(workspace: workspace)
            } else {
                ContentUnavailableView("Workspace not found", systemImage: "exclamationmark.triangle")
            }
        case .homework(let id):
            if let homework = homeworks.first(where: { $0.id == id }) {
                HomeworkDetailView(homework: homework)
            } else {
                HomeworkLibraryView()
            }
        case .homeworkLibrary:
            HomeworkLibraryView()
        case .templates:
            NoteTemplateLibraryView()
        }
    }
}


private struct CourseCard: View {
    let course: CourseRecord
    let workspaceCount: Int

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "book.closed")
                .appIconBadge(size: 34, radius: 10)
            VStack(alignment: .leading, spacing: 6) {
                Text(course.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("Lesson \(course.currentSequence) · \(workspaceCount) \(workspaceCount == 1 ? "workspace" : "workspaces")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .appCard(padding: 16, radius: AppTheme.cardRadius)
    }
}

private struct StudyToolRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .appIconBadge(size: 34, radius: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    if !subtitle.isEmpty {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
    }
}

private struct CourseEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var settings: AppSettings
    @State private var title = ""
    @State private var details = ""
    @State private var missedPolicy: MissedOccurrencePolicy = .carryForward
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Course") {
                    TextField("Course name", text: $title)
                    TextField("Description", text: $details, axis: .vertical)
                }
                Section("When a session is missed") {
                    Picker("Policy", selection: $missedPolicy) {
                        ForEach(MissedOccurrencePolicy.allCases) { policy in
                            Text(policy.title).tag(policy)
                        }
                    }
                    Text("Progress advances only after you finish the lesson.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New course")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { missedPolicy = settings.defaultMissedPolicy }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let course = CourseRecord(title: title.trimmingCharacters(in: .whitespacesAndNewlines), details: details)
                        course.missedPolicy = missedPolicy
                        modelContext.insert(course)
                        do { try modelContext.save(); dismiss() } catch {
                            modelContext.rollback()
                            saveError = error.localizedDescription
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("Course not saved", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(saveError ?? "") }
        }
    }
}

struct CourseDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StudyWorkspaceRecord.sequence) private var allWorkspaces: [StudyWorkspaceRecord]
    @Query(sort: \StudyAssetRecord.importedAt) private var allAssets: [StudyAssetRecord]
    @Query(sort: \StudyNoteRecord.createdAt) private var allNotes: [StudyNoteRecord]
    @Query(sort: \HomeworkDefinitionRecord.importedAt) private var allHomeworks: [HomeworkDefinitionRecord]
    @Query(sort: \TodoRecord.createdAt) private var allTodos: [TodoRecord]
    let course: CourseRecord

    @State private var showsImporter = false
    @State private var importError: String?
    @State private var editingWorkspace: StudyWorkspaceRecord?
    @State private var importTask: Task<Void, Never>?
    @State private var isImporting = false

    private var workspaces: [StudyWorkspaceRecord] {
        allWorkspaces.filter { $0.courseID == course.id }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Up next").font(.caption).foregroundStyle(.secondary)
                        Text("Day \(course.currentSequence)").font(.title.bold())
                    }
                    Spacer()
                    Button("Import PDF") { showsImporter = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(isImporting)
                }
                .padding(.vertical, 6)
            }

            Section("Workspaces") {
                if workspaces.isEmpty {
                    Text("Lesson order is detected when you import PDFs.")
                        .foregroundStyle(.secondary)
                }
                ForEach(workspaces) { workspace in
                    NavigationLink(value: StudyRoute.workspace(workspace.id)) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(workspace.title).font(.headline)
                                if workspace.isCompleted {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                }
                            }
                            let assets = allAssets.filter { $0.workspaceID == workspace.id }
                            Text("\(assets.count) materials" + (assets.contains { $0.inferenceConfidence < 0.5 } ? " · Check lesson order" : ""))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            editingWorkspace = workspace
                        } label: {
                            Label("Edit lesson number", systemImage: "number")
                        }
                        .tint(AppTheme.accent)
                    }
                    .contextMenu {
                        Button {
                            editingWorkspace = workspace
                        } label: {
                            Label("Edit lesson order", systemImage: "number")
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.pageBackground)
        .navigationTitle(course.title)
        .safeAreaInset(edge: .bottom) {
            if isImporting {
                HStack {
                    ProgressView("Checking and importing materials…")
                    Spacer()
                    Button("Cancel") { importTask?.cancel() }
                }
                .padding()
                .background(.regularMaterial)
            }
        }
        .onDisappear { importTask?.cancel() }
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true,
            onCompletion: importPDFs
        )
        .alert("Import failed", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .sheet(item: $editingWorkspace) { workspace in
            WorkspaceSequenceEditor(workspace: workspace) { sequence in
                correctSequence(for: workspace, to: sequence)
            }
        }
    }

    private func importPDFs(_ result: Result<[URL], Error>) {
        guard !isImporting else { return }
        isImporting = true
        importTask = Task {
            defer { isImporting = false; importTask = nil }
            do {
                let urls = try result.get()
                let prepared = try await StudyMaterialImporter.prepare(urls: urls, startingSequence: course.currentSequence)
                try Task.checkCancellation()
                guard !course.isDeleted else { return }
                try StudyMaterialImporter.commit(prepared, course: course, context: modelContext)
            } catch is CancellationError {
                // Preparation is read-only, so cancelling never leaves partial imports.
            } catch let error as CocoaError where error.code == .userCancelled {
            } catch {
                importError = error.localizedDescription
            }
        }
    }

    private func correctSequence(for workspace: StudyWorkspaceRecord, to sequence: Int) {
        guard sequence > 0 else { return }
        let sourceID = workspace.id
        let sourceAssets = allAssets.filter { $0.workspaceID == sourceID }

        if let destination = workspaces.first(where: { $0.sequence == sequence && $0.id != sourceID }) {
            for asset in sourceAssets {
                asset.workspaceID = destination.id
                asset.resolvedSequence = sequence
                asset.inferenceConfidence = 1
                asset.inferenceEvidence = "Manually corrected and merged into an existing lesson"
            }
            for note in allNotes where note.workspaceID == sourceID {
                note.workspaceID = destination.id
            }
            if destination.mainNoteID == nil { destination.mainNoteID = workspace.mainNoteID }
            for homework in allHomeworks where homework.workspaceID == sourceID {
                homework.workspaceID = destination.id
            }
            for todo in allTodos where todo.workspaceID == sourceID {
                todo.workspaceID = destination.id
            }
            if workspace.isCompleted {
                destination.isCompleted = true
                destination.completedAt = destination.completedAt ?? workspace.completedAt
            }
            modelContext.delete(workspace)
        } else {
            workspace.sequence = sequence
            workspace.title = "\(course.title) · Day \(sequence)"
            for asset in sourceAssets {
                asset.resolvedSequence = sequence
                asset.inferenceConfidence = 1
                asset.inferenceEvidence = "Manually corrected"
            }
        }
        do { try modelContext.save(); editingWorkspace = nil } catch {
            modelContext.rollback()
            importError = error.localizedDescription
        }
    }
}

private struct WorkspaceSequenceEditor: View {
    @Environment(\.dismiss) private var dismiss
    let workspace: StudyWorkspaceRecord
    let onSave: (Int) -> Void
    @State private var sequence: Int

    init(workspace: StudyWorkspaceRecord, onSave: @escaping (Int) -> Void) {
        self.workspace = workspace
        self.onSave = onSave
        _sequence = State(initialValue: workspace.sequence)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Lesson order") {
                    Stepper("Day \(sequence)", value: $sequence, in: 1...10_000)
                }
                Section {
                        Text("If that lesson already exists, its materials, notes, assignments, and tasks will be merged.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit \(workspace.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(sequence)
                        dismiss()
                    }
                }
            }
        }
    }
}
