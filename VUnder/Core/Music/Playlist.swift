import Foundation

struct Playlist: Equatable, Sendable {
    let ownerID: Int64
    let id: Int64
    let title: String
    let accessKey: String?
    let trackCount: Int
    let coverURL: String?

    init?(json: JSONObject) {
        guard let id = json.int64("id"), let ownerID = json.int64("owner_id") else { return nil }
        self.id = id
        self.ownerID = ownerID
        title = json.string("title") ?? ""
        let key = json.string("access_key") ?? ""
        accessKey = key.isEmpty ? nil : key
        trackCount = json.int("count") ?? 0
        coverURL = json.object("photo")?.string("photo_135")
    }
}
