import UIKit
import os

final class PlaylistTracksViewController: FilterableTrackListViewController {
    private let audioAPI: AudioAPI
    private let network: NetworkMonitor
    private let playlist: Playlist
    private var loaded = false
    private var loadTask: Task<Void, Never>?

    init(audioAPI: AudioAPI, network: NetworkMonitor, playlist: Playlist) {
        self.audioAPI = audioAPI
        self.network = network
        self.playlist = playlist
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override var emptyMessage: String {
        if loadTask != nil {
            return "Loading..."
        }
        if !allTracks.isEmpty {
            return super.emptyMessage
        }
        return network.isConnected ? (loaded ? "Playlist is empty" : "") : "No internet connection"
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = playlist.title
        load()
    }

    private func load() {
        guard network.isConnected else {
            updateEmptyState()
            return
        }
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await audioAPI.allTracks(ownerID: playlist.ownerID, playlist: playlist) { _, _ in }
                loaded = true
                loadTask = nil
                allTracks = result
            } catch {
                Log.music.error("playlist \(self.playlist.id, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                loadTask = nil
                updateEmptyState()
                showError(error)
            }
        }
    }
}
