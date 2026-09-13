import Foundation

struct JSONObject {
    let raw: [String: Any]

    init(_ raw: [String: Any]) {
        self.raw = raw
    }

    init?(data: Data) {
        guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        raw = parsed
    }

    func string(_ key: String) -> String? {
        switch raw[key] {
        case let value as String: return value
        case let value as NSNumber: return value.stringValue
        default: return nil
        }
    }

    func int(_ key: String) -> Int? {
        switch raw[key] {
        case let value as NSNumber: return value.intValue
        case let value as String: return Int(value)
        default: return nil
        }
    }

    func int64(_ key: String) -> Int64? {
        switch raw[key] {
        case let value as NSNumber: return value.int64Value
        case let value as String: return Int64(value)
        default: return nil
        }
    }

    func bool(_ key: String) -> Bool {
        switch raw[key] {
        case let value as NSNumber: return value.boolValue
        case let value as String: return value == "1" || value.lowercased() == "true"
        default: return false
        }
    }

    func object(_ key: String) -> JSONObject? {
        (raw[key] as? [String: Any]).map(JSONObject.init)
    }

    func objects(_ key: String) -> [JSONObject] {
        (raw[key] as? [[String: Any]])?.map(JSONObject.init) ?? []
    }

    func strings(_ key: String) -> [String] {
        raw[key] as? [String] ?? []
    }

    func has(_ key: String) -> Bool {
        raw[key] != nil
    }
}
