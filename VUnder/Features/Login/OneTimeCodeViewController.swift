import UIKit

final class OneTimeCodeViewController: FormViewController {
    var onSubmit: ((String) -> Void)?
    var onCancel: (() -> Void)?

    private var challenge: OneTimeCodeChallenge
    private let descriptionLabel = FormControls.bodyLabel("")
    private let codeField = FormControls.textField(placeholder: "Code")
    private let continueButton = FormControls.primaryButton(title: "Continue")
    private let resendButton = FormControls.linkButton(title: "Send SMS")
    private var sendTask: Task<Void, Never>?
    private var awaitingSubmit = false

    init(challenge: OneTimeCodeChallenge) {
        self.challenge = challenge
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Confirmation"
        codeField.keyboardType = .numberPad
        codeField.textContentType = .oneTimeCode
        codeField.textAlignment = .center
        continueButton.addTarget(self, action: #selector(submit), for: .touchUpInside)
        resendButton.addTarget(self, action: #selector(sendCode), for: .touchUpInside)
        contentStack.addArrangedSubview(descriptionLabel)
        contentStack.addArrangedSubview(codeField)
        contentStack.addArrangedSubview(continueButton)
        contentStack.addArrangedSubview(resendButton)
        contentStack.addArrangedSubview(errorLabel)
        apply(challenge)
        if challenge.deliversAutomatically {
            sendCode()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        codeField.becomeFirstResponder()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent {
            sendTask?.cancel()
            onCancel?()
        }
    }

    func apply(_ challenge: OneTimeCodeChallenge) {
        self.challenge = challenge
        awaitingSubmit = true
        setBusy(false)
        showError(challenge.failureMessage)
        if challenge.failureMessage != nil {
            codeField.text = ""
            codeField.becomeFirstResponder()
        }
        if descriptionLabel.text?.isEmpty ?? true {
            descriptionLabel.text = OneTimeCodeViewController.description(for: challenge.method)
        }
        resendButton.isHidden = challenge.method == "codegen" || challenge.method == "reserve_code"
    }

    private static func description(for method: String) -> String {
        switch method {
        case "sms": return "Sending an SMS with the code"
        case "callreset": return "You will receive a call. Enter the last digits of the number"
        case "push": return "Enter the code from the notification in the VK app"
        case "codegen": return "Enter the code from your authenticator app"
        case "email": return "Enter the code sent to your email"
        case "reserve_code": return "Enter one of your reserve codes"
        default: return "Enter the confirmation code"
        }
    }

    @objc private func sendCode() {
        resendButton.isEnabled = false
        sendTask = Task { [weak self] in
            guard let self else { return }
            do {
                let delivery = try await challenge.send()
                guard !Task.isCancelled else { return }
                if delivery.codeLength > 0 {
                    descriptionLabel.text = "Enter the last \(delivery.codeLength) digits of the calling number" + (delivery.phoneMask.map { " (\($0))" } ?? "")
                } else {
                    descriptionLabel.text = "SMS with the code was sent" + (delivery.phoneMask.map { " to \($0)" } ?? "")
                }
                resendButton.configuration?.title = "Resend"
            } catch {
                guard !Task.isCancelled else { return }
                showError(error.localizedDescription)
            }
            resendButton.isEnabled = true
        }
    }

    @objc private func submit() {
        guard let code = codeField.text?.trimmingCharacters(in: .whitespaces), !code.isEmpty else {
            showError("Enter the code")
            return
        }
        guard awaitingSubmit else { return }
        awaitingSubmit = false
        showError(nil)
        view.endEditing(true)
        setBusy(true)
        onSubmit?(code)
    }
}
