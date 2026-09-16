import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct HomeworkLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \HomeworkDefinitionRecord.importedAt, order: .reverse) private var homeworks: [HomeworkDefinitionRecord]
    @Query(sort: \HomeworkAttemptRecord.createdAt, order: .reverse) private var attempts: [HomeworkAttemptRecord]
    @Query(sort: \StudyWorkspaceRecord.sequence) private var workspaces: [StudyWorkspaceRecord]

    @State private var showsImporter = false
    @State private var importError: String?

    var body: some View {
        List {
            if homeworks.isEmpty {
                ContentUnavailableView {
                    Label("No assignments yet", systemImage: "pencil.and.list.clipboard")
                } description: {
                    Text("Import .sshomework or JSON using schema version 1.")
                } actions: {
                    Button("Import assignment") { showsImporter = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                Section("Assignments") {
                    ForEach(homeworks) { homework in
                        NavigationLink(value: StudyRoute.homework(homework.id)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(homework.title).font(.headline)
                                let related = attempts.filter { $0.homeworkID == homework.id }
                                Text("\(homework.package?.questions.count ?? 0) questions · \(related.filter { $0.state == .submitted }.count) submissions")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Practice")
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.pageBackground)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showsImporter = true } label: { Label("Import assignment", systemImage: "square.and.arrow.down") }
            }
        }
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: [ProductFileType.homework, .json],
            onCompletion: importHomework
        )
        .alert("Assignment import failed", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    private func importHomework(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            if let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               fileSize > HomeworkImporter.maximumFileSize {
                throw HomeworkImportError.fileTooLarge
            }
            let package = try HomeworkImporter.decodeAndValidate(Data(contentsOf: url))
            guard !homeworks.contains(where: { $0.packageID == package.id }) else {
                throw HomeworkLibraryError.duplicate(package.id)
            }
            let matchingWorkspaces = workspaces.filter { $0.sequence == package.lessonSequence }
            let workspaceID = matchingWorkspaces.count == 1 ? matchingWorkspaces[0].id : nil
            modelContext.insert(HomeworkDefinitionRecord(
                package: package,
                sourceFileName: url.lastPathComponent,
                workspaceID: workspaceID
            ))
            try modelContext.save()
        } catch {
            modelContext.rollback()
            importError = error.localizedDescription
        }
    }

    private enum HomeworkLibraryError: LocalizedError {
        case duplicate(String)
        var errorDescription: String? {
            switch self { case .duplicate(let id): "An assignment with this ID already exists: \(id)" }
        }
    }
}

struct HomeworkDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var actionEngine: TodoActionEngine
    @Query(sort: \HomeworkAttemptRecord.createdAt, order: .reverse) private var allAttempts: [HomeworkAttemptRecord]
    @Query(sort: \TodoRecord.createdAt) private var todos: [TodoRecord]
    @Query(sort: \StudyWorkspaceRecord.sequence) private var workspaces: [StudyWorkspaceRecord]
    let homework: HomeworkDefinitionRecord

    @State private var attempt: HomeworkAttemptRecord?
    @State private var responses: [String: HomeworkResponse] = [:]
    @State private var showsResetConfirmation = false
    @State private var submissionError: String?

    private var package: HomeworkPackage? { homework.package }
    private var history: [HomeworkAttemptRecord] {
        allAttempts.filter { $0.homeworkID == homework.id && $0.state == .submitted }
    }

    var body: some View {
        Group {
            if let package, let attempt {
                if attempt.state == .submitted, let grade = attempt.grade {
                    HomeworkGradeView(
                        package: package,
                        attempt: attempt,
                        grade: grade,
                        onReset: { showsResetConfirmation = true }
                    )
                } else {
                    HomeworkAnswerView(
                        package: package,
                        attemptNumber: attempt.attemptNumber,
                        responses: $responses,
                        onAnswerChanged: persistDraft,
                        onSubmit: submit
                    )
                    .id(attempt.id)
                }
            } else if package == nil {
                ContentUnavailableView("Assignment data is damaged", systemImage: "exclamationmark.triangle")
            } else {
                ProgressView("Preparing your assignment…")
            }
        }
        .navigationTitle(homework.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    ForEach(allAttempts.filter { $0.homeworkID == homework.id }.sorted { $0.attemptNumber > $1.attemptNumber }) { item in
                        Button("Attempt \(item.attemptNumber) · \(item.state == .submitted ? "Submitted" : "Draft")") {
                            selectAttempt(item)
                        }
                    }
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .accessibilityLabel("Attempt history")

                Menu {
                    Button("Not linked") { linkWorkspace(nil) }
                    ForEach(workspaces) { workspace in
                        Button(workspace.title) {
                            linkWorkspace(workspace.id)
                        }
                    }
                } label: {
                    Image(systemName: "link")
                }
                .accessibilityLabel("Linked study materials")

                Button { showsResetConfirmation = true } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .accessibilityLabel("Start over")
            }
        }
        .task { prepareAttempt() }
        .confirmationDialog(
            "Start a new attempt?",
            isPresented: $showsResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("New blank attempt", role: .destructive) { resetAttempt() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Clear the current draft and start a blank attempt. Past submissions and task completion are kept.")
        }
        .alert("Assignment action failed", isPresented: Binding(get: { submissionError != nil }, set: { if !$0 { submissionError = nil } })) {
            Button("OK", role: .cancel) { submissionError = nil }
        } message: {
            Text(submissionError ?? "")
        }
    }

    private func prepareAttempt() {
        guard attempt == nil else { return }
        do {
            let value = try HomeworkAttemptService.currentOrLatest(for: homework.id, context: modelContext)
            attempt = value
            responses = value.answers
        } catch { submissionError = error.localizedDescription }
    }

    private func persistDraft() {
        do { try saveDraft() } catch { submissionError = "Answers were not saved. Your input is still on this page. \(error.localizedDescription)" }
    }

    private func saveDraft() throws {
        guard let attempt, attempt.state == .draft else { return }
        attempt.answers = responses
        attempt.updatedAt = Date()
        do { try modelContext.save() } catch { modelContext.rollback(); throw error }
    }

    private func selectAttempt(_ item: HomeworkAttemptRecord) {
        guard attempt?.id != item.id else { return }
        do {
            try saveDraft()
            responses = item.answers
            attempt = item
        } catch { submissionError = "Save the current draft before switching attempts. \(error.localizedDescription)" }
    }

    private func linkWorkspace(_ id: UUID?) {
        homework.workspaceID = id
        do { try modelContext.save() } catch {
            modelContext.rollback()
            submissionError = error.localizedDescription
        }
    }

    private func submit() {
        guard let package, let attempt else { return }
        do {
            try HomeworkAttemptService.submit(
                attempt: attempt,
                package: package,
                responses: responses,
                context: modelContext
            )
            let linked = todos.filter {
                $0.storedState != .completed &&
                $0.completionRule == .homeworkSubmission &&
                ($0.homeworkID == homework.id ||
                 (homework.workspaceID != nil && $0.homeworkID == nil && $0.workspaceID == homework.workspaceID))
            }
            Task {
                for todo in linked {
                    todo.homeworkID = homework.id
                    await actionEngine.complete(todo: todo, context: modelContext)
                }
            }
        } catch {
            submissionError = error.localizedDescription
        }
    }

    private func resetAttempt() {
        do {
            let fresh = try HomeworkAttemptService.reset(homeworkID: homework.id, context: modelContext)
            responses = [:]
            attempt = fresh
        } catch { submissionError = error.localizedDescription }
    }
}

private struct HomeworkAnswerView: View {
    let package: HomeworkPackage
    let attemptNumber: Int
    @Binding var responses: [String: HomeworkResponse]
    let onAnswerChanged: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Attempt \(attemptNumber)", systemImage: "pencil.line")
                    Spacer()
                    Text("\(answeredCount)/\(package.questions.count) answered")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline.weight(.semibold))

                ForEach(Array(package.questions.enumerated()), id: \.element.id) { index, question in
                    HomeworkQuestionCard(
                        index: index,
                        question: question,
                        response: responseBinding(for: question.id),
                        onChange: onAnswerChanged
                    )
                }

                Button(action: onSubmit) {
                    Text("Submit and review")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

            }
            .frame(maxWidth: 760)
            .padding(AppTheme.pagePadding)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.pageBackground)
    }

    private var answeredCount: Int {
        package.questions.filter { !(responses[$0.id] ?? HomeworkResponse()).isEmpty }.count
    }

    private func responseBinding(for id: String) -> Binding<HomeworkResponse> {
        Binding(
            get: { responses[id] ?? HomeworkResponse() },
            set: { responses[id] = $0 }
        )
    }
}

