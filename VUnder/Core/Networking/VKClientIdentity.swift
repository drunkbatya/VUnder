import Foundation

enum VKClientIdentity {
    static let clientID = "2274003"
    static let clientSecret = "hHbZxrka2uZ6jB1inYsH"
    static let apiHost = "api.vk.ru"
    static let oauthHost = "oauth.vk.ru"

    enum AppVersion: String {
        case general = "8.108-26257"
        case auth = "8.183-54468"
        case audio = "8.96-22758"
    }

    static func userAgent(_ version: AppVersion) -> String {
        "VKAndroidApp/\(version.rawValue) (Android 11; SDK 30; arm64-v8a; Xiaomi; M2101K6G; \(language); 2400x1080)"
    }

    static var language: String {
        let supported = ["en", "ru", "ua", "be"]
        let preferred = Locale.preferredLanguages.first.map { Locale(identifier: $0).languageCode ?? "en" } ?? "en"
        let normalized = preferred == "uk" ? "ua" : preferred
        return supported.contains(normalized) ? normalized : "en"
    }

    static func makeDeviceID() -> String {
        let short = String(format: "%016llx", UInt64.random(in: UInt64.min...UInt64.max))
        let long = (0..<16).map { _ in String(format: "%02x", UInt8.random(in: UInt8.min...UInt8.max)) }.joined()
        return "\(short):\(long)"
    }
}
