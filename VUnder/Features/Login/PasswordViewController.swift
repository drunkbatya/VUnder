import UIKit

final class PasswordViewController: FormViewController {
    var onSubmit: ((String) -> Void)?
    var onCancel: (() -> Void)?

    private let login: String
    private let passwordField = FormControls.textField(placeholder: "Password")
    private let signInButton = FormControls.primaryButton(title: "Sign in")
    private var submitted = false

    init(login: String) {
        self.login = login
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Password"
        let loginField = FormControls.textField(placeholder: "")
        loginField.text = login
        loginField.isEnabled = false
        passwordField.isSecureTextEntry = true
        passwordField.textContentType = .password
        passwordField.returnKeyType = .go
        passwordField.delegate = self
        signInButton.addTarget(self, action: #selector(submit), for: .touchUpInside)
        contentStack.addArrangedSubview(FormControls.bodyLabel("Enter the password for your account"))
        contentStack.addArrangedSubview(loginField)
        contentStack.addArrangedSubview(passwordField)
        contentStack.addArrangedSubview(signInButton)
        contentStack.addArrangedSubview(errorLabel)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        passwordField.becomeFirstResponder()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent, !submitted {
            onCancel?()
        }
    }

    @objc private func submit() {
        guard let password = passwordField.text, !password.isEmpty else {
            showError("Enter password")
            return
        }
        showError(nil)
        submitted = true
        view.endEditing(true)
        setBusy(true)
        onSubmit?(password)
    }
}

extension PasswordViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        submit()
        return true
    }
}
