import Foundation
import SwiftData
import UIKit

@MainActor
enum TodoStateResolver {
    static func state(for todo: TodoRecord, allTodos: [TodoRecord], now: Date = Date()) -> TodoState {
        if todo.storedState == .completed || todo.storedState == .cancelled {
            return todo.storedState
        }

        let prerequisites = todo.prerequisiteIDs
        if !prerequisites.isEmpty {
            let completeIDs = Set(allTodos.filter { $0.storedState == .completed }.map(\.id))
            if !prerequisites.allSatisfy(completeIDs.contains) {
                return .waitingDependency
            }
        }

        if todo.storedState == .partialFailure || todo.storedState == .runningActions {
            return todo.storedState
        }

        switch todo.triggerKind {
        case .manual, .courseProgress:
            return .ready
        case .dependencyCompletion:
            // Older recurring instances used dependencyCompletion. A recurring
            // instance must satisfy both its dependency and its scheduled time.
            if todo.recurrence != .none && todo.originalScheduledAt > now { return .scheduled }
            return todo.originalScheduledAt <= now ? .overdue : .ready
        case .scheduledTime:
            return todo.originalScheduledAt <= now ? .overdue : .scheduled
        }
    }

    static func overdueText(for todo: TodoRecord, now: Date = Date()) -> String? {
        guard todo.triggerKind != .manual, todo.triggerKind != .courseProgress,
              todo.originalScheduledAt < now,
              todo.storedState != .completed, todo.storedState != .cancelled else { return nil }
        let components = Calendar.current.dateComponents([.day, .hour, .minute], from: todo.originalScheduledAt, to: now)
        if let day = components.day, day > 0 { return "\(day) days overdue" }
        if let hour = components.hour, hour > 0 { return "\(hour) hours overdue" }
        return "\(max(1, components.minute ?? 1)) minutes overdue"
    }
}

struct TodoWorkflowStep {
    let todo: TodoRecord
    let state: TodoState
    let waitingFor: [String]
}

@MainActor
enum TodoWorkflowPlanner {
    /// Selects one explainable next step without changing task state or
    /// executing any configured action. The Today screen can use this as a
    /// focus point while the task list remains the source of truth.
    static func nextStep(
        activeTodos: [TodoRecord],
        allTodos: [TodoRecord],
        now: Date = Date()
    ) -> TodoWorkflowStep? {
        let candidates = activeTodos.compactMap { todo -> (TodoRecord, TodoState)? in
            let state = TodoStateResolver.state(for: todo, allTodos: allTodos, now: now)
            guard state != .completed, state != .cancelled else { return nil }
            return (todo, state)
        }

        guard let selected = candidates.sorted(by: isHigherPriority).first else { return nil }
        let waitingFor = allTodos
            .filter {
                selected.1 == .waitingDependency &&
                    selected.0.prerequisiteIDs.contains($0.id) &&
                    $0.storedState != .completed &&
                    $0.storedState != .cancelled
            }
            .sorted { $0.originalScheduledAt < $1.originalScheduledAt }
            .map(\.title)
        return TodoWorkflowStep(todo: selected.0, state: selected.1, waitingFor: waitingFor)
    }

    private static func isHigherPriority(
        _ lhs: (TodoRecord, TodoState),
        _ rhs: (TodoRecord, TodoState)
    ) -> Bool {
        let leftRank = rank(for: lhs.1)
        let rightRank = rank(for: rhs.1)
        if leftRank != rightRank { return leftRank < rightRank }

        let leftDate = sortDate(for: lhs.0, state: lhs.1)
        let rightDate = sortDate(for: rhs.0, state: rhs.1)
        if leftDate != rightDate { return leftDate < rightDate }
        return lhs.0.title.localizedCaseInsensitiveCompare(rhs.0.title) == .orderedAscending
    }

    private static func rank(for state: TodoState) -> Int {
        switch state {
        case .partialFailure: 0
        case .runningActions: 1
        case .overdue: 2
        case .ready: 3
        case .waitingDependency: 4
        case .scheduled: 5
        case .completed, .cancelled: 6
        }
    }

    private static func sortDate(for todo: TodoRecord, state: TodoState) -> Date {
        switch state {
        case .overdue, .waitingDependency, .scheduled:
            return todo.originalScheduledAt
        default:
            return todo.createdAt
        }
    }
}

