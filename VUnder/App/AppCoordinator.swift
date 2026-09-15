import OTAUpdater
import UIKit
import os

@MainActor
final class AppCoordinator {
    private let window: UIWindow
    private let environment: AppEnvironment
    private let challengePresenter: ChallengePresenter
    private let player: PlayerService
    private let cacheState = CacheState()
    private let fileInfoProvider: TrackFileInfoProvider
    private let exporter: TrackExporter
    private let downloads: DownloadCenter
    private let updater: OTAUpdater
    private let voicePlayer = VoicePlayer()
    private lazy var conversationQueue = ConversationQueueLoader(api: environment.messagesAPI, player: player, network: environment.network)
    private var autoCache: AutoCacheController?
    private var messaging: MessagingContext?
    private weak var tabs: MainTabBarController?
    private weak var messagesNavigation: UINavigationController?
    private var loginCoordinator: LoginCoordinator?
    private weak var musicNavigation: UINavigationController?
    private weak var musicRoot: MusicRootViewController?
    private weak var myMusic: MyMusicViewController?
    private var recommendations: RecommendationsViewController?
    private var libraryEditor: LibraryEditor?
    private var observers: [NSObjectProtocol] = []

    init(window: UIWindow, environment: AppEnvironment) {
        self.window = window
        self.environment = environment
        challengePresenter = ChallengePresenter(presentingViewController: { [weak window] in
            window?.rootViewController?.topmostPresentedViewController
        })
        player = PlayerService(audioAPI: environment.audioAPI, library: environment.library, settings: environment.settings, network: environment.network)
        player.localFileURL = { [cache = environment.cache] track in cache.localFileURL(for: track) }
        ImageLoader.shared.localCoverURL = { [cache = environment.cache] track in cache.localCoverURL(for: track) }
        fileInfoProvider = TrackFileInfoProvider(localFileURL: { [cache = environment.cache] track in cache.localFileURL(for: track) })
        exporter = TrackExporter()
        downloads = DownloadCenter(cache: environment.cache, exporter: exporter)
        updater = OTAUpdater(feedURL: ReleaseFeed.url)
        voicePlayer.pauseMusic = { [player] in
            if player.isPlaying {
                player.pause()
            }
        }
    }

    func start() {
        applyAppearance()
        Task { [api = environment.api, challengePresenter] in
            await api.setChallengeHandler(challengePresenter)
        }
        observers.append(NotificationCenter.default.addObserver(forName: AppSettings.didChange, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.applyAppearance() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: SessionStore.sessionDidChange, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.sessionDidChange() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: MessageStore.didChange, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.updateMessagesBadge() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: DownloadCenter.jobDidFinish, object: downloads, queue: .main) { [weak self] notification in
            guard let self, let job = notification.userInfo?["job"] as? DownloadCenter.Job else { return }
            MainActor.assumeIsolated { self.downloadDidFinish(job) }
        })
        Task { [cache = environment.cache] in
            await cache.reconcile()
        }
        if let session = environment.sessionStore.session {
            Log.app.info("launch with session user_id=\(session.userID, privacy: .public)")
            showMusic()
        } else {
            Log.app.info("launch without session")
            showLogin()
        }
        window.makeKeyAndVisible()
        updater.checkOnLaunch { [weak window] in
            window?.rootViewController?.topmostPresentedViewController
        }
    }

    private func applyAppearance() {
        let appearance = environment.settings.appearance
        Log.app.info("appearance \(appearance.rawValue, privacy: .public)")
        window.overrideUserInterfaceStyle = appearance.interfaceStyle
    }

    private func sessionDidChange() {
        if environment.sessionStore.session == nil, loginCoordinator == nil {
            Log.app.info("session gone, showing login")
            showLogin()
        }
    }

