import Foundation
import os

enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "VUnder"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let api = Logger(subsystem: subsystem, category: "api")
    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let session = Logger(subsystem: subsystem, category: "session")
    static let storage = Logger(subsystem: subsystem, category: "storage")
    static let music = Logger(subsystem: subsystem, category: "music")
    static let player = Logger(subsystem: subsystem, category: "player")
}

enum LogRedaction {
    private static let secretKeyFragments = ["token", "secret", "hash", "password", "sig"]
    private static let hiddenKeys: Set<String> = ["password", "sig", "client_secret"]

    static func parameters(_ parameters: [(String, String)]) -> String {
        parameters.map { "\($0.0)=\(value($0.1, key: $0.0))" }.joined(separator: "&")
    }

    static func json(_ json: JSONObject) -> String {
        json.raw.keys.sorted().map { key in
            let raw = json.raw[key]
            let rendered: String
            switch raw {
            case let string as String: rendered = value(string, key: key)
            case let number as NSNumber: rendered = number.stringValue
            case is [Any]: rendered = "[...]"
            case let object as [String: Any]: rendered = "{\(self.json(JSONObject(object)))}"
            default: rendered = "?"
            }
            return "\(key)=\(rendered)"
        }.joined(separator: " ")
    }

    static func value(_ value: String, key: String) -> String {
        if hiddenKeys.contains(key) {
            return "***"
        }
        guard secretKeyFragments.contains(where: { key.contains($0) }) else { return value }
        guard value.count > 12 else { return "***" }
        return "\(value.prefix(4))...\(value.suffix(4))"
    }
}