@MainActor
final class TodoActionEngine: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var navigationRequest: ActionNavigationRequest?
    @Published var operationError: String?
    @Published private(set) var systemAlarms: [SystemAlarmSnapshot] = []
    @Published private(set) var hasLoadedSystemAlarms = false
    @Published private(set) var alarmRefreshError: String?
    private let alarmClient: any SystemAlarmClient
    private var executionWaiters: [CheckedContinuation<Void, Never>] = []
    private var isRefreshing = false
    private var isReconcilingLearning = false

    init(alarmClient: (any SystemAlarmClient)? = nil) {
        self.alarmClient = alarmClient ?? AlarmService()
    }

    // Management reads the actual system inventory without activating TODOs,
    // requesting permission, or deleting alarms whose business data is missing.
    func refreshAlarmInventory() {
        do {
            publishAlarmInventory(try alarmClient.alarms())
        } catch {
            alarmRefreshError = "Unable to read system alarms. Pull to retry. You can still try canceling recorded alarms."
        }
    }

    private func publishAlarmInventory(_ alarms: [SystemAlarmSnapshot]) {
        systemAlarms = alarms.sorted {
            if ($0.state == .fired) != ($1.state == .fired) { return $0.state == .fired }
            return ($0.fireDate ?? .distantFuture) < ($1.fireDate ?? .distantFuture)
        }
        hasLoadedSystemAlarms = true
        alarmRefreshError = nil
    }

    private func acquireExecution() async {
        if isRunning {
            await withCheckedContinuation { executionWaiters.append($0) }
        } else {
            isRunning = true
        }
    }

    private func releaseExecution() {
        if executionWaiters.isEmpty {
            isRunning = false
        } else {
            executionWaiters.removeFirst().resume()
        }
    }

    func refreshStates(context: ModelContext) {
        guard !isRunning else { return }
        let todos = (try? context.fetch(FetchDescriptor<TodoRecord>())) ?? []
        for todo in todos where todo.storedState != .completed && todo.storedState != .cancelled && todo.storedState != .partialFailure {
            if todo.recurrence != .none && todo.occurrenceIndex > 0 &&
                [.vocabularyUnitCompletion, .vocabularyCoursewareCompletion].contains(todo.completionRule) {
                todo.completionRule = .vocabularyReviewSession
            }
            if todo.storedState == .runningActions {
                // A previous process ended mid-action. Successful actions retain
                // their idempotency keys; interrupted actions require a retry.
                var actions = todo.actions
                for index in actions.indices where actions[index].state == .running {
                    actions[index].state = .failed
                    actions[index].errorMessage = "The previous operation was interrupted. Try again."
                }
                todo.actions = actions
                todo.storedState = .partialFailure
                todo.lastActionError = "The previous operation was interrupted. Try again."
            }
            todo.storedState = TodoStateResolver.state(for: todo, allTodos: todos)
        }
        saveExecution(context: context)
    }

    func refreshAndActivateReadyTasks(context: ModelContext) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        refreshStates(context: context)
        let todos = (try? context.fetch(FetchDescriptor<TodoRecord>())) ?? []
        for todo in todos where todo.storedState != .completed && todo.storedState != .cancelled {
            let state = TodoStateResolver.state(for: todo, allTodos: todos)
            let shouldActivate = state == .overdue ||
                (state == .ready && todo.triggerKind != .manual)
            let hasPendingActivation = todo.actions.contains {
                $0.phase == .activation && $0.isEnabled && $0.state != .succeeded
            }
            if state == .scheduled {
                await prepareScheduledActions(todo: todo, context: context)
            }
            if shouldActivate && hasPendingActivation {
                await activate(todo: todo, context: context, allowsNavigation: false)
            }
        }
        await reconcileLearningCompletion(context: context)
        await syncTodoReminders(context: context)
        await syncTodoNotifications(context: context)
    }

    /// Recheck persisted results after relaunch, time changes, and dependency
    /// completion. A bounded fixed point handles chains in any fetch order.
    func reconcileLearningCompletion(context: ModelContext) async {
        guard !isReconcilingLearning else { return }
        isReconcilingLearning = true
        defer { isReconcilingLearning = false }
        do {
            let candidates = try context.fetch(FetchDescriptor<TodoRecord>())
            var madeProgress = true
            var remainingPasses = candidates.count
            while madeProgress && remainingPasses > 0 {
                madeProgress = false
                remainingPasses -= 1
                let allTodos = try context.fetch(FetchDescriptor<TodoRecord>())
                for todo in candidates {
                    let state = TodoStateResolver.state(for: todo, allTodos: allTodos)
                    guard state == .ready || state == .overdue,
                          try LearningCompletionService.hasEvidence(for: todo, context: context) else { continue }
                    await complete(todo: todo, context: context, allowsNavigation: false)
                    if todo.storedState == .completed { madeProgress = true }
                }
            }
        } catch {
            operationError = "Unable to reconcile saved learning progress. Your results are kept; try again: \(error.localizedDescription)"
        }
    }

    func prepareScheduledActions(todo: TodoRecord, context: ModelContext) async {
        guard todo.triggerKind == .scheduledTime || todo.recurrence != .none else { return }
        await execute(
            todo: todo,
            phase: .activation,
            context: context,
            completeAfterSuccess: false,
            allowedKinds: [.scheduleAlarm, .localNotification]
        )
    }

    func consumeNavigationRequest() {
        navigationRequest = nil
    }

    /// Opening learning content is not activation: it never runs reminders,
    /// shortcuts, or completion effects and does not bypass task readiness.
    func openLearningContent(todo: TodoRecord, context: ModelContext) {
        guard !isRunning else { return }
        do {
            switch todo.completionRule {
            case .lessonCompletion:
                let workspace = try ensureWorkspace(for: todo, preferredCourseID: todo.courseID, context: context)
                try context.save()
                navigationRequest = .study(workspace.id)
            case .homeworkSubmission:
                navigationRequest = .homework(todo.homeworkID)
            case .vocabularyUnitCompletion, .vocabularyCoursewareCompletion, .vocabularyReviewSession:
                navigationRequest = .vocabulary(coursewareID: todo.vocabularyCoursewareID, unitID: todo.vocabularyUnitID)
            case .manual:
                break
            }
        } catch {
            context.rollback()
            operationError = "Unable to open learning content: \(error.localizedDescription)"
        }
    }

    func processPendingDeviceAlarms(context: ModelContext) async {
        await acquireExecution()
        defer { releaseExecution() }
        var didStartWriting = false
        do {
            let todos = try context.fetch(FetchDescriptor<TodoRecord>())
            let registrations = try context.fetch(FetchDescriptor<AlarmRegistrationRecord>())
            let inventory = try alarmClient.alarms()
            publishAlarmInventory(inventory)

            didStartWriting = true
            for registration in registrations {
                let actual = inventory.first { $0.id == registration.alarmID }
                // An exact system ID match proves local ownership even when a
                // restore changed the device ID. Never guess by title or time.
                if let actual {
                    registration.deviceID = DeviceIdentity.id
                    registration.deviceKind = DeviceIdentity.kind
                    registration.state = actual.state
                } else if registration.deviceID == DeviceIdentity.id,
                          registration.alarmID != nil,
                          registration.state == .scheduled || registration.state == .fired {
                    registration.state = .stopped
                }
                guard registration.deviceID == DeviceIdentity.id else { continue }
                // Missing TODOs may simply not have arrived from iCloud. Keep
                // these alarms manageable instead of silently cancelling them.
                guard let todo = todos.first(where: { $0.id == registration.todoID }) else { continue }
                let isDisabled = !todo.actions.contains {
                    $0.isEnabled && $0.kind == .scheduleAlarm && $0.parameters.alarmTarget != .none
                }
                if actual != nil && (todo.storedState == .completed || todo.storedState == .cancelled || isDisabled) {
                    do {
                        try cancelSystemAlarm(alarmID: registration.alarmID)
                        registration.state = .stopped
                        registration.errorMessage = nil
                    } catch {
                        registration.errorMessage = "Cancellation is unconfirmed. Retry in alarm management."
                    }
                }
            }

            for todo in todos {
                try updateTodoAlarmState(todoID: todo.id, context: context)
            }
            try context.save()

            for todo in todos where todo.storedState != .completed && todo.storedState != .cancelled {
                guard TodoStateResolver.state(for: todo, allTodos: todos) != .waitingDependency else { continue }
                guard let alarmAction = todo.actions.first(where: {
                    $0.isEnabled && $0.kind == .scheduleAlarm && $0.state == .succeeded
                }) else { continue }
                let parameters = alarmAction.parameters
                guard DeviceIdentity.shouldSchedule(target: parameters.alarmTarget, targetDeviceID: parameters.alarmTargetDeviceID) else { continue }
                let existing = registrations.first { $0.todoID == todo.id && $0.deviceID == DeviceIdentity.id }
                // Do not recreate cancelled/fired alarms on each foreground.
                // A prepared ID with notRequested is a recoverable interrupted schedule.
                guard existing == nil || existing?.state == .notRequested else { continue }
                do {
                    try await scheduleAlarm(for: todo, parameters: parameters, context: context)
                } catch {
                    todo.lastActionError = error.localizedDescription
                }
                try context.save()
            }
        } catch {
            if didStartWriting { context.rollback() }
            alarmRefreshError = "Unable to update alarm status. Refresh alarm management and retry."
        }
    }

    func activate(todo: TodoRecord, context: ModelContext, allowsNavigation: Bool = true) async {
        await execute(todo: todo, phase: .activation, context: context, completeAfterSuccess: false, allowsNavigation: allowsNavigation)
    }

    func complete(todo: TodoRecord, context: ModelContext, allowsNavigation: Bool = true) async {
        // Business events and buttons use the same dependency/time gate.
        let todos = (try? context.fetch(FetchDescriptor<TodoRecord>())) ?? []
        let state = TodoStateResolver.state(for: todo, allTodos: todos)
        guard state != .waitingDependency, state != .scheduled,
              state != .completed, state != .cancelled else { return }
        if todo.completionRule != .manual {
            do {
                guard try LearningCompletionService.hasEvidence(for: todo, context: context) else { return }
            } catch {
                operationError = "Unable to read saved learning progress: \(error.localizedDescription)"
                return
            }
        }
        if todo.actions.contains(where: {
            $0.phase == .activation && $0.isEnabled &&
            ($0.state == .pending || $0.state == .running || ($0.state == .failed && $0.isCritical))
        }) {
            await activate(todo: todo, context: context, allowsNavigation: allowsNavigation)
            guard !todo.actions.contains(where: { $0.phase == .activation && $0.isEnabled && $0.isCritical && $0.state == .failed }) else { return }
        }
        await execute(todo: todo, phase: .completion, context: context, completeAfterSuccess: true, allowsNavigation: allowsNavigation)
        if todo.storedState == .completed {
            await NotificationService.cancel(todoID: todo.id)
            await TodoReminderService.markCompleted(todoID: todo.id, context: context)
            await activateNewlyReadyTasks(after: todo.id, context: context)
            await syncTodoReminders(context: context)
            await syncTodoNotifications(context: context)
        }
    }

    /// Vocabulary first-learning completion is emitted by the review flow rather
    /// than by a manual TODO tap. It still goes through the normal completion
    /// pipeline so completion actions, recurring successors and dependencies
    /// keep the same semantics as every other TODO.
    func completeVocabularyTasks(
        coursewareID: UUID,
        unitID: UUID?,
        context: ModelContext
    ) async {
        let todos = (try? context.fetch(FetchDescriptor<TodoRecord>())) ?? []
        let linked = todos.filter { todo in
            guard todo.storedState != .completed,
                  todo.storedState != .cancelled,
                  todo.completionRule == (unitID == nil ? .vocabularyCoursewareCompletion : .vocabularyUnitCompletion),
                  todo.vocabularyCoursewareID == coursewareID else {
                return false
            }
            if let unitID { return todo.vocabularyUnitID == unitID }
            return true
        }

        for todo in linked {
            await complete(todo: todo, context: context)
        }
    }

    func retryFailedActions(todo: TodoRecord, context: ModelContext) async {
        let hasCompletionFailure = todo.actions.contains { $0.phase == .completion && $0.state == .failed }
        await execute(
            todo: todo,
            phase: hasCompletionFailure ? .completion : .activation,
            context: context,
            completeAfterSuccess: hasCompletionFailure
        )
        if todo.storedState == .completed {
            await NotificationService.cancel(todoID: todo.id)
            await TodoReminderService.markCompleted(todoID: todo.id, context: context)
            await activateNewlyReadyTasks(after: todo.id, context: context)
            await syncTodoReminders(context: context)
            await syncTodoNotifications(context: context)
        }
    }

    func syncTodoReminders(context: ModelContext, requestAccess: Bool = false) async {
        await TodoReminderService.syncAll(context: context, requestAccess: requestAccess)
    }

    func syncTodoNotifications(context: ModelContext, requestAccess: Bool = false) async {
        await TodoNotificationService.syncAll(context: context, requestAccess: requestAccess)
    }

    func delete(todo: TodoRecord, context: ModelContext) async throws {
        guard !isRunning else { throw TodoDeletionError.busy }
        isRunning = true
        defer { releaseExecution() }

        let allTodos = try context.fetch(FetchDescriptor<TodoRecord>())
        let registrations = try context.fetch(FetchDescriptor<AlarmRegistrationRecord>())
        let alarmIDs = registrations
            .filter { $0.todoID == todo.id }
            .compactMap(\.alarmID)
        // Keep the registrations (and the TODO) if local cancellation cannot be
        // confirmed. Otherwise a failed deletion loses the only management ID.
        if !alarmIDs.isEmpty {
            let inventory = try alarmClient.alarms()
            for alarmID in Set(alarmIDs) where inventory.contains(where: { $0.id == alarmID }) {
                try cancelSystemAlarm(alarmID: alarmID)
            }
        }

        let remainingTodos = allTodos.filter { $0.id != todo.id }
        for dependent in remainingTodos where dependent.prerequisiteIDs.contains(todo.id) {
            dependent.prerequisiteIDs.removeAll { $0 == todo.id }
            dependent.updatedAt = Date()
            if dependent.storedState != .completed,
               dependent.storedState != .cancelled,
               dependent.storedState != .partialFailure {
                dependent.storedState = TodoStateResolver.state(for: dependent, allTodos: remainingTodos)
            }
        }

        for registration in registrations where registration.todoID == todo.id {
            context.delete(registration)
        }
        context.delete(todo)

        do {
            try context.save()
        } catch {
            context.rollback()
            throw TodoDeletionError.saveFailed(error.localizedDescription)
        }

        await NotificationService.cancel(todoID: todo.id)
        await TodoReminderService.remove(todoID: todo.id, context: context)
        await TodoNotificationService.remove(todoID: todo.id, context: context)
    }

    @discardableResult
    func cancelScheduledEffects(todoID: UUID, context: ModelContext) async -> Bool {
        await acquireExecution()
        defer { releaseExecution() }
        do {
            let registrations = try context.fetch(FetchDescriptor<AlarmRegistrationRecord>())
                .filter { $0.todoID == todoID }
            let alarmIDs = Set(registrations.compactMap(\.alarmID))
            if !alarmIDs.isEmpty {
                let inventory = try alarmClient.alarms()
                for alarmID in alarmIDs where inventory.contains(where: { $0.id == alarmID }) {
                    try cancelSystemAlarm(alarmID: alarmID)
                }
            }
            for registration in registrations { context.delete(registration) }
            if let todo = try context.fetch(FetchDescriptor<TodoRecord>()).first(where: { $0.id == todoID }) {
                todo.alarmState = .notRequested
                todo.updatedAt = Date()
            }
            try context.save()
            await NotificationService.cancel(todoID: todoID)
            return true
        } catch {
            context.rollback()
            operationError = "Changes saved, but cancellation of the old alarm is unconfirmed. Its record is retained. Retry in alarm management."
            return false
        }
    }

    func cancelAlarmRegistration(
        _ registration: AlarmRegistrationRecord,
        context: ModelContext
    ) async throws {
        guard !isRunning else { throw AlarmManagementError.busy }
        try requireLocalAlarm(registration)

        isRunning = true
        defer { releaseExecution() }

        try cancelSystemAlarm(alarmID: registration.alarmID)
        registration.deviceID = DeviceIdentity.id
        registration.deviceKind = DeviceIdentity.kind
        registration.state = .stopped
        registration.errorMessage = nil
        registration.updatedAt = Date()

        do {
            try updateTodoAlarmState(todoID: registration.todoID, context: context)
            try context.save()
        } catch {
            context.rollback()
            throw AlarmManagementError.saveFailed(error.localizedDescription)
        }
    }

    func cancelRecoveredAlarm(id: UUID) async throws {
        guard !isRunning else { throw AlarmManagementError.busy }
        isRunning = true
        defer { releaseExecution() }
        // This path deliberately does not depend on SwiftData: even an alarm
        // whose registration is missing must remain cancellable by its exact ID.
        try cancelSystemAlarm(alarmID: id)
    }

    func deleteAlarmRegistration(
        _ registration: AlarmRegistrationRecord,
        context: ModelContext
    ) async throws {
        guard !isRunning else { throw AlarmManagementError.busy }
        try requireLocalAlarm(registration)

        isRunning = true
        defer { releaseExecution() }

        let todos = try context.fetch(FetchDescriptor<TodoRecord>())
        let registrations = try context.fetch(FetchDescriptor<AlarmRegistrationRecord>())
        let hasSystemIDs = registrations.contains { $0.todoID == registration.todoID && $0.alarmID != nil }
        let inventory = hasSystemIDs ? try alarmClient.alarms() : []
        let localRegistrations = registrations.filter { record in
            record.todoID == registration.todoID &&
                (record.deviceID == DeviceIdentity.id || inventory.contains(where: { $0.id == record.alarmID }))
        }

        for alarmID in localRegistrations.compactMap(\.alarmID) {
            try cancelSystemAlarm(alarmID: alarmID)
        }

        if let todo = todos.first(where: { $0.id == registration.todoID }) {
            var actions = todo.actions
            for index in actions.indices where actions[index].kind == .scheduleAlarm {
                actions[index].isEnabled = false
                actions[index].state = .skipped
                actions[index].errorMessage = nil
            }
            todo.actions = actions
            todo.updatedAt = Date()
        }

        for localRegistration in localRegistrations {
            context.delete(localRegistration)
        }

        do {
            if let todo = todos.first(where: { $0.id == registration.todoID }) {
                try updateTodoAlarmState(
                    todoID: todo.id,
                    context: context,
                    excludingRegistrationIDs: Set(localRegistrations.map(\.id))
                )
            }
            try context.save()
        } catch {
            context.rollback()
            throw AlarmManagementError.saveFailed(error.localizedDescription)
        }
    }

    private func execute(
        todo: TodoRecord,
        phase: TodoActionPhase,
        context: ModelContext,
        completeAfterSuccess: Bool,
        allowedKinds: Set<TodoActionKind>? = nil,
        allowsNavigation: Bool = true
    ) async {
        await acquireExecution()
        defer { releaseExecution() }
        guard !todo.isDeleted, todo.storedState != .completed, todo.storedState != .cancelled else { return }
        let allTodos = (try? context.fetch(FetchDescriptor<TodoRecord>())) ?? []
        let currentState = TodoStateResolver.state(for: todo, allTodos: allTodos)
        guard currentState != .waitingDependency else { return }
        guard allowedKinds != nil || currentState != .scheduled else { return }

        var actions = todo.actions
        let indexes = actions.indices.filter {
            actions[$0].phase == phase &&
            actions[$0].isEnabled &&
            actions[$0].state != .succeeded &&
            (allowedKinds?.contains(actions[$0].kind) ?? true)
        }

        if indexes.isEmpty {
            if completeAfterSuccess {
                markCompleted(todo, context: context)
                saveExecution(context: context)
            }
            return
        }

        todo.storedState = .runningActions
        todo.lastActionError = nil
        guard saveExecution(context: context) else { return }

        var criticalFailure = false
        var anyFailure = false
        for index in indexes {
            actions[index].state = .running
            actions[index].startedAt = Date()
            actions[index].attemptCount += 1
            todo.actions = actions
            guard saveExecution(context: context) else { return }

            do {
                try await perform(action: actions[index], for: todo, context: context, allowsNavigation: allowsNavigation)
                actions[index].state = .succeeded
                actions[index].errorMessage = nil
            } catch {
                actions[index].state = .failed
                actions[index].errorMessage = error.localizedDescription
                todo.lastActionError = error.localizedDescription
                anyFailure = true
                if actions[index].isCritical { criticalFailure = true }
            }
            actions[index].finishedAt = Date()
            todo.actions = actions
            guard saveExecution(context: context) else { return }

            if criticalFailure { break }
        }

        if criticalFailure || (anyFailure && !completeAfterSuccess) {
            todo.storedState = .partialFailure
        } else if completeAfterSuccess {
            markCompleted(todo, context: context)
        } else {
            let todos = (try? context.fetch(FetchDescriptor<TodoRecord>())) ?? []
            todo.storedState = .ready
            todo.storedState = TodoStateResolver.state(for: todo, allTodos: todos)
        }
        todo.updatedAt = Date()
        saveExecution(context: context)
    }

    @discardableResult
    private func saveExecution(context: ModelContext) -> Bool {
        do {
            try context.save()
            return true
        } catch {
            context.rollback()
            operationError = "Unable to save progress. Try again: \(error.localizedDescription)"
            return false
        }
    }

    private func perform(action: TodoAction, for todo: TodoRecord, context: ModelContext, allowsNavigation: Bool) async throws {
        switch action.kind {
        case .scheduleAlarm:
            try await scheduleAlarm(for: todo, parameters: action.parameters, context: context)

        case .localNotification:
            try await NotificationService.schedule(
                todo: todo,
                message: action.parameters.message,
                offsetMinutes: action.parameters.reminderOffsetMinutes,
                repeatMinutes: action.parameters.reminderRepeatMinutes,
                actionID: action.id
            )

        case .createWorkspace:
            _ = try ensureWorkspace(for: todo, preferredCourseID: action.parameters.courseID, context: context)

        case .createNote:
            let workspace = try ensureWorkspace(for: todo, preferredCourseID: action.parameters.courseID, context: context)
            try ensureMainNote(
                workspace: workspace,
                preferredTemplateID: action.parameters.noteTemplateID,
                context: context
            )

        case .resolveCourseMaterial:
            let workspace = try ensureWorkspace(for: todo, preferredCourseID: action.parameters.courseID, context: context)
            let assets = (try? context.fetch(FetchDescriptor<StudyAssetRecord>())) ?? []
            guard assets.contains(where: { $0.workspaceID == workspace.id }) else {
                throw TodoActionError.noCourseMaterial
            }

        case .openStudy:
            let requestedCourseID = action.parameters.courseID ?? todo.courseID
            guard requestedCourseID != nil else {
                if allowsNavigation { navigationRequest = .study(nil) }
                return
            }
            let workspace = try ensureWorkspace(
                for: todo,
                preferredCourseID: requestedCourseID,
                context: context
            )
            if allowsNavigation { navigationRequest = .study(workspace.id) }

        case .openHomework:
            let homeworks = (try? context.fetch(FetchDescriptor<HomeworkDefinitionRecord>())) ?? []
            let requestedID = action.parameters.homeworkID ?? todo.homeworkID
            let workspaceID = action.parameters.workspaceID ?? todo.workspaceID
            let homework = requestedID.flatMap { id in homeworks.first(where: { $0.id == id }) }
                ?? workspaceID.flatMap { id in homeworks.first(where: { $0.workspaceID == id }) }
            if let homework {
                todo.homeworkID = homework.id
                if allowsNavigation { navigationRequest = .homework(homework.id) }
            } else {
                if allowsNavigation { navigationRequest = .homework(nil) }
            }

        case .openVocabularyReview:
            guard allowsNavigation else { return }
            navigationRequest = .vocabulary(
                coursewareID: action.parameters.vocabularyCoursewareID ?? todo.vocabularyCoursewareID,
                unitID: action.parameters.vocabularyUnitID ?? todo.vocabularyUnitID
            )

        case .vocabularyReminder:
            try await NotificationService.schedule(
                todo: todo,
                message: action.parameters.message.isEmpty ? "Time to review." : action.parameters.message,
                offsetMinutes: action.parameters.reminderOffsetMinutes,
                repeatMinutes: action.parameters.reminderRepeatMinutes,
                actionID: action.id
            )

        case .updateCourseProgress:
            try completeLinkedLesson(todo: todo, context: context)

        case .runShortcut:
            let name = action.parameters.shortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { throw TodoActionError.missingShortcutName }
            var components = URLComponents()
            components.scheme = "shortcuts"
            components.host = "run-shortcut"
            components.queryItems = [URLQueryItem(name: "name", value: name)]
            guard let url = components.url else { throw TodoActionError.invalidShortcutURL }
            let opened = await UIApplication.shared.open(url)
            if !opened { throw TodoActionError.shortcutUnavailable }
        }
    }

    private func scheduleAlarm(for todo: TodoRecord, parameters: TodoActionParameters, context: ModelContext) async throws {
        guard parameters.alarmTarget != .none else { return }
        let registrations = try context.fetch(FetchDescriptor<AlarmRegistrationRecord>())
        let isTarget = DeviceIdentity.shouldSchedule(target: parameters.alarmTarget, targetDeviceID: parameters.alarmTargetDeviceID)
        let needsReconciliation = isTarget && registrations.contains { $0.todoID == todo.id && $0.alarmID != nil }
        let inventory = needsReconciliation ? try alarmClient.alarms() : []
        if needsReconciliation { publishAlarmInventory(inventory) }
        let existing = registrations.first { record in
            record.todoID == todo.id && (record.deviceID == DeviceIdentity.id || inventory.contains { $0.id == record.alarmID })
        }
        let registration = existing ?? AlarmRegistrationRecord(
            todoID: todo.id, deviceID: DeviceIdentity.id, deviceKind: DeviceIdentity.kind, fireDate: todo.originalScheduledAt
        )
        if registration.modelContext == nil { context.insert(registration) }
        guard isTarget else {
            registration.state = .awaitingDevice
            todo.alarmState = .awaitingDevice
            return
        }
        registration.deviceID = DeviceIdentity.id
        registration.deviceKind = DeviceIdentity.kind
        if let actual = inventory.first(where: { $0.id == registration.alarmID }) {
            if registration.requestedFireDate == todo.originalScheduledAt {
                registration.state = actual.state
                registration.errorMessage = nil
                todo.alarmState = actual.state
                return
            }
            // An edit must remove the previous system schedule before replacement.
            try cancelSystemAlarm(alarmID: actual.id)
        } else if registration.state == .stopped && registration.requestedFireDate == todo.originalScheduledAt {
            todo.alarmState = .stopped
            return
        }

        let alarmID = registration.alarmID ?? UUID()
        registration.alarmID = alarmID
        registration.requestedFireDate = todo.originalScheduledAt
        registration.state = .notRequested
        // Persist the exact ID BEFORE the external side effect. If the process
        // ends after registration, the next read recovers that ID, not a new alarm.
        do { try context.save() }
        catch { context.rollback(); throw AlarmManagementError.saveFailed(error.localizedDescription) }
        do {
            let fireDate = max(todo.originalScheduledAt, Date().addingTimeInterval(2))
            try await alarmClient.schedule(id: alarmID, todo: todo, target: parameters.alarmTarget,
                                           targetDeviceID: parameters.alarmTargetDeviceID, fireDate: fireDate)
            registration.state = .scheduled
            registration.errorMessage = nil
            todo.alarmState = .scheduled
            refreshAlarmInventory()
        } catch AlarmSchedulingError.permissionDenied {
            registration.state = .permissionDenied
            registration.errorMessage = AlarmSchedulingError.permissionDenied.localizedDescription
            todo.alarmState = .permissionDenied
            throw AlarmSchedulingError.permissionDenied
        } catch {
            registration.state = .failed
            registration.errorMessage = error.localizedDescription
            todo.alarmState = registration.state
            throw error
        }
    }

    private func requireLocalAlarm(_ registration: AlarmRegistrationRecord) throws {
        if registration.deviceID == DeviceIdentity.id { return }
        let inventory = try alarmClient.alarms()
        publishAlarmInventory(inventory)
        guard inventory.contains(where: { $0.id == registration.alarmID }) else {
            throw AlarmManagementError.otherDevice
        }
    }

    private func cancelSystemAlarm(alarmID: UUID?) throws {
        guard let alarmID else { return }
        var cancellationError: Error?
        do { try alarmClient.cancel(id: alarmID) }
        catch { cancellationError = error }
        let inventory: [SystemAlarmSnapshot]
        do { inventory = try alarmClient.alarms() }
        catch {
            alarmRefreshError = "Cancellation is unconfirmed. Refresh to check or try again."
            throw AlarmManagementError.cancellationUnconfirmed
        }
        publishAlarmInventory(inventory)
        guard !inventory.contains(where: { $0.id == alarmID }) else {
            throw cancellationError ?? AlarmManagementError.stillActive
        }
    }

    private func updateTodoAlarmState(
        todoID: UUID,
        context: ModelContext,
        excludingRegistrationIDs: Set<UUID> = []
    ) throws {
        guard let todo = try context.fetch(FetchDescriptor<TodoRecord>()).first(where: { $0.id == todoID }) else {
            return
        }

        let states = try context.fetch(FetchDescriptor<AlarmRegistrationRecord>())
            .filter { $0.todoID == todoID && !excludingRegistrationIDs.contains($0.id) }
            .map(\.state)
        let priority: [AlarmRegistrationState] = [
            .fired,
            .scheduled,
            .awaitingDevice,
            .permissionDenied,
            .failed,
            .stopped,
            .notRequested
        ]
        todo.alarmState = priority.first(where: states.contains) ?? .notRequested
    }

    private func ensureWorkspace(
        for todo: TodoRecord,
        preferredCourseID: UUID?,
        context: ModelContext
    ) throws -> StudyWorkspaceRecord {
        let workspaces = (try? context.fetch(FetchDescriptor<StudyWorkspaceRecord>())) ?? []
        if let workspaceID = todo.workspaceID,
           let existing = workspaces.first(where: { $0.id == workspaceID }) {
            return existing
        }

        let courseID = preferredCourseID ?? todo.courseID
        let courses = (try? context.fetch(FetchDescriptor<CourseRecord>())) ?? []
        guard let courseID, let course = courses.first(where: { $0.id == courseID }) else {
            throw TodoActionError.missingCourse
        }

        if let existing = workspaces.first(where: { $0.courseID == course.id && $0.sequence == course.currentSequence }) {
            todo.workspaceID = existing.id
            return existing
        }

        let workspace = StudyWorkspaceRecord(
            courseID: course.id,
            sequence: course.currentSequence,
            title: "\(course.title) · Day \(course.currentSequence)"
        )
        context.insert(workspace)
        todo.courseID = course.id
        todo.workspaceID = workspace.id
        return workspace
    }

    private func ensureMainNote(
        workspace: StudyWorkspaceRecord,
        preferredTemplateID: UUID?,
        context: ModelContext
    ) throws {
        let notes = (try? context.fetch(FetchDescriptor<StudyNoteRecord>())) ?? []
        if let noteID = workspace.mainNoteID, notes.contains(where: { $0.id == noteID }) { return }
        if let existing = notes.first(where: { $0.workspaceID == workspace.id }) {
            workspace.mainNoteID = existing.id
            return
        }

        let templates = (try? context.fetch(FetchDescriptor<NoteTemplateRecord>())) ?? []
        let templateID = preferredTemplateID ?? AppSettings().defaultTemplateID
        let template = templateID.flatMap { id in templates.first(where: { $0.id == id }) }
            ?? templates.first(where: { $0.name == "Sentence study" })
            ?? templates.first
        guard let template else { throw TodoActionError.missingTemplate }

        let content = NoteRenderingService.render(
            template: template,
            courseTitle: workspace.title.components(separatedBy: " · ").first ?? workspace.title,
            day: workspace.sequence,
            materialName: nil
        )
        let note = StudyNoteRecord(
            workspaceID: workspace.id,
            title: workspace.title,
            content: content,
            template: template.snapshot
        )
        context.insert(note)
        workspace.mainNoteID = note.id
    }

    private func completeLinkedLesson(todo: TodoRecord, context: ModelContext) throws {
        guard let workspaceID = todo.workspaceID else { throw TodoActionError.missingWorkspace }
        let workspaces = (try? context.fetch(FetchDescriptor<StudyWorkspaceRecord>())) ?? []
        let courses = (try? context.fetch(FetchDescriptor<CourseRecord>())) ?? []
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }),
              let course = courses.first(where: { $0.id == workspace.courseID }) else {
            throw TodoActionError.missingWorkspace
        }
        _ = course
        try CourseProgressService.complete(workspace, context: context)
    }

    private func activateNewlyReadyTasks(after completedID: UUID, context: ModelContext) async {
        let todos = (try? context.fetch(FetchDescriptor<TodoRecord>())) ?? []
        for candidate in todos where candidate.prerequisiteIDs.contains(completedID) {
            let state = TodoStateResolver.state(for: candidate, allTodos: todos)
            guard state != .waitingDependency, state != .completed, state != .cancelled else { continue }
            candidate.storedState = state
            if state == .scheduled {
                await prepareScheduledActions(todo: candidate, context: context)
            } else {
                await activate(todo: candidate, context: context, allowsNavigation: false)
            }
        }
        await reconcileLearningCompletion(context: context)
    }

    private func markCompleted(_ todo: TodoRecord, context: ModelContext) {
        todo.storedState = .completed
        todo.completedAt = Date()
        todo.updatedAt = Date()
        createRecurringSuccessorsIfNeeded(from: todo, context: context)
    }

    private func createRecurringSuccessorsIfNeeded(from todo: TodoRecord, context: ModelContext) {
        guard todo.recurrence != .none else { return }
        let allTodos = (try? context.fetch(FetchDescriptor<TodoRecord>())) ?? []
        let calendar = Calendar.current

        func addingInterval(to date: Date) -> Date? {
            switch todo.recurrence {
            case .none: nil
            case .daily: calendar.date(byAdding: .day, value: 1, to: date)
            case .weekly: calendar.date(byAdding: .weekOfYear, value: 1, to: date)
            }
        }

        var dates: [Date] = []
        if todo.missedPolicy == .carryForward {
            // Keep the planned clock time; finishing late must not move tomorrow's alarm.
            let completedDay = calendar.startOfDay(for: max(todo.completedAt ?? Date(), todo.originalScheduledAt))
            if let nextDay = addingInterval(to: completedDay) {
                let time = calendar.dateComponents([.hour, .minute, .second], from: todo.originalScheduledAt)
                if let next = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0,
                                            second: time.second ?? 0, of: nextDay) {
                    dates = [next]
                }
            }
        } else {
            var cursor = addingInterval(to: todo.originalScheduledAt)
            var safety = 0
            while let date = cursor, safety < 366 {
                dates.append(date)
                safety += 1
                if date > Date() { break }
                cursor = addingInterval(to: date)
            }
        }

        var previousID = todo.id
        var nextIndex = todo.occurrenceIndex + 1
        for date in dates {
            if let existing = allTodos.first(where: { $0.seriesID == todo.seriesID && $0.occurrenceIndex == nextIndex }) {
                previousID = existing.id
                nextIndex += 1
                continue
            }
            let successor = TodoRecord(
                title: todo.title,
                details: todo.details,
                kind: todo.kind,
                triggerKind: .scheduledTime,
                scheduledAt: date
            )
            successor.seriesID = todo.seriesID
            successor.occurrenceIndex = nextIndex
            successor.recurrence = todo.recurrence
            successor.missedPolicy = todo.missedPolicy
            // Initial exposure is a one-time milestone, not a recurring goal.
            // Existing recurring vocabulary tasks continue as review sessions.
            successor.completionRule = [.vocabularyUnitCompletion, .vocabularyCoursewareCompletion].contains(todo.completionRule)
                ? .vocabularyReviewSession : todo.completionRule
            successor.courseID = todo.courseID
            if todo.completionRule == .homeworkSubmission { successor.homeworkID = todo.homeworkID }
            successor.vocabularyCoursewareID = todo.vocabularyCoursewareID
            successor.vocabularyUnitID = todo.vocabularyUnitID
            successor.prerequisiteIDs = [previousID]
            successor.actions = todo.actions.map { action in
                var reset = action
                reset.id = UUID()
                reset.idempotencyKey = UUID().uuidString
                reset.state = .pending
                reset.attemptCount = 0
                reset.startedAt = nil
                reset.finishedAt = nil
                reset.errorMessage = nil
                reset.parameters.workspaceID = nil
                reset.parameters.homeworkID = nil
                return reset
            }
            successor.storedState = date <= Date() ? .overdue : .scheduled
            context.insert(successor)
            previousID = successor.id
            nextIndex += 1
        }
    }
}

