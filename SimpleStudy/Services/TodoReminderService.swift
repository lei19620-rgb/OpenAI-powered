import EventKit
import Foundation
import SwiftData

struct TodoReminderDescriptor: Identifiable, Equatable {
    let stepKey: String
    let actionID: UUID?
    let title: String
    let notes: String
    let dueDate: Date

    var id: String { stepKey }
}

enum TodoReminderPlanner {
    static func descriptors(for todo: TodoRecord) -> [TodoReminderDescriptor] {
        let userActions = todo.actions.filter {
            $0.isEnabled && $0.kind.requiresUserActionForReminder
        }

        if userActions.isEmpty {
            return [TodoReminderDescriptor(
                stepKey: "task",
                actionID: nil,
                title: todo.title,
                notes: notes(for: todo, stepKey: "task"),
                dueDate: todo.originalScheduledAt
            )]
        }

        return userActions.map { action in
            let stepKey = "action-" + action.id.uuidString
            return TodoReminderDescriptor(
                stepKey: stepKey,
                actionID: action.id,
                title: action.kind.reminderTitle(for: todo.title),
                notes: notes(for: todo, stepKey: stepKey),
                dueDate: todo.originalScheduledAt
            )
        }
    }

    static func marker(todoID: UUID, stepKey: String) -> String {
        "[SimpleStudy TODO " + todoID.uuidString + " STEP " + stepKey + "]"
    }

    private static func notes(for todo: TodoRecord, stepKey: String) -> String {
        var lines = [
            "Automatically synced by Study AI",
            "Completion rule: " + todo.completionRule.title
        ]
        if !todo.details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append(todo.details)
        }
        lines.append(marker(todoID: todo.id, stepKey: stepKey))
        return lines.joined(separator: "\n")
    }
}

@MainActor
enum TodoReminderService {
    private static let eventStore = EKEventStore()

