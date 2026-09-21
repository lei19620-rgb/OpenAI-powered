import SwiftUI

struct TodoFlowView: View {
    @Environment(\.dismiss) private var dismiss

    let todo: TodoRecord
    let allTodos: [TodoRecord]

    private var state: TodoState {
        TodoStateResolver.state(for: todo, allTodos: allTodos)
    }

    private var prerequisiteTodos: [TodoRecord] {
        todo.prerequisiteIDs.compactMap { id in
            allTodos.first { $0.id == id }
        }
    }

    private var downstreamTodos: [TodoRecord] {
        allTodos
            .filter { $0.id != todo.id && $0.prerequisiteIDs.contains(todo.id) }
            .sorted { lhs, rhs in
                if lhs.originalScheduledAt == rhs.originalScheduledAt {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                return lhs.originalScheduledAt < rhs.originalScheduledAt
            }
    }

    private var activationActions: [TodoAction] {
        todo.actions.filter { $0.phase == .activation && $0.isEnabled }
    }

    private var completionActions: [TodoAction] {
        todo.actions.filter { $0.phase == .completion && $0.isEnabled }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    TodoFlowHeader(todo: todo, state: state)
                    timeline
                }
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.vertical, 18)
            }
            .scrollIndicators(.hidden)
            .background(AppTheme.pageBackground)
            .navigationTitle("Task flow")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var timeline: some View {
        TodoFlowConnector()
        TodoFlowStageCard(
            number: 1,
            icon: triggerIcon,
            title: "Start condition",
            subtitle: triggerSummary,
            tint: AppTheme.accent,
            items: startItems
        )

        TodoFlowConnector()
        TodoFlowStageCard(
            number: 2,
            icon: "wand.and.sparkles",
            title: "Actions on start",
            subtitle: activationActions.isEmpty ? "No automation; go straight to the task" : "Run in this order. Failed actions can be retried individually.",
            tint: .purple,
            items: actionItems(activationActions, prefix: "activation")
        )

        TodoFlowConnector()
        TodoFlowStageCard(
            number: 3,
            icon: todo.kind.icon,
            title: "Do the task",
            subtitle: todo.details.isEmpty ? todo.kind.title : todo.details,
            tint: .teal,
            items: [
                TodoFlowItem(
                    id: "task",
                    icon: todo.kind.icon,
                    title: todo.title,
                    detail: todo.kind.title,
                    actionState: nil
                )
            ]
        )

        TodoFlowConnector()
        TodoFlowStageCard(
            number: 4,
            icon: "checkmark.seal",
            title: "Completion rule",
            subtitle: todo.completionRule.title,
            tint: .green,
            items: [
                TodoFlowItem(
                    id: "completion-rule",
                    icon: completionRuleIcon,
                    title: todo.completionRule.title,
                    detail: todo.completionRule.flowExplanation,
                    actionState: nil
                )
            ]
        )

        TodoFlowConnector()
        TodoFlowStageCard(
            number: 5,
            icon: "arrow.forward.circle",
            title: "After completion",
            subtitle: completionActions.isEmpty ? finishSummary : "Run completion actions before scheduling what comes next",
            tint: .orange,
            items: finishItems
        )
    }

    private var triggerIcon: String {
        switch todo.triggerKind {
        case .manual: "hand.tap"
        case .scheduledTime: "calendar.badge.clock"
        case .dependencyCompletion: "link"
        case .courseProgress: "chart.line.uptrend.xyaxis"
        }
    }

    private var triggerSummary: String {
        switch todo.triggerKind {
        case .manual:
            return "Start the task manually"
        case .scheduledTime:
            let date = todo.originalScheduledAt.formatted(date: .abbreviated, time: .shortened)
            return todo.recurrence == .none
                ? "Start at " + date + " "
                : "From " + date + ", repeat " + todo.recurrence.title + " "
        case .dependencyCompletion:
            return "Start when prerequisite tasks are complete"
        case .courseProgress:
            return "Start when course progress changes"
        }
    }

    private var startItems: [TodoFlowItem] {
        var items: [TodoFlowItem] = []

        switch todo.triggerKind {
        case .manual:
            items.append(TodoFlowItem(
                id: "manual-trigger",
                icon: "hand.tap",
                title: "Start manually",
                detail: "Start the task from Today or open its linked content",
                actionState: nil
            ))
        case .scheduledTime:
            items.append(TodoFlowItem(
                id: "scheduled-trigger",
                icon: "calendar.badge.clock",
                title: todo.originalScheduledAt.formatted(date: .abbreviated, time: .shortened),
                detail: missedScheduleDetail,
                actionState: nil
            ))
        case .dependencyCompletion:
            items.append(TodoFlowItem(
                id: "dependency-trigger",
                icon: "link",
                title: "Await prerequisites",
                detail: prerequisiteTodos.isEmpty ? "No prerequisite task found" : "Starts only after all are complete",
                actionState: nil
            ))
        case .courseProgress:
            items.append(TodoFlowItem(
                id: "progress-trigger",
                icon: "chart.line.uptrend.xyaxis",
                title: "Course progress changes",
                detail: "Check readiness when course progress advances",
                actionState: nil
            ))
        }

        if !prerequisiteTodos.isEmpty && todo.triggerKind != .dependencyCompletion {
            items.append(TodoFlowItem(
                id: "additional-prerequisites",
                icon: "arrow.triangle.branch",
                title: "Remaining: " + String(prerequisiteTodos.count) + " prerequisites",
                detail: "Continue only when every prerequisite is complete",
                actionState: nil
            ))
        }

        for prerequisite in prerequisiteTodos {
            let prerequisiteState: TodoActionState? = prerequisite.storedState == .completed ? .succeeded : nil
            items.append(TodoFlowItem(
                id: prerequisite.id.uuidString,
                icon: prerequisiteState == .succeeded ? "checkmark.circle.fill" : "circle.dashed",
                title: prerequisite.title,
                detail: prerequisiteState == .succeeded ? "Completed" : "Awaiting completion",
                actionState: prerequisiteState
            ))
        }

        return items
    }

    private var missedScheduleDetail: String {
        switch todo.missedPolicy {
        case .carryForward:
            return "Show as overdue and carry the current task forward without accumulating occurrences"
        case .accumulate:
            return "Show as overdue and keep each missed occurrence"
        }
    }

    private var completionRuleIcon: String {
        switch todo.completionRule {
        case .manual: "hand.tap"
        case .homeworkSubmission: "pencil.and.list.clipboard"
        case .lessonCompletion: "book.pages"
        case .vocabularyUnitCompletion, .vocabularyCoursewareCompletion, .vocabularyReviewSession: "character.book.closed"
        }
    }

    private var finishSummary: String {
        if todo.recurrence != .none {
            return "On completion, create the next " + todo.recurrence.title + " task"
        }
        if downstreamTodos.isEmpty {
            return "Finish this task after completion"
        }
        return "On completion, unlock " + String(downstreamTodos.count) + " downstream tasks"
    }

    private var finishItems: [TodoFlowItem] {
        var items = [TodoFlowItem(
            id: "finish-rule",
            icon: state == .completed ? "checkmark.circle.fill" : "flag.checkered",
            title: state == .completed ? "Task completed" : todo.completionRule.title,
            detail: state == .completed ? "Completion is recorded in the app" : "The app marks it complete only when the rule is satisfied",
            actionState: state == .completed ? .succeeded : nil
        )]

        items.append(contentsOf: actionItems(completionActions, prefix: "completion"))

        if todo.recurrence != .none {
            items.append(TodoFlowItem(
                id: "recurrence",
                icon: "repeat",
                title: "Continue " + todo.recurrence.title + " ",
                detail: todo.missedPolicy.title,
                actionState: nil
            ))
        }

        for downstream in downstreamTodos {
            items.append(TodoFlowItem(
                id: "downstream-\(downstream.id.uuidString)",
                icon: "arrow.down.circle",
                title: downstream.title,
                detail: "Unlock after this task is complete",
                actionState: nil
            ))
        }

        return items
    }

    private func actionItems(_ actions: [TodoAction], prefix: String) -> [TodoFlowItem] {
        guard !actions.isEmpty else {
            return [TodoFlowItem(
                id: "\(prefix)-empty",
                icon: "minus.circle",
                title: prefix == "activation" ? "No automatic actions" : "No additional actions",
                detail: prefix == "activation" ? "Handle the task yourself once it is ready" : "Finish or continue to the next step once complete",
                actionState: nil
            )]
        }

        return actions.enumerated().map { index, action in
            TodoFlowItem(
                id: "\(prefix)-\(action.id.uuidString)",
                icon: action.kind.icon,
                title: "\(index + 1). \(action.kind.title)",
                detail: actionDetail(action),
                actionState: action.state
            )
        }
    }

    private func actionDetail(_ action: TodoAction) -> String {
        switch action.kind {
        case .scheduleAlarm:
            return "Target: \(action.parameters.alarmTarget.title)"
        case .localNotification:
            let message = action.parameters.message.trimmingCharacters(in: .whitespacesAndNewlines)
            return message.isEmpty ? "Send a notification" : "Message: \(message)"
        case .createWorkspace:
            return "Create or reuse the linked course workspace"
        case .createNote:
            return action.parameters.noteTemplateID == nil ? "Create the main note with the default template" : "Create the main note with the selected template"
        case .resolveCourseMaterial:
            return "Find and link materials for the current course progress"
        case .openStudy:
            return "Open the linked workspace"
        case .openHomework:
            return "Open the linked assignment"
        case .openVocabularyReview:
            return "Open the linked word unit or collection"
        case .vocabularyReminder:
            return reminderDetail(action)
        case .updateCourseProgress:
            return "Update course progress on completion"
        case .runShortcut:
            let name = action.parameters.shortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "Run the selected shortcut" : "Shortcut: \(name)"
        }
    }

    private func reminderDetail(_ action: TodoAction) -> String {
        let offset = action.parameters.reminderOffsetMinutes
        let repeatMinutes = action.parameters.reminderRepeatMinutes
        if repeatMinutes > 0 {
            return "Offset by " + String(abs(offset)) + " minutes; repeat every " + String(repeatMinutes) + " minutes"
        }
        return offset == 0 ? "Send a review reminder" : "Offset by " + String(abs(offset)) + " minutes"
    }
}

