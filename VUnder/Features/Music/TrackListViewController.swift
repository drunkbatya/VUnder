import UIKit

struct TrackSection {
    var title: String?
    var tracks: [Track]
}

class TrackListViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    let tableView = UITableView(frame: .zero, style: .plain)
    let emptyLabel = FormControls.bodyLabel("")
    private var tableTop: NSLayoutConstraint?

    var sections: [TrackSection] = [] {
        didSet {
            tableView.reloadData()
            updateEmptyState()
        }
    }

    var tracks: [Track] {
        get { sections.flatMap(\.tracks) }
        set { sections = [TrackSection(title: nil, tracks: newValue)] }
    }

    var onSelectTrack: ((Track, [Track]) -> Void)?
    var currentTrack: (() -> Track?)?
    var isCached: ((Track) -> Bool)?
    var onToggleCache: ((Track) -> Void)?
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
        updateEmptyState()
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
        let alert = UIAlertController(title: "Error", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    func showNotice(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            alert.dismiss(animated: true)
        }
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
        onSelectTrack?(section.tracks[indexPath.row], section.tracks)
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard let onToggleCache else { return nil }
        let track = sections[indexPath.section].tracks[indexPath.row]
        let cached = isCached?(track) ?? false
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            let action = UIAction(
                title: cached ? "Remove from saved" : "Save offline",
                image: UIImage(systemName: cached ? "trash" : "arrow.down.circle"),
                attributes: cached ? [.destructive] : []
            ) { _ in
                onToggleCache(track)
            }
            return UIMenu(children: [action])
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
