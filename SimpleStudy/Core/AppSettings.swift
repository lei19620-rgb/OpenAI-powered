import Foundation
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let iCloudEnabled = "simpleStudy.settings.iCloudEnabled"
        static let appearance = "simpleStudy.settings.appearance"
        static let defaultAlarmTarget = "simpleStudy.settings.defaultAlarmTarget"
        static let defaultMissedPolicy = "simpleStudy.settings.defaultMissedPolicy"
        static let defaultTemplateID = "simpleStudy.settings.defaultTemplateID"
    }

    // The independent CloudKit container must be provisioned before enabling sync.
    nonisolated static let defaultICloudEnabled = false

    private let defaults: UserDefaults

    @Published var isICloudEnabled: Bool {
        didSet { defaults.set(isICloudEnabled, forKey: Key.iCloudEnabled) }
    }

    @Published var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }

    @Published var defaultAlarmTarget: AlarmTarget {
        didSet { defaults.set(defaultAlarmTarget.rawValue, forKey: Key.defaultAlarmTarget) }
    }

    @Published var defaultMissedPolicy: MissedOccurrencePolicy {
        didSet { defaults.set(defaultMissedPolicy.rawValue, forKey: Key.defaultMissedPolicy) }
    }

    @Published var defaultTemplateID: UUID? {
        didSet {
            if let defaultTemplateID {
                defaults.set(defaultTemplateID.uuidString, forKey: Key.defaultTemplateID)
            } else {
                defaults.removeObject(forKey: Key.defaultTemplateID)
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Key.iCloudEnabled) == nil {
            isICloudEnabled = Self.defaultICloudEnabled
        } else {
            isICloudEnabled = defaults.bool(forKey: Key.iCloudEnabled)
        }
        appearance = AppAppearance(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system
        defaultAlarmTarget = AlarmTarget(rawValue: defaults.string(forKey: Key.defaultAlarmTarget) ?? "") ?? .iPhone
        defaultMissedPolicy = MissedOccurrencePolicy(
            rawValue: defaults.string(forKey: Key.defaultMissedPolicy) ?? ""
        ) ?? .carryForward
        defaultTemplateID = defaults.string(forKey: Key.defaultTemplateID).flatMap(UUID.init(uuidString:))
    }

    var preferredColorScheme: ColorScheme? {
        switch appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
