import Foundation
import os

enum LongPollEvent {
    case newMessage(id: Int64, peerID: Int64, outgoing: Bool)
    case flagsSet(id: Int64, peerID: Int64, mask: Int)
    case incomingRead(peerID: Int64, messageID: Int64)
    case outgoingRead(peerID: Int64, messageID: Int64)
}

enum LongPollResult {
    case events([LongPollEvent], ts: Int64)
    case outdatedTS(Int64)
    case keyExpired
}

enum LongPollError: Error, LocalizedError {
    case httpStatus(Int)
    case malformed

    var errorDescription: String? {
        switch self {
        case .httpStatus(let status): return "Long poll http=\(status)"
        case .malformed: return "Long poll response malformed"
        }
    }
}

struct LongPollClient: Sendable {
    static let waitSeconds = 25
    static let deletedFlag = 128
    static let outboxFlag = 2

    let urlSession: URLSession

    func poll(_ server: LongPollServer, ts: Int64) async throws -> LongPollResult {
        var components = URLComponents(url: server.url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "act", value: "a_check"),
            URLQueryItem(name: "key", value: server.key),
            URLQueryItem(name: "ts", value: String(ts)),
            URLQueryItem(name: "wait", value: String(LongPollClient.waitSeconds)),
            URLQueryItem(name: "mode", value: "2"),
            URLQueryItem(name: "version", value: "3"),
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = TimeInterval(LongPollClient.waitSeconds + 10)
        request.setValue(VKClientIdentity.userAgent(.general), forHTTPHeaderField: "User-Agent")
        let (data, response) = try await urlSession.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw LongPollError.httpStatus(status) }
        guard let json = JSONObject(data: data) else { throw LongPollError.malformed }
        if let failed = json.int("failed") {
            Log.messages.notice("long poll failed=\(failed, privacy: .public)")
            if failed == 1, let newTS = json.int64("ts") {
                return .outdatedTS(newTS)
            }
            return .keyExpired
        }
        guard let newTS = json.int64("ts") else { throw LongPollError.malformed }
        let updates = json.raw["updates"] as? [[Any]] ?? []
        return .events(updates.compactMap(LongPollClient.event), ts: newTS)
    }

    private static func event(_ update: [Any]) -> LongPollEvent? {
        func int64(_ index: Int) -> Int64? {
            guard index < update.count else { return nil }
            return (update[index] as? NSNumber)?.int64Value
        }
        guard let code = int64(0) else { return nil }
        switch code {
        case 4:
            guard let id = int64(1), let flags = int64(2), let peerID = int64(3) else { return nil }
            return .newMessage(id: id, peerID: peerID, outgoing: Int(flags) & outboxFlag != 0)
        case 2:
            guard let id = int64(1), let mask = int64(2), let peerID = int64(3) else { return nil }
            return .flagsSet(id: id, peerID: peerID, mask: Int(mask))
        case 6:
            guard let peerID = int64(1), let messageID = int64(2) else { return nil }
            return .incomingRead(peerID: peerID, messageID: messageID)
        case 7:
            guard let peerID = int64(1), let messageID = int64(2) else { return nil }
            return .outgoingRead(peerID: peerID, messageID: messageID)
        default:
            return nil
        }
    }
}
