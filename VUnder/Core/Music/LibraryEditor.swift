import Foundation
import os

@MainActor
final class LibraryEditor {
    static let didChange = Notification.Name("LibraryEditor.didChange")

    private let userID: Int64
    private let audioAPI: AudioAPI
    private let library: TrackLibrary
    private let player: PlayerService

    init(userID: Int64, audioAPI: AudioAPI, library: TrackLibrary, player: PlayerService) {
        self.userID = userID
        self.audioAPI = audioAPI
        self.library = library
        self.player = player
    }

    func isMine(_ track: Track) -> Bool {
        track.ownerID == userID
    }

    func add(_ track: Track) async throws -> Track {
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
        player.replace(track, with: added)
        NotificationCenter.default.post(name: LibraryEditor.didChange, object: self, userInfo: ["added": added])
        return added
    }

    func delete(_ track: Track) async throws {
        try await audioAPI.delete(track)
        try await library.removeFromLibrary(track)
        NotificationCenter.default.post(name: LibraryEditor.didChange, object: self, userInfo: ["removed": track])
    }
}
