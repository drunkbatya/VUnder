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

final class AppSettings {
    static let didChange = Notification.Name("AppSettings.didChange")

    private enum Key {
        static let appearance = "appearance"
        static let historyEnabled = "history_enabled"
        static let cacheEnabled = "cache_enabled"
        static let cacheOnlyMine = "cache_only_mine"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Key.historyEnabled: true, Key.cacheEnabled: true, Key.cacheOnlyMine: true])
    }

    var appearance: Appearance {
        get { defaults.string(forKey: Key.appearance).flatMap(Appearance.init) ?? .system }
        set { update(Key.appearance, newValue.rawValue) }
    }

    var historyEnabled: Bool {
        get { defaults.bool(forKey: Key.historyEnabled) }
        set { update(Key.historyEnabled, newValue) }
    }

    var cacheEnabled: Bool {
        get { defaults.bool(forKey: Key.cacheEnabled) }
        set { update(Key.cacheEnabled, newValue) }
    }

    var cacheOnlyMine: Bool {
        get { defaults.bool(forKey: Key.cacheOnlyMine) }
        set { update(Key.cacheOnlyMine, newValue) }
    }

    private func update(_ key: String, _ value: Any) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: AppSettings.didChange, object: self)
    }
}
