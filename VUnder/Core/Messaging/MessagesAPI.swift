import Foundation
import os

struct ConversationPage {
    let conversations: [Conversation]
    let profiles: [Profile]
    let total: Int
}

struct HistoryPage {
    let messages: [Message]
    let profiles: [Profile]
    let total: Int
    let inRead: Int64
    let outRead: Int64
}

struct FriendPage {
    let friends: [Profile]
    let total: Int
}

struct LongPollServer {
    let url: URL
    let key: String
    let ts: Int64
}

final class MessagesAPI: Sendable {
    static let conversationsPageSize = 30
    static let historyPageSize = 30
    static let friendsPageSize = 50

    private static let conversationsVersion = "5.163"
    private static let historyVersion = "5.129"
    private static let profileFields = "first_name,last_name,photo_100,photo_50"

    private let api: VKAPIClient

    init(api: VKAPIClient) {
        self.api = api
    }

    func conversations(offset: Int, count: Int = MessagesAPI.conversationsPageSize) async throws -> ConversationPage {
        let response = try await api.response(VKAPIRequest(method: "messages.getConversations", version: MessagesAPI.conversationsVersion, parameters: [
            ("offset", String(offset)),
            ("count", String(count)),
            ("extended", "1"),
            ("filter", "all"),
            ("fields", MessagesAPI.profileFields),
        ]))
        let profiles = Profile.parseAll(from: response)
        let byID = Dictionary(profiles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let conversations = response.objects("items").compactMap { Conversation(json: $0, profiles: byID) }
        Log.messages.info("conversations offset=\(offset, privacy: .public) items=\(conversations.count, privacy: .public) total=\(response.int("count") ?? 0, privacy: .public)")
        return ConversationPage(conversations: conversations, profiles: profiles, total: response.int("count") ?? 0)
    }

    func history(peerID: Int64, before messageID: Int64? = nil, count: Int = MessagesAPI.historyPageSize) async throws -> HistoryPage {
        var parameters: [(String, String)] = [
            ("peer_id", String(peerID)),
            ("offset", "0"),
            ("count", String(count + (messageID == nil ? 0 : 1))),
            ("extended", "1"),
            ("fields", MessagesAPI.profileFields),
        ]
        if let messageID {
            parameters.append(("start_message_id", String(messageID)))
        }
        let response = try await api.response(VKAPIRequest(method: "messages.getHistory", version: MessagesAPI.historyVersion, parameters: parameters))
        var messages = response.objects("items").compactMap(Message.init(json:))
        if let messageID {
            messages = messages.filter { $0.id < messageID }
        }
        messages.sort { $0.id < $1.id }
        let conversation = response.objects("conversations").first
        Log.messages.info("history peer=\(peerID, privacy: .public) before=\(messageID ?? 0, privacy: .public) items=\(messages.count, privacy: .public) total=\(response.int("count") ?? 0, privacy: .public)")
        return HistoryPage(
            messages: messages,
            profiles: Profile.parseAll(from: response),
            total: response.int("count") ?? 0,
            inRead: conversation?.int64("in_read") ?? 0,
            outRead: conversation?.int64("out_read") ?? 0
        )
    }

    func messages(ids: [Int64]) async throws -> (messages: [Message], profiles: [Profile]) {
        let response = try await api.response(VKAPIRequest(method: "messages.getById", version: MessagesAPI.historyVersion, parameters: [
            ("message_ids", ids.map(String.init).joined(separator: ",")),
            ("extended", "1"),
            ("fields", MessagesAPI.profileFields),
        ]))
        let messages = response.objects("items").compactMap(Message.init(json:))
        Log.messages.info("messages by id requested=\(ids.count, privacy: .public) items=\(messages.count, privacy: .public)")
        return (messages, Profile.parseAll(from: response))
    }

    func send(_ message: OutgoingMessage) async throws -> Int64 {
        var parameters: [(String, String)] = [
            ("peer_id", String(message.peerID)),
            ("random_id", String(message.randomID)),
            ("dont_parse_links", "1"),
        ]
        if !message.text.isEmpty {
            parameters.append(("message", message.text))
        }
        if !message.attachments.isEmpty {
            parameters.append(("attachment", message.attachments.map { "audio\($0.fullID)" }.joined(separator: ",")))
        }
        let json = try await api.call(VKAPIRequest(method: "messages.send", version: message.peerID < 0 ? "5.81" : "5.84", parameters: parameters))
        guard let id = (json.raw["response"] as? NSNumber)?.int64Value, id > 0 else {
            throw VKAPIError.malformedResponse(method: "messages.send")
        }
        Log.messages.info("sent peer=\(message.peerID, privacy: .public) id=\(id, privacy: .public) attachments=\(message.attachments.count, privacy: .public)")
        return id
    }

    func markAsRead(peerID: Int64, upTo messageID: Int64) async throws {
        _ = try await api.call(VKAPIRequest(method: "messages.markAsRead", version: MessagesAPI.historyVersion, parameters: [
            ("peer_id", String(peerID)),
            ("start_message_id", String(messageID)),
        ]))
        Log.messages.info("marked read peer=\(peerID, privacy: .public) up to \(messageID, privacy: .public)")
    }

    func setOffline() async throws {
        _ = try await api.call(VKAPIRequest(method: "account.setOffline"))
        Log.messages.info("presence set offline")
    }

    func longPollServer() async throws -> LongPollServer {
        let response = try await api.response(VKAPIRequest(method: "messages.getLongPollServer", version: MessagesAPI.historyVersion, parameters: [
            ("lp_version", "3"),
            ("need_pts", "0"),
        ]))
        guard let server = response.string("server"), let key = response.string("key"), let ts = response.int64("ts"),
              let url = URL(string: server.hasPrefix("http") ? server : "https://\(server)") else {
            throw VKAPIError.malformedResponse(method: "messages.getLongPollServer")
        }
        Log.messages.info("long poll server \(url.host ?? "", privacy: .public) ts=\(ts, privacy: .public)")
        return LongPollServer(url: url, key: key, ts: ts)
    }

    func friends(offset: Int, count: Int = MessagesAPI.friendsPageSize) async throws -> FriendPage {
        let response = try await api.response(VKAPIRequest(method: "friends.get", parameters: [
            ("order", "hints"),
            ("fields", MessagesAPI.profileFields),
            ("offset", String(offset)),
            ("count", String(count)),
        ]))
        let friends = response.objects("items").compactMap(Profile.init(user:))
        Log.messages.info("friends offset=\(offset, privacy: .public) items=\(friends.count, privacy: .public) total=\(response.int("count") ?? 0, privacy: .public)")
        return FriendPage(friends: friends, total: response.int("count") ?? 0)
    }

    func searchFriends(query: String, offset: Int, count: Int = MessagesAPI.friendsPageSize) async throws -> FriendPage {
        let response = try await api.response(VKAPIRequest(method: "friends.search", parameters: [
            ("q", query),
            ("fields", MessagesAPI.profileFields),
            ("offset", String(offset)),
            ("count", String(count)),
        ]))
        let friends = response.objects("items").compactMap(Profile.init(user:))
        Log.messages.info("friends search '\(query, privacy: .public)' offset=\(offset, privacy: .public) items=\(friends.count, privacy: .public)")
        return FriendPage(friends: friends, total: response.int("count") ?? 0)
    }
}
