import UIKit

final class LoginViewController: FormViewController {
    var onSubmit: ((String) -> Void)?

    private let loginField = FormControls.textField(placeholder: "Phone or email")
    private let signInButton = FormControls.primaryButton(title: "Sign in")

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "VUnder"
        loginField.keyboardType = .emailAddress
        loginField.textContentType = .username
        loginField.returnKeyType = .go
        loginField.delegate = self
        signInButton.addTarget(self, action: #selector(submit), for: .touchUpInside)
        contentStack.addArrangedSubview(FormControls.titleLabel("Sign in to VK"))
        contentStack.addArrangedSubview(FormControls.bodyLabel("Music only. Nothing else."))
        contentStack.setCustomSpacing(24, after: contentStack.arrangedSubviews[1])
        contentStack.addArrangedSubview(loginField)
        contentStack.addArrangedSubview(signInButton)
        contentStack.addArrangedSubview(errorLabel)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if loginField.text?.isEmpty ?? true {
            loginField.becomeFirstResponder()
        }
    }

    @objc private func submit() {
        let login = loginField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !login.isEmpty else {
            showError("Enter phone or email")
            return
        }
        showError(nil)
        view.endEditing(true)
        onSubmit?(login)
    }
}

extension LoginViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        submit()
        return true
    }
}