    private func showLogin() {
        let coordinator = LoginCoordinator(authFlow: environment.authFlow, challengePresenter: challengePresenter)
        coordinator.onSignedIn = { [weak self] _ in
            self?.loginCoordinator = nil
            self?.showMusic()
        }
        loginCoordinator = coordinator
        window.rootViewController = coordinator.navigationController
    }

    private func showMusic() {
        guard let session = environment.sessionStore.session else { return }
        recommendations = nil
        let editor = LibraryEditor(userID: session.userID, audioAPI: environment.audioAPI, library: environment.library, player: player, cache: environment.cache, downloads: downloads)
        libraryEditor = editor
        let myMusic = MyMusicViewController(
            audioAPI: environment.audioAPI,
            library: environment.library,
            network: environment.network,
            ownerID: session.userID
        )
        let general = GeneralViewController(settings: environment.settings)
        let root = MusicRootViewController(myMusic: myMusic, general: general)
        let navigation = UINavigationController(rootViewController: root)
        autoCache = AutoCacheController(
            player: player,
            downloads: downloads,
            cacheState: cacheState,
            settings: environment.settings,
            network: environment.network,
            userID: session.userID
        )
        bindPlayer(to: myMusic)
        root.onDownloads = { [weak self, weak navigation] in
            guard let self, let navigation else { return }
            navigation.pushViewController(DownloadsViewController(center: downloads), animated: true)
        }
        general.onSelectRow = { [weak self, weak navigation] row in
            guard let self, let navigation else { return }
            navigation.pushViewController(makeGeneralScreen(row, userID: session.userID, navigation: navigation), animated: true)
        }
        musicNavigation = navigation
        musicRoot = root
        self.myMusic = myMusic
        let messaging = startMessaging(userID: session.userID)
        let messagesNavigation = UINavigationController(rootViewController: makeConversations(messaging))
        self.messagesNavigation = messagesNavigation
        let settings = SettingsViewController(settings: environment.settings, cache: environment.cache, updater: updater)
        settings.onSignOut = { [weak self] in self?.signOut() }
        let tabs = MainTabBarController(music: navigation, messages: messagesNavigation, settings: UINavigationController(rootViewController: settings), player: player, fileInfoProvider: fileInfoProvider)
        tabs.onJumpToTrack = { [weak self] track, source in
            self?.jump(to: track, source: source)
        }
        tabs.membership = { [editor] track in editor.membership(of: track) }
        tabs.onToggleLibrary = { [weak self] track, mine, screen in
            self?.editLibrary(track, delete: mine, notice: screen.showNotice, failure: screen.showError)
        }
        tabs.onShareTrack = { [weak self] track in
            self?.shareTrack(track)
        }
        self.tabs = tabs
        window.rootViewController = tabs
        updateMessagesBadge()
    }

    private func startMessaging(userID: Int64) -> MessagingContext {
        let presence = OfflinePresence(api: environment.messagesAPI)
        let outbox = Outbox(api: environment.messagesAPI, store: environment.messageStore, network: environment.network, presence: presence, userID: userID)
        let sync = MessagesSync(api: environment.messagesAPI, store: environment.messageStore, network: environment.network, settings: environment.settings)
        let context = MessagingContext(userID: userID, outbox: outbox, sync: sync)
        messaging = context
        sync.start()
        outbox.flush()
        return context
    }

    private func updateMessagesBadge() {
        Task { [weak self, store = environment.messageStore] in
            let unread = (try? await store.unreadTotal()) ?? 0
            self?.tabs?.setMessagesBadge(unread)
        }
    }

