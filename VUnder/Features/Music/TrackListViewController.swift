import UIKit

struct TrackSection {
    var title: String?
    var tracks: [Track]
    var source: QueueSource? = nil
}

class TrackListViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    let tableView = UITableView(frame: .zero, style: .plain)
    let emptyLabel = FormControls.bodyLabel("")
    private var tableTop: NSLayoutConstraint?
    private lazy var scrollToTopButton = ScrollToTopButton(scrollView: tableView)

    var sections: [TrackSection] = [] {
        didSet {
            tableView.reloadData()
            updateEmptyState()
            if let pending = pendingReveal, !tracks.isEmpty {
                pendingReveal = nil
                reveal(pending)
            }
        }
    }

    var tracks: [Track] {
        get { sections.flatMap(\.tracks) }
        set { sections = [TrackSection(title: nil, tracks: newValue)] }
    }

    var queueSource: QueueSource?
    var onSelectTrack: ((Track, [Track], QueueSource?) -> Void)?
    var onPlayNext: ((Track) -> Void)?
    var onAddToQueue: ((Track) -> Void)?
    var currentTrack: (() -> Track?)?
    var isCached: ((Track) -> Bool)?
    var onToggleCache: ((Track) -> Void)?
    var onDownload: ((Track, TrackListViewController) -> Void)?
    var onSaveTo: ((Track, TrackListViewController) -> Void)?
    private var pendingReveal: Track?
    private var observers: [NSObjectProtocol] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        for name in [PlayerService.stateDidChange, CacheState.didChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                MainActor.assumeIsolated { self.refreshVisibleRows() }
            })
        }
        view.backgroundColor = Theme.background
        tableView.backgroundColor = Theme.background
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.register(TrackCell.self, forCellReuseIdentifier: TrackCell.reuseIdentifier)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 56
        tableView.keyboardDismissMode = .onDrag
        view.addSubview(tableView)
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)
        let top = tableView.topAnchor.constraint(equalTo: view.topAnchor)
        tableTop = top
        NSLayoutConstraint.activate([
            top,
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            emptyLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
        ])
        scrollToTopButton.attach(to: view)
        updateEmptyState()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        scrollToTopButton.scrollViewDidScroll()
    }

    var emptyMessage: String {
        ""
    }

    func pinAboveTable(_ header: UIView) {
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)
        tableTop?.isActive = false
        let top = tableView.topAnchor.constraint(equalTo: header.bottomAnchor)
        tableTop = top
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            top,
        ])
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.contentInset.bottom = view.safeAreaInsets.bottom
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        if tableView.contentInsetAdjustmentBehavior == .never {
            tableView.contentInset.bottom = view.safeAreaInsets.bottom
            tableView.verticalScrollIndicatorInsets.bottom = view.safeAreaInsets.bottom
        }
    }

    func updateEmptyState() {
        emptyLabel.text = emptyMessage
        emptyLabel.isHidden = !tracks.isEmpty
    }

    func showError(_ error: Error) {
        dismissNotice { [weak self] in
            let alert = UIAlertController(title: "Error", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self?.present(alert, animated: true)
        }
    }

    func reveal(_ track: Track) {
        guard isViewLoaded, !tracks.isEmpty else {
            pendingReveal = track
            return
        }
        for (sectionIndex, section) in sections.enumerated() {
            if let row = section.tracks.firstIndex(where: { $0.isSame(as: track) }) {
                let indexPath = IndexPath(row: row, section: sectionIndex)
                tableView.layoutIfNeeded()
                tableView.scrollToRow(at: indexPath, at: .middle, animated: true)
                tableView.selectRow(at: indexPath, animated: true, scrollPosition: .none)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.tableView.deselectRow(at: indexPath, animated: true)
                }
                return
            }
        }
        showNotice("Track is not in this list anymore")
    }

    private weak var noticeAlert: UIAlertController?

    func showNotice(_ message: String) {
        dismissNotice { [weak self] in
            guard let self else { return }
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            noticeAlert = alert
            present(alert, animated: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak alert] in
                guard let alert, alert.presentingViewController != nil else { return }
                alert.dismiss(animated: true)
            }
        }
    }

    func dismissNotice(completion: @escaping () -> Void) {
        guard let noticeAlert, noticeAlert.presentingViewController != nil else {
            completion()
            return
        }
        noticeAlert.dismiss(animated: false, completion: completion)
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].tracks.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].title
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: TrackCell.reuseIdentifier, for: indexPath) as! TrackCell
        let track = sections[indexPath.section].tracks[indexPath.row]
        cell.configure(with: track, isCurrent: track.isSame(as: currentTrack?()), isCached: isCached?(track) ?? false)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let section = sections[indexPath.section]
        onSelectTrack?(section.tracks[indexPath.row], section.tracks, section.source ?? queueSource)
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let track = sections[indexPath.section].tracks[indexPath.row]
        let cached = isCached?(track) ?? false
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            var actions: [UIAction] = []
            if let onPlayNext = self?.onPlayNext {
                actions.append(UIAction(title: "Play next", image: UIImage(systemName: "text.insert")) { _ in onPlayNext(track) })
            }
            if let onAddToQueue = self?.onAddToQueue {
                actions.append(UIAction(title: "Add to queue", image: UIImage(systemName: "text.append")) { _ in onAddToQueue(track) })
            }
            if let onToggleCache = self?.onToggleCache {
                actions.append(UIAction(
                    title: cached ? "Remove from saved" : "Save offline",
                    image: UIImage(systemName: cached ? "trash" : "arrow.down.circle"),
                    attributes: cached ? [.destructive] : []
                ) { _ in onToggleCache(track) })
            }
            if track.isAvailable, let self, let onDownload = onDownload {
                actions.append(UIAction(title: "Download to Music folder", image: UIImage(systemName: "folder")) { [weak self] _ in
                    guard let self else { return }
                    onDownload(track, self)
                })
            }
            if track.isAvailable, let self, let onSaveTo = onSaveTo {
                actions.append(UIAction(title: "Save to...", image: UIImage(systemName: "square.and.arrow.down")) { [weak self] _ in
                    guard let self else { return }
                    onSaveTo(track, self)
                })
            }
            return actions.isEmpty ? nil : UIMenu(children: actions)
        }
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard indexPath.section == sections.count - 1 else { return }
        if indexPath.row >= sections[indexPath.section].tracks.count - 20 {
            loadMoreIfNeeded()
        }
    }

    func loadMoreIfNeeded() {
    }

    private func refreshVisibleRows() {
        for indexPath in tableView.indexPathsForVisibleRows ?? [] {
            guard let cell = tableView.cellForRow(at: indexPath) as? TrackCell else { continue }
            let track = sections[indexPath.section].tracks[indexPath.row]
            cell.configure(with: track, isCurrent: track.isSame(as: currentTrack?()), isCached: isCached?(track) ?? false)
        }
    }
}
