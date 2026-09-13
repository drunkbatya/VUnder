import UIKit
import os

final class MyMusicViewController: TrackListViewController, UISearchBarDelegate {
    var onSignOut: (() -> Void)?

    private let audioAPI: AudioAPI
    private let library: TrackLibrary
    private let network: NetworkMonitor
    private let ownerID: Int64
    private let searchBar = UISearchBar()
    private let refreshControl = UIRefreshControl()
    private let countLabel = FormControls.bodyLabel("")
    private var libraryTracks: [Track] = []
    private var query = ""
    private var globalQuery = ""
    private var globalResults: [Track] = []
    private var globalExhausted = false
    private var globalTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?

    init(audioAPI: AudioAPI, library: TrackLibrary, network: NetworkMonitor, ownerID: Int64) {
        self.audioAPI = audioAPI
        self.library = library
        self.network = network
        self.ownerID = ownerID
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override var emptyMessage: String {
        if query.isEmpty {
            return "No tracks yet. Pull down to load your music."
        }
        if globalQuery == query {
            return globalTask == nil ? "Nothing found for \"\(query)\"" : "Searching..."
        }
        return network.isConnected ? "No matches in your music. Press Search to look everywhere." : "No matches in your music. Global search needs internet."
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "My music"
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Sign out", style: .plain, target: self, action: #selector(signOut))
        searchBar.placeholder = "Search"
        searchBar.delegate = self
        searchBar.autocapitalizationType = .none
        searchBar.returnKeyType = .search
        searchBar.searchBarStyle = .minimal
        searchBar.backgroundColor = Theme.background
        pinAboveTable(searchBar)
        refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged)
        tableView.refreshControl = refreshControl
        countLabel.frame = CGRect(x: 0, y: 0, width: 0, height: 44)
        tableView.tableFooterView = countLabel
        loadSavedTracks()
    }

    private func loadSavedTracks() {
        Task { [weak self] in
            guard let self else { return }
            do {
                libraryTracks = try await library.tracks()
                Log.music.info("saved library loaded tracks=\(self.libraryTracks.count, privacy: .public)")
                rebuildSections()
                if libraryTracks.isEmpty, network.isConnected {
                    refreshControl.beginRefreshing()
                    tableView.setContentOffset(CGPoint(x: 0, y: -refreshControl.frame.height), animated: true)
                    refresh()
                }
            } catch {
                Log.music.error("saved library failed: \(error.localizedDescription, privacy: .public)")
                showError(error)
            }
        }
    }

    @objc private func refresh() {
        guard refreshTask == nil else { return }
        guard network.isConnected else {
            refreshControl.endRefreshing()
            showNotice("No internet connection")
            return
        }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                let loaded = try await audioAPI.allTracks(ownerID: ownerID) { [weak self] count, total in
                    self?.refreshControl.attributedTitle = NSAttributedString(string: "Loaded \(count) of \(total)")
                }
                try await library.replace(with: loaded)
                libraryTracks = loaded
                rebuildSections()
            } catch {
                Log.music.error("library refresh failed: \(error.localizedDescription, privacy: .public)")
                showError(error)
            }
            refreshControl.attributedTitle = nil
            refreshControl.endRefreshing()
            refreshTask = nil
        }
    }

    private func rebuildSections() {
        if query.isEmpty {
            tracks = libraryTracks
            countLabel.text = libraryTracks.isEmpty ? "" : "\(libraryTracks.count) tracks"
            return
        }
        let lowered = query.lowercased()
        let local = libraryTracks.filter { $0.matches(lowered) }
        var result: [TrackSection] = []
        if !local.isEmpty {
            result.append(TrackSection(title: "My music", tracks: local))
        }
        if globalQuery == query, !globalResults.isEmpty {
            result.append(TrackSection(title: "Search results", tracks: globalResults))
        }
        sections = result
        countLabel.text = ""
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        globalTask?.cancel()
        globalTask = nil
        globalQuery = ""
        globalResults = []
        rebuildSections()
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
        guard !query.isEmpty else { return }
        guard network.isConnected else {
            showNotice("No internet connection")
            return
        }
        globalQuery = query
        globalResults = []
        globalExhausted = false
        loadGlobalPage()
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.text = ""
        searchBar.resignFirstResponder()
        self.searchBar(searchBar, textDidChange: "")
    }

    override func loadMoreIfNeeded() {
        guard !globalQuery.isEmpty, globalQuery == query, !globalExhausted, globalTask == nil else { return }
        loadGlobalPage()
    }

    private func loadGlobalPage() {
        let searched = globalQuery
        let offset = globalResults.count
        globalTask = Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await audioAPI.search(query: searched, offset: offset)
                guard !Task.isCancelled, searched == globalQuery else { return }
                globalExhausted = page.count < AudioAPI.searchPageSize
                globalResults += page
                rebuildSections()
            } catch {
                guard !Task.isCancelled else { return }
                Log.music.error("search failed: \(error.localizedDescription, privacy: .public)")
                showError(error)
            }
            globalTask = nil
        }
    }

    @objc private func signOut() {
        onSignOut?()
    }
}
