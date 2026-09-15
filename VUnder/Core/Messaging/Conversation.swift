import Foundation
import GRDB

struct Conversation: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "conversation"

    let peerID: Int64
    var title: String
    var photoURL: String?
    var unreadCount: Int
    var inRead: Int64
    var outRead: Int64
    var canWrite: Bool
    var lastMessage: Message?
    var sortDate: Date

    enum Columns {
        static let peerID = Column(CodingKeys.peerID)
        static let sortDate = Column(CodingKeys.sortDate)
    }

    init(peerID: Int64, title: String, photoURL: String?, unreadCount: Int = 0, inRead: Int64 = 0, outRead: Int64 = 0, canWrite: Bool = true, lastMessage: Message? = nil, sortDate: Date = Date()) {
        self.peerID = peerID
        self.title = title
        self.photoURL = photoURL
        self.unreadCount = unreadCount
        self.inRead = inRead
        self.outRead = outRead
        self.canWrite = canWrite
        self.lastMessage = lastMessage
        self.sortDate = sortDate
    }

    init?(json: JSONObject, profiles: [Int64: Profile]) {
        guard let conversation = json.object("conversation"), let peerID = conversation.object("peer")?.int64("id") else { return nil }
        self.peerID = peerID
        if let settings = conversation.object("chat_settings") {
            title = settings.string("title") ?? "Chat"
            photoURL = settings.object("photo")?.string("photo_100")
        } else {
            title = profiles[peerID]?.name ?? "id\(peerID)"
            photoURL = profiles[peerID]?.photoURL
        }
        unreadCount = conversation.int("unread_count") ?? 0
        inRead = conversation.int64("in_read") ?? 0
        outRead = conversation.int64("out_read") ?? 0
        canWrite = conversation.object("can_write")?.bool("allowed") ?? true
        lastMessage = json.object("last_message").flatMap(Message.init(json:))
        sortDate = lastMessage?.date ?? Date(timeIntervalSince1970: 0)
    }

    var isChat: Bool {
        Peer.isChat(peerID)
    }
}
