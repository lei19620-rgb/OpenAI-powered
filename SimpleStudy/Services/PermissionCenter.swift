import AlarmKit
import CloudKit
import Combine
import EventKit
import Foundation
import UIKit
import UserNotifications

enum PermissionAccessState: Equatable {
    case checking
    case notDetermined
    case granted
    case denied
    case unavailable(String)

    var title: String {
        switch self {
        case .checking: "Checking"
        case .notDetermined: "Not requested"
        case .granted: "Allowed"
        case .denied: "Not allowed"
        case .unavailable(let reason): reason
        }
    }

    var systemImage: String {
        switch self {
        case .checking: "clock"
        case .notDetermined: "questionmark.circle"
        case .granted: "checkmark.circle.fill"
        case .denied: "xmark.circle.fill"
        case .unavailable: "exclamationmark.triangle.fill"
        }
    }
}

@MainActor
final class PermissionCenter: ObservableObject {
    @Published private(set) var notification: PermissionAccessState = .checking
    @Published private(set) var alarm: PermissionAccessState = .checking
    @Published private(set) var reminders: PermissionAccessState = .checking
    @Published private(set) var iCloud: PermissionAccessState = .checking
    private var shouldCheckICloud = false

    func refresh(checkICloud: Bool) async {
        shouldCheckICloud = checkICloud
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notification = switch settings.authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized, .provisional, .ephemeral: .granted
        @unknown default: .unavailable("Unknown status")
        }

        alarm = switch AlarmManager.shared.authorizationState {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized: .granted
        @unknown default: .unavailable("Unknown status")
        }

        reminders = switch EKEventStore.authorizationStatus(for: .reminder) {
        case .notDetermined: .notDetermined
        case .fullAccess: .granted
        case .denied, .restricted, .writeOnly: .denied
        @unknown default: .unavailable("Unknown status")
        }

        guard checkICloud else {
            iCloud = .unavailable("Local mode for this session")
            return
        }

        #if targetEnvironment(simulator)
        iCloud = .unavailable("Check on a physical device")
        return
        #else

        do {
            let status = try await accountStatus()
            iCloud = switch status {
            case .available: .granted
            case .noAccount: .unavailable("Not signed in to iCloud")
            case .restricted: .unavailable("Account restricted")
            case .couldNotDetermine: .unavailable("Unable to determine status")
            case .temporarilyUnavailable: .unavailable("Service temporarily unavailable")
            @unknown default: .unavailable("Unknown status")
            }
        } catch {
            iCloud = .unavailable("Check failed")
        }
        #endif
    }

    func requestNotifications() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            notification = .unavailable("Request failed")
        }
        await refresh(checkICloud: shouldCheckICloud)
    }

    func requestAlarm() async {
        do {
            _ = try await AlarmManager.shared.requestAuthorization()
        } catch {
            alarm = .unavailable("Request failed")
        }
        await refresh(checkICloud: shouldCheckICloud)
    }

    func requestReminders() async {
        do {
            _ = try await TodoReminderService.requestAccess()
        } catch {
            reminders = .unavailable("Request failed")
        }
        await refresh(checkICloud: shouldCheckICloud)
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func accountStatus() async throws -> CKAccountStatus {
        try await withCheckedThrowingContinuation { continuation in
            CKContainer.default().accountStatus { status, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
    }
}
