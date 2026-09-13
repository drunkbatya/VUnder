import UIKit

final class GeneralViewController: UITableViewController {
    enum Row: CaseIterable {
        case saved
        case playlists
        case listened

        var title: String {
            switch self {
            case .saved: return "Saved"
            case .playlists: return "Playlists"
            case .listened: return "Listened"
            }
        }
    }

    var onSelectRow: ((Row) -> Void)?

    private let settings: AppSettings
    private var rows: [Row] = []
    private var settingsObserver: NSObjectProtocol?

    init(settings: AppSettings) {
        self.settings = settings
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "General"
        tableView.backgroundColor = Theme.groupedBackground
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "row")
        reloadRows()
        settingsObserver = NotificationCenter.default.addObserver(forName: AppSettings.didChange, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.reloadRows() }
        }
    }

    private func reloadRows() {
        rows = Row.allCases.filter { $0 != .listened || settings.historyEnabled }
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath)
        cell.textLabel?.text = rows[indexPath.row].title
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        onSelectRow?(rows[indexPath.row])
    }
}
