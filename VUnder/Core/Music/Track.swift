import Foundation
import GRDB

struct Track: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "track"

    let ownerID: Int64
    let id: Int64
    var artist: String
    var title: String
    var duration: Int
    var url: String?
    var accessKey: String?
    var coverURL: String?
    var libraryPosition: Int?
    var cachedAt: Date?

    enum Columns {
        static let ownerID = Column(CodingKeys.ownerID)
        static let id = Column(CodingKeys.id)
        static let libraryPosition = Column(CodingKeys.libraryPosition)
        static let cachedAt = Column(CodingKeys.cachedAt)
    }

    var fullID: String {
        let base = "\(ownerID)_\(id)"
        guard let accessKey, !accessKey.isEmpty else { return base }
        return "\(base)_\(accessKey)"
    }

    var isAvailable: Bool {
        !(url ?? "").isEmpty
    }

    var formattedDuration: String {
        String(format: "%d:%02d", duration / 60, duration % 60)
    }

    func isSame(as other: Track?) -> Bool {
        guard let other else { return false }
        return ownerID == other.ownerID && id == other.id
    }

    func matches(_ loweredQuery: String) -> Bool {
        artist.lowercased().contains(loweredQuery) || title.lowercased().contains(loweredQuery)
    }
}

extension Track {
    private static let explicitMarker = " \u{24BA}"
    private static let unavailableURLFragment = "audio_api_unavailable.mp3"

    init?(json: JSONObject) {
        guard let id = json.int64("id") ?? json.int64("aid"), let ownerID = json.int64("owner_id") else { return nil }
        self.id = id
        self.ownerID = ownerID
        artist = Track.stripExplicitMarker(json.string("artist") ?? "")
        title = Track.cleanTitle(Track.stripExplicitMarker(json.string("title") ?? ""), subtitle: json.string("subtitle"))
        duration = json.int("duration") ?? 0
        let rawURL = json.string("url") ?? ""
        url = rawURL.isEmpty || rawURL.contains(Track.unavailableURLFragment) ? nil : rawURL
        let key = json.string("access_key") ?? ""
        accessKey = key.isEmpty ? nil : key
        let thumb = json.object("album")?.object("thumb")
        coverURL = thumb?.string("photo_300") ?? thumb?.string("photo_270")
        libraryPosition = nil
        cachedAt = nil
    }

    private static func stripExplicitMarker(_ value: String) -> String {
        value.hasSuffix(explicitMarker) ? String(value.dropLast(explicitMarker.count)) : value
    }

    private static func cleanTitle(_ title: String, subtitle: String?) -> String {
        var result = title
        if let match = result.range(of: #" \((.+)\) \(\1\)$"#, options: .regularExpression) {
            let duplicate = result[match]
            let single = duplicate.dropLast(duplicate.count / 2)
            result.replaceSubrange(match, with: single)
        }
        if let subtitle, !subtitle.isEmpty, !result.contains(subtitle) {
            result += " (\(subtitle))"
        }
        return result
    }
}
