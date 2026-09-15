import Foundation
import os

@MainActor
final class Outbox {
    static let didSend = Notification.Name("Outbox.didSend")

    private let api: MessagesAPI
    private let store: MessageStore
    private let network: NetworkMonitor
    private let presence: OfflinePresence
    private let userID: Int64
    private var flushTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    init(api: MessagesAPI, store: MessageStore, network: NetworkMonitor, presence: OfflinePresence, userID: Int64) {
        self.api = api
        self.store = store
        self.network = network
        self.presence = presence
        self.userID = userID
        observers.append(NotificationCenter.default.addObserver(forName: NetworkMonitor.didChange, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.flush() }
        })
    }

    func enqueue(peerID: Int64, text: String, attachments: [Track]) {
        let message = OutgoingMessage(peerID: peerID, text: text, attachments: attachments)
        Log.messages.info("outbox enqueue peer=\(peerID, privacy: .public) text=\(text.count, privacy: .public) chars attachments=\(attachments.map(\.fullID).joined(separator: ","), privacy: .public)")
        Task {
            do {
                _ = try await store.insertOutgoing(message)
                flush()
            } catch {
                Log.messages.error("outbox insert failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func retry(_ message: OutgoingMessage) {
        var retried = message
        retried.failure = nil
        Task {
            try? await store.updateOutgoing(retried)
            flush()
        }
    }

    func delete(_ message: OutgoingMessage) {
        guard let id = message.id else { return }
        Task {
            try? await store.deleteOutgoing(id: id, peerID: message.peerID)
        }
    }

    func flush() {
        guard flushTask == nil, network.isConnected else { return }
        flushTask = Task { [weak self] in
            await self?.sendPending()
            self?.flushTask = nil
        }
    }

    private func sendPending() async {
        while network.isConnected {
            let pending: OutgoingMessage?
            do {
                pending = try await store.outgoing().first { $0.failure == nil }
            } catch {
                Log.messages.error("outbox read failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            guard let message = pending, let localID = message.id else { return }
            do {
                let id = try await api.send(message)
                let sent = Message(
                    id: id,
                    peerID: message.peerID,
                    fromID: userID,
                    date: Date(),
                    text: message.text,
                    out: true,
                    attachments: message.attachments.map { .audio($0) },
                    randomID: message.randomID
                )
                try await store.deleteOutgoing(id: localID, peerID: message.peerID)
                try await store.insertMessages([sent], profiles: [])
                let updated = try await store.updateConversation(peerID: message.peerID) { conversation in
                    conversation.lastMessage = sent
                    conversation.sortDate = sent.date
                }
                presence.scheduleSetOffline()
                NotificationCenter.default.post(name: Outbox.didSend, object: self, userInfo: [MessageStore.peerIDKey: message.peerID, "known": updated])
            } catch VKAPIError.api(let response) {
                Log.messages.error("outbox send peer=\(message.peerID, privacy: .public) rejected \(response.code, privacy: .public): \(response.message, privacy: .public)")
                var failed = message
                failed.failure = "\(response.message) (code \(response.code))"
                try? await store.updateOutgoing(failed)
            } catch {
                Log.messages.error("outbox send peer=\(message.peerID, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                return
            }
        }
    }
}
