import SwiftData
import SwiftUI
import UIKit

struct AdaptiveRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var actionEngine: TodoActionEngine
    @EnvironmentObject private var persistence: PersistenceController

    var body: some View {
        if let startupIssue = persistence.startupIssue {
            StartupRecoveryView(details: startupIssue)
        } else {
            content
        }
    }

    private var content: some View {
        TabView(selection: $router.selectedTab) {
            Tab("Today", systemImage: "checklist", value: RootTab.today) {
                TodayView()
            }

            Tab("Study", systemImage: "book.pages", value: RootTab.study) {
                StudyHomeView()
            }

            Tab("Words", systemImage: "character.book.closed", value: RootTab.vocabulary) {
                VocabularyView()
            }

            Tab("Settings", systemImage: "person.crop.circle", value: RootTab.my) {
                MyView()
            }
        }
        .background(AppTheme.pageBackground)
        .onReceive(NotificationNavigation.shared.$todoID) { id in
            guard let id else { return }
            router.requestedTodoID = id
            router.selectedTab = .today
            NotificationNavigation.shared.todoID = nil
        }
        .alert("Unable to save", isPresented: Binding(
            get: { actionEngine.operationError != nil },
            set: { if !$0 { actionEngine.operationError = nil } }
        )) {
            Button("OK", role: .cancel) { actionEngine.operationError = nil }
        } message: { Text(actionEngine.operationError ?? "") }
        .task {
            applyDebugOrientationIfNeeded()
            guard !AppPreviewSupport.isUnitTesting else { return }
            StarterDataService.bootstrapIfNeeded(in: modelContext)
            AppPreviewSupport.prepare(context: modelContext, router: router)
            #if DEBUG && targetEnvironment(simulator)
            if AppPreviewSupport.isPreview {
                try? await Task.sleep(for: .milliseconds(600))
                applyDebugOrientationIfNeeded()
            }
            #endif
            guard !AppPreviewSupport.isPreview else { return }
            await actionEngine.refreshAndActivateReadyTasks(context: modelContext)
            await actionEngine.processPendingDeviceAlarms(context: modelContext)
        }
        .onChange(of: actionEngine.navigationRequest) { _, request in
            guard let request else { return }
            switch request {
            case .study(let workspaceID):
                router.openStudy(workspaceID: workspaceID)
            case .homework(let homeworkID):
                router.openHomework(homeworkID: homeworkID)
            case .vocabulary(let coursewareID, let unitID):
                router.openVocabulary(coursewareID: coursewareID, unitID: unitID)
            }
            actionEngine.consumeNavigationRequest()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            applyDebugOrientationIfNeeded()
            guard !AppPreviewSupport.isPreview, !AppPreviewSupport.isUnitTesting else { return }
            Task {
                await actionEngine.refreshAndActivateReadyTasks(context: modelContext)
                await actionEngine.processPendingDeviceAlarms(context: modelContext)
            }
        }
    }

    private func applyDebugOrientationIfNeeded() {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-SimpleStudyLandscape"),
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            return
        }
        let preferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: .landscapeRight)
        scene.requestGeometryUpdate(preferences) { error in
            print("Preview orientation: \(error.localizedDescription)")
        }
        #endif
    }
}

private struct StartupRecoveryView: View {
    let details: String
    @State private var showsDetails = false

    var body: some View {
        ContentUnavailableView {
            Label("Study data unavailable", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text("Your data has not been deleted. Editing is paused to protect your changes. Check device storage and iCloud, then reopen the app.")
        } actions: {
            Button("View error details") { showsDetails = true }
                .buttonStyle(.bordered)
        }
        .background(AppTheme.pageBackground)
        .sheet(isPresented: $showsDetails) {
            NavigationStack {
                ScrollView { Text(details).textSelection(.enabled).padding() }
                    .navigationTitle("Error details")
                    .toolbar { Button("Done") { showsDetails = false } }
            }
        }
    }
}
