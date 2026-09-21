import SwiftData
import SwiftUI

struct TodoEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var actionEngine: TodoActionEngine
    @EnvironmentObject private var settings: AppSettings
    @Query(sort: \TodoRecord.originalScheduledAt) private var todos: [TodoRecord]
    @Query(sort: \CourseRecord.title) private var courses: [CourseRecord]
    @Query(sort: \NoteTemplateRecord.name) private var templates: [NoteTemplateRecord]
    @Query(sort: \HomeworkDefinitionRecord.importedAt, order: .reverse) private var homeworks: [HomeworkDefinitionRecord]
    @Query(sort: \VocabularyCoursewareRecord.title) private var vocabularyCoursewares: [VocabularyCoursewareRecord]
    @Query(sort: \VocabularyUnitRecord.sequence) private var vocabularyUnits: [VocabularyUnitRecord]

    @State private var quickPlan: TodoQuickPlan = .basic
    @State private var title = ""
    @State private var details = ""
    @State private var kind: TodoKind = .general
    @State private var trigger: TodoTriggerKind = .manual
    @State private var scheduledAt = Date().addingTimeInterval(3600)
    @State private var recurrence: RecurrencePolicy = .none
    @State private var missedPolicy: MissedOccurrencePolicy = .carryForward
    @State private var completionRule: TodoCompletionRule = .manual
    @State private var selectedCourseID: UUID?
    @State private var selectedTemplateID: UUID?
    @State private var selectedHomeworkID: UUID?
    @State private var selectedVocabularyCoursewareID: UUID?
    @State private var selectedVocabularyUnitID: UUID?
    @State private var prerequisiteIDs = Set<UUID>()
    @State private var actions: [TodoAction] = []
    @State private var didApplyInitialPlan = false
    @State private var isSaving = false
    @State private var saveError: String?
    @FocusState private var isTitleFocused: Bool

    private let editingTodoID: UUID?

    init(todo: TodoRecord? = nil) {
        let existingActions = todo?.actions ?? []
        editingTodoID = todo?.id
        _quickPlan = State(initialValue: todo == nil ? .basic : .custom)
        _title = State(initialValue: todo?.title ?? "")
        _details = State(initialValue: todo?.details ?? "")
        _kind = State(initialValue: todo?.kind ?? .general)
        _trigger = State(initialValue: todo?.triggerKind ?? .manual)
        _scheduledAt = State(initialValue: todo?.originalScheduledAt ?? Date().addingTimeInterval(3600))
        _recurrence = State(initialValue: todo?.recurrence ?? .none)
        _missedPolicy = State(initialValue: todo?.missedPolicy ?? .carryForward)
        _completionRule = State(initialValue: todo?.completionRule ?? .manual)
        _selectedCourseID = State(initialValue: todo?.courseID ?? existingActions.compactMap(\.parameters.courseID).first)
        _selectedTemplateID = State(initialValue: existingActions.first(where: { $0.kind == .createNote })?.parameters.noteTemplateID)
        _selectedHomeworkID = State(initialValue: todo?.homeworkID ?? existingActions.compactMap(\.parameters.homeworkID).first)
        _selectedVocabularyCoursewareID = State(
            initialValue: todo?.vocabularyCoursewareID
                ?? existingActions.compactMap(\.parameters.vocabularyCoursewareID).first
        )
        _selectedVocabularyUnitID = State(
            initialValue: todo?.vocabularyUnitID
                ?? existingActions.compactMap(\.parameters.vocabularyUnitID).first
        )
        _prerequisiteIDs = State(initialValue: Set(todo?.prerequisiteIDs ?? []))
        _actions = State(initialValue: existingActions)
    }

    private var selectableTodos: [TodoRecord] {
        todos.filter {
            $0.id != editingTodoID &&
            ($0.storedState != .completed || prerequisiteIDs.contains($0.id)) &&
            $0.storedState != .cancelled
        }
    }

    private var activationActionIndices: [Int] {
        actions.indices.filter { actions[$0].phase == .activation }
    }

    private var completionActionIndices: [Int] {
        actions.indices.filter { actions[$0].phase == .completion }
    }

    private var actionsRequiringCourse: Bool {
        actions.contains {
            $0.isEnabled && [.createWorkspace, .createNote, .resolveCourseMaterial, .updateCourseProgress].contains($0.kind)
        }
    }

    private var showsVocabularyAssociation: Bool {
        kind == .vocabulary ||
        completionRule == .vocabularyUnitCompletion ||
        completionRule == .vocabularyCoursewareCompletion ||
        completionRule == .vocabularyReviewSession ||
        actions.contains { $0.isEnabled && $0.kind == .openVocabularyReview }
    }

    private var selectedVocabularyUnits: [VocabularyUnitRecord] {
        guard let selectedVocabularyCoursewareID else { return [] }
        return vocabularyUnits
            .filter { $0.coursewareID == selectedVocabularyCoursewareID && $0.isActive }
            .sorted { lhs, rhs in
                if lhs.sequence == rhs.sequence { return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending }
                return lhs.sequence < rhs.sequence
            }
    }

    private var validationMessage: String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter a task title first."
        }
        if trigger == .dependencyCompletion && prerequisiteIDs.isEmpty {
            return "A task sequence needs at least one prerequisite."
        }
        if let editingTodoID, trigger == .dependencyCompletion,
           TodoDependencyValidator.createsCycle(todoID: editingTodoID, prerequisites: prerequisiteIDs, allTodos: todos) {
            return "These tasks would wait for each other. Choose a different prerequisite."
        }
        if trigger == .dependencyCompletion, !prerequisiteIDs.isSubset(of: Set(todos.map(\.id))) {
            return "A prerequisite was deleted. Select another one."
        }
        if (actionsRequiringCourse || completionRule == .lessonCompletion), selectedCourseID == nil {
            return "This workflow requires a linked course."
        }
        if completionRule == .homeworkSubmission && selectedHomeworkID == nil {
            return "Select the assignment whose submission completes this task."
        }
        if trigger == .scheduledTime && recurrence != .none &&
            (completionRule == .vocabularyUnitCompletion || completionRule == .vocabularyCoursewareCompletion) {
            return "First learning happens once. Choose a word review session for a repeating task."
        }
        if (completionRule == .vocabularyCoursewareCompletion || completionRule == .vocabularyReviewSession) && selectedVocabularyCoursewareID == nil {
            return "Select the word collection that completes this task."
        }
        if completionRule == .vocabularyUnitCompletion,
           selectedVocabularyCoursewareID == nil || selectedVocabularyUnitID == nil {
            return "Select the word unit that completes this task."
        }
        if let selectedVocabularyUnitID,
           !selectedVocabularyUnits.contains(where: { $0.id == selectedVocabularyUnitID }) {
            return "The selected word unit is not in this collection. Select another unit."
        }
        if actions.contains(where: {
            $0.isEnabled && $0.kind == .runShortcut &&
            $0.parameters.shortcutName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) {
            return "Enter the shortcut name."
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TodoFlowOverview(
                        start: startSummary,
                        task: taskSummary,
                        activation: actionSummary(for: .activation),
                        completion: completionSummary
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(TodoQuickPlan.allCases) { plan in
                                TodoQuickPlanCard(
                                    plan: plan,
                                    isSelected: quickPlan == plan,
                                    select: { select(plan) }
                                )
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("Quick start")
                }

                Section {
                    Picker("Start condition", selection: $trigger) {
                        ForEach(TodoTriggerKind.creationOptions) { trigger in
                            Text(trigger.title).tag(trigger)
                        }
                    }

                    if trigger == .scheduledTime || trigger == .dependencyCompletion {
                        DatePicker(
                            trigger == .scheduledTime ? "Start time" : "Preferred start time",
                            selection: $scheduledAt
                        )
                    }

                    if trigger == .dependencyCompletion {
                        if selectableTodos.isEmpty {
                            Label("Create another task first to use it as a prerequisite.", systemImage: "link.badge.plus")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(selectableTodos) { todo in
                                Button {
                                    togglePrerequisite(todo.id)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(todo.title)
                                                .foregroundStyle(.primary)
                                            Text(todo.originalScheduledAt.formatted(date: .abbreviated, time: .shortened))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: prerequisiteIDs.contains(todo.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(prerequisiteIDs.contains(todo.id) ? AppTheme.accent : .secondary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if trigger == .scheduledTime {
                        Picker("Repeat", selection: $recurrence) {
                            ForEach(RecurrencePolicy.allCases) { policy in
                                Text(policy.title).tag(policy)
                            }
                        }

                        if recurrence != .none {
                            Picker("If missed", selection: $missedPolicy) {
                                ForEach(MissedOccurrencePolicy.allCases) { policy in
                                    Text(policy.title).tag(policy)
                                }
                            }
                            Text("Carry overdue tasks forward. Finish the current one before starting the next.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    TodoStepHeader(number: 1, title: "When to start", subtitle: "Now, on a schedule, or after another task.")
                }

                Section {
                    TextField("For example: Review chapter 3", text: $title)
                        .focused($isTitleFocused)
                        .submitLabel(.done)
                    TextField("Details (optional)", text: $details, axis: .vertical)
                        .lineLimit(2...5)
                    Picker("Category (optional)", selection: $kind) {
                        ForEach(TodoKind.allCases) { kind in
                            Label(kind.title, systemImage: kind.icon).tag(kind)
                        }
                    }
                } header: {
                    TodoStepHeader(number: 2, title: "What to do", subtitle: "")
                }

                actionSection(phase: .activation, step: 3, title: "Actions on start")

                Section {
                    Picker("Linked course", selection: $selectedCourseID) {
                        Text("Not linked").tag(UUID?.none)
                        ForEach(courses) { course in
                            Text(course.title).tag(Optional(course.id))
                        }
                    }

                    if actions.contains(where: { $0.kind == .createNote }) {
                        Picker("Note templates", selection: $selectedTemplateID) {
                            Text("Use default template").tag(UUID?.none)
                            ForEach(templates) { template in
                                Text("\(template.name) · v\(template.version)").tag(Optional(template.id))
                            }
                        }
                    }

                    if actions.contains(where: { $0.kind == .openHomework }) || completionRule == .homeworkSubmission {
                        Picker("Linked assignment", selection: $selectedHomeworkID) {
                            Text("Open assignment library").tag(UUID?.none)
                            ForEach(homeworks) { homework in
                                Text(homework.title).tag(Optional(homework.id))
                            }
                        }
                    }

                    if showsVocabularyAssociation {
                        Picker("Linked word collection", selection: $selectedVocabularyCoursewareID) {
                            Text("Not linked").tag(UUID?.none)
                            ForEach(vocabularyCoursewares) { courseware in
                                Text(courseware.title).tag(Optional(courseware.id))
                            }
                        }

                        if selectedVocabularyCoursewareID != nil {
                            Picker("Unit (optional)", selection: $selectedVocabularyUnitID) {
                                Text("Entire collection").tag(UUID?.none)
                                ForEach(selectedVocabularyUnits) { unit in
                                    Text("\(unit.sequence). \(unit.title)").tag(Optional(unit.id))
                                }
                            }
                            Text("Completion is based on whole units, not a word-count target.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if courses.isEmpty {
                        Text("No courses yet. You can still create tasks that do not need a workspace.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Linked content (optional)")
                } footer: {
                    Text("Choose a course for study materials or a collection for words.")
                }

                Section {
                    Picker("Completion rule", selection: $completionRule) {
                        ForEach(TodoCompletionRule.allCases) { rule in
                            Text(rule.title).tag(rule)
                        }
                    }

                    Text(completionRuleExplanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    TodoStepHeader(number: 4, title: "When it is complete", subtitle: "The app's completion state is authoritative.")
                }

                actionSection(phase: .completion, step: 5, title: "Actions after completion")

                if let validationMessage, !title.isEmpty {
                    Section {
                        Label(validationMessage, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(editingTodoID == nil ? "New task" : "Edit task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving" : (editingTodoID == nil ? "Create" : "Save")) { save() }
                        .disabled(validationMessage != nil || isSaving || actionEngine.isRunning)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Dismiss keyboard") { isTitleFocused = false }
                }
            }
            .onAppear {
                guard !didApplyInitialPlan else { return }
                didApplyInitialPlan = true
                guard editingTodoID == nil else { return }
                missedPolicy = settings.defaultMissedPolicy
                selectedTemplateID = settings.defaultTemplateID
                apply(.basic)
            }
            .alert(editingTodoID == nil ? "Could not create task" : "Could not save task", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    @ViewBuilder
    private func actionSection(phase: TodoActionPhase, step: Int, title: String) -> some View {
        let indices = phase == .activation ? activationActionIndices : completionActionIndices
        Section {
            if indices.isEmpty {
                Label(
                    phase == .activation ? "No automatic actions. Show the task directly." : "Finish here after completion.",
                    systemImage: phase == .activation ? "hand.tap" : "flag.checkered"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            ForEach(Array(indices.enumerated()), id: \.element) { position, index in
                TodoActionEditorRow(
                    action: $actions[index],
                    canMoveUp: position > 0,
                    canMoveDown: position < indices.count - 1,
                    moveUp: { moveAction(at: index, in: phase, by: -1) },
                    moveDown: { moveAction(at: index, in: phase, by: 1) },
                    remove: { actions.remove(at: index) }
                )
            }

            Menu {
                ForEach(TodoActionKind.creationOptions) { kind in
                    Button {
                        actions.append(defaultAction(kind: kind, phase: phase))
                    } label: {
                        Label(kind.title, systemImage: kind.icon)
                    }
                }
            } label: {
                Label(phase == .activation ? "Add start action" : "Add completion action", systemImage: "plus.circle")
            }
        } header: {
            TodoStepHeader(
                number: step,
                title: title,
                subtitle: phase == .activation
                    ? "Notify, open content, or create notes."
                    : "Optional."
            )
        } footer: {
            Text("Run in order. Failed actions can be retried.")
        }
    }

    private var startSummary: String {
        switch trigger {
        case .manual:
            "Start anytime"
        case .scheduledTime:
            scheduledAt.formatted(date: .abbreviated, time: .shortened)
        case .dependencyCompletion:
            prerequisiteIDs.isEmpty ? "Choose prerequisites" : "Wait for \(prerequisiteIDs.count) tasks"
        case .courseProgress:
            "When progress changes"
        }
    }

    private var taskSummary: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Enter a task title" : trimmed
    }

    private var completionSummary: String {
        let base = switch completionRule {
        case .manual: "Mark complete in the app"
        case .homeworkSubmission: "After submitting practice"
        case .lessonCompletion: "After finishing the lesson"
        case .vocabularyUnitCompletion: "After studying the word unit"
        case .vocabularyCoursewareCompletion: "After first studying the whole collection"
        case .vocabularyReviewSession: "After finishing a word review session"
        }
        let after = actionSummary(for: .completion)
        return completionActionIndices.isEmpty ? base : "\(base) · \(after)"
    }

    private var completionRuleExplanation: String {
        switch completionRule {
        case .manual:
            "Alarms and opened notifications or materials do not complete the task. Confirm completion in the app."
        case .homeworkSubmission:
            "Complete after the selected assignment is submitted and graded locally."
        case .lessonCompletion:
            "Complete after marking the lesson finished in its workspace."
        case .vocabularyUnitCompletion:
            "Complete after every word in this unit receives its first rating. Difficult words remain scheduled for review."
        case .vocabularyCoursewareCompletion:
            "Complete after every unit has been studied once. Reviews never reopen completed tasks."
        case .vocabularyReviewSession:
            "Complete after a nonempty review session in this collection or unit. Repeating tasks require a new session on their scheduled day or later."
        }
    }

    private func actionSummary(for phase: TodoActionPhase) -> String {
        let selected = actions.filter { $0.phase == phase && $0.isEnabled }
        guard !selected.isEmpty else { return phase == .activation ? "No automatic actions" : "Finish here" }
        let titles = selected.prefix(2).map(\.kind.title)
        return selected.count > 2 ? titles.joined(separator: ", ") + " and more" : titles.joined(separator: ", ")
    }

    private func select(_ plan: TodoQuickPlan) {
        quickPlan = plan
        apply(plan)
    }

    private func apply(_ plan: TodoQuickPlan) {
        completionRule = .manual
        selectedHomeworkID = nil
        selectedVocabularyCoursewareID = nil
        selectedVocabularyUnitID = nil

        switch plan {
        case .basic:
            kind = .general
            trigger = .manual
            recurrence = .none
            actions = []

        case .reminder:
            kind = .general
            trigger = .scheduledTime
            ensureFutureSchedule()
            recurrence = .none
            actions = [
                TodoAction(
                    kind: .localNotification,
                    phase: .activation,
                    isCritical: false,
                    parameters: .init(message: "Time for this task.")
                )
            ]

        case .alarm:
            kind = .general
            trigger = .scheduledTime
            ensureFutureSchedule()
            recurrence = .none
            actions = [
                TodoAction(
                    kind: .scheduleAlarm,
                    phase: .activation,
                    isCritical: false,
                    parameters: .init(alarmTarget: settings.defaultAlarmTarget)
                )
            ]

        case .openContent:
            kind = .study
            trigger = .manual
            recurrence = .none
            actions = [TodoAction(kind: .openStudy, phase: .activation, isCritical: false)]
            if selectedCourseID == nil, courses.count == 1 {
                selectedCourseID = courses.first?.id
            }

        case .chained:
            kind = .general
            trigger = .dependencyCompletion
            ensureFutureSchedule()
            recurrence = .none
            actions = []

        case .recurring:
            kind = .general
            trigger = .scheduledTime
            ensureFutureSchedule()
            recurrence = .daily
            actions = [
                TodoAction(
                    kind: .localNotification,
                    phase: .activation,
                    isCritical: false,
                    parameters: .init(message: "Time for this recurring task.")
                )
            ]

        case .custom:
            kind = .general
            trigger = .manual
            recurrence = .none
            actions = []
        }
    }

    private func ensureFutureSchedule() {
        if scheduledAt <= Date() {
            scheduledAt = Date().addingTimeInterval(3600)
        }
    }

    private func togglePrerequisite(_ id: UUID) {
        if prerequisiteIDs.contains(id) {
            prerequisiteIDs.remove(id)
        } else {
            prerequisiteIDs.insert(id)
        }
    }

    private func moveAction(at index: Int, in phase: TodoActionPhase, by offset: Int) {
        let indices = actions.indices.filter { actions[$0].phase == phase }
        guard let position = indices.firstIndex(of: index) else { return }
        let destination = position + offset
        guard indices.indices.contains(destination) else { return }
        actions.swapAt(index, indices[destination])
    }

    private func defaultAction(kind: TodoActionKind, phase: TodoActionPhase) -> TodoAction {
        var parameters = TodoActionParameters()
        if kind == .scheduleAlarm { parameters.alarmTarget = settings.defaultAlarmTarget }
        if kind == .localNotification { parameters.message = "Time for this task." }
        if kind == .openVocabularyReview {
            parameters.vocabularyCoursewareID = selectedVocabularyCoursewareID
            parameters.vocabularyUnitID = selectedVocabularyUnitID
        }
        return TodoAction(kind: kind, phase: phase, parameters: parameters)
    }

    private func save() {
        guard validationMessage == nil, !isSaving, !actionEngine.isRunning else { return }
        isTitleFocused = false
        isSaving = true

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        var configuredActions = actions.map { action in
            var updated = action
            updated.parameters.courseID = selectedCourseID
            updated.parameters.homeworkID = selectedHomeworkID
            updated.parameters.vocabularyCoursewareID = selectedVocabularyCoursewareID
            updated.parameters.vocabularyUnitID = selectedVocabularyUnitID
            if updated.kind == .createNote { updated.parameters.noteTemplateID = selectedTemplateID }
            return updated
        }

        if let editingTodoID {
            guard let todo = todos.first(where: { $0.id == editingTodoID }) else {
                isSaving = false
                saveError = "This task was not found. It may have been deleted on another device."
                return
            }

            let wasManualTrigger = todo.triggerKind == .manual
            let scheduleChanged = todo.triggerKind != trigger || (trigger != .manual && todo.originalScheduledAt != scheduledAt)
            let associationChanged = todo.courseID != selectedCourseID || todo.homeworkID != selectedHomeworkID
            let previousActions = todo.actions
            configuredActions = configuredActions.map { action in
                guard let previous = previousActions.first(where: { $0.id == action.id }),
                      previous.kind == action.kind, previous.phase == action.phase,
                      previous.parameters == action.parameters, previous.isEnabled == action.isEnabled,
                      !scheduleChanged, !associationChanged else { return resetRuntime(action) }
                return previous
            }
            let timedKinds: Set<TodoActionKind> = [.scheduleAlarm, .localNotification, .vocabularyReminder]
            let resetTimedEffects = scheduleChanged || configuredActions.filter { timedKinds.contains($0.kind) } != previousActions.filter { timedKinds.contains($0.kind) }
            if associationChanged { todo.workspaceID = nil }
            todo.title = trimmedTitle
            todo.details = trimmedDetails
            todo.kind = kind
            todo.triggerKind = trigger
            if trigger == .manual {
                if !wasManualTrigger {
                    todo.originalScheduledAt = Date()
                }
            } else {
                todo.originalScheduledAt = scheduledAt
            }
            todo.recurrence = trigger == .scheduledTime ? recurrence : .none
            todo.missedPolicy = missedPolicy
            todo.completionRule = completionRule
            todo.courseID = selectedCourseID
            todo.homeworkID = selectedHomeworkID
            todo.vocabularyCoursewareID = selectedVocabularyCoursewareID
            todo.vocabularyUnitID = selectedVocabularyUnitID
            todo.prerequisiteIDs = trigger == .dependencyCompletion || (trigger == .scheduledTime && recurrence != .none) ? Array(prerequisiteIDs) : []
            todo.actions = configuredActions
            if resetTimedEffects { todo.alarmState = .notRequested }
            todo.lastActionError = nil
            todo.storedState = .scheduled
            todo.storedState = TodoStateResolver.state(for: todo, allTodos: todos)
            todo.updatedAt = Date()

            do {
                try modelContext.save()
            } catch {
                modelContext.rollback()
                isSaving = false
                saveError = "Could not save: \(error.localizedDescription)"
                return
            }

            isSaving = false
            Task {
                if resetTimedEffects {
                    guard await actionEngine.cancelScheduledEffects(todoID: todo.id, context: modelContext) else { return }
                }
                if todo.triggerKind == .scheduledTime {
                    await actionEngine.prepareScheduledActions(todo: todo, context: modelContext)
                } else if todo.storedState != .waitingDependency && todo.triggerKind != .manual {
                    await actionEngine.activate(todo: todo, context: modelContext)
                }
                await actionEngine.syncTodoReminders(context: modelContext, requestAccess: true)
                await actionEngine.syncTodoNotifications(context: modelContext, requestAccess: true)
            }
            dismiss()
            return
        }

        let todo = TodoRecord(
            title: trimmedTitle,
            details: trimmedDetails,
            kind: kind,
            triggerKind: trigger,
            scheduledAt: trigger == .manual ? Date() : scheduledAt
        )
        todo.recurrence = trigger == .scheduledTime ? recurrence : .none
        todo.missedPolicy = missedPolicy
        todo.completionRule = completionRule
        todo.courseID = selectedCourseID
        todo.homeworkID = selectedHomeworkID
        todo.vocabularyCoursewareID = selectedVocabularyCoursewareID
        todo.vocabularyUnitID = selectedVocabularyUnitID
        todo.prerequisiteIDs = trigger == .dependencyCompletion ? Array(prerequisiteIDs) : []
        todo.actions = configuredActions
        todo.storedState = TodoStateResolver.state(for: todo, allTodos: todos + [todo])
        modelContext.insert(todo)

        do {
            try modelContext.save()
        } catch {
            modelContext.delete(todo)
            isSaving = false
            saveError = "Could not save: \(error.localizedDescription)"
            return
        }

        isSaving = false
        Task {
            if todo.triggerKind == .scheduledTime {
                await actionEngine.prepareScheduledActions(todo: todo, context: modelContext)
            } else if todo.storedState != .waitingDependency && todo.triggerKind != .manual {
                await actionEngine.activate(todo: todo, context: modelContext)
            }
            await actionEngine.syncTodoReminders(context: modelContext, requestAccess: true)
            await actionEngine.syncTodoNotifications(context: modelContext, requestAccess: true)
        }
        dismiss()
    }

    private func resetRuntime(_ action: TodoAction) -> TodoAction {
        var reset = action
        reset.state = .pending
        reset.idempotencyKey = UUID().uuidString
        reset.attemptCount = 0
        reset.startedAt = nil
        reset.finishedAt = nil
        reset.errorMessage = nil
        return reset
    }
}

private struct TodoFlowOverview: View {
    let start: String
    let task: String
    let activation: String
    let completion: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Task flow preview", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.headline)
                .foregroundStyle(AppTheme.accent)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    node(number: 1, title: "Start", value: start)
                        .frame(width: 145)
                    connector("chevron.right")
                    node(number: 2, title: "Task", value: task)
                        .frame(width: 145)
                    connector("chevron.right")
                    node(number: 3, title: "On start", value: activation)
                        .frame(width: 145)
                    connector("chevron.right")
                    node(number: 4, title: "Done", value: completion)
                        .frame(width: 145)
                }
                .fixedSize(horizontal: true, vertical: false)

                VStack(spacing: 5) {
                    HStack(spacing: 6) {
                        node(number: 1, title: "Start", value: start)
                        connector("chevron.right")
                        node(number: 2, title: "Task", value: task)
                    }
                    HStack(spacing: 6) {
                        Spacer()
                        connector("chevron.down")
                            .frame(maxWidth: .infinity)
                    }
                    HStack(spacing: 6) {
                        node(number: 4, title: "Done", value: completion)
                        connector("chevron.left")
                        node(number: 3, title: "On start", value: activation)
                    }
                }
            }
        }
        .appCard(padding: 16, radius: AppTheme.heroRadius)
        .padding(.vertical, 6)
    }

    private func node(number: Int, title: String, value: String) -> some View {
        HStack(spacing: 9) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(AppTheme.accent, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .padding(10)
        .background(AppTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: 14))
    }

    private func connector(_ name: String) -> some View {
        Image(systemName: name)
            .font(.caption.bold())
            .foregroundStyle(AppTheme.accent.opacity(0.7))
    }
}

private struct TodoQuickPlanCard: View {
    let plan: TodoQuickPlan
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: plan.icon)
                    .font(.title3)
                    .foregroundStyle(isSelected ? .white : AppTheme.accent)
                Text(plan.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : .primary)
            }
            .frame(width: 132, alignment: .leading)
            .padding(12)
            .background(isSelected ? AppTheme.accent : AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.clear : Color.secondary.opacity(0.18))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(plan.title)，\(plan.subtitle)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct TodoStepHeader: View {
    let number: Int
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Text("\(number)")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(AppTheme.accent, in: Circle())
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .textCase(nil)
        .padding(.vertical, 2)
    }
}

private struct TodoActionEditorRow: View {
    @Binding var action: TodoAction
    let canMoveUp: Bool
    let canMoveDown: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(action.kind.title, systemImage: action.kind.icon)
                    .font(.headline)
                Spacer()
                Menu {
                    Button("Move up", systemImage: "arrow.up", action: moveUp)
                        .disabled(!canMoveUp)
                    Button("Move down", systemImage: "arrow.down", action: moveDown)
                        .disabled(!canMoveDown)
                    Divider()
                    Button("Remove action", systemImage: "trash", role: .destructive, action: remove)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
                .accessibilityLabel("Action menu")
            }

            if action.kind == .scheduleAlarm {
                Picker("Alarm device", selection: $action.parameters.alarmTarget) {
                    ForEach(AlarmTarget.allCases) { target in
                        Text(target.title).tag(target)
                    }
                }
                .onChange(of: action.parameters.alarmTarget) { _, target in
                    action.parameters.alarmTargetDeviceID = target == .currentIPad ? DeviceIdentity.id : nil
                }
            }

            if action.kind == .localNotification || action.kind == .vocabularyReminder {
                TextField("Reminder message", text: $action.parameters.message, axis: .vertical)
                Stepper(
                    action.parameters.reminderOffsetMinutes == 0
                        ? "Notify at the scheduled time"
                        : "Offset: \(action.parameters.reminderOffsetMinutes) minutes",
                    value: $action.parameters.reminderOffsetMinutes,
                    in: -1440...1440,
                    step: 5
                )
                Stepper(
                    action.parameters.reminderRepeatMinutes == 0
                        ? "No follow-up notifications"
                        : "Repeat every \(action.parameters.reminderRepeatMinutes) minutes until complete",
                    value: $action.parameters.reminderRepeatMinutes,
                    in: 0...240,
                    step: 15
                )
            }

            if action.kind == .runShortcut {
                TextField("Shortcut name", text: $action.parameters.shortcutName)
                Text("Opens Apple Shortcuts. Completion is still recorded in this app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if action.kind == .openVocabularyReview {
                Text("Opens the linked word collection or unit. Choose it under Linked content below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            DisclosureGroup("More settings") {
                Picker("Execution phase", selection: $action.phase) {
                    ForEach(TodoActionPhase.allCases) { phase in
                        Text(phase.title).tag(phase)
                    }
                }
                Toggle("Enable this action", isOn: $action.isEnabled)
                Toggle("Block later steps on failure", isOn: $action.isCritical)
            }
            .font(.subheadline)
        }
        .padding(.vertical, 4)
    }
}
