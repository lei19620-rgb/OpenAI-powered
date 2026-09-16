import SwiftUI

@main
struct SimpleStudyApp: App {
    @UIApplicationDelegateAdaptor(AppNotificationDelegate.self) private var appDelegate
    @StateObject private var settings: AppSettings
    @StateObject private var persistence: PersistenceController
    @StateObject private var router = AppRouter()
    @StateObject private var actionEngine = TodoActionEngine()
    @StateObject private var dictionaryStore = LocalDictionaryStore()

    init() {
        let settings = AppSettings()
        _settings = StateObject(wrappedValue: settings)
        _persistence = StateObject(
            wrappedValue: PersistenceController(inMemory: AppPreviewSupport.isPreview || AppPreviewSupport.isUnitTesting,
                                               iCloudEnabled: settings.isICloudEnabled)
        )
    }

    var body: some Scene {
        WindowGroup {
            AdaptiveRootView()
                .tint(AppTheme.accent)
                .preferredColorScheme(settings.preferredColorScheme)
                .environmentObject(settings)
                .environmentObject(persistence)
                .environmentObject(router)
                .environmentObject(actionEngine)
                .environmentObject(dictionaryStore)
                .modelContainer(persistence.container)
        }
    }
}
