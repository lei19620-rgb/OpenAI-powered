import Foundation
import SwiftData
import UserNotifications

struct TodoNotificationDescriptor: Identifiable, Equatable {
    let stepKey: String
    let actionID: UUID?
    let title: String
    let body: String
    let dueDate: Date

    var id: String { stepKey }
}

enum TodoNotificationPlanner {
    static func descriptors(for todo: TodoRecord) -> [TodoNotificationDescriptor] {
        let reminderDescriptors = TodoReminderPlanner.descriptors(for: todo)
        let hasConfiguredNotification = todo.actions.contains {
            $0.isEnabled && ($0.kind == .localNotification || $0.kind == .vocabularyReminder)
        }
        let descriptors = reminderDescriptors.filter {
            $0.actionID != nil || !hasConfiguredNotification
        }

        return descriptors.map { descriptor in
            TodoNotificationDescriptor(
                stepKey: descriptor.stepKey,
                actionID: descriptor.actionID,
                title: descriptor.title,
                body: body(for: descriptor, todo: todo),
                dueDate: descriptor.dueDate
            )
        }
    }

    private static func body(
        for descriptor: TodoReminderDescriptor,
        todo: TodoRecord
    ) -> String {
        let details = todo.details.trimmingCharacters(in: .whitespacesAndNewlines)
        if !details.isEmpty { return details }
        if descriptor.actionID == nil {
            return "This task is ready to start."
        }
        return "Complete this step, then return to Study AI."
    }
}

@MainActor
enum TodoNotificationService {
    private static let center = UNUserNotificationCenter.current()
    private static let managedPrefix = "todo."

    static func syncAll(
        context: ModelContext,
        requestAccess: Bool = false
    ) async {
        if requestAccess,
           await authorizationStatus() == .notDetermined {
            _ = try? await NotificationService.requestAccess()
        }

        let permission = await authorizationStatus()
        var knownNotificationIDs = await existingNotificationIdentifiers()
        let todos = (try? context.fetch(FetchDescriptor<TodoRecord>())) ?? []

        for todo in todos {
            await sync(
                todo: todo,
                allTodos: todos,
                context: context,
                permission: permission,
                knownNotificationIDs: &knownNotificationIDs
            )
        }

        let todoIDs = Set(todos.map(\.id))
        let localRecords = ((try? context.fetch(FetchDescriptor<TodoNotificationRecord>())) ?? [])
            .filter { $0.deviceID == DeviceIdentity.id }
        for record in localRecords where !todoIDs.contains(record.todoID) {
            await NotificationService.cancel(todoID: record.todoID)
            context.delete(record)
        }

        try? context.save()
    }

    static func remove(todoID: UUID, context: ModelContext) async {
        await NotificationService.cancel(todoID: todoID)
        let records = localRecords(for: todoID, context: context)
        for record in records {
            context.delete(record)
        }
        try? context.save()
    }

