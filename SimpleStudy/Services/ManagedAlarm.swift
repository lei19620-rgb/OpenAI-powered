import Foundation

/// A management row may exist without a database registration. The system's
/// app-scoped inventory is authoritative for local ownership and live state.
@MainActor
struct ManagedAlarm: Identifiable {
    let id: String
    let system: SystemAlarmSnapshot?
    let registration: AlarmRegistrationRecord?
    let todo: TodoRecord?
    let isLocal: Bool
    let isConfirmedAbsent: Bool
    let needsVerification: Bool

    var isRecovered: Bool { system != nil && registration == nil }
    var canCancel: Bool {
        isLocal && (system != nil || (registration?.alarmID != nil && !isConfirmedAbsent))
    }
    var state: AlarmRegistrationState {
        if let system { return system.state }
        let recorded = registration?.state ?? .notRequested
        if isConfirmedAbsent && (recorded == .scheduled || recorded == .fired) { return .stopped }
        return recorded
    }
    var title: String { todo?.title ?? (isRecovered ? "Recovered alarm" : "Unlinked alarm") }
    var statusDescription: String {
        if needsVerification { return "Needs verification" }
        if system != nil && state == .fired { return "Ringing" }
        if system == nil && isLocal && registration?.alarmID == nil && (state == .scheduled || state == .fired) {
            return "Registration unconfirmed"
        }
        return state.title
    }
    var timeDescription: String {
        system?.timeDescription
            ?? registration?.requestedFireDate.formatted(date: .abbreviated, time: .shortened)
            ?? "Time unavailable"
    }

    static func rows(
        system: [SystemAlarmSnapshot], registrations: [AlarmRegistrationRecord], todos: [TodoRecord],
        deviceID: String, inventoryIsCurrent: Bool
    ) -> [ManagedAlarm] {
        let liveIDs = Set(system.map(\.id))
        let live = system.map { alarm in
            // Prefer an existing local registration when legacy data has duplicates.
            let matches = registrations.filter { $0.alarmID == alarm.id }
            let record = matches.first { $0.deviceID == deviceID } ?? matches.first
            return ManagedAlarm(id: alarm.id.uuidString, system: alarm, registration: record,
                                todo: todos.first { $0.id == record?.todoID }, isLocal: true, isConfirmedAbsent: false,
                                needsVerification: !inventoryIsCurrent)
        }
        let remaining = registrations.filter { record in
            !(record.alarmID.map(liveIDs.contains) ?? false)
        }.map { record in
            let isLocal = record.deviceID == deviceID
            return ManagedAlarm(id: "record-\(record.id)", system: nil, registration: record,
                                todo: todos.first { $0.id == record.todoID }, isLocal: isLocal,
                                isConfirmedAbsent: isLocal && inventoryIsCurrent && record.alarmID != nil,
                                needsVerification: isLocal && !inventoryIsCurrent && record.alarmID != nil)
        }
        return live + remaining
    }
}