private struct TodoFlowHeader: View {
    let todo: TodoRecord
    let state: TodoState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.title2)
                    .appIconBadge(size: 44, radius: 14)

                VStack(alignment: .leading, spacing: 4) {
                    Text(todo.title)
                        .font(.title3.bold())
                }
                Spacer(minLength: 0)
                TodoFlowStateBadge(state: state)
            }

            Text("Generated from the current configuration.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .appCard(padding: 16, radius: AppTheme.heroRadius)
    }
}

private struct TodoFlowStageCard: View {
    let number: Int
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color
    let items: [TodoFlowItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Text("\(number)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .frame(width: 25, height: 25)
                    .background(tint, in: Circle())

                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(tint)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            VStack(spacing: 0) {
                ForEach(items) { item in
                    TodoFlowItemRow(item: item, tint: tint)
                    if item.id != items.last?.id {
                        Divider()
                            .padding(.leading, 34)
                    }
                }
            }
            .padding(.leading, 35)
        }
        .padding(16)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(tint.opacity(0.14))
        }
    }
}

private struct TodoFlowItem: Identifiable {
    let id: String
    let icon: String
    let title: String
    let detail: String
    let actionState: TodoActionState?
}

private struct TodoFlowItemRow: View {
    let item: TodoFlowItem
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.actionState?.flowIcon ?? item.icon)
                .foregroundStyle(item.actionState?.flowColor ?? tint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                    if let actionState = item.actionState {
                        Text(actionState.flowTitle)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(actionState.flowColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(actionState.flowColor.opacity(0.12), in: Capsule())
                    }
                }
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }
}

