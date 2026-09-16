import AlarmKit
import SwiftData
import SwiftUI

struct AlarmManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var actionEngine: TodoActionEngine
    @Query(sort: \AlarmRegistrationRecord.requestedFireDate, order: .reverse)
    private var registrations: [AlarmRegistrationRecord]
    @Query private var todos: [TodoRecord]

    @State private var cancelTarget: ManagedAlarm?
    @State private var deleteTarget: ManagedAlarm?
    @State private var operationError: String?
    @State private var showsHistory = false

    private var rows: [ManagedAlarm] {
        ManagedAlarm.rows(system: actionEngine.systemAlarms, registrations: registrations, todos: todos,
                          deviceID: DeviceIdentity.id,
                          inventoryIsCurrent: actionEngine.hasLoadedSystemAlarms && actionEngine.alarmRefreshError == nil)
    }

    var body: some View {
        List {
            if let error = actionEngine.alarmRefreshError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                    Button("Refresh") { actionEngine.refreshAlarmInventory() }
                }
            }
            alarmSections
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.pageBackground)
        .navigationTitle("Alarms")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            actionEngine.refreshAlarmInventory()
            for await _ in AlarmManager.shared.alarmUpdates {
                guard !Task.isCancelled else { break }
                actionEngine.refreshAlarmInventory()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { actionEngine.refreshAlarmInventory() }
        }
        .refreshable { actionEngine.refreshAlarmInventory() }
        .confirmationDialog(
            cancelTarget?.state == .fired ? "Stop the ringing alarm?" : "Cancel this alarm occurrence?",
            isPresented: Binding(get: { cancelTarget != nil }, set: { if !$0 { cancelTarget = nil } }),
            titleVisibility: .visible
        ) {
            if let target = cancelTarget {
                Button(target.state == .fired ? "Stop ringing" : "Cancel alarm", role: .destructive) {
                    cancelTarget = nil
                    Task { await cancel(target) }
                }
            }
            Button("Back", role: .cancel) { cancelTarget = nil }
        } message: {
            Text("Cancel this occurrence on this device only. The task and other devices are unaffected.")
        }
        .confirmationDialog(
            "Delete this alarm configuration?",
            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
            titleVisibility: .visible
        ) {
            if let target = deleteTarget {
                Button("Delete alarm configuration", role: .destructive) {
                    deleteTarget = nil
                    Task { await delete(target) }
                }
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("Cancel this task's local alarm and disable its alarm action. Keep the task. Configuration changes follow your iCloud sync settings.")
        }
        .alert("Alarm action failed", isPresented: Binding(
            get: { operationError != nil }, set: { if !$0 { operationError = nil } }
        )) {
            Button("OK", role: .cancel) { operationError = nil }
        } message: { Text(operationError ?? "") }
    }

    @ViewBuilder
    private var alarmSections: some View {
        let local = rows.filter { $0.isLocal && ($0.system != nil || $0.canCancel) }
        let history = rows.filter { $0.isLocal && $0.system == nil && !$0.canCancel }
        let remote = rows.filter { !$0.isLocal }

        if !local.isEmpty {
            Section {
                ForEach(local) { alarm in alarmRow(alarm) }
            } header: { Text("On this device · \(local.count)") }
            footer: { Text("Managed by this app. Stopping an alarm does not complete its task.") }
        } else if actionEngine.hasLoadedSystemAlarms && actionEngine.alarmRefreshError == nil {
            ContentUnavailableView("No upcoming alarms on this device", systemImage: "alarm")
                .listRowBackground(Color.clear)
        } else if actionEngine.alarmRefreshError == nil {
            ProgressView("Reading system alarms")
                .frame(maxWidth: .infinity)
        }

        if !history.isEmpty {
            Section {
                DisclosureGroup("Inactive and history · \(history.count)", isExpanded: $showsHistory) {
                    ForEach(history) { alarm in alarmRow(alarm) }
                }
            }
        }
        if !remote.isEmpty {
            Section {
                ForEach(remote) { alarm in alarmRow(alarm) }
            } header: { Text("Other devices · \(remote.count)") }
            footer: { Text("Open alarm management on the device that rings to view or cancel its alarms.") }
        }
    }

    private func alarmRow(_ alarm: ManagedAlarm) -> some View {
        AlarmManagementRow(alarm: alarm, isBusy: actionEngine.isRunning,
                           cancel: { cancelTarget = alarm }, delete: { deleteTarget = alarm })
    }

    private func cancel(_ alarm: ManagedAlarm) async {
        do {
            if let registration = alarm.registration {
                try await actionEngine.cancelAlarmRegistration(registration, context: modelContext)
            } else if let system = alarm.system {
                try await actionEngine.cancelRecoveredAlarm(id: system.id)
            }
        } catch { operationError = error.localizedDescription }
        actionEngine.refreshAlarmInventory()
    }

    private func delete(_ alarm: ManagedAlarm) async {
        guard let registration = alarm.registration else { return }
        do { try await actionEngine.deleteAlarmRegistration(registration, context: modelContext) }
        catch { operationError = error.localizedDescription }
        actionEngine.refreshAlarmInventory()
    }
}

private struct AlarmManagementRow: View {
    let alarm: ManagedAlarm
    let isBusy: Bool
    let cancel: () -> Void
    let delete: () -> Void

    private var color: Color {
        switch alarm.state {
        case .fired: .orange
        case .scheduled: AppTheme.accent
        case .failed, .permissionDenied: .red
        default: .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: alarm.state == .fired ? "bell.and.waveform.fill" : "alarm")
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 36, height: 40)
                VStack(alignment: .leading, spacing: 5) {
                    Text(alarm.title).font(.headline)
                    Text(alarm.timeDescription).font(.subheadline).foregroundStyle(.secondary)
                    if alarm.isRecovered {
                        Text("Recovered from the system; original record missing")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !alarm.isLocal {
                        Text(alarm.registration?.deviceKind ?? "Other device")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Text(alarm.statusDescription)
                    .font(.caption.weight(.medium)).foregroundStyle(color)
                if alarm.isLocal && alarm.registration != nil {
                    Menu {
                        Button("Delete alarm configuration", systemImage: "trash", role: .destructive, action: delete)
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("More alarm actions")
                    .disabled(isBusy)
                }
            }
            if let error = alarm.registration?.errorMessage, !error.isEmpty, alarm.system == nil {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            if alarm.canCancel {
                Button(action: cancel) {
                    Label(alarm.state == .fired ? "Stop ringing" : "Cancel this occurrence", systemImage: "alarm.slash")
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.bordered)
                .tint(alarm.state == .fired ? .orange : AppTheme.accent)
                .disabled(isBusy)
            }
        }
        .padding(.vertical, 8)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if alarm.canCancel {
                Button(action: cancel) { Label("Cancel alarm", systemImage: "alarm.slash") }.tint(.orange)
            }
            if alarm.isLocal && alarm.registration != nil {
                Button(role: .destructive, action: delete) { Label("Delete configuration", systemImage: "trash") }
            }
        }
    }
}
