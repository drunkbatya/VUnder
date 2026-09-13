import UIKit

enum Theme {
    static let accent = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(hex: 0x7F8EC7) : UIColor(hex: 0x527DAD)
    }

    static let barBackground = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(hex: 0x1B1A1F) : UIColor(hex: 0x527DAD)
    }

    static let barForeground = UIColor.white

    static let background = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(hex: 0x1B1A1F) : UIColor.white
    }

    static let groupedBackground = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(hex: 0x141317) : UIColor(hex: 0xEBEDF0)
    }

    static let secondaryText = UIColor.secondaryLabel
    static let text = UIColor.label

    @MainActor
    static func applyGlobalAppearance() {
        let navigationBar = UINavigationBarAppearance()
        navigationBar.configureWithOpaqueBackground()
        navigationBar.backgroundColor = barBackground
        navigationBar.titleTextAttributes = [.foregroundColor: barForeground]
        navigationBar.largeTitleTextAttributes = [.foregroundColor: barForeground]
        UINavigationBar.appearance().standardAppearance = navigationBar
        UINavigationBar.appearance().scrollEdgeAppearance = navigationBar
        UINavigationBar.appearance().compactAppearance = navigationBar
        UINavigationBar.appearance().tintColor = barForeground

        UIWindow.appearance().tintColor = accent
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