    private static func sync(
        todo: TodoRecord,
        allTodos: [TodoRecord],
        context: ModelContext,
        permission: UNAuthorizationStatus,
        knownNotificationIDs: inout Set<String>
    ) async {
        let descriptors = TodoNotificationPlanner.descriptors(for: todo)
        let desiredKeys = Set(descriptors.map(\.stepKey))
        let records = localRecords(for: todo.id, context: context)
        let state = TodoStateResolver.state(for: todo, allTodos: allTodos)

        if todo.storedState == .cancelled ||
            state == .completed ||
            state == .waitingDependency {
            await NotificationService.cancel(todoID: todo.id)
            for record in records {
                context.delete(record)
            }
            return
        }

        for record in records where !desiredKeys.contains(record.stepKey) {
            removeNotification(identifier: record.notificationIdentifier)
            context.delete(record)
        }

        for descriptor in descriptors {
            let identifier = notificationIdentifier(todoID: todo.id, stepKey: descriptor.stepKey)
            let record = record(
                for: descriptor,
                identifier: identifier,
                todo: todo,
                existing: records,
                context: context
            )
            let previousIdentifier = record.notificationIdentifier
            let previousState = record.state
            let contentChanged = previousIdentifier != identifier ||
                record.title != descriptor.title ||
                record.body != descriptor.body ||
                record.dueDate != descriptor.dueDate

            record.actionID = descriptor.actionID
            record.notificationIdentifier = identifier
            record.title = descriptor.title
            record.body = descriptor.body
            record.dueDate = descriptor.dueDate
            record.updatedAt = Date()

            let isAuthorized = permission == .authorized ||
                permission == .provisional ||
                permission == .ephemeral
            guard isAuthorized else {
                record.state = .pending
                record.errorMessage = permissionMessage(for: permission)
                continue
            }

            let needsScheduling = contentChanged ||
                previousState != .scheduled ||
                (descriptor.dueDate > Date() && !knownNotificationIDs.contains(identifier))
            guard needsScheduling else { continue }

            if contentChanged || previousState != .scheduled {
                removeNotification(identifier: previousIdentifier)
            }

            do {
                try await schedule(descriptor, todoID: todo.id, identifier: identifier)
                record.state = .scheduled
                record.errorMessage = nil
                record.updatedAt = Date()
                knownNotificationIDs.insert(identifier)
            } catch {
                record.state = .failed
                record.errorMessage = error.localizedDescription
                record.updatedAt = Date()
            }
        }
    }

    private static func record(
        for descriptor: TodoNotificationDescriptor,
        identifier: String,
        todo: TodoRecord,
        existing: [TodoNotificationRecord],
        context: ModelContext
    ) -> TodoNotificationRecord {
        if let existing = existing.first(where: { $0.stepKey == descriptor.stepKey }) {
            return existing
        }

        let record = TodoNotificationRecord(
            todoID: todo.id,
            actionID: descriptor.actionID,
            stepKey: descriptor.stepKey,
            deviceID: DeviceIdentity.id,
            deviceKind: DeviceIdentity.kind,
            notificationIdentifier: identifier,
            title: descriptor.title,
            body: descriptor.body,
            dueDate: descriptor.dueDate
        )
        context.insert(record)
        return record
    }

    private static func schedule(
        _ descriptor: TodoNotificationDescriptor,
        todoID: UUID,
        identifier: String
    ) async throws {
        let content = UNMutableNotificationContent()
        content.title = descriptor.title
        content.body = descriptor.body
        content.sound = .default
        content.userInfo = [
            "todoID": todoID.uuidString,
            "stepKey": descriptor.stepKey
        ]

        let fireDate = max(descriptor.dueDate, Date().addingTimeInterval(1))
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, fireDate.timeIntervalSinceNow),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        try await center.add(request)
    }

    private static func notificationIdentifier(todoID: UUID, stepKey: String) -> String {
        managedPrefix + todoID.uuidString + ".managed." + stepKey
    }

    private static func localRecords(
        for todoID: UUID,
        context: ModelContext
    ) -> [TodoNotificationRecord] {
        ((try? context.fetch(FetchDescriptor<TodoNotificationRecord>())) ?? [])
            .filter { $0.todoID == todoID && $0.deviceID == DeviceIdentity.id }
    }

    private static func removeNotification(identifier: String) {
        guard !identifier.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    private static func existingNotificationIdentifiers() async -> Set<String> {
        let pending = await center.pendingNotificationRequests()
        let delivered = await withCheckedContinuation {
            (continuation: CheckedContinuation<[UNNotification], Never>) in
            center.getDeliveredNotifications { notifications in
                continuation.resume(returning: notifications)
            }
        }
        return Set(
            pending.map(\.identifier) + delivered.map(\.request.identifier)
        )
    }

    private static func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    private static func permissionMessage(for status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            "Allow notifications in Settings."
        case .denied:
            "Allow notifications in system Settings."
        case .authorized, .provisional, .ephemeral:
            ""
        @unknown default:
            "Notifications are temporarily unavailable."
        }
    }
}