private struct TodoFlowConnector: View {
    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(AppTheme.accent.opacity(0.38))
                .frame(width: 2, height: 12)
            Image(systemName: "chevron.down")
                .font(.caption2.bold())
                .foregroundStyle(AppTheme.accent.opacity(0.75))
            Rectangle()
                .fill(AppTheme.accent.opacity(0.38))
                .frame(width: 2, height: 12)
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

private struct TodoFlowStateBadge: View {
    let state: TodoState

    private var color: Color {
        switch state {
        case .overdue, .partialFailure: .orange
        case .completed: .green
        case .waitingDependency: .secondary
        case .runningActions: .blue
        case .cancelled: .gray
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

private extension TodoCompletionRule {
    var flowExplanation: String {
        switch self {
        case .manual:
            "Ringing an alarm or opening a notification or material does not complete the task. Confirm completion in the app."
        case .homeworkSubmission:
            "The task completes after the linked assignment is submitted and graded locally."
        case .lessonCompletion:
            "Finish the lesson in the linked workspace to complete the task."
        case .vocabularyUnitCompletion:
            "The task completes when every word in the target unit has received its first study rating."
        case .vocabularyCoursewareCompletion:
            "The task completes when every unit in the collection has been studied once."
        case .vocabularyReviewSession:
            "Finish a nonempty review session in the linked collection or unit. Each repeating occurrence needs fresh practice."
        }
    }
}

private extension TodoActionState {
    var flowTitle: String {
        switch self {
        case .pending: "Pending"
        case .running: "Running"
        case .succeeded: "Completed"
        case .failed: "Failed; retry available"
        case .skipped: "Skipped"
        }
    }

    var flowIcon: String {
        switch self {
        case .pending: "circle.dashed"
        case .running: "arrow.triangle.2.circlepath"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .skipped: "minus.circle"
        }
    }

    var flowColor: Color {
        switch self {
        case .pending: .secondary
        case .running: .blue
        case .succeeded: .green
        case .failed: .orange
        case .skipped: .gray
        }
    }
}
