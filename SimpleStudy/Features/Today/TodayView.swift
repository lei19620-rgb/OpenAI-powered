import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var persistence: PersistenceController
    @EnvironmentObject private var actionEngine: TodoActionEngine
    @EnvironmentObject private var router: AppRouter
    @Query(sort: \TodoRecord.originalScheduledAt) private var todos: [TodoRecord]

    @State private var showsEditor = false
    @State private var editingTodo: TodoRecord?
    @State private var deleteTarget: TodoRecord?
    @State private var deleteError: String?
    @State private var isDeleting = false
    @State private var showsCompletedHistory = false
    @State private var showsWaiting = false
    @State private var showsUpcoming = false

    private var activeTodos: [TodoRecord] {
        todos.filter { $0.storedState != .completed && $0.storedState != .cancelled }
    }

    private var completedTodos: [TodoRecord] {
        todos.filter { $0.storedState == .completed }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    private var availableTodos: [TodoRecord] {
        activeTodos.filter {
            let state = TodoStateResolver.state(for: $0, allTodos: todos)
            return state != .waitingDependency && state != .scheduled
        }
    }

    private var waitingTodos: [TodoRecord] {
        activeTodos.filter { TodoStateResolver.state(for: $0, allTodos: todos) == .waitingDependency }
    }

    private var upcomingTodos: [TodoRecord] {
        activeTodos.filter { TodoStateResolver.state(for: $0, allTodos: todos) == .scheduled }
    }

    var body: some View {
        NavigationStack {
          ScrollViewReader { reader in
            List {
                TodayHeader(activeCount: availableTodos.count, completedCount: completedTodos.filter {
                    $0.completedAt.map { Calendar.current.isDateInToday($0) } ?? false
                }.count)
                    .todayListRow()
                TodoHowItWorksCard { showsEditor = true }
                    .todayListRow()

                Picker("Task filter", selection: $showsCompletedHistory) {
                    Text("Pending · \(activeTodos.count)").tag(false)
                    Text("Completed · \(completedTodos.count)").tag(true)
                }
                .pickerStyle(.segmented)
                .todayListRow()

                if showsCompletedHistory {
                    if completedTodos.isEmpty {
                        ContentUnavailableView("No completed tasks yet", systemImage: "checkmark.circle")
                            .todayListRow()
                    }
                    taskRows(completedTodos)
                } else if activeTodos.isEmpty {
                    ContentUnavailableView {
                        Label("No tasks yet", systemImage: "checklist")
                    } description: {
                        Text("Start with one thing you want to do.")
                    } actions: {
                        Button("New task") { showsEditor = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(minHeight: 230)
                    .todayListRow()
                } else {
                    if !availableTodos.isEmpty {
                        Section("Ready now") { taskRows(availableTodos) }
                            .textCase(nil)
                    } else {
                        Label("Everything is scheduled", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 16)
                            .todayListRow()
                    }
                    if !waitingTodos.isEmpty {
                        DisclosureGroup("Waiting · \(waitingTodos.count)", isExpanded: $showsWaiting) {
                            taskRows(waitingTodos)
                        }
                        .todayListRow()
                    }
                    if !upcomingTodos.isEmpty {
                        DisclosureGroup("Upcoming · \(upcomingTodos.count)", isExpanded: $showsUpcoming) {
                            taskRows(upcomingTodos)
                        }
                        .todayListRow()
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AppTheme.pageBackground)
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showsEditor = true } label: {
                        Label("New task", systemImage: "plus")
                    }
                }
            }
            .task(id: router.requestedTodoID) {
                guard let id = router.requestedTodoID, let todo = todos.first(where: { $0.id == id }) else { return }
                showsCompletedHistory = todo.storedState == .completed
                showsWaiting = true
                showsUpcoming = true
                do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
                withAnimation { reader.scrollTo(id, anchor: .center) }
                router.requestedTodoID = nil
            }
            .sheet(isPresented: $showsEditor) {
                TodoEditorView()
            }
            .sheet(item: $editingTodo) { todo in
                TodoEditorView(todo: todo)
            }
            .confirmationDialog(
                deleteDialogTitle,
                isPresented: Binding(
                    get: { deleteTarget != nil },
                    set: { if !$0 { deleteTarget = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let deleteTarget {
                    Button(deleteActionTitle, role: .destructive) {
                        let target = deleteTarget
                        self.deleteTarget = nil
                        Task { @MainActor in
                            await deleteTodo(target)
                        }
                    }
                    .disabled(isDeleting)
                }
                Button("Cancel", role: .cancel) { deleteTarget = nil }
            } message: {
                Text(deleteDialogMessage)
            }
            .alert("Could not delete", isPresented: Binding(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            )) {
                Button("OK", role: .cancel) { deleteError = nil }
            } message: {
                Text(deleteError ?? "")
            }
            .task {
                openDebugEditorIfNeeded()
                guard !AppPreviewSupport.isPreview, !AppPreviewSupport.isUnitTesting else { return }
                await actionEngine.refreshAndActivateReadyTasks(context: modelContext)
                await actionEngine.processPendingDeviceAlarms(context: modelContext)
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(30)) } catch { return }
                    await actionEngine.refreshAndActivateReadyTasks(context: modelContext)
                }
            }
          }
        }
    }

    @ViewBuilder
    private func taskRows(_ records: [TodoRecord]) -> some View {
        ForEach(records) { todo in
            TodoCard(todo: todo, allTodos: todos,
                     onEdit: todo.storedState == .completed ? nil : { editingTodo = todo },
                     onDelete: { deleteTarget = todo })
                .todayListRow()
                .id(todo.id)
        }
    }

    private var dependentTodosForDeletion: [TodoRecord] {
        guard let deleteTarget else { return [] }
        return todos.filter {
            $0.id != deleteTarget.id && $0.prerequisiteIDs.contains(deleteTarget.id)
        }
    }

    private var deleteDialogTitle: String {
        deleteTarget?.storedState == .completed ? "Delete this completed record?" : "Delete this task?"
    }

    private var deleteActionTitle: String {
        dependentTodosForDeletion.isEmpty ? "Delete task" : "Delete and unlink"
    }

    private var deleteDialogMessage: String {
        let historyNote = deleteTarget?.storedState == .completed ? "Assignment submission history will be kept." : ""
        if dependentTodosForDeletion.isEmpty {
            return "Only this task and its reminders will be deleted. Linked courses, notes, and assignments will be kept. \(historyNote)"
        }
        return "\(dependentTodosForDeletion.count) tasks depend on this one. Deleting it removes those dependencies but keeps downstream tasks, courses, notes, and assignments. \(historyNote)"
    }

    private func deleteTodo(_ todo: TodoRecord) async {
        guard !isDeleting else { return }
        isDeleting = true
        do {
            try await actionEngine.delete(todo: todo, context: modelContext)
        } catch {
            deleteError = error.localizedDescription
        }
        isDeleting = false
    }

    private func openDebugEditorIfNeeded() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-SimpleStudyOpenTodoEditor") {
            showsEditor = true
        }
        #endif
    }
}

