import Foundation
import os

@MainActor
final class AutoCacheController {
    private let player: PlayerService
    private let cache: AudioCache
    private let cacheState: CacheState
    private let settings: AppSettings
    private let network: NetworkMonitor
    private let userID: Int64
    private var triggeredTrack: Track?
    private var observers: [NSObjectProtocol] = []

    init(player: PlayerService, cache: AudioCache, cacheState: CacheState, settings: AppSettings, network: NetworkMonitor, userID: Int64) {
        self.player = player
        self.cache = cache
        self.cacheState = cacheState
        self.settings = settings
        self.network = network
        self.userID = userID
        observers.append(NotificationCenter.default.addObserver(forName: PlayerService.progressDidChange, object: player, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.progressChanged() }
        })
    }

    func shouldCache(_ track: Track) -> Bool {
        settings.cacheEnabled && (track.ownerID == userID || !settings.cacheOnlyMine)
    }

    private func progressChanged() {
        guard player.state == .playing, let track = player.current, !track.isSame(as: triggeredTrack) else { return }
        let threshold: TimeInterval = network.isExpensive ? 30 : 10
        guard player.progress.position >= threshold, network.isConnected else { return }
        triggeredTrack = track
        var candidates = [track]
        if let upcoming = player.upcoming {
            candidates.append(upcoming)
        }
        for candidate in candidates where shouldCache(candidate) && !cacheState.isCached(candidate) {
            Log.cache.info("auto-cache \(candidate.storageID, privacy: .public)")
            Task { [cache] in
                await cache.enqueue(candidate)
            }
        }
    }
}
