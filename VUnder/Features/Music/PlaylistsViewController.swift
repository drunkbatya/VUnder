import UIKit
import os

final class PlaylistsViewController: UITableViewController {
    var onSelectPlaylist: ((Playlist) -> Void)?

    private let audioAPI: AudioAPI
    private let network: NetworkMonitor
    private let ownerID: Int64
    private let emptyLabel = FormControls.bodyLabel("")
    private var playlists: [Playlist] = []
    private var loadTask: Task<Void, Never>?

    init(audioAPI: AudioAPI, network: NetworkMonitor, ownerID: Int64) {
        self.audioAPI = audioAPI
        self.network = network
        self.ownerID = ownerID
        super.init(style: .plain)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Playlists"
        tableView.backgroundColor = Theme.background
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "playlist")
        tableView.backgroundView = emptyLabel
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(load), for: .valueChanged)
        load()
    }

    @objc private func load() {
        guard loadTask == nil else { return }
        guard network.isConnected else {
            refreshControl?.endRefreshing()
            emptyLabel.text = playlists.isEmpty ? "No internet connection" : ""
            return
        }
        emptyLabel.text = playlists.isEmpty ? "Loading..." : ""
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                playlists = try await audioAPI.playlists(ownerID: ownerID)
                emptyLabel.text = playlists.isEmpty ? "No playlists" : ""
                tableView.reloadData()
            } catch {
                Log.music.error("playlists failed: \(error.localizedDescription, privacy: .public)")
                emptyLabel.text = playlists.isEmpty ? error.localizedDescription : ""
            }
            refreshControl?.endRefreshing()
            loadTask = nil
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        playlists.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "playlist", for: indexPath)
        let playlist = playlists[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = playlist.title
        content.secondaryText = "\(playlist.trackCount) tracks"
        cell.contentConfiguration = content
        cell.backgroundColor = Theme.background
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        onSelectPlaylist?(playlists[indexPath.row])
    }
}
