import Foundation

struct VoiceMessage: Codable, Equatable, Sendable {
    let id: Int64
    let ownerID: Int64
    let duration: Int
    let mp3URL: String?

    init?(json: JSONObject) {
        guard let id = json.int64("id"), let ownerID = json.int64("owner_id") else { return nil }
        self.id = id
        self.ownerID = ownerID
        duration = json.int("duration") ?? 0
        mp3URL = json.string("link_mp3") ?? json.string("link_ogg")
    }

    var storageID: String {
        "\(ownerID)_\(id)"
    }

    var formattedDuration: String {
        String(format: "%d:%02d", duration / 60, duration % 60)
    }
}
