import SwiftData
import SwiftUI
import UIKit

struct MyView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var persistence: PersistenceController
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var actionEngine: TodoActionEngine
    @Query(sort: \NoteTemplateRecord.name) private var templates: [NoteTemplateRecord]
    @StateObject private var permissions = PermissionCenter()

    private var storageSettingChanged: Bool {
        settings.isICloudEnabled != persistence.iCloudEnabledAtLaunch
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    MyHeaderCard(storageTitle: persistence.mode.title)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section {
                    NavigationLink { AISettingsView() } label: {
                        Label("AI service", systemImage: "sparkles")
                    }
                }

                Section {
                    Toggle("Sync with iCloud", isOn: $settings.isICloudEnabled)

                    PermissionSettingRow(
                        title: "iCloud account",
                        subtitle: "",
                        state: permissions.iCloud,
                        actionTitle: permissions.iCloud == .granted ? nil : "System Settings",
                        action: permissions.openSystemSettings
                    )

                    if storageSettingChanged {
                        Label("Storage preference saved. Quit and reopen the app to apply it.", systemImage: "arrow.clockwise.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Sync and storage")
                } footer: {
                    Text("Turning this off stops future sync after restarting the app.\n\(persistence.mode.details)")
                }

                Section {
                    PermissionSettingRow(
                        title: "Notifications",
                        subtitle: "",
                        state: permissions.notification,
                        actionTitle: permissionActionTitle(permissions.notification),
                        action: handleNotificationPermission
                    )

                    PermissionSettingRow(
                        title: "Alarm",
                        subtitle: "",
                        state: permissions.alarm,
                        actionTitle: permissionActionTitle(permissions.alarm),
                        action: handleAlarmPermission
                    )

                    PermissionSettingRow(
                        title: "Reminders",
                        subtitle: "",
                        state: permissions.reminders,
                        actionTitle: permissionActionTitle(permissions.reminders),
                        action: handleReminderPermission
                    )

                    NavigationLink {
                        AlarmManagementView()
                    } label: {
                        MyNavigationLabel(
                            icon: "alarm",
                            title: "Alarms",
                            subtitle: ""
                        )
                    }
                } header: {
                    Text("Permissions")
                }

                Section {
                    NavigationLink {
                        Form {
                Section {
                    Picker("Appearance", selection: $settings.appearance) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.title).tag(appearance)
                        }
                    }

                    Picker("Default alarm device", selection: $settings.defaultAlarmTarget) {
                        ForEach(AlarmTarget.allCases) { target in
                            Text(target.title).tag(target)
                        }
                    }

                    Picker("Default missed-task policy", selection: $settings.defaultMissedPolicy) {
                        ForEach(MissedOccurrencePolicy.allCases) { policy in
                            Text(policy.title).tag(policy)
                        }
                    }

                    Picker("Default note template", selection: $settings.defaultTemplateID) {
                        Text("Sentence study or first template").tag(UUID?.none)
                        ForEach(templates) { template in
                            Text("\(template.name) · v\(template.version)").tag(Optional(template.id))
                        }
                    }
                } header: {
                    Text("Preferences")
                } footer: {
                    Text("Applies only to new content.")
                }
                        }
                        .navigationTitle("Preferences")
                        .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        Label("Preferences", systemImage: "slider.horizontal.3")
                    }
                }

                Section {
                    NavigationLink {
                        ImportLibraryView()
                    } label: {
                        Label("Materials, dictionaries, and templates", systemImage: "square.and.arrow.down")
                    }
                }

                Section("Privacy and about") {
                    NavigationLink {
                        PrivacyPolicyView()
                    } label: {
                        Label("Privacy policy", systemImage: "hand.raised")
                    }

                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Device", value: UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppTheme.pageBackground)
            .navigationTitle("Settings")
            .task { await permissions.refresh(checkICloud: persistence.mode.usesICloud) }
            .refreshable { await permissions.refresh(checkICloud: persistence.mode.usesICloud) }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func permissionActionTitle(_ state: PermissionAccessState) -> String? {
        switch state {
        case .notDetermined: "Allow"
        case .denied, .unavailable: "System Settings"
        case .checking, .granted: nil
        }
    }

    private func handleNotificationPermission() {
        if permissions.notification == .notDetermined {
            Task {
                await permissions.requestNotifications()
                await actionEngine.syncTodoNotifications(context: modelContext)
            }
        } else {
            permissions.openSystemSettings()
        }
    }

    private func handleAlarmPermission() {
        if permissions.alarm == .notDetermined {
            Task { await permissions.requestAlarm() }
        } else {
            permissions.openSystemSettings()
        }
    }

    private func handleReminderPermission() {
        if permissions.reminders == .notDetermined {
            Task {
                await permissions.requestReminders()
                await actionEngine.syncTodoReminders(context: modelContext)
            }
        } else {
            permissions.openSystemSettings()
        }
    }
}

