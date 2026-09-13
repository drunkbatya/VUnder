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
        observers.append(NotificationCenter.default.addObserver(forName: AppearanceSettings.didChange, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.applyAppearance() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: SessionStore.sessionDidChange, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.sessionDidChange() }
        })
        if let session = environment.sessionStore.session {
            Log.app.info("launch with session user_id=\(session.userID, privacy: .public)")
            showHome(profile: nil)
        } else {
            Log.app.info("launch without session")
            showLogin()
        }
        window.makeKeyAndVisible()
    }

    private func applyAppearance() {
        let appearance = environment.appearance.current
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
        coordinator.onSignedIn = { [weak self] profile in
            self?.loginCoordinator = nil
            self?.showHome(profile: profile)
        }
        loginCoordinator = coordinator
        window.rootViewController = coordinator.navigationController
    }

    private func showHome(profile: AccountProfile?) {
        let home = HomeViewController(profile: profile)
        home.onSignOut = { [weak self] in
            self?.environment.sessionStore.clear()
        }
        window.rootViewController = UINavigationController(rootViewController: home)
    }
}
