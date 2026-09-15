import Foundation
import GRDB

struct OutgoingMessage: Codable, Equatable, Sendable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "outgoingMessage"

    var id: Int64?
    let peerID: Int64
    let text: String
    let attachments: [Track]
    let randomID: Int64
    let createdAt: Date
    var failure: String?

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let peerID = Column(CodingKeys.peerID)
        static let failure = Column(CodingKeys.failure)
    }

    init(peerID: Int64, text: String, attachments: [Track]) {
        id = nil
        self.peerID = peerID
        self.text = text
        self.attachments = attachments
        randomID = Int64(Int32.random(in: 1...Int32.max))
        createdAt = Date()
        failure = nil
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    var previewText: String {
        if !text.isEmpty {
            return text
        }
        guard let first = attachments.first else { return "" }
        return attachments.count > 1 ? "Audio: \(attachments.count) tracks" : "Audio: \(first.artist) - \(first.title)"
    }
}
