import Combine
import UIKit
import UserNotifications

@MainActor
final class NotificationNavigation: ObservableObject {
    static let shared = NotificationNavigation()
    @Published var todoID: UUID?
}

final class AppNotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void) {
        if let value = response.notification.request.content.userInfo["todoID"] as? String,
           let id = UUID(uuidString: value), response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            Task { @MainActor in NotificationNavigation.shared.todoID = id }
        }
        completionHandler()
    }
}
