import Foundation
import GRDB

struct Message: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "message"

    let id: Int64
    let peerID: Int64
    let fromID: Int64
    let date: Date
    var text: String
    let out: Bool
    var attachments: [MessageAttachment]
    var randomID: Int64

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let peerID = Column(CodingKeys.peerID)
    }

    init(id: Int64, peerID: Int64, fromID: Int64, date: Date, text: String, out: Bool, attachments: [MessageAttachment], randomID: Int64) {
        self.id = id
        self.peerID = peerID
        self.fromID = fromID
        self.date = date
        self.text = text
        self.out = out
        self.attachments = attachments
        self.randomID = randomID
    }

    init?(json: JSONObject) {
        guard let id = json.int64("id"), let peerID = json.int64("peer_id"), let fromID = json.int64("from_id") else { return nil }
        self.id = id
        self.peerID = peerID
        self.fromID = fromID
        date = Date(timeIntervalSince1970: TimeInterval(json.int("date") ?? 0))
        text = json.string("text") ?? ""
        out = json.bool("out")
        attachments = json.objects("attachments").compactMap(MessageAttachment.init(json:))
        randomID = json.int64("random_id") ?? 0
    }

    var previewText: String {
        if !text.isEmpty {
            return text
        }
        return attachments.first?.previewText ?? ""
    }

    var tracks: [Track] {
        attachments.compactMap(\.track)
    }
}
