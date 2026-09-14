import UIKit
import os

final class RecommendationsViewController: FilterableTrackListViewController {
    enum Kind {
        case forUser(Int64)
        case similar(Track)

        var title: String {
            switch self {
            case .forUser: return "Recommendations"
            case .similar(let track): return "Similar to \(track.title)"
            }
        }

        var queueSource: QueueSource {
            switch self {
            case .forUser: return .recommendations
            case .similar(let track): return .similar(track)
            }
        }

        var fallbackNotice: String {
            switch self {
            case .forUser: return "No personal recommendations yet, showing general ones"
            case .similar(let track): return "Nothing similar found, showing tracks by \(track.artist)"
            }
        }
    }

    private let audioAPI: AudioAPI
    private let network: NetworkMonitor
    private let kind: Kind
    private let refreshControl = UIRefreshControl()
    private var loaded = false
    private var loadTask: Task<Void, Never>?

    init(audioAPI: AudioAPI, network: NetworkMonitor, kind: Kind) {
        self.audioAPI = audioAPI
        self.network = network
        self.kind = kind
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
        return network.isConnected ? (loaded ? "Nothing found" : "Pull down to load") : "No internet connection"
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = kind.title
        queueSource = kind.queueSource
        refreshControl.addTarget(self, action: #selector(load), for: .valueChanged)
        tableView.refreshControl = refreshControl
        load()
    }

    @objc private func load() {
        guard loadTask == nil else { return }
        guard network.isConnected else {
            refreshControl.endRefreshing()
            updateEmptyState()
            if loaded {
                showNotice("No internet connection")
            }
            return
        }
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let recommendations: Recommendations
                switch kind {
                case .forUser(let userID):
                    recommendations = try await audioAPI.recommendations(userID: userID)
                case .similar(let track):
                    recommendations = try await audioAPI.similar(to: track)
                }
                loaded = true
                loadTask = nil
                allTracks = recommendations.tracks
                if !recommendations.personal, !recommendations.tracks.isEmpty {
                    showNotice(kind.fallbackNotice)
                }
            } catch {
                Log.music.error("\(self.kind.title, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                loadTask = nil
                updateEmptyState()
                showError(error)
            }
            refreshControl.endRefreshing()
        }
    }
}
