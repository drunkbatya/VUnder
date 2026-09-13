import UIKit

final class QueueViewController: UITableViewController, UITableViewDragDelegate, UITableViewDropDelegate {
    private let player: PlayerService
    private var observer: NSObjectProtocol?

    init(player: PlayerService) {
        self.player = player
        super.init(style: .plain)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = player.source?.title ?? "Queue"
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(close))
        tableView.backgroundColor = Theme.background
        tableView.register(TrackCell.self, forCellReuseIdentifier: TrackCell.reuseIdentifier)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 56
        tableView.dragDelegate = self
        tableView.dropDelegate = self
        tableView.dragInteractionEnabled = true
        observer = NotificationCenter.default.addObserver(forName: PlayerService.stateDidChange, object: player, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.refreshVisibleRows() }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let position = player.currentOrderPosition, position < tableView.numberOfRows(inSection: 0) {
            tableView.scrollToRow(at: IndexPath(row: position, section: 0), at: .middle, animated: false)
        }
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    private func refreshVisibleRows() {
        guard tableView.numberOfRows(inSection: 0) == player.orderedQueue.count else {
            tableView.reloadData()
            return
        }
        for indexPath in tableView.indexPathsForVisibleRows ?? [] {
            configure(tableView.cellForRow(at: indexPath) as? TrackCell, at: indexPath)
        }
    }

    private func configure(_ cell: TrackCell?, at indexPath: IndexPath) {
        let queue = player.orderedQueue
        guard let cell, indexPath.row < queue.count else { return }
        cell.configure(with: queue[indexPath.row], isCurrent: indexPath.row == player.currentOrderPosition, isCached: false)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        player.orderedQueue.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: TrackCell.reuseIdentifier, for: indexPath) as! TrackCell
        configure(cell, at: indexPath)
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        player.playQueueItem(at: indexPath.row)
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        indexPath.row != player.currentOrderPosition
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        player.removeQueueItem(at: indexPath.row)
        tableView.deleteRows(at: [indexPath], with: .automatic)
        refreshVisibleRows()
    }

    override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        player.moveQueueItem(from: sourceIndexPath.row, to: destinationIndexPath.row)
    }

    func tableView(_ tableView: UITableView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        [UIDragItem(itemProvider: NSItemProvider())]
    }

    func tableView(_ tableView: UITableView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UITableViewDropProposal {
        UITableViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
    }

    func tableView(_ tableView: UITableView, performDropWith coordinator: UITableViewDropCoordinator) {
    }
}