    private func makeConversations(_ messaging: MessagingContext) -> ConversationsViewController {
        let conversations = ConversationsViewController(api: environment.messagesAPI, store: environment.messageStore, sync: messaging.sync, network: environment.network)
        conversations.onSelect = { [weak self] conversation in
            self?.openChat(peerID: conversation.peerID, title: conversation.title)
        }
        conversations.onCompose = { [weak self] in
            guard let self, let navigation = messagesNavigation else { return }
            let friends = FriendsViewController(api: environment.messagesAPI, network: environment.network)
            friends.onSelect = { [weak self, weak navigation] profile in
                guard let self, let navigation, let chat = makeChat(peerID: profile.id, title: profile.name) else { return }
                var stack = navigation.viewControllers
                stack.removeLast()
                stack.append(chat)
                navigation.setViewControllers(stack, animated: true)
            }
            navigation.pushViewController(friends, animated: true)
        }
        return conversations
    }

    @discardableResult
    private func openChat(peerID: Int64, title: String) -> ChatViewController? {
        guard let navigation = messagesNavigation else { return nil }
        if let top = navigation.topViewController as? ChatViewController, top.peerID == peerID {
            return top
        }
        guard let chat = makeChat(peerID: peerID, title: title) else { return nil }
        navigation.pushViewController(chat, animated: true)
        return chat
    }

    private func shareTrack(_ track: Track) {
        guard let navigation = messagesNavigation else { return }
        Log.app.info("share \(track.storageID, privacy: .public) from player")
        tabs?.selectedIndex = 1
        navigation.presentedViewController?.dismiss(animated: false)
        let picker = ConversationPickerViewController(store: environment.messageStore, api: environment.messagesAPI, network: environment.network)
        picker.onPick = { [weak self, weak picker] peerID, title in
            picker?.dismiss(animated: true) {
                self?.openChat(peerID: peerID, title: title)?.attach([track])
            }
        }
        navigation.present(UINavigationController(rootViewController: picker), animated: true)
    }

    private func makeChat(peerID: Int64, title: String) -> ChatViewController? {
        guard let messaging else { return nil }
        let chat = ChatViewController(
            peerID: peerID,
            title: title,
            userID: messaging.userID,
            api: environment.messagesAPI,
            store: environment.messageStore,
            outbox: messaging.outbox,
            network: environment.network,
            settings: environment.settings,
            player: player,
            voicePlayer: voicePlayer
        )
        chat.onPlayTrack = { [weak self] track, tracks in
            guard let self else { return }
            let source = QueueSource.conversation(peerID: peerID, title: title)
            player.play(track, in: Array(tracks.reversed()), source: source)
            conversationQueue.start(peerID: peerID, source: source)
        }
        chat.trackMenu = { [weak self] track, chat in
            self?.chatTrackMenu(track, chat: chat)
        }
        chat.onAttach = { [weak self] chat in
            guard let self else { return }
            let picker = TrackPickerViewController(library: environment.library, limit: ChatInputBar.maxAttachments - chat.attachedCount)
            picker.onPick = { [weak chat, weak picker] tracks in
                chat?.attach(tracks)
                picker?.dismiss(animated: true)
            }
            chat.present(UINavigationController(rootViewController: picker), animated: true)
        }
        return chat
    }

    private func chatTrackMenu(_ track: Track, chat: ChatViewController) -> UIMenu? {
        var actions: [UIAction] = [
            UIAction(title: "Play next", image: UIImage(systemName: "text.insert")) { [player] _ in player.playNext(track) },
            UIAction(title: "Add to queue", image: UIImage(systemName: "text.append")) { [player] _ in player.addToQueue(track) },
        ]
        if track.isAvailable, libraryEditor?.membership(of: track) != .mine {
            actions.append(UIAction(title: "Add to my music", image: UIImage(systemName: "plus.circle")) { [weak self, weak chat] _ in
                guard let self, let chat else { return }
                editLibrary(track, delete: false, notice: chat.showNotice, failure: chat.showError)
            })
        }
        if track.isAvailable {
            actions.append(UIAction(title: "Save offline", image: UIImage(systemName: "arrow.down.circle")) { [downloads] _ in
                downloads.enqueue(track, kind: .cache)
            })
        }
        return UIMenu(children: actions)
    }

