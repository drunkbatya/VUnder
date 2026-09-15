import UIKit
import os

final class FriendsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate {
    var onSelect: ((Profile) -> Void)?

    private let api: MessagesAPI
    private let network: NetworkMonitor
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let searchBar = UISearchBar()
    private let emptyLabel = FormControls.bodyLabel("")
    private var friends: [Profile] = []
    private var total = 0
    private var query = ""
    private var loadTask: Task<Void, Never>?
    private var searchDebounce: Task<Void, Never>?

    init(api: MessagesAPI, network: NetworkMonitor) {
        self.api = api
        self.network = network
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Friends"
        view.backgroundColor = Theme.background
        searchBar.placeholder = "Search friends"
        searchBar.delegate = self
        searchBar.autocapitalizationType = .none
        searchBar.searchBarStyle = .minimal
        searchBar.backgroundColor = Theme.background
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = Theme.background
        tableView.register(FriendCell.self, forCellReuseIdentifier: FriendCell.reuseIdentifier)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.keyboardDismissMode = .onDrag
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.backgroundView = emptyLabel
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
        reload()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        tableView.contentInset.bottom = view.safeAreaInsets.bottom
        tableView.verticalScrollIndicatorInsets.bottom = view.safeAreaInsets.bottom
    }

    private func reload() {
        loadTask?.cancel()
        loadTask = nil
        friends = []
        total = 0
        tableView.reloadData()
        loadPage()
    }

    private func loadPage() {
        guard loadTask == nil else { return }
        guard network.isConnected else {
            emptyLabel.text = friends.isEmpty ? "No internet connection" : ""
            return
        }
        emptyLabel.text = friends.isEmpty ? "Loading..." : ""
        let offset = friends.count
        let query = query
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let page: FriendPage
                if query.isEmpty {
                    page = try await api.friends(offset: offset)
                } else {
                    page = try await api.searchFriends(query: query, offset: offset)
                }
                guard !Task.isCancelled, query == self.query else { return }
                let known = Set(friends.map(\.id))
                friends += page.friends.filter { !known.contains($0.id) }
                total = page.total
                emptyLabel.text = friends.isEmpty ? (query.isEmpty ? "No friends" : "Nobody matches \"\(query)\"") : ""
                tableView.reloadData()
            } catch {
                guard !Task.isCancelled else { return }
                Log.messages.error("friends offset=\(offset, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                emptyLabel.text = friends.isEmpty ? error.localizedDescription : ""
            }
            loadTask = nil
        }
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        searchDebounce?.cancel()
        searchDebounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let self, !Task.isCancelled, trimmed != query else { return }
            query = trimmed
            reload()
        }
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        friends.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: FriendCell.reuseIdentifier, for: indexPath) as! FriendCell
        cell.configure(with: friends[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        onSelect?(friends[indexPath.row])
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if indexPath.row >= friends.count - 10, friends.count < total {
            loadPage()
        }
    }
}

final class FriendCell: UITableViewCell {
    static let reuseIdentifier = "FriendCell"

    private let avatar = AvatarView()
    private let nameLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = Theme.background
        nameLabel.font = .preferredFont(forTextStyle: .body)
        nameLabel.textColor = Theme.text
        let row = UIStackView(arrangedSubviews: [avatar, nameLabel])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            row.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    func configure(with profile: Profile) {
        avatar.configure(name: profile.name, photoURL: profile.photoURL)
        nameLabel.text = profile.name
    }
}