private struct HomeworkQuestionCard: View {
    let index: Int
    let question: HomeworkQuestion
    @Binding var response: HomeworkResponse
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(index + 1).")
                    .font(.headline)
                Text(question.prompt)
                    .font(.body.weight(.semibold))
                Spacer()
                Text("\(question.points.formatted()) points")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            switch question.type {
            case .singleChoice:
                ForEach(question.options ?? []) { option in
                    ChoiceRow(
                        option: option,
                        selected: response.selectedOptionIDs.contains(option.id),
                        allowsMultiple: false
                    ) {
                        response.selectedOptionIDs = [option.id]
                        onChange()
                    }
                }

            case .multipleChoice:
                ForEach(question.options ?? []) { option in
                    ChoiceRow(
                        option: option,
                        selected: response.selectedOptionIDs.contains(option.id),
                        allowsMultiple: true
                    ) {
                        if response.selectedOptionIDs.contains(option.id) {
                            response.selectedOptionIDs.removeAll { $0 == option.id }
                        } else {
                            response.selectedOptionIDs.append(option.id)
                        }
                        onChange()
                    }
                }
                Text("Select every correct option to earn points.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .fillBlank:
                TextField("Your answer", text: $response.text)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: response.text) { _, _ in onChange() }
                Text("Case and spaces must match exactly.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .openResponse:
                TextEditor(text: $response.text)
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(.background, in: RoundedRectangle(cornerRadius: 12))
                    .onChange(of: response.text) { _, _ in onChange() }
                Text("Open responses show a reference answer and are excluded from objective accuracy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct ChoiceRow: View {
    let option: HomeworkOption
    let selected: Bool
    let allowsMultiple: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? (allowsMultiple ? "checkmark.square.fill" : "circle.inset.filled") : (allowsMultiple ? "square" : "circle"))
                    .foregroundStyle(selected ? AppTheme.accent : .secondary)
                Text(option.text)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct HomeworkGradeView: View {
    let package: HomeworkPackage
    let attempt: HomeworkAttemptRecord
    let grade: HomeworkGradeSummary
    let onReset: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Results ready")
                        .font(.largeTitle.bold())
                    HStack(spacing: 18) {
                        GradeMetric(title: "Score", value: "\(grade.earnedPoints.formatted()) / \(grade.possiblePoints.formatted())")
                        GradeMetric(title: "Objective accuracy", value: grade.objectiveQuestions == 0 ? "—" : grade.objectiveAccuracy.formatted(.percent.precision(.fractionLength(0))))
                        GradeMetric(title: "Answered", value: "\(grade.answeredQuestions) / \(grade.totalQuestions)")
                    }
                }
                .appCard(padding: 18, radius: AppTheme.heroRadius)

                ForEach(Array(package.questions.enumerated()), id: \.element.id) { index, question in
                    let result = grade.results.first { $0.questionID == question.id }
                    let response = attempt.answers[question.id] ?? HomeworkResponse()
                    GradedQuestionCard(index: index, question: question, response: response, result: result)
                }

                Button("Reset and start a new attempt", role: .destructive, action: onReset)
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: 760)
            .padding(AppTheme.pagePadding)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.pageBackground)
    }
}

