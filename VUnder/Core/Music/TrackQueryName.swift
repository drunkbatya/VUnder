import Foundation

extension Track {
    var searchQuery: String {
        "\(Track.queryName(artist)) \(Track.queryName(title))"
    }

    var artistQuery: String {
        Track.queryName(artist)
    }

    static func queryName(_ value: String) -> String {
        var name = value
        if let dot = name.firstIndex(of: "."), name[..<dot].allSatisfy(\.isNumber), !name[..<dot].isEmpty {
            name = String(name[name.index(after: dot)...])
        }
        name = name.replacingOccurrences(of: "[", with: "(").replacingOccurrences(of: "]", with: ")").trimmingCharacters(in: .whitespaces)
        while name.hasSuffix(")"), let open = name.lastIndex(of: "(") {
            name = String(name[..<open]).trimmingCharacters(in: .whitespaces)
        }
        return name.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "\\", with: "").trimmingCharacters(in: .whitespaces)
    }
}
