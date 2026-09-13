import UIKit

enum Appearance: String, CaseIterable {
    case system
    case light
    case dark

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }
}

final class AppearanceSettings {
    static let didChange = Notification.Name("AppearanceSettings.didChange")

    private let defaults: UserDefaults
    private let key = "appearance"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var current: Appearance {
        get { defaults.string(forKey: key).flatMap(Appearance.init) ?? .system }
        set {
            defaults.set(newValue.rawValue, forKey: key)
            NotificationCenter.default.post(name: AppearanceSettings.didChange, object: self)
        }
    }
}
