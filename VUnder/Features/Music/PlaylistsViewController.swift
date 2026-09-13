import UIKit
import os

final class PlaylistsViewController: UITableViewController, UISearchBarDelegate {
    var onSelectPlaylist: ((Playlist) -> Void)?

    private let audioAPI: AudioAPI
    private let network: NetworkMonitor
    private let ownerID: Int64
    private let emptyLabel = FormControls.bodyLabel("")
    private let searchBar = UISearchBar()
    private var playlists: [Playlist] = []
    private var shown: [Playlist] = []
    private var query = ""
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
        searchBar.placeholder = "Filter"
        searchBar.delegate = self
        searchBar.autocapitalizationType = .none
        searchBar.searchBarStyle = .minimal
        searchBar.sizeToFit()
        tableView.tableHeaderView = searchBar
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
                applyFilter()
            } catch {
                Log.music.error("playlists failed: \(error.localizedDescription, privacy: .public)")
                emptyLabel.text = playlists.isEmpty ? error.localizedDescription : ""
            }
            refreshControl?.endRefreshing()
            loadTask = nil
        }
    }

    private func applyFilter() {
        let lowered = query.lowercased()
        shown = query.isEmpty ? playlists : playlists.filter { $0.title.lowercased().contains(lowered) }
        if !playlists.isEmpty {
            emptyLabel.text = shown.isEmpty ? "Nothing matches \"\(query)\"" : ""
        }
        tableView.reloadData()
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        applyFilter()
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        shown.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "playlist", for: indexPath)
        let playlist = shown[indexPath.row]
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
        onSelectPlaylist?(shown[indexPath.row])
    }
}
