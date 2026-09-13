import UIKit
import os

final class StoredTracksViewController: FilterableTrackListViewController {
    enum Source {
        case saved
        case listened

        var title: String {
            switch self {
            case .saved: return "Saved"
            case .listened: return "Listened"
            }
        }

        var emptyMessage: String {
            switch self {
            case .saved: return "No saved tracks"
            case .listened: return "No listened tracks yet"
            }
        }
    }

    private let library: TrackLibrary
    private let source: Source
    private var cacheObserver: NSObjectProtocol?

    init(library: TrackLibrary, source: Source) {
        self.library = library
        self.source = source
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override var emptyMessage: String {
        allTracks.isEmpty ? source.emptyMessage : super.emptyMessage
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = source.title
        if source == .saved {
            cacheObserver = NotificationCenter.default.addObserver(forName: CacheState.didChange, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                MainActor.assumeIsolated { self.reload() }
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    private func reload() {
        Task { [weak self] in
            guard let self else { return }
            do {
                switch source {
                case .saved: allTracks = try await library.savedTracks()
                case .listened: allTracks = try await library.listenedTracks()
                }
            } catch {
                Log.music.error("\(self.source.title, privacy: .public) load failed: \(error.localizedDescription, privacy: .public)")
                showError(error)
            }
        }
    }
}
