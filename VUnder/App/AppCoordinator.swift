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
    private var autoCache: AutoCacheController?
    private var loginCoordinator: LoginCoordinator?
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
            cache: environment.cache,
            cacheState: cacheState,
            settings: environment.settings,
            network: environment.network,
            userID: session.userID
        )
        bindPlayer(to: myMusic)
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
        window.rootViewController = PlayerContainerViewController(content: navigation, player: player, fileInfoProvider: fileInfoProvider)
    }

    private func signOut() {
        Log.app.info("sign out")
        player.stop()
        autoCache = nil
        Task { [library = environment.library, cache = environment.cache] in
            await cache.clear()
            try? await library.clear()
        }
        environment.sessionStore.clear()
    }

    private func bindPlayer(to list: TrackListViewController) {
        list.currentTrack = { [player] in player.current }
        list.onSelectTrack = { [player] track, queue in
            player.play(track, in: queue)
        }
        list.isCached = { [cacheState] track in cacheState.isCached(track) }
        list.onToggleCache = { [cacheState, cache = environment.cache] track in
            let cached = cacheState.isCached(track)
            Log.cache.info("\(cached ? "remove" : "save", privacy: .public) requested for \(track.storageID, privacy: .public)")
            Task {
                if cached {
                    await cache.remove(track)
                } else {
                    await cache.enqueue(track)
                }
            }
        }
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
