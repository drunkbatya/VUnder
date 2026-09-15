import Foundation
import GRDB

struct Profile: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "profile"

    let id: Int64
    var name: String
    var photoURL: String?

    init(id: Int64, name: String, photoURL: String?) {
        self.id = id
        self.name = name
        self.photoURL = photoURL
    }

    init?(user json: JSONObject) {
        guard let id = json.int64("id") else { return nil }
        self.id = id
        name = [json.string("first_name"), json.string("last_name")].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        photoURL = json.string("photo_100") ?? json.string("photo_50")
    }

    init?(group json: JSONObject) {
        guard let id = json.int64("id") else { return nil }
        self.id = -id
        name = json.string("name") ?? ""
        photoURL = json.string("photo_100") ?? json.string("photo_50")
    }

    static func parseAll(from response: JSONObject) -> [Profile] {
        response.objects("profiles").compactMap(Profile.init(user:)) + response.objects("groups").compactMap(Profile.init(group:))
    }
}
