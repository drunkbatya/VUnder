import UIKit

final class CaptchaViewController: FormViewController {
    var onSubmit: ((String) -> Void)?
    var onCancel: (() -> Void)?

    private let imageURL: URL
    private let imageView = UIImageView()
    private let keyField = FormControls.textField(placeholder: "Text from the image")
    private var finished = false

    init(imageURL: URL) {
        self.imageURL = imageURL
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Captcha"
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        imageView.contentMode = .scaleAspectFit
        imageView.heightAnchor.constraint(equalToConstant: 100).isActive = true
        keyField.textAlignment = .center
        keyField.returnKeyType = .done
        keyField.delegate = self
        let button = FormControls.primaryButton(title: "Continue")
        button.addTarget(self, action: #selector(submit), for: .touchUpInside)
        contentStack.addArrangedSubview(imageView)
        contentStack.addArrangedSubview(keyField)
        contentStack.addArrangedSubview(button)
        contentStack.addArrangedSubview(errorLabel)
        loadImage()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        keyField.becomeFirstResponder()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if !finished {
            finished = true
            onCancel?()
        }
    }

    private func loadImage() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let (data, _) = try await URLSession.shared.data(from: imageURL)
                imageView.image = UIImage(data: data)
            } catch {
                showError("Captcha image failed to load: \(imageURL.absoluteString)")
            }
        }
    }

    @objc private func submit() {
        guard let key = keyField.text?.trimmingCharacters(in: .whitespaces), !key.isEmpty else {
            showError("Enter the text from the image")
            return
        }
        finished = true
        onSubmit?(key)
    }

    @objc private func cancel() {
        finished = true
        onCancel?()
    }
}

extension CaptchaViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        submit()
        return true
    }
}
