import Foundation
import UIKit
import os

@MainActor
final class MessagesSync {
    static let conversationsRefreshDidFinish = Notification.Name("MessagesSync.conversationsRefreshDidFinish")

    private let api: MessagesAPI
    private let store: MessageStore
    private let network: NetworkMonitor
    private let settings: AppSettings
    private let longPoll: LongPollClient
    private var pollTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var active = false

    init(api: MessagesAPI, store: MessageStore, network: NetworkMonitor, settings: AppSettings) {
        self.api = api
        self.store = store
        self.network = network
        self.settings = settings
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = TimeInterval(LongPollClient.waitSeconds + 15)
        configuration.httpShouldSetCookies = false
        configuration.waitsForConnectivity = false
        longPoll = LongPollClient(urlSession: URLSession(configuration: configuration))
    }

    func start() {
        guard !active else { return }
        active = true
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.refreshConversations()
                self.startPolling()
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.stopPolling() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NetworkMonitor.didChange, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                if self.network.isConnected {
                    self.refreshConversations()
                    self.startPolling()
                } else {
                    self.stopPolling()
                }
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: Outbox.didSend, object: nil, queue: .main) { [weak self] notification in
            guard let self, notification.userInfo?["known"] as? Bool == false else { return }
            MainActor.assumeIsolated { self.refreshConversations() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: AppSettings.didChange, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                if self.settings.longPollEnabled {
                    self.startPolling()
                } else {
                    self.stopPolling()
                }
            }
        })
        refreshConversations()
        startPolling()
    }

    func stop() {
        active = false
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
        refreshTask?.cancel()
        refreshTask = nil
        stopPolling()
    }

    func refreshConversations() {
        guard active, refreshTask == nil, network.isConnected else { return }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await api.conversations(offset: 0)
                try await store.replaceConversations(page.conversations, profiles: page.profiles)
                NotificationCenter.default.post(name: MessagesSync.conversationsRefreshDidFinish, object: self, userInfo: ["total": page.total])
            } catch {
                Log.messages.error("conversations refresh failed: \(error.localizedDescription, privacy: .public)")
                NotificationCenter.default.post(name: MessagesSync.conversationsRefreshDidFinish, object: self)
            }
            refreshTask = nil
        }
    }

    private func startPolling() {
        guard active, pollTask == nil, settings.longPollEnabled, network.isConnected, UIApplication.shared.applicationState != .background else { return }
        Log.messages.info("long poll start")
        pollTask = Task { [weak self] in
            await self?.pollLoop()
        }
    }

    private func stopPolling() {
        guard let pollTask else { return }
        Log.messages.info("long poll stop")
        pollTask.cancel()
        self.pollTask = nil
    }

    private func pollLoop() async {
        var server: LongPollServer?
        var ts: Int64 = 0
        while !Task.isCancelled {
            do {
                if server == nil {
                    let fresh = try await api.longPollServer()
                    server = fresh
                    ts = fresh.ts
                }
                guard let current = server else { return }
                switch try await longPoll.poll(current, ts: ts) {
                case .events(let events, let newTS):
                    ts = newTS
                    await handle(events)
                case .outdatedTS(let newTS):
                    ts = newTS
                case .keyExpired:
                    server = nil
                }
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                    return
                }
                Log.messages.error("long poll failed: \(error.localizedDescription, privacy: .public)")
                server = nil
                guard network.isConnected else {
                    pollTask = nil
                    return
                }
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    private func handle(_ events: [LongPollEvent]) async {
        var newIDs: [Int64] = []
        for event in events {
            switch event {
            case .newMessage(let id, _, _):
                newIDs.append(id)
            case .flagsSet(let id, let peerID, let mask):
                if mask & LongPollClient.deletedFlag != 0 {
                    Log.messages.info("message deleted id=\(id, privacy: .public) peer=\(peerID, privacy: .public)")
                    try? await store.deleteMessage(id: id, peerID: peerID)
                    if let conversation = try? await store.conversation(peerID: peerID), conversation.lastMessage?.id == id {
                        refreshConversations()
                    }
                }
            case .incomingRead(let peerID, let messageID):
                _ = try? await store.updateConversation(peerID: peerID) { conversation in
                    conversation.inRead = messageID
                    if (conversation.lastMessage?.id ?? 0) <= messageID {
                        conversation.unreadCount = 0
                    }
                }
            case .outgoingRead(let peerID, let messageID):
                _ = try? await store.updateConversation(peerID: peerID) { conversation in
                    conversation.outRead = messageID
                }
            }
        }
        guard !newIDs.isEmpty else { return }
        do {
            let (messages, profiles) = try await api.messages(ids: newIDs)
            try await store.insertMessages(messages, profiles: profiles)
            var unknownPeer = false
            for message in messages {
                let known = try await store.updateConversation(peerID: message.peerID) { conversation in
                    if message.id > (conversation.lastMessage?.id ?? 0) {
                        conversation.lastMessage = message
                        conversation.sortDate = message.date
                    }
                    if !message.out, message.id > conversation.inRead {
                        conversation.unreadCount += 1
                    }
                }
                unknownPeer = unknownPeer || !known
            }
            if unknownPeer {
                refreshConversations()
            }
        } catch {
            Log.messages.error("new messages fetch failed ids=\(newIDs.count, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