    private func sendTrack(_ track: Track, from list: TrackListViewController) {
        let picker = ConversationPickerViewController(store: environment.messageStore, api: environment.messagesAPI, network: environment.network)
        picker.onPick = { [weak self, weak picker, weak list] peerID, title in
            guard let self else { return }
            messaging?.outbox.enqueue(peerID: peerID, text: "", attachments: [track])
            picker?.dismiss(animated: true) {
                list?.showNotice(self.environment.network.isConnected ? "Sent to \(title)" : "Will send to \(title) when online")
            }
        }
        list.present(UINavigationController(rootViewController: picker), animated: true)
    }

    private func jump(to track: Track, source: QueueSource) {
        guard let navigation = musicNavigation, let root = musicRoot, let myMusic else { return }
        Log.app.info("jump to \(track.storageID, privacy: .public) in \(source.title, privacy: .public)")
        if case .conversation(let peerID, let title) = source {
            tabs?.selectedIndex = 1
            messagesNavigation?.presentedViewController?.dismiss(animated: false)
            openChat(peerID: peerID, title: title)
            (messagesNavigation?.topViewController as? ChatViewController)?.reveal(track)
            return
        }
        tabs?.selectedIndex = 0
        navigation.presentedViewController?.dismiss(animated: false)
        navigation.popToRootViewController(animated: false)
        switch source {
        case .myMusic:
            root.select(0)
            myMusic.revealInLibrary(track)
        case .search(let query):
            root.select(0)
            myMusic.revealInSearch(query: query, track: track)
        case .saved, .listened, .playlist, .recommendations, .similar, .conversation:
            root.select(1)
            let screen: TrackListViewController
            switch source {
            case .playlist(let playlist):
                screen = PlaylistTracksViewController(audioAPI: environment.audioAPI, network: environment.network, playlist: playlist)
                bindPlayer(to: screen)
            case .listened:
                screen = StoredTracksViewController(library: environment.library, source: .listened)
                bindPlayer(to: screen)
            case .recommendations:
                guard let userID = environment.sessionStore.session?.userID else { return }
                screen = recommendationsScreen(userID: userID)
            case .similar(let seed):
                screen = RecommendationsViewController(audioAPI: environment.audioAPI, network: environment.network, kind: .similar(seed))
                bindPlayer(to: screen)
            default:
                screen = StoredTracksViewController(library: environment.library, source: .saved)
                bindPlayer(to: screen)
            }
            navigation.pushViewController(screen, animated: true)
            screen.reveal(track)
        }
    }

    private func showDownloads(from list: UIViewController) {
        guard let navigation = list.navigationController ?? musicNavigation else { return }
        if navigation.topViewController is DownloadsViewController {
            return
        }
        navigation.pushViewController(DownloadsViewController(center: downloads), animated: true)
    }

    private func downloadDidFinish(_ job: DownloadCenter.Job) {
        guard job.kind == .saveTo, case .done(let url) = job.state, let url, let presenter = window.rootViewController?.topmostPresentedViewController else { return }
        DocumentExport.present(fileURL: url, from: presenter)
    }

    private func signOut() {
        Log.app.info("sign out")
        player.stop()
        voicePlayer.stop()
        messaging?.sync.stop()
        messaging = nil
        autoCache = nil
        recommendations = nil
        libraryEditor = nil
        downloads.cancelAll()
        downloads.clearFinished()
        Task { [library = environment.library, cache = environment.cache, messages = environment.messageStore] in
            await cache.clear()
            try? await library.clear()
            try? await messages.clear()
        }
        environment.sessionStore.clear()
    }

