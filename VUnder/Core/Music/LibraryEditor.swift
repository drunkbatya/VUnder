import Foundation
import os

@MainActor
final class LibraryEditor {
    static let didChange = Notification.Name("LibraryEditor.didChange")

    private let userID: Int64
    private let audioAPI: AudioAPI
    private let library: TrackLibrary
    private let player: PlayerService
    private let cache: AudioCache
    private let downloads: DownloadCenter
    private var libraryIDs: Set<String>?
    private var observer: NSObjectProtocol?

    init(userID: Int64, audioAPI: AudioAPI, library: TrackLibrary, player: PlayerService, cache: AudioCache, downloads: DownloadCenter) {
        self.userID = userID
        self.audioAPI = audioAPI
        self.library = library
        self.player = player
        self.cache = cache
        self.downloads = downloads
        observer = NotificationCenter.default.addObserver(forName: TrackLibrary.didChange, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.reloadIDs() }
        }
        reloadIDs()
    }

    private func reloadIDs() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let ids = try await library.libraryIDs()
                libraryIDs = ids
                NotificationCenter.default.post(name: LibraryEditor.didChange, object: self)
            } catch {
                Log.storage.error("library ids failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func membership(of track: Track) -> LibraryMembership {
        guard track.ownerID == userID else { return .foreign }
        guard let libraryIDs else { return .mine }
        return libraryIDs.contains(track.storageID) ? .mine : .removed
    }

    func add(_ track: Track) async throws -> Track {
        if membership(of: track) == .removed {
            return try await restore(track)
        }
        let newID = try await audioAPI.add(track)
        let added = Track(
            ownerID: userID,
            id: newID,
            artist: track.artist,
            title: track.title,
            duration: track.duration,
            url: track.url,
            accessKey: nil,
            coverURL: track.coverURL,
            libraryPosition: 0,
            cachedAt: nil
        )
        try await library.insertAtTop(added)
        libraryIDs?.insert(added.storageID)
        player.replace(track, with: added)
        NotificationCenter.default.post(name: LibraryEditor.didChange, object: self, userInfo: ["added": added])
        return added
    }

    private func restore(_ track: Track) async throws -> Track {
        do {
            try await audioAPI.restore(track)
        } catch VKAPIError.api(let rejection) {
            Log.music.error("restore \(track.storageID, privacy: .public) rejected \(rejection.code, privacy: .public): \(rejection.message, privacy: .public), adding instead")
            _ = try await audioAPI.add(track)
        }
        var restored = track
        restored.libraryPosition = 0
        try await library.insertAtTop(restored)
        libraryIDs?.insert(restored.storageID)
        NotificationCenter.default.post(name: LibraryEditor.didChange, object: self, userInfo: ["added": restored])
        return restored
    }

    func delete(_ track: Track) async throws {
        try await audioAPI.delete(track)
        downloads.cancelCacheJobs(for: track)
        if await cache.isCached(track) {
            await cache.remove(track)
        }
        try await library.removeFromLibrary(track)
        libraryIDs?.remove(track.storageID)
        NotificationCenter.default.post(name: LibraryEditor.didChange, object: self, userInfo: ["removed": track])
    }
}
