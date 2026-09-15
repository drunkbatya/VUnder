import UIKit
import os

final class ConversationPickerViewController: UITableViewController {
    var onPick: ((Int64, String) -> Void)?

    private let store: MessageStore
    private let api: MessagesAPI
    private let network: NetworkMonitor
    private var conversations: [Conversation] = []

    init(store: MessageStore, api: MessagesAPI, network: NetworkMonitor) {
        self.store = store
        self.api = api
        self.network = network
        super.init(style: .plain)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Send to"
        tableView.backgroundColor = Theme.background
        tableView.register(ConversationCell.self, forCellReuseIdentifier: ConversationCell.reuseIdentifier)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "friends")
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        Task { [weak self] in
            guard let self else { return }
            do {
                conversations = try await store.conversations()
                tableView.reloadData()
            } catch {
                Log.messages.error("conversation picker read failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    @objc private func cancel() {
        dismiss(animated: true)
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        2
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 1 : conversations.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 1 && !conversations.isEmpty ? "Recent" : nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "friends", for: indexPath)
            var content = cell.defaultContentConfiguration()
            content.text = "Friends"
            content.image = UIImage(systemName: "person.2")
            cell.contentConfiguration = content
            cell.backgroundColor = Theme.background
            cell.accessoryType = .disclosureIndicator
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: ConversationCell.reuseIdentifier, for: indexPath) as! ConversationCell
        cell.configure(with: conversations[indexPath.row], pending: nil)
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 {
            let friends = FriendsViewController(api: api, network: network)
            friends.onSelect = { [weak self] profile in
                self?.onPick?(profile.id, profile.name)
            }
            navigationController?.pushViewController(friends, animated: true)
            return
        }
        let conversation = conversations[indexPath.row]
        onPick?(conversation.peerID, conversation.title)
    }
}
