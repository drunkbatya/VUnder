import UIKit

final class DownloadsViewController: UITableViewController {
    private let center: DownloadCenter
    private let emptyLabel = FormControls.bodyLabel("No downloads")
    private var observer: NSObjectProtocol?

    init(center: DownloadCenter) {
        self.center = center
        super.init(style: .plain)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Downloads"
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Clear", style: .plain, target: self, action: #selector(clearFinished))
        tableView.backgroundColor = Theme.background
        tableView.register(DownloadCell.self, forCellReuseIdentifier: DownloadCell.reuseIdentifier)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
        tableView.backgroundView = emptyLabel
        observer = NotificationCenter.default.addObserver(forName: DownloadCenter.didChange, object: center, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.reload() }
        }
        reload()
    }

    private func reload() {
        let jobs = center.jobs
        emptyLabel.isHidden = !jobs.isEmpty
        navigationItem.rightBarButtonItem?.isEnabled = jobs.contains { $0.state.isFinished }
        if tableView.numberOfRows(inSection: 0) == jobs.count {
            for indexPath in tableView.indexPathsForVisibleRows ?? [] {
                (tableView.cellForRow(at: indexPath) as? DownloadCell).map { configure($0, at: indexPath) }
            }
        } else {
            tableView.reloadData()
        }
    }

    private func configure(_ cell: DownloadCell, at indexPath: IndexPath) {
        let job = center.jobs[indexPath.row]
        cell.configure(with: job)
        cell.onCancel = { [weak self] in self?.center.cancel(job) }
    }

    @objc private func clearFinished() {
        center.clearFinished()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        center.jobs.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: DownloadCell.reuseIdentifier, for: indexPath) as! DownloadCell
        configure(cell, at: indexPath)
        return cell
    }
}
