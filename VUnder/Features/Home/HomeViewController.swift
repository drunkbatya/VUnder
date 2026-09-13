import UIKit

final class HomeViewController: UIViewController {
    var onSignOut: (() -> Void)?

    private let profile: AccountProfile?
    private let label = FormControls.bodyLabel("")

    init(profile: AccountProfile?) {
        self.profile = profile
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "My music"
        view.backgroundColor = Theme.background
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Sign out", style: .plain, target: self, action: #selector(signOut))
        label.text = profile.map { "Signed in as \($0.firstName) \($0.lastName)" } ?? "Signed in"
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
        ])
    }

    @objc private func signOut() {
        onSignOut?()
    }
}