private struct ImportLibraryView: View {
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        List {
                Section {
                    NavigationLink {
                        NoteTemplateLibraryView()
                    } label: {
                        MyNavigationLabel(
                            icon: "rectangle.stack.badge.plus",
                            title: "Note templates",
                            subtitle: "Import and export JSON"
                        )
                    }

                    Button {
                        router.openHomework()
                    } label: {
                        MyNavigationLabel(
                            icon: "pencil.and.list.clipboard",
                            title: "Assignments",
                            subtitle: ".sshomework / JSON"
                        )
                    }

                    Button {
                        router.openStudy()
                    } label: {
                        MyNavigationLabel(
                            icon: "doc.richtext",
                            title: "Course materials",
                            subtitle: "PDF with lesson-order detection"
                        )
                    }

                    Button {
                        router.selectedTab = .vocabulary
                    } label: {
                        MyNavigationLabel(
                            icon: "character.book.closed",
                            title: "Word collections",
                            subtitle: "Import grouped JSON"
                        )
                    }

                    NavigationLink {
                        VocabularyFormatView()
                    } label: {
                        MyNavigationLabel(
                            icon: "curlybraces",
                            title: "Word collection JSON example",
                            subtitle: "schemaVersion 1"
                        )
                    }

                    NavigationLink {
                        LocalDictionaryManagementView()
                    } label: {
                        MyNavigationLabel(
                            icon: "character.book.closed",
                            title: "Offline dictionaries",
                            subtitle: "Offline lookup only"
                        )
                    }

                    NavigationLink {
                        LocalDictionaryFormatView()
                    } label: {
                        MyNavigationLabel(
                            icon: "text.book.closed",
                            title: "Dictionary JSON example",
                            subtitle: "Standard JSON format"
                        )
                    }

                    Button {
                        router.openStudy()
                    } label: {
                        MyNavigationLabel(
                            icon: "doc.text",
                            title: "Markdown notes",
                            subtitle: "Import and export .md"
                        )
                    }

                    NavigationLink {
                        FileExampleView(
                            title: "Note template JSON",
                            fileName: "note-template-example.sstemplate.json",
                            data: try? NoteTemplatePackageService.exampleData()
                        )
                    } label: {
                        MyNavigationLabel(
                            icon: "curlybraces",
                            title: "Note template JSON example",
                            subtitle: "schemaVersion 1"
                        )
                    }

                    NavigationLink {
                        FileExampleView(
                            title: "Daily study Markdown",
                            fileName: "daily-learning-note.md",
                            data: Data(NoteMarkdownService.exampleContent.utf8)
                        )
                    } label: {
                        MyNavigationLabel(
                            icon: "text.document",
                            title: "Markdown note example",
                            subtitle: "Daily study note"
                        )
                    }

                    NavigationLink {
                        FileExampleView(
                            title: "Assignment JSON",
                            fileName: "homework-example.sshomework",
                            data: try? HomeworkExampleService.exampleData()
                        )
                    } label: {
                        MyNavigationLabel(
                            icon: "checklist.checked",
                            title: "Assignment JSON example",
                            subtitle: "Single choice, multiple choice, fill-in, and open response"
                        )
                    }
                } header: {
                    Text("Imports and examples")
                } footer: {
                    Text("Formats are validated before import. Import PDFs within a course.")
                }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Materials and templates")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MyHeaderCard: View {
    let storageTitle: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "book.pages.fill")
                .font(.title2)
                .appIconBadge(size: 56, radius: 18)
            VStack(alignment: .leading, spacing: 5) {
                Text("Study AI").font(.system(.title, design: .rounded).weight(.semibold))
                Text("Learn with purpose. Practice with insight.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Label(storageTitle, systemImage: "icloud")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .appCard(padding: 24, radius: AppTheme.heroRadius)
    }
}

private struct PermissionSettingRow: View {
    let title: String
    let subtitle: String
    let state: PermissionAccessState
    let actionTitle: String?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: state.systemImage)
                .foregroundStyle(state == .granted ? .green : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let actionTitle {
                Button(actionTitle, action: action)
                    .font(.subheadline)
                    .buttonStyle(.bordered)
            } else {
                Text(state.title)
                    .font(.subheadline)
                    .foregroundStyle(state == .granted ? .green : .secondary)
            }
        }
    }
}

private struct MyNavigationLabel: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(AppTheme.accent)
        }
    }
}

private struct FileExampleView: View {
    let title: String
    let fileName: String
    let data: Data?
    @State private var exportURL: URL?

    private var text: String {
        guard let data else { return "Could not generate the example." }
        return String(data: data, encoding: .utf8) ?? "The example is not valid UTF-8."
    }

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppTheme.pagePadding)
        }
        .background(AppTheme.pageBackground)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("Share example", systemImage: "square.and.arrow.up")
                }
            }
        }
        .task { prepareExport() }
    }

    private func prepareExport() {
        guard exportURL == nil, let data else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: .atomic)
            exportURL = url
        } catch {
            exportURL = nil
        }
    }
}
