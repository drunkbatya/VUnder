import UIKit
import os

final class PlaylistsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate {
    var onSelectPlaylist: ((Playlist) -> Void)?

    private let audioAPI: AudioAPI
    private let network: NetworkMonitor
    private let ownerID: Int64
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let searchBar = UISearchBar()
    private let emptyLabel = FormControls.bodyLabel("")
    private let refreshControl = UIRefreshControl()
    private lazy var scrollToTopButton = ScrollToTopButton(scrollView: tableView)
    private var playlists: [Playlist] = []
    private var shown: [Playlist] = []
    private var query = ""
    private var loadTask: Task<Void, Never>?

    init(audioAPI: AudioAPI, network: NetworkMonitor, ownerID: Int64) {
        self.audioAPI = audioAPI
        self.network = network
        self.ownerID = ownerID
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Playlists"
        view.backgroundColor = Theme.background
        searchBar.placeholder = "Filter"
        searchBar.delegate = self
        searchBar.autocapitalizationType = .none
        searchBar.searchBarStyle = .minimal
        searchBar.backgroundColor = Theme.background
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = Theme.background
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "playlist")
        tableView.dataSource = self
        tableView.delegate = self
        tableView.keyboardDismissMode = .onDrag
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.backgroundView = emptyLabel
        tableView.refreshControl = refreshControl
        refreshControl.addTarget(self, action: #selector(load), for: .valueChanged)
        view.addSubview(searchBar)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        scrollToTopButton.attach(to: view)
        load()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        tableView.contentInset.bottom = view.safeAreaInsets.bottom
        tableView.verticalScrollIndicatorInsets.bottom = view.safeAreaInsets.bottom
    }

    @objc private func load() {
        guard loadTask == nil else { return }
        guard network.isConnected else {
            refreshControl.endRefreshing()
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
            refreshControl.endRefreshing()
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

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        scrollToTopButton.scrollViewDidScroll()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        shown.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
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

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        onSelectPlaylist?(shown[indexPath.row])
    }
}