private struct GradeMetric: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline)
        }
    }
}

private struct GradedQuestionCard: View {
    let index: Int
    let question: HomeworkQuestion
    let response: HomeworkResponse
    let result: HomeworkQuestionResult?
    @State private var showsFeedback = false

    private var outcomeColor: Color {
        switch result?.outcome {
        case .correct: .green
        case .incorrect, .unanswered: .red
        case .awaitingSelfReview: .orange
        case nil: .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(index + 1). \(question.prompt)").font(.headline)
                Spacer()
                Text(outcomeTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(outcomeColor)
            }
            ReviewLine(title: "Your answer", value: responseText)
            ReviewLine(title: "Correct answer", value: correctAnswerText)
            ReviewLine(title: "Explanation", value: question.explanation.isEmpty ? "No explanation provided" : question.explanation)
            Text("Score: \((result?.earnedPoints ?? 0).formatted()) / \(question.points.formatted())")
                .font(.caption.weight(.semibold))
            Button { showsFeedback = true } label: {
                Label("Explain this question", systemImage: "sparkles")
            }.buttonStyle(.bordered)
        }
        .padding(16)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 18))
        .sheet(isPresented: $showsFeedback) {
            AIStudyView(source: AIStudySource(
                text: "Question: \(question.prompt)\nOptions: \((question.options ?? []).map { "\($0.id). \($0.text)" }.joined(separator: "\n"))\nMy answer: \(responseText)\nOriginal reference answer: \(correctAnswerText)\nOriginal explanation: \(question.explanation)",
                title: "Question \(index + 1)", operation: .feedback))
        }
    }

    private var outcomeTitle: String {
        switch result?.outcome {
        case .correct: "Correct"
        case .incorrect: "Incorrect"
        case .unanswered: "Unanswered"
        case .awaitingSelfReview: "Review yourself"
        case nil: "No result"
        }
    }

    private var responseText: String {
        if !response.selectedOptionIDs.isEmpty { return optionTexts(for: response.selectedOptionIDs) }
        return response.text.isEmpty ? "Unanswered" : response.text
    }

    private var correctAnswerText: String {
        if let ids = question.answer.selectedOptionIDs { return optionTexts(for: ids) }
        if let texts = question.answer.acceptedTexts { return texts.joined(separator: " / ") }
        return question.answer.referenceText ?? "Not provided"
    }

    private func optionTexts(for ids: [String]) -> String {
        let options = question.options ?? []
        return ids.map { id in options.first(where: { $0.id == id })?.text ?? id }.joined(separator: ", ")
    }
}

private struct ReviewLine: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }
}
