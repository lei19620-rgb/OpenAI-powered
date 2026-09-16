import Foundation
import UserNotifications

enum NotificationService {
    static func requestAccess() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    static func schedule(
        todo: TodoRecord,
        message: String,
        offsetMinutes: Int,
        repeatMinutes: Int = 0,
        actionID: UUID? = nil
    ) async throws {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            let granted = try await requestAccess()
            guard granted else { throw NotificationError.denied }
        } else if settings.authorizationStatus == .denied {
            throw NotificationError.denied
        }

        let content = UNMutableNotificationContent()
        content.title = todo.title
        content.body = message.isEmpty ? (todo.details.isEmpty ? "This task is ready to start." : todo.details) : message
        content.sound = .default
        content.userInfo = ["todoID": todo.id.uuidString]

        let requested = todo.originalScheduledAt.addingTimeInterval(TimeInterval(offsetMinutes * 60))
        let firstFireDate = max(requested, Date().addingTimeInterval(1))
        let repeats = repeatMinutes > 0 ? 12 : 1
        for index in 0..<repeats {
            let date = firstFireDate.addingTimeInterval(TimeInterval(index * repeatMinutes * 60))
            let interval = max(1, date.timeIntervalSinceNow)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            let request = UNNotificationRequest(
                identifier: "todo.\(todo.id.uuidString).action.\(actionID?.uuidString ?? "default").\(index)",
                content: content,
                trigger: trigger
            )
            try await center.add(request)
        }
    }

    static func cancel(todoID: UUID) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let delivered = await withCheckedContinuation { (continuation: CheckedContinuation<[UNNotification], Never>) in
            center.getDeliveredNotifications { notifications in
                continuation.resume(returning: notifications)
            }
        }
        let prefix = "todo.\(todoID.uuidString)."
        let identifiers = Set(
            pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
                + delivered.map(\.request.identifier).filter { $0.hasPrefix(prefix) }
        )
        guard !identifiers.isEmpty else { return }
        let values = Array(identifiers)
        center.removePendingNotificationRequests(withIdentifiers: values)
        center.removeDeliveredNotifications(withIdentifiers: values)
    }

    enum NotificationError: LocalizedError {
        case denied

        var errorDescription: String? { "Notification access denied" }
    }
}
