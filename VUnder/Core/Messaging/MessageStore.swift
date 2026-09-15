import Foundation
import GRDB
import os

final class MessageStore: Sendable {
    static let didChange = Notification.Name("MessageStore.didChange")
    static let peerIDKey = "peerID"

    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func conversations() async throws -> [Conversation] {
        try await database.queue.read { db in
            try Conversation.order(Conversation.Columns.sortDate.desc).fetchAll(db)
        }
    }

    func conversation(peerID: Int64) async throws -> Conversation? {
        try await database.queue.read { db in
            try Conversation.fetchOne(db, key: peerID)
        }
    }

    func replaceConversations(_ conversations: [Conversation], profiles: [Profile]) async throws {
        try await database.queue.write { db in
            try Conversation.deleteAll(db)
            for conversation in conversations {
                try conversation.insert(db)
            }
            for profile in profiles {
                try profile.save(db)
            }
        }
        Log.messages.info("conversations replaced count=\(conversations.count, privacy: .public)")
        notify(peerID: nil)
    }

    func saveConversation(_ conversation: Conversation) async throws {
        try await database.queue.write { db in
            try conversation.save(db)
        }
        notify(peerID: conversation.peerID)
    }

    func updateConversation(peerID: Int64, _ change: @Sendable @escaping (inout Conversation) -> Void) async throws -> Bool {
        let updated = try await database.queue.write { db -> Bool in
            guard var conversation = try Conversation.fetchOne(db, key: peerID) else { return false }
            change(&conversation)
            try conversation.save(db)
            return true
        }
        if updated {
            notify(peerID: peerID)
        }
        return updated
    }

    func unreadTotal() async throws -> Int {
        try await database.queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COALESCE(SUM(unreadCount), 0) FROM conversation") ?? 0
        }
    }

    func messages(peerID: Int64) async throws -> [Message] {
        try await database.queue.read { db in
            try Message.filter(Message.Columns.peerID == peerID).order(Message.Columns.id).fetchAll(db)
        }
    }

    func replaceMessages(peerID: Int64, with messages: [Message], profiles: [Profile]) async throws {
        try await database.queue.write { db in
            try Message.filter(Message.Columns.peerID == peerID).deleteAll(db)
            for message in messages {
                try message.insert(db)
            }
            for profile in profiles {
                try profile.save(db)
            }
        }
        Log.messages.info("messages cached peer=\(peerID, privacy: .public) count=\(messages.count, privacy: .public)")
    }

    func insertMessages(_ messages: [Message], profiles: [Profile]) async throws {
        try await database.queue.write { db in
            for message in messages {
                try message.save(db)
            }
            for profile in profiles {
                try profile.save(db)
            }
        }
        for peerID in Set(messages.map(\.peerID)) {
            notify(peerID: peerID)
        }
    }

    func deleteMessage(id: Int64, peerID: Int64) async throws {
        _ = try await database.queue.write { db in
            try Message.deleteOne(db, key: id)
        }
        notify(peerID: peerID)
    }

    func profiles(ids: [Int64]) async throws -> [Int64: Profile] {
        try await database.queue.read { db in
            let rows = try Profile.filter(ids.contains(Column("id"))).fetchAll(db)
            return Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
    }

    func saveProfiles(_ profiles: [Profile]) async throws {
        try await database.queue.write { db in
            for profile in profiles {
                try profile.save(db)
            }
        }
    }

    func outgoing() async throws -> [OutgoingMessage] {
        try await database.queue.read { db in
            try OutgoingMessage.order(OutgoingMessage.Columns.id).fetchAll(db)
        }
    }

    func insertOutgoing(_ message: OutgoingMessage) async throws -> OutgoingMessage {
        let inserted = try await database.queue.write { db in
            try message.inserted(db)
        }
        notify(peerID: message.peerID)
        return inserted
    }

    func updateOutgoing(_ message: OutgoingMessage) async throws {
        try await database.queue.write { db in
            try message.update(db)
        }
        notify(peerID: message.peerID)
    }

    func deleteOutgoing(id: Int64, peerID: Int64) async throws {
        _ = try await database.queue.write { db in
            try OutgoingMessage.deleteOne(db, key: id)
        }
        notify(peerID: peerID)
    }

    func clear() async throws {
        try await database.queue.write { db in
            try OutgoingMessage.deleteAll(db)
            try Message.deleteAll(db)
            try Conversation.deleteAll(db)
            try Profile.deleteAll(db)
        }
        Log.messages.info("message store cleared")
        notify(peerID: nil)
    }

    private func notify(peerID: Int64?) {
        let info: [AnyHashable: Any]? = peerID.map { [MessageStore.peerIDKey: $0] }
        Task { @MainActor in
            NotificationCenter.default.post(name: MessageStore.didChange, object: nil, userInfo: info)
        }
    }
}