    static var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .reminder)
    }

    static var hasFullAccess: Bool {
        authorizationStatus == .fullAccess
    }

    static func requestAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            eventStore.requestFullAccessToReminders { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    static func syncAll(
        context: ModelContext,
        requestAccess: Bool = false
    ) async {
        if requestAccess && authorizationStatus == .notDetermined {
            _ = try? await Self.requestAccess()
        }

        let todos = (try? context.fetch(FetchDescriptor<TodoRecord>())) ?? []
        var managedReminders: [String: EKReminder] = hasFullAccess ? await fetchManagedReminders() : [:]

        for todo in todos {
            sync(todo: todo, allTodos: todos, context: context, managedReminders: &managedReminders)
        }

        let todoIDs = Set(todos.map(\.id))
        let localRecords = ((try? context.fetch(FetchDescriptor<TodoReminderRecord>())) ?? [])
            .filter { $0.deviceID == DeviceIdentity.id }
        for record in localRecords where !todoIDs.contains(record.todoID) {
            removeExternal(
                record,
                marker: TodoReminderPlanner.marker(todoID: record.todoID, stepKey: record.stepKey),
                managedReminders: &managedReminders
            )
            if record.state != .failed && record.state != .pending {
                context.delete(record)
            }
        }

        try? context.save()
    }

    static func markCompleted(todoID: UUID, context: ModelContext) async {
        let records = localRecords(for: todoID, context: context)
        var managedReminders: [String: EKReminder] = hasFullAccess ? await fetchManagedReminders() : [:]
        for record in records {
            completeExternal(
                record,
                marker: TodoReminderPlanner.marker(todoID: todoID, stepKey: record.stepKey),
                managedReminders: &managedReminders
            )
        }
        try? context.save()
    }

    static func remove(todoID: UUID, context: ModelContext) async {
        let records = localRecords(for: todoID, context: context)
        var managedReminders: [String: EKReminder] = hasFullAccess ? await fetchManagedReminders() : [:]
        for record in records {
            removeExternal(
                record,
                marker: TodoReminderPlanner.marker(todoID: todoID, stepKey: record.stepKey),
                managedReminders: &managedReminders
            )
            if record.state != .failed && record.state != .pending {
                context.delete(record)
            }
        }
        try? context.save()
    }

    private static func sync(
        todo: TodoRecord,
        allTodos: [TodoRecord],
        context: ModelContext,
        managedReminders: inout [String: EKReminder]
    ) {
        let descriptors = TodoReminderPlanner.descriptors(for: todo)
        let desiredKeys = Set(descriptors.map(\.stepKey))
        let records = localRecords(for: todo.id, context: context)

        let state = TodoStateResolver.state(for: todo, allTodos: allTodos)
        if todo.storedState == .cancelled {
            for record in records {
                removeExternal(
                    record,
                    marker: TodoReminderPlanner.marker(todoID: todo.id, stepKey: record.stepKey),
                    managedReminders: &managedReminders
                )
                if record.state != .failed && record.state != .pending {
                    context.delete(record)
                }
            }
            return
        }

        if state == .completed {
            for record in records {
                completeExternal(
                    record,
                    marker: TodoReminderPlanner.marker(todoID: todo.id, stepKey: record.stepKey),
                    managedReminders: &managedReminders
                )
            }
            return
        }

        if state == .overdue {
            for record in records {
                removeExternal(
                    record,
                    marker: TodoReminderPlanner.marker(todoID: todo.id, stepKey: record.stepKey),
                    managedReminders: &managedReminders
                )
            }
            return
        }

        if state == .waitingDependency {
            for record in records {
                removeExternal(
                    record,
                    marker: TodoReminderPlanner.marker(todoID: todo.id, stepKey: record.stepKey),
                    managedReminders: &managedReminders
                )
                if record.state == .deleted {
                    record.state = .pending
                }
            }
            return
        }

        for record in records where !desiredKeys.contains(record.stepKey) {
            removeExternal(
                record,
                marker: TodoReminderPlanner.marker(todoID: todo.id, stepKey: record.stepKey),
                managedReminders: &managedReminders
            )
            if record.state != .failed && record.state != .pending {
                context.delete(record)
            }
        }

        for descriptor in descriptors {
            let record = record(for: descriptor, todo: todo, existing: records, context: context)
            record.title = descriptor.title
            record.dueDate = descriptor.dueDate
            record.actionID = descriptor.actionID
            record.updatedAt = Date()

            guard hasFullAccess else {
                record.state = .pending
                record.errorMessage = permissionMessage
                continue
            }

            upsertExternal(
                record,
                descriptor: descriptor,
                todoID: todo.id,
                managedReminders: &managedReminders
            )
        }
    }

    private static func record(
        for descriptor: TodoReminderDescriptor,
        todo: TodoRecord,
        existing: [TodoReminderRecord],
        context: ModelContext
    ) -> TodoReminderRecord {
        if let existing = existing.first(where: { $0.stepKey == descriptor.stepKey }) {
            return existing
        }

        let record = TodoReminderRecord(
            todoID: todo.id,
            actionID: descriptor.actionID,
            stepKey: descriptor.stepKey,
            deviceID: DeviceIdentity.id,
            deviceKind: DeviceIdentity.kind,
            title: descriptor.title,
            dueDate: descriptor.dueDate
        )
        context.insert(record)
        return record
    }

    private static func upsertExternal(
        _ record: TodoReminderRecord,
        descriptor: TodoReminderDescriptor,
        todoID: UUID,
        managedReminders: inout [String: EKReminder]
    ) {
        let marker = TodoReminderPlanner.marker(todoID: todoID, stepKey: descriptor.stepKey)
        let reminder = existingReminder(
            for: record,
            marker: marker,
            managedReminders: managedReminders
        ) ?? newReminder()

        guard let reminder else {
            record.state = .failed
            record.errorMessage = "No reminder list is available."
            record.updatedAt = Date()
            return
        }

        if reminder.calendar == nil {
            guard let calendar = eventStore.defaultCalendarForNewReminders()
                ?? eventStore.calendars(for: .reminder).first else {
                record.state = .failed
                record.errorMessage = "No reminder list is available."
                record.updatedAt = Date()
                return
            }
            reminder.calendar = calendar
        }

        reminder.title = descriptor.title
        reminder.notes = descriptor.notes
        reminder.dueDateComponents = dateComponents(for: descriptor.dueDate)
        reminder.alarms = [EKAlarm(absoluteDate: descriptor.dueDate)]
        reminder.isCompleted = false

        do {
            try eventStore.save(reminder, commit: true)
            record.reminderIdentifier = reminder.calendarItemIdentifier
            record.state = .active
            record.errorMessage = nil
            record.updatedAt = Date()
            managedReminders[marker] = reminder
        } catch {
            record.state = .failed
            record.errorMessage = error.localizedDescription
            record.updatedAt = Date()
        }
    }

    private static func completeExternal(
        _ record: TodoReminderRecord,
        marker: String,
        managedReminders: inout [String: EKReminder]
    ) {
        guard hasFullAccess else {
            if record.reminderIdentifier == nil {
                record.state = .completed
                record.errorMessage = nil
            } else {
                record.state = .pending
                record.errorMessage = permissionMessage
            }
            record.updatedAt = Date()
            return
        }

        guard let reminder = existingReminder(
            for: record,
            marker: marker,
            managedReminders: managedReminders
        ) else {
            record.state = .completed
            record.reminderIdentifier = nil
            record.errorMessage = nil
            record.updatedAt = Date()
            return
        }

        do {
            if !reminder.isCompleted {
                reminder.isCompleted = true
                try eventStore.save(reminder, commit: true)
            }
            record.state = .completed
            record.reminderIdentifier = reminder.calendarItemIdentifier
            record.errorMessage = nil
            record.updatedAt = Date()
        } catch {
            record.state = .failed
            record.errorMessage = error.localizedDescription
            record.updatedAt = Date()
        }
    }

    private static func removeExternal(
        _ record: TodoReminderRecord,
        marker: String,
        managedReminders: inout [String: EKReminder]
    ) {
        guard hasFullAccess else {
            if record.reminderIdentifier == nil {
                record.state = .deleted
                record.errorMessage = nil
            } else {
                record.state = .pending
                record.errorMessage = permissionMessage
            }
            record.updatedAt = Date()
            return
        }

        guard let reminder = existingReminder(
            for: record,
            marker: marker,
            managedReminders: managedReminders
        ) else {
            record.state = .deleted
            record.reminderIdentifier = nil
            record.errorMessage = nil
            record.updatedAt = Date()
            managedReminders.removeValue(forKey: marker)
            return
        }

        do {
            try eventStore.remove(reminder, commit: true)
            record.state = .deleted
            record.reminderIdentifier = nil
            record.errorMessage = nil
            record.updatedAt = Date()
            managedReminders.removeValue(forKey: marker)
        } catch {
            record.state = .failed
            record.errorMessage = error.localizedDescription
            record.updatedAt = Date()
        }
    }

    private static func existingReminder(
        for record: TodoReminderRecord,
        marker: String,
        managedReminders: [String: EKReminder]
    ) -> EKReminder? {
        if let identifier = record.reminderIdentifier,
           let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder {
            return reminder
        }
        return managedReminders[marker]
    }

    private static func newReminder() -> EKReminder? {
        EKReminder(eventStore: eventStore)
    }

    private static func localRecords(for todoID: UUID, context: ModelContext) -> [TodoReminderRecord] {
        ((try? context.fetch(FetchDescriptor<TodoReminderRecord>())) ?? [])
            .filter { $0.todoID == todoID && $0.deviceID == DeviceIdentity.id }
    }

    private static func fetchManagedReminders() async -> [String: EKReminder] {
        await withCheckedContinuation { (continuation: CheckedContinuation<[String: EKReminder], Never>) in
            let predicate = eventStore.predicateForReminders(in: nil)
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: index(reminders ?? []))
            }
        }
    }

    private static func index(_ reminders: [EKReminder]) -> [String: EKReminder] {
        var indexed: [String: EKReminder] = [:]
        for reminder in reminders {
            guard let notes = reminder.notes else { continue }
            guard let marker = notes.split(separator: "\n").first(where: {
                $0.hasPrefix("[SimpleStudy TODO ") && $0.contains(" STEP ") && $0.hasSuffix("]")
            }) else { continue }
            indexed[String(marker)] = reminder
        }
        return indexed
    }

    private static func dateComponents(for date: Date) -> DateComponents {
        var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        components.calendar = Calendar.current
        components.timeZone = .current
        return components
    }

    private static var permissionMessage: String {
        switch authorizationStatus {
        case .notDetermined:
            "Allow Reminders access in Settings."
        case .denied, .restricted, .writeOnly:
            "Allow full Reminders access in system Settings."
        case .fullAccess:
            ""
        @unknown default:
            "Reminders are temporarily unavailable."
        }
    }
}

private extension TodoActionKind {
    var requiresUserActionForReminder: Bool {
        switch self {
        case .openStudy, .openHomework, .openVocabularyReview:
            true
        default:
            false
        }
    }

    func reminderTitle(for todoTitle: String) -> String {
        switch self {
        case .openStudy:
            return "Study: " + todoTitle
        case .openHomework:
            return "Practice: " + todoTitle
        case .openVocabularyReview:
            return "Vocabulary: " + todoTitle
        default:
            return todoTitle
        }
    }
}
