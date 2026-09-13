import UIKit

@MainActor
final class ChallengePresenter: VKAPIChallengeHandling {
    private let presentingViewController: @MainActor () -> UIViewController?
    private let captchaPrompt = AsyncPrompt<String>()
    private let validationPrompt = AsyncPrompt<WebValidationOutcome>()

    init(presentingViewController: @escaping @MainActor () -> UIViewController?) {
        self.presentingViewController = presentingViewController
    }

    func solveCaptcha(imageURL: URL) async throws -> String {
        guard let presenter = presentingViewController() else { throw VKAPIError.challengeUnavailable }
        let controller = CaptchaViewController(imageURL: imageURL)
        let navigation = UINavigationController(rootViewController: controller)
        navigation.isModalInPresentation = true
        controller.onSubmit = { [weak navigation, captchaPrompt] key in
            navigation?.dismiss(animated: true)
            captchaPrompt.fulfill(key)
        }
        controller.onCancel = { [weak navigation, captchaPrompt] in
            navigation?.dismiss(animated: true)
            captchaPrompt.cancel()
        }
        presenter.present(navigation, animated: true)
        return try await captchaPrompt.wait()
    }

    func validate(url: URL) async throws -> WebValidationOutcome {
        guard let presenter = presentingViewController() else { throw VKAPIError.challengeUnavailable }
        let controller = WebValidationViewController(url: url)
        let navigation = UINavigationController(rootViewController: controller)
        navigation.isModalInPresentation = true
        controller.onFinish = { [weak navigation, validationPrompt] outcome in
            navigation?.dismiss(animated: true)
            validationPrompt.fulfill(outcome)
        }
        controller.onCancel = { [weak navigation, validationPrompt] in
            navigation?.dismiss(animated: true)
            validationPrompt.cancel()
        }
        presenter.present(navigation, animated: true)
        return try await validationPrompt.wait()
    }

    func completeValidation(url: URL) async throws {
        _ = try await validate(url: url)
    }
}

extension UIViewController {
    var topmostPresentedViewController: UIViewController {
        var current = self
        while let presented = current.presentedViewController {
            current = presented
        }
        return current
    }
}
