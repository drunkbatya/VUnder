import UIKit
import os

final class ChatViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    var onPlayTrack: ((Track, [Track]) -> Void)?
    var trackMenu: ((Track, ChatViewController) -> UIMenu?)?
    var onAttach: ((ChatViewController) -> Void)?

    let peerID: Int64

    private enum Item {
        case day(Date)
        case message(Message)
        case pending(OutgoingMessage)
    }

    private let api: MessagesAPI
    private let store: MessageStore
    private let outbox: Outbox
    private let network: NetworkMonitor
    private let settings: AppSettings
    private let player: PlayerService
    private let voicePlayer: VoicePlayer
    private let userID: Int64
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let inputBar = ChatInputBar()
    private let statusLabel = FormControls.bodyLabel("")
    private var messages: [Message] = []
    private var pending: [OutgoingMessage] = []
    private var items: [Item] = []
    private var profiles: [Int64: Profile] = [:]
    private var total = 0
    private var conversation: Conversation?
    private var lastMarkedID: Int64 = 0
    private var refreshTask: Task<Void, Never>?
    private var olderTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var pendingReveal: Track?

    init(peerID: Int64, title: String, userID: Int64, api: MessagesAPI, store: MessageStore, outbox: Outbox, network: NetworkMonitor, settings: AppSettings, player: PlayerService, voicePlayer: VoicePlayer) {
        self.peerID = peerID
        self.userID = userID
        self.api = api
        self.store = store
        self.outbox = outbox
        self.network = network
        self.settings = settings
        self.player = player
        self.voicePlayer = voicePlayer
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    var tracks: [Track] {
        messages.flatMap(\.tracks)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = Theme.background
        tableView.separatorStyle = .none
        tableView.register(MessageCell.self, forCellReuseIdentifier: MessageCell.reuseIdentifier)
        tableView.register(DayHeaderCell.self, forCellReuseIdentifier: DayHeaderCell.reuseIdentifier)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        tableView.keyboardDismissMode = .interactive
        tableView.backgroundView = statusLabel
        inputBar.translatesAutoresizingMaskIntoConstraints = false
        inputBar.onSend = { [weak self] text in self?.send(text) }
        inputBar.onAttach = { [weak self] in
            guard let self else { return }
            onAttach?(self)
        }
        view.addSubview(tableView)
        view.addSubview(inputBar)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: inputBar.topAnchor),
            inputBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputBar.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
        ])
        observers.append(NotificationCenter.default.addObserver(forName: MessageStore.didChange, object: nil, queue: .main) { [weak self] notification in
            guard let self, (notification.userInfo?[MessageStore.peerIDKey] as? Int64).map({ $0 == self.peerID }) ?? true else { return }
            MainActor.assumeIsolated { self.loadFromStore(scrollToBottom: false) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NetworkMonitor.didChange, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.updateStatus()
                if self.network.isConnected {
                    self.refreshLatest()
                }
            }
        })
        for name in [PlayerService.stateDidChange, VoicePlayer.stateDidChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                MainActor.assumeIsolated { self.refreshVisibleRows() }
            })
        }
        loadFromStore(scrollToBottom: true)
        refreshLatest()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent || isBeingDismissed {
            voicePlayer.stop()
        }
    }

    var attachedCount: Int {
        inputBar.attachments.count
    }

    func attach(_ tracks: [Track]) {
        inputBar.addAttachments(tracks)
    }

    func reveal(_ track: Track) {
        guard isViewLoaded, !messages.isEmpty else {
            pendingReveal = track
            return
        }
        guard let index = items.firstIndex(where: { item in
            if case .message(let message) = item { return message.tracks.contains { $0.isSame(as: track) } }
            return false
        }) else {
            showNotice("Track is not in this chat anymore")
            return
        }
        tableView.scrollToRow(at: IndexPath(row: index, section: 0), at: .middle, animated: true)
    }

    func showNotice(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak alert] in
            guard let alert, alert.presentingViewController != nil else { return }
            alert.dismiss(animated: true)
        }
    }

    func showError(_ error: Error) {
        let alert = UIAlertController(title: "Error", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func send(_ text: String) {
        let attachments = inputBar.attachments
        guard !text.isEmpty || !attachments.isEmpty else { return }
        inputBar.clear()
        outbox.enqueue(peerID: peerID, text: text, attachments: attachments)
    }

    private func loadFromStore(scrollToBottom: Bool) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let cachedPage = try await store.messages(peerID: peerID)
                if let first = cachedPage.first {
                    messages = messages.filter { $0.id < first.id } + cachedPage
                }
                pending = try await store.outgoing().filter { $0.peerID == peerID }
                conversation = try await store.conversation(peerID: peerID)
                await loadMissingProfiles()
                let wasNearBottom = isNearBottom
                rebuildItems()
                if scrollToBottom || wasNearBottom {
                    self.scrollToBottom(animated: !scrollToBottom)
                }
                markReadIfNeeded()
            } catch {
                Log.messages.error("chat peer=\(peerID, privacy: .public) store read failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func refreshLatest() {
        guard refreshTask == nil, network.isConnected else {
            updateStatus()
            return
        }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await api.history(peerID: peerID)
                total = page.total
                try await store.replaceMessages(peerID: peerID, with: page.messages, profiles: page.profiles)
                _ = try await store.updateConversation(peerID: peerID) { conversation in
                    conversation.inRead = page.inRead
                    conversation.outRead = page.outRead
                }
                if let newest = messages.last, let oldestFetched = page.messages.first, oldestFetched.id > newest.id {
                    messages = []
                }
                loadFromStore(scrollToBottom: messages.isEmpty)
            } catch {
                Log.messages.error("chat peer=\(peerID, privacy: .public) refresh failed: \(error.localizedDescription, privacy: .public)")
            }
            refreshTask = nil
            updateStatus()
        }
    }

    private func loadOlderIfNeeded() {
        guard olderTask == nil, refreshTask == nil, network.isConnected, let oldest = messages.first, messages.count < total else { return }
        olderTask = Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await api.history(peerID: peerID, before: oldest.id)
                total = page.total
                try await store.saveProfiles(page.profiles)
                let known = Set(messages.map(\.id))
                let older = page.messages.filter { !known.contains($0.id) }
                if older.isEmpty {
                    total = messages.count
                } else {
                    messages = (older + messages).sorted { $0.id < $1.id }
                    await loadMissingProfiles()
                    let heightBefore = tableView.contentSize.height
                    let offsetBefore = tableView.contentOffset.y
                    rebuildItems()
                    tableView.layoutIfNeeded()
                    tableView.contentOffset.y = offsetBefore + (tableView.contentSize.height - heightBefore)
                }
            } catch {
                Log.messages.error("chat peer=\(peerID, privacy: .public) older page failed: \(error.localizedDescription, privacy: .public)")
            }
            olderTask = nil
        }
    }

    private func loadMissingProfiles() async {
        let needed = Set(messages.map(\.fromID)).subtracting(profiles.keys)
        guard !needed.isEmpty else { return }
        if let loaded = try? await store.profiles(ids: Array(needed)) {
            profiles.merge(loaded) { _, new in new }
        }
    }

    private func rebuildItems() {
        var built: [Item] = []
        var lastDay: DateComponents?
        let calendar = Calendar.current
        for message in messages {
            let day = calendar.dateComponents([.year, .month, .day], from: message.date)
            if day != lastDay {
                built.append(.day(message.date))
                lastDay = day
            }
            built.append(.message(message))
        }
        for outgoing in pending {
            built.append(.pending(outgoing))
        }
        items = built
        tableView.reloadData()
        updateStatus()
        if let pendingReveal, !messages.isEmpty {
            self.pendingReveal = nil
            reveal(pendingReveal)
        }
    }

    private func updateStatus() {
        if !items.isEmpty {
            statusLabel.text = ""
        } else if refreshTask != nil {
            statusLabel.text = "Loading..."
        } else if network.isConnected {
            statusLabel.text = "No messages yet"
        } else {
            statusLabel.text = "No internet connection"
        }
    }

    private var isNearBottom: Bool {
        let bottom = tableView.contentSize.height - tableView.bounds.height + tableView.adjustedContentInset.bottom
        return tableView.contentOffset.y >= bottom - 120
    }

    private func scrollToBottom(animated: Bool) {
        guard !items.isEmpty else { return }
        tableView.layoutIfNeeded()
        tableView.scrollToRow(at: IndexPath(row: items.count - 1, section: 0), at: .bottom, animated: animated)
    }

    private func markReadIfNeeded() {
        guard settings.markAsRead, network.isConnected, view.window != nil, let conversation else { return }
        guard let latestIncoming = messages.last(where: { !$0.out })?.id, latestIncoming > conversation.inRead, latestIncoming > lastMarkedID else { return }
        lastMarkedID = latestIncoming
        Task { [api, store, peerID] in
            do {
                try await api.markAsRead(peerID: peerID, upTo: latestIncoming)
                _ = try await store.updateConversation(peerID: peerID) { conversation in
                    conversation.inRead = latestIncoming
                    conversation.unreadCount = 0
                }
            } catch {
                Log.messages.error("mark read peer=\(peerID, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func refreshVisibleRows() {
        for indexPath in tableView.indexPathsForVisibleRows ?? [] {
            guard let cell = tableView.cellForRow(at: indexPath) as? MessageCell else { continue }
            configure(cell, at: indexPath)
        }
    }

    private func configure(_ cell: MessageCell, at indexPath: IndexPath) {
        cell.onTapTrack = { [weak self] track in
            guard let self else { return }
            if track.isSame(as: player.current) {
                player.togglePlayPause()
            } else {
                onPlayTrack?(track, tracks)
            }
        }
        cell.trackMenu = { [weak self] track in
            guard let self else { return nil }
            return trackMenu?(track, self)
        }
        cell.onTapVoice = { [weak self] voice in self?.voicePlayer.toggle(voice) }
        cell.isCurrentTrack = { [player] track in track.isSame(as: player.current) }
        cell.isMusicPlaying = { [player] in player.isPlaying }
        cell.isVoicePlaying = { [voicePlayer] voice in voicePlayer.isPlaying(voice) }
        switch items[indexPath.row] {
        case .message(let message):
            let sender = Peer.isChat(peerID) && !message.out ? (profiles[message.fromID]?.name ?? "id\(message.fromID)") : nil
            cell.configure(with: MessageCellContent(senderName: sender, text: message.text, attachments: message.attachments, outgoing: message.out, footer: MessageDates.timeOnly(message.date), failed: false))
        case .pending(let outgoing):
            let footer = outgoing.failure.map { "Not sent: \($0)" } ?? (network.isConnected ? "Sending..." : "Waiting for network")
            cell.configure(with: MessageCellContent(senderName: nil, text: outgoing.text, attachments: outgoing.attachments.map { .audio($0) }, outgoing: true, footer: footer, failed: outgoing.failure != nil))
        case .day:
            break
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch items[indexPath.row] {
        case .day(let date):
            let cell = tableView.dequeueReusableCell(withIdentifier: DayHeaderCell.reuseIdentifier, for: indexPath) as! DayHeaderCell
            cell.configure(with: date)
            return cell
        case .message, .pending:
            let cell = tableView.dequeueReusableCell(withIdentifier: MessageCell.reuseIdentifier, for: indexPath) as! MessageCell
            configure(cell, at: indexPath)
            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard case .pending(let outgoing) = items[indexPath.row] else { return }
        let sheet = UIAlertController(title: outgoing.failure ?? "Message is queued", message: nil, preferredStyle: .actionSheet)
        if outgoing.failure != nil {
            sheet.addAction(UIAlertAction(title: "Retry", style: .default) { [weak self] _ in self?.outbox.retry(outgoing) })
        }
        sheet.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in self?.outbox.delete(outgoing) })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(sheet, animated: true)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView.isDragging || scrollView.isDecelerating else { return }
        if scrollView.contentOffset.y + scrollView.adjustedContentInset.top < 200 {
            loadOlderIfNeeded()
        }
    }
}
