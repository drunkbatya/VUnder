import UIKit
import os

@MainActor
final class LoginCoordinator {
    let navigationController = UINavigationController()
    var onSignedIn: ((AccountProfile) -> Void)?

    private let authFlow: VKAuthFlow
    private let challengePresenter: ChallengePresenter
    private let loginViewController = LoginViewController()
    private let codePrompt = AsyncPrompt<String>()
    private let passwordPrompt = AsyncPrompt<String>()
    private weak var codeViewController: OneTimeCodeViewController?
    private var signInTask: Task<Void, Never>?

    init(authFlow: VKAuthFlow, challengePresenter: ChallengePresenter) {
        self.authFlow = authFlow
        self.challengePresenter = challengePresenter
        navigationController.viewControllers = [loginViewController]
        loginViewController.onSubmit = { [weak self] login in
            self?.signIn(login: login)
        }
    }

    private func signIn(login: String) {
        signInTask?.cancel()
        loginViewController.setBusy(true)
        signInTask = Task { [weak self] in
            guard let self else { return }
            do {
                let profile = try await authFlow.signIn(login: login, interaction: self)
                loginViewController.setBusy(false)
                onSignedIn?(profile)
            } catch {
                if error is CancellationError {
                    Log.auth.info("sign in cancelled")
                } else {
                    Log.auth.error("sign in failed: \(error.localizedDescription, privacy: .public)")
                }
                navigationController.popToRootViewController(animated: true)
                loginViewController.setBusy(false)
                if !(error is CancellationError) {
                    loginViewController.showError(error.localizedDescription)
                }
            }
        }
    }
}

extension LoginCoordinator: AuthInteraction {
    func requestOneTimeCode(_ challenge: OneTimeCodeChallenge) async throws -> String {
        if let existing = codeViewController, navigationController.viewControllers.contains(existing) {
            existing.apply(challenge)
        } else {
            let controller = OneTimeCodeViewController(challenge: challenge)
            controller.onSubmit = { [codePrompt] code in codePrompt.fulfill(code) }
            controller.onCancel = { [codePrompt] in codePrompt.cancel() }
            codeViewController = controller
            navigationController.pushViewController(controller, animated: true)
        }
        return try await codePrompt.wait()
    }

    func requestPassword(login: String) async throws -> String {
        let controller = PasswordViewController(login: login)
        controller.onSubmit = { [passwordPrompt] password in passwordPrompt.fulfill(password) }
        controller.onCancel = { [passwordPrompt] in passwordPrompt.cancel() }
        navigationController.pushViewController(controller, animated: true)
        return try await passwordPrompt.wait()
    }

    func requestCaptcha(imageURL: URL) async throws -> String {
        try await challengePresenter.solveCaptcha(imageURL: imageURL)
    }

    func requestWebValidation(url: URL) async throws -> WebValidationOutcome {
        try await challengePresenter.validate(url: url)
    }
}
