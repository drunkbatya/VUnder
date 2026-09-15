import Foundation
import os

@MainActor
final class ConversationQueueLoader {
    static let prefetchThreshold = 5

    private let api: MessagesAPI
    private let player: PlayerService
    private let network: NetworkMonitor
    private var peerID: Int64?
    private var source: QueueSource?
    private var nextFrom: String?
    private var exhausted = false
    private var task: Task<Void, Never>?
    private var observer: NSObjectProtocol?

    init(api: MessagesAPI, player: PlayerService, network: NetworkMonitor) {
        self.api = api
        self.player = player
        self.network = network
        observer = NotificationCenter.default.addObserver(forName: PlayerService.stateDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.loadNextPageIfNeeded()
            }
        }
    }

    func start(peerID: Int64, source: QueueSource) {
        task?.cancel()
        self.peerID = peerID
        self.source = source
        nextFrom = nil
        exhausted = false
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await api.audioAttachments(peerID: peerID)
                guard !Task.isCancelled else { return }
                player.replaceQueue(with: page.tracks, source: source)
                nextFrom = page.nextFrom
                exhausted = page.nextFrom == nil
            } catch {
                exhausted = true
                Log.messages.error("conversation queue peer=\(peerID, privacy: .public) first page failed: \(error.localizedDescription, privacy: .public)")
            }
            task = nil
            loadNextPageIfNeeded()
        }
    }

    private func loadNextPageIfNeeded() {
        guard let peerID, let source else { return }
        guard player.source == source else {
            self.peerID = nil
            self.source = nil
            task?.cancel()
            task = nil
            return
        }
        guard !exhausted, task == nil, network.isConnected, let nextFrom, player.remainingCount <= ConversationQueueLoader.prefetchThreshold else { return }
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await api.audioAttachments(peerID: peerID, startFrom: nextFrom)
                guard !Task.isCancelled else { return }
                player.appendToQueue(page.tracks, source: source)
                self.nextFrom = page.nextFrom
                exhausted = page.nextFrom == nil || page.tracks.isEmpty
            } catch {
                exhausted = true
                Log.messages.error("conversation queue peer=\(peerID, privacy: .public) from=\(nextFrom, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
            task = nil
        }
    }
}
