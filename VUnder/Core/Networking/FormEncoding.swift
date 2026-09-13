import Foundation

enum FormEncoding {
    private static let allowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._*")
        return set
    }()

    static func body(_ parameters: [(String, String)]) -> Data {
        let encoded = parameters.map { "\(escape($0.0))=\(escape($0.1))" }.joined(separator: "&")
        return Data(encoded.utf8)
    }

    static func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
