import Foundation
import GRDB

struct ListenHistoryEntry: Codable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "listenHistory"

    let trackOwnerID: Int64
    let trackID: Int64
    var listenedAt: Date

    enum Columns {
        static let listenedAt = Column(CodingKeys.listenedAt)
    }
}