@MainActor
enum TodoDependencyValidator {
    static func createsCycle(todoID: UUID, prerequisites: Set<UUID>, allTodos: [TodoRecord]) -> Bool {
        let edges = Dictionary(allTodos.map { ($0.id, $0.prerequisiteIDs) }, uniquingKeysWith: { first, _ in first })
        var pending = Array(prerequisites)
        var visited = Set<UUID>()
        while let id = pending.popLast() {
            if id == todoID { return true }
            guard visited.insert(id).inserted else { continue }
            pending.append(contentsOf: edges[id] ?? [])
        }
        return false
    }
}

enum TodoDeletionError: LocalizedError {
    case busy
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .busy:
            "Another task operation is in progress. Try again shortly."
        case .saveFailed(let reason):
            "Unable to delete task: \(reason)"
        }
    }
}

enum AlarmManagementError: LocalizedError {
    case busy
    case otherDevice
    case saveFailed(String)
    case cancellationUnconfirmed
    case stillActive

    var errorDescription: String? {
        switch self {
        case .busy:
            "Another operation is in progress. Try again shortly."
        case .otherDevice:
            "Manage this alarm on the device where it rings."
        case .saveFailed(let reason):
            "Unable to save alarm status: \(reason)"
        case .cancellationUnconfirmed:
            "Cancellation is unconfirmed. Refresh the alarm list or cancel again."
        case .stillActive:
            "This alarm is still registered. Try canceling it again."
        }
    }
}

enum TodoActionError: LocalizedError {
    case missingCourse
    case missingWorkspace
    case missingTemplate
    case noCourseMaterial
    case missingShortcutName
    case invalidShortcutURL
    case shortcutUnavailable

    var errorDescription: String? {
        switch self {
        case .missingCourse: "Link a course before using this action"
        case .missingWorkspace: "Linked workspace not found"
        case .missingTemplate: "No note template available"
        case .noCourseMaterial: "Import study materials, then try again"
        case .missingShortcutName: "Enter the shortcut name"
        case .invalidShortcutURL: "Unable to create shortcut URL"
        case .shortcutUnavailable: "Unable to open shortcut. Check its name and system settings."
        }
    }
}