    private func bindPlayer(to list: TrackListViewController) {
        list.currentTrack = { [player] in player.current }
        list.onSelectTrack = { [player] track, queue, source in
            player.play(track, in: queue, source: source)
        }
        list.onPlayNext = { [player] track in player.playNext(track) }
        list.onShowSimilar = { [weak self] track, list in
            guard let self, let navigation = list.navigationController ?? musicNavigation else { return }
            let similar = RecommendationsViewController(audioAPI: environment.audioAPI, network: environment.network, kind: .similar(track))
            bindPlayer(to: similar)
            navigation.pushViewController(similar, animated: true)
        }
        list.onAddToQueue = { [player] track in player.addToQueue(track) }
        list.membership = { [weak self] track in self?.libraryEditor?.membership(of: track) ?? .removed }
        list.onAddToLibrary = { [weak self] track, list in
            self?.editLibrary(track, delete: false, notice: list.showNotice, failure: list.showError)
        }
        list.onDeleteFromLibrary = { [weak self] track, list in
            self?.editLibrary(track, delete: true, notice: list.showNotice, failure: list.showError)
        }
        list.isCached = { [cacheState] track in cacheState.isCached(track) }
        list.onDownload = { [weak self] track, list in
            guard let self else { return }
            downloads.enqueue(track, kind: .musicFolder)
            showDownloads(from: list)
        }
        list.onSaveTo = { [weak self] track, list in
            guard let self else { return }
            downloads.enqueue(track, kind: .saveTo)
            showDownloads(from: list)
        }
        list.onSend = { [weak self] track, list in
            self?.sendTrack(track, from: list)
        }
        list.onToggleCache = { [cacheState, downloads, cache = environment.cache] track in
            let cached = cacheState.isCached(track)
            Log.cache.info("\(cached ? "remove" : "save", privacy: .public) requested for \(track.storageID, privacy: .public)")
            if cached {
                downloads.cancelCacheJobs(for: track)
                Task {
                    await cache.remove(track)
                }
            } else {
                downloads.enqueue(track, kind: .cache)
            }
        }
    }

    private func editLibrary(_ track: Track, delete: Bool, notice: @escaping @MainActor (String) -> Void, failure: @escaping @MainActor (Error) -> Void) {
        guard let editor = libraryEditor else { return }
        guard environment.network.isConnected else {
            notice("No internet connection")
            return
        }
        Task {
            do {
                if delete {
                    try await editor.delete(track)
                    notice("Deleted from my music")
                } else {
                    _ = try await editor.add(track)
                    notice("Added to my music")
                }
            } catch {
                Log.music.error("\(delete ? "delete" : "add", privacy: .public) \(track.fullID, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                failure(error)
            }
        }
    }

    private func recommendationsScreen(userID: Int64) -> RecommendationsViewController {
        if let recommendations {
            return recommendations
        }
        let screen = RecommendationsViewController(audioAPI: environment.audioAPI, network: environment.network, kind: .forUser(userID))
        bindPlayer(to: screen)
        recommendations = screen
        return screen
    }

    private func makeGeneralScreen(_ row: GeneralViewController.Row, userID: Int64, navigation: UINavigationController) -> UIViewController {
        switch row {
        case .saved:
            let saved = StoredTracksViewController(library: environment.library, source: .saved)
            bindPlayer(to: saved)
            return saved
        case .listened:
            let listened = StoredTracksViewController(library: environment.library, source: .listened)
            bindPlayer(to: listened)
            return listened
        case .recommendations:
            return recommendationsScreen(userID: userID)
        case .playlists:
            let playlists = PlaylistsViewController(audioAPI: environment.audioAPI, network: environment.network, ownerID: userID)
            playlists.onSelectPlaylist = { [weak self, weak navigation] playlist in
                guard let self, let navigation else { return }
                let tracks = PlaylistTracksViewController(audioAPI: environment.audioAPI, network: environment.network, playlist: playlist)
                bindPlayer(to: tracks)
                navigation.pushViewController(tracks, animated: true)
            }
            return playlists
        }
    }
}

struct MessagingContext {
    let userID: Int64
    let outbox: Outbox
    let sync: MessagesSync
}
