import UIKit
import os

@MainActor
final class AppCoordinator {
    private let window: UIWindow
    private let environment: AppEnvironment
    private let challengePresenter: ChallengePresenter
    private var loginCoordinator: LoginCoordinator?
    private var observers: [NSObjectProtocol] = []

    init(window: UIWindow, environment: AppEnvironment) {
        self.window = window
        self.environment = environment
        challengePresenter = ChallengePresenter(presentingViewController: { [weak window] in
            window?.rootViewController?.topmostPresentedViewController
        })
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
        myMusic.onSignOut = { [weak self] in
            guard let self else { return }
            Task { [library = environment.library] in
                try? await library.clear()
            }
            environment.sessionStore.clear()
        }
        general.onSelectRow = { [weak self, weak navigation] row in
            guard let self, let navigation else { return }
            navigation.pushViewController(makeGeneralScreen(row, userID: session.userID, navigation: navigation), animated: true)
        }
        window.rootViewController = navigation
    }

    private func makeGeneralScreen(_ row: GeneralViewController.Row, userID: Int64, navigation: UINavigationController) -> UIViewController {
        switch row {
        case .saved:
            return StoredTracksViewController(library: environment.library, source: .saved)
        case .listened:
            return StoredTracksViewController(library: environment.library, source: .listened)
        case .playlists:
            let playlists = PlaylistsViewController(audioAPI: environment.audioAPI, network: environment.network, ownerID: userID)
            playlists.onSelectPlaylist = { [weak self, weak navigation] playlist in
                guard let self, let navigation else { return }
                let tracks = PlaylistTracksViewController(audioAPI: environment.audioAPI, network: environment.network, playlist: playlist)
                navigation.pushViewController(tracks, animated: true)
            }
            return playlists
        }
    }
}
