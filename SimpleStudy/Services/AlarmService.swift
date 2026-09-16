import AlarmKit
import Foundation
import SwiftUI
import UIKit

struct StudyAlarmMetadata: AlarmMetadata {
    let todoID: UUID
    let title: String
}

enum AlarmSchedulingError: LocalizedError {
    case permissionDenied
    case wrongDevice

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "Alarm access denied"
        case .wrongDevice: "Waiting for the selected device to schedule the alarm"
        }
    }
}

enum DeviceIdentity {
    private static let key = "simpleStudy.deviceID"

    static var id: String {
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let value = UUID().uuidString
        UserDefaults.standard.set(value, forKey: key)
        return value
    }

    static var kind: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
    }

    static func shouldSchedule(target: AlarmTarget, targetDeviceID: String? = nil) -> Bool {
        switch target {
        case .none: false
        case .iPhone: UIDevice.current.userInterfaceIdiom == .phone
        case .currentIPad:
            UIDevice.current.userInterfaceIdiom == .pad && (targetDeviceID == nil || targetDeviceID == id)
        case .allAuthorizedDevices: true
        }
    }
}

@MainActor
protocol SystemAlarmClient {
    func alarms() throws -> [SystemAlarmSnapshot]
    func schedule(id: UUID, todo: TodoRecord, target: AlarmTarget, targetDeviceID: String?, fireDate: Date) async throws
    func cancel(id: UUID) throws
}

struct SystemAlarmSnapshot: Identifiable, Equatable {
    let id: UUID
    let state: AlarmRegistrationState
    let fireDate: Date?
    var scheduleDescription: String? = nil

    var timeDescription: String {
        fireDate?.formatted(date: .abbreviated, time: .shortened)
            ?? scheduleDescription ?? "Alarm time unavailable"
    }
}

@MainActor
struct AlarmService: SystemAlarmClient {
    func schedule(id: UUID, todo: TodoRecord, target: AlarmTarget, targetDeviceID: String?, fireDate: Date) async throws {
        guard DeviceIdentity.shouldSchedule(target: target, targetDeviceID: targetDeviceID) else {
            throw AlarmSchedulingError.wrongDevice
        }

        let manager = AlarmManager.shared
        var authorization = manager.authorizationState
        if authorization == .notDetermined {
            authorization = try await manager.requestAuthorization()
        }
        guard authorization == .authorized else {
            throw AlarmSchedulingError.permissionDenied
        }

        let stopButton = AlarmButton(
            text: "Stop",
            textColor: .white,
            systemImageName: "stop.circle.fill"
        )
        let title: LocalizedStringResource = "\(todo.title)"
        let alert = AlarmPresentation.Alert(title: title, stopButton: stopButton)
        let presentation = AlarmPresentation(alert: alert)
        let metadata = StudyAlarmMetadata(todoID: todo.id, title: todo.title)
        let attributes = AlarmAttributes(
            presentation: presentation,
            metadata: metadata,
            tintColor: AppTheme.accent
        )
        let configuration = AlarmManager.AlarmConfiguration.alarm(
            schedule: .fixed(fireDate),
            attributes: attributes
        )
        _ = try await manager.schedule(id: id, configuration: configuration)
    }

    func alarms() throws -> [SystemAlarmSnapshot] {
        // A failed read is not an empty inventory. Only the system's successful
        // response can confirm that an alarm has gone away.
        try AlarmManager.shared.alarms.map { alarm in
            let state: AlarmRegistrationState
            switch alarm.state {
            case .scheduled, .countdown, .paused: state = .scheduled
            case .alerting: state = .fired
            @unknown default: state = .failed
            }
            var fireDate: Date?
            var description: String?
            switch alarm.schedule {
            case .fixed(let date): fireDate = date
            case .relative(let relative):
                let time = Calendar.current.date(from: DateComponents(hour: relative.time.hour, minute: relative.time.minute))
                description = time?.formatted(date: .omitted, time: .shortened)
                if case .weekly = relative.repeats {
                    description = "Weekly · \(description ?? "")"
                }
            case nil: break
            @unknown default: break
            }
            return SystemAlarmSnapshot(id: alarm.id, state: state, fireDate: fireDate, scheduleDescription: description)
        }
    }

    func cancel(id: UUID) throws {
        try AlarmManager.shared.cancel(id: id)
    }
}
