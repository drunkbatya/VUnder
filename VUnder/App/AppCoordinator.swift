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
    private var autoCache: AutoCacheController?
    private var loginCoordinator: LoginCoordinator?
    private weak var musicNavigation: UINavigationController?
    private weak var musicRoot: MusicRootViewController?
    private weak var myMusic: MyMusicViewController?
    private var recommendations: RecommendationsViewController?
    private var observers: [NSObjectProtocol] = []

    init(window: UIWindow, environment: AppEnvironment) {
        self.window = window
        self.environment = environment
        challengePresenter = ChallengePresenter(presentingViewController: { [weak window] in
            window?.rootViewController?.topmostPresentedViewController
        })
        player = PlayerService(audioAPI: environment.audioAPI, library: environment.library, settings: environment.settings, network: environment.network)
        player.localFileURL = { [cache = environment.cache] track in cache.localFileURL(for: track) }
        fileInfoProvider = TrackFileInfoProvider(localFileURL: { [cache = environment.cache] track in cache.localFileURL(for: track) })
        exporter = TrackExporter()
        downloads = DownloadCenter(cache: environment.cache, exporter: exporter)
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
        root.onSettings = { [weak self, weak navigation] in
            guard let self, let navigation else { return }
            let settings = SettingsViewController(settings: environment.settings, cache: environment.cache)
            settings.onSignOut = { [weak self] in self?.signOut() }
            navigation.pushViewController(settings, animated: true)
        }
        general.onSelectRow = { [weak self, weak navigation] row in
            guard let self, let navigation else { return }
            navigation.pushViewController(makeGeneralScreen(row, userID: session.userID, navigation: navigation), animated: true)
        }
        musicNavigation = navigation
        musicRoot = root
        self.myMusic = myMusic
        let container = PlayerContainerViewController(content: navigation, player: player, fileInfoProvider: fileInfoProvider)
        container.onJumpToTrack = { [weak self] track, source in
            self?.jump(to: track, source: source)
        }
        window.rootViewController = container
    }

    private func jump(to track: Track, source: QueueSource) {
        guard let navigation = musicNavigation, let root = musicRoot, let myMusic else { return }
        Log.app.info("jump to \(track.storageID, privacy: .public) in \(source.title, privacy: .public)")
        navigation.presentedViewController?.dismiss(animated: false)
        navigation.popToRootViewController(animated: false)
        switch source {
        case .myMusic:
            root.select(0)
            myMusic.revealInLibrary(track)
        case .search(let query):
            root.select(0)
            myMusic.revealInSearch(query: query, track: track)
        case .saved, .listened, .playlist, .recommendations, .similar:
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
        autoCache = nil
        recommendations = nil
        downloads.cancelAll()
        downloads.clearFinished()
        Task { [library = environment.library, cache = environment.cache] in
            await cache.clear()
            try? await library.clear()
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
