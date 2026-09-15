import UIKit
import os

final class TrackPickerViewController: FilterableTrackListViewController {
    var onPick: (([Track]) -> Void)?

    private let library: TrackLibrary
    private let limit: Int
    private var selected: [Track] = []

    init(library: TrackLibrary, limit: Int) {
        self.library = library
        self.limit = limit
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Attach audio"
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Attach", style: .done, target: self, action: #selector(done))
        navigationItem.rightBarButtonItem?.isEnabled = false
        onSelectTrack = { [weak self] track, _, _ in
            self?.toggle(track)
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                allTracks = try await library.tracks()
            } catch {
                Log.messages.error("track picker library read failed: \(error.localizedDescription, privacy: .public)")
                showError(error)
            }
        }
    }

    override var emptyMessage: String {
        allTracks.isEmpty ? "My music is empty" : super.emptyMessage
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = super.tableView(tableView, cellForRowAt: indexPath)
        let track = sections[indexPath.section].tracks[indexPath.row]
        cell.accessoryType = selected.contains { $0.isSame(as: track) } ? .checkmark : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        nil
    }

    private func toggle(_ track: Track) {
        if let index = selected.firstIndex(where: { $0.isSame(as: track) }) {
            selected.remove(at: index)
        } else if selected.count < limit {
            selected.append(track)
        } else {
            showNotice("Up to \(limit) tracks per message")
        }
        navigationItem.rightBarButtonItem?.isEnabled = !selected.isEmpty
        navigationItem.rightBarButtonItem?.title = selected.isEmpty ? "Attach" : "Attach (\(selected.count))"
        for indexPath in tableView.indexPathsForVisibleRows ?? [] where sections[indexPath.section].tracks[indexPath.row].isSame(as: track) {
            tableView.cellForRow(at: indexPath)?.accessoryType = selected.contains { $0.isSame(as: track) } ? .checkmark : .none
        }
    }

    @objc private func done() {
        onPick?(selected)
    }

    @objc private func cancel() {
        dismiss(animated: true)
    }
}