private struct TodoHowItWorksCard: View {
    let create: () -> Void
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Choose a time and actions. Complete each task in the app to continue. Missed tasks carry forward instead of being skipped.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("New task", action: create).buttonStyle(.bordered)
            }
            .padding(.top, 8)
        } label: {
            Label("Plan → Act → Complete", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.subheadline.weight(.medium))
        }
        .appCard()
    }
}

private struct TodayHeader: View {
    let activeCount: Int
    let completedCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Date().formatted(.dateTime.month(.wide).day().weekday(.wide)))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(activeCount == 0 ? "Make a little room for learning." : "\(activeCount) ready now")
                        .font(.title2.weight(.semibold))
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(completedCount)")
                        .font(.system(.title, design: .rounded).weight(.semibold))
                        .foregroundStyle(.green)
                    Text("Done today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .appCard(padding: 24, radius: AppTheme.heroRadius)
    }
}

private struct TodoCard: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var actionEngine: TodoActionEngine

    let todo: TodoRecord
    let allTodos: [TodoRecord]
    let onEdit: (() -> Void)?
    let onDelete: (() -> Void)?

    @State private var showsFlow = false

    private var state: TodoState { TodoStateResolver.state(for: todo, allTodos: allTodos) }

    private var hasPendingActivationActions: Bool {
        todo.actions.contains {
            $0.phase == .activation && $0.isEnabled && $0.state != .succeeded && $0.state != .skipped
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: todo.kind.icon)
                    .appIconBadge(size: 40, radius: 12)

                VStack(alignment: .leading, spacing: 4) {
                    Text(todo.title)
                        .font(.headline)
                    if !todo.details.isEmpty {
                        Text(todo.details)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                StatusBadge(state: state)
            }

            HStack(spacing: 10) {
                if let overdue = TodoStateResolver.overdueText(for: todo) {
                    Label(overdue, systemImage: "clock.badge.exclamationmark")
                        .foregroundStyle(.orange)
                } else if todo.storedState == .completed, let date = todo.completedAt {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                } else if todo.triggerKind != .manual && todo.triggerKind != .courseProgress {
                    Label(todo.originalScheduledAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                        .lineLimit(1)
                } else {
                    Text("Start anytime")
                }
                Spacer(minLength: 8)
                Button {
                    showsFlow = true
                } label: {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.body)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.accent)
                .accessibilityLabel("View task flow")
                if onEdit != nil || onDelete != nil {
                    Menu {
                        if let onEdit {
                            Button("Edit", systemImage: "pencil", action: onEdit)
                        }
                        if let onDelete {
                            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Task actions")
                    .disabled(actionEngine.isRunning)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if todo.storedState == .partialFailure, let error = todo.lastActionError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()

            actionButton
                .disabled(actionEngine.isRunning)
        }
        .appCard()
        .sheet(isPresented: $showsFlow) {
            TodoFlowView(todo: todo, allTodos: allTodos)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if let onEdit {
                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(AppTheme.accent)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .accessibilityHint(onEdit == nil ? "View the flow, or swipe left to delete" : "View the flow, swipe right to edit, or left to delete")
    }

    @ViewBuilder
    private var actionButton: some View {
        if todo.storedState == .completed {
            Label("Completed", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
        } else if state == .waitingDependency {
            let names = allTodos.filter { todo.prerequisiteIDs.contains($0.id) && $0.storedState != .completed }.map(\.title)
            Label(names.isEmpty ? "Waiting for prerequisites" : "Waiting for: " + names.joined(separator: ", "), systemImage: "link")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        } else if state == .runningActions {
            ProgressView("Running…").font(.subheadline)
        } else if todo.storedState == .partialFailure {
            HStack {
                Button("Try again") {
                    Task { await actionEngine.retryFailedActions(todo: todo, context: modelContext) }
                }
                .buttonStyle(.bordered)
                if !todo.actions.contains(where: { $0.isEnabled && $0.isCritical && $0.state == .failed }) {
                    completionButton
                }
            }
        } else if state == .scheduled {
            Label("Waiting for scheduled time", systemImage: "clock")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else if hasPendingActivationActions {
            Button("Start") {
                Task { await actionEngine.activate(todo: todo, context: modelContext) }
            }
            .buttonStyle(.borderedProminent)
        } else {
            completionButton
        }
    }

    @ViewBuilder
    private var completionButton: some View {
        if todo.completionRule == .homeworkSubmission {
            Button("Start practice") { router.openHomework(homeworkID: todo.homeworkID) }
                .buttonStyle(.borderedProminent)
        } else if todo.completionRule == .lessonCompletion {
            Button("Start studying") { router.openStudy(workspaceID: todo.workspaceID) }
                .buttonStyle(.borderedProminent)
        } else if todo.completionRule == .vocabularyUnitCompletion ||
                  todo.completionRule == .vocabularyCoursewareCompletion {
            Button("Study words") {
                router.openVocabulary(
                    coursewareID: todo.vocabularyCoursewareID,
                    unitID: todo.completionRule == .vocabularyUnitCompletion ? todo.vocabularyUnitID : nil
                )
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button {
                Task { await actionEngine.complete(todo: todo, context: modelContext) }
            } label: {
                Label("Done", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .disabled(actionEngine.isRunning)
        }
    }
}

private extension View {
    func todayListRow() -> some View {
        self
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 7)
            .listRowInsets(EdgeInsets(
                top: 0,
                leading: AppTheme.pagePadding,
                bottom: 0,
                trailing: AppTheme.pagePadding
            ))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

private struct StatusBadge: View {
    let state: TodoState

    private var color: Color {
        switch state {
        case .overdue, .partialFailure: .orange
        case .completed: .green
        case .waitingDependency: .secondary
        case .runningActions: .blue
        default: AppTheme.accent
        }
    }

    var body: some View {
        Text(state.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule())
    }
}
