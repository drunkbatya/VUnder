import UIKit
import os

final class ConversationsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    var onSelect: ((Conversation) -> Void)?
    var onCompose: (() -> Void)?

    private let api: MessagesAPI
    private let store: MessageStore
    private let sync: MessagesSync
    private let network: NetworkMonitor
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let refreshControl = UIRefreshControl()
    private let emptyLabel = FormControls.bodyLabel("")
    private var cached: [Conversation] = []
    private var extra: [Conversation] = []
    private var pendingByPeer: [Int64: String] = [:]
    private var total = 0
    private var loadMoreTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    init(api: MessagesAPI, store: MessageStore, sync: MessagesSync, network: NetworkMonitor) {
        self.api = api
        self.store = store
        self.sync = sync
        self.network = network
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    private var shown: [Conversation] {
        cached + extra
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Messages"
        view.backgroundColor = Theme.background
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "square.and.pencil"), style: .plain, target: self, action: #selector(compose))
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = Theme.background
        tableView.register(ConversationCell.self, forCellReuseIdentifier: ConversationCell.reuseIdentifier)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        tableView.backgroundView = emptyLabel
        tableView.refreshControl = refreshControl
        refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        observers.append(NotificationCenter.default.addObserver(forName: MessageStore.didChange, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.reloadFromStore() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: MessagesSync.conversationsRefreshDidFinish, object: nil, queue: .main) { [weak self] notification in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.refreshControl.endRefreshing()
                guard let total = notification.userInfo?["total"] as? Int else { return }
                self.total = total
                self.extra = []
                self.reloadFromStore()
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NetworkMonitor.didChange, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.updateEmptyState() }
        })
        reloadFromStore()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let selected = tableView.indexPathForSelectedRow {
            tableView.deselectRow(at: selected, animated: animated)
        }
    }

    @objc private func compose() {
        onCompose?()
    }

    @objc private func refresh() {
        guard network.isConnected else {
            refreshControl.endRefreshing()
            return
        }
        sync.refreshConversations()
    }

    private func reloadFromStore() {
        Task { [weak self] in
            guard let self else { return }
            do {
                cached = try await store.conversations()
                let cachedIDs = Set(cached.map(\.peerID))
                extra.removeAll { cachedIDs.contains($0.peerID) }
                let outgoing = try await store.outgoing()
                pendingByPeer = Dictionary(outgoing.map { ($0.peerID, $0.previewText) }, uniquingKeysWith: { _, last in last })
                tableView.reloadData()
                updateEmptyState()
            } catch {
                Log.messages.error("conversations read failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func updateEmptyState() {
        if !shown.isEmpty {
            emptyLabel.text = ""
        } else if network.isConnected {
            emptyLabel.text = "No conversations"
        } else {
            emptyLabel.text = "No internet connection"
        }
    }

    private func loadMoreIfNeeded() {
        guard loadMoreTask == nil, network.isConnected, shown.count < total else { return }
        let offset = shown.count
        loadMoreTask = Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await api.conversations(offset: offset)
                try await store.saveProfiles(page.profiles)
                total = page.total
                let known = Set(shown.map(\.peerID))
                extra += page.conversations.filter { !known.contains($0.peerID) }
                tableView.reloadData()
            } catch {
                Log.messages.error("conversations page offset=\(offset, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
            loadMoreTask = nil
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        shown.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ConversationCell.reuseIdentifier, for: indexPath) as! ConversationCell
        let conversation = shown[indexPath.row]
        cell.configure(with: conversation, pending: pendingByPeer[conversation.peerID])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        onSelect?(shown[indexPath.row])
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if indexPath.row >= shown.count - 5 {
            loadMoreIfNeeded()
        }
    }
}
