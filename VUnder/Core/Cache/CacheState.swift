import Foundation

@MainActor
final class CacheState {
    static let didChange = Notification.Name("CacheState.didChange")

    private(set) var cachedIDs: Set<String> = []
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(forName: AudioCache.didChange, object: nil, queue: .main) { [weak self] notification in
            guard let self, let ids = notification.userInfo?["ids"] as? Set<String> else { return }
            MainActor.assumeIsolated {
                self.cachedIDs = ids
                NotificationCenter.default.post(name: CacheState.didChange, object: self)
            }
        }
    }

    func isCached(_ track: Track) -> Bool {
        cachedIDs.contains(track.storageID)
    }
}
