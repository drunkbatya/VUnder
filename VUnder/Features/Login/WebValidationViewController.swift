import UIKit
import WebKit

final class WebValidationViewController: UIViewController {
    var onFinish: ((WebValidationOutcome) -> Void)?
    var onCancel: (() -> Void)?

    private let startURL: URL
    private let webView: WKWebView
    private var finished = false

    init(url: URL) {
        startURL = url
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Verification"
        view.backgroundColor = Theme.background
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.customUserAgent = "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.7559.133 Mobile Safari/537.36"
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        webView.load(URLRequest(url: startURL))
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if !finished {
            finished = true
            onCancel?()
        }
    }

    @objc private func cancel() {
        finished = true
        onCancel?()
    }

    private func handleBlankPage(_ url: URL) -> Bool {
        guard url.host == VKClientIdentity.oauthHost || url.host == "oauth.vk.com", url.path == "/blank.html" else {
            return false
        }
        let query = url.absoluteString.replacingOccurrences(of: "#", with: "?")
        let items = URLComponents(string: query)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first(where: { $0.name == name })?.value
        }
        finished = true
        if value("cancel") != nil || value("success") == nil {
            onCancel?()
        } else {
            onFinish?(WebValidationOutcome(
                accessToken: value("access_token"),
                secret: value("secret"),
                userID: value("user_id").flatMap(Int64.init)
            ))
        }
        return true
    }
}

extension WebValidationViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        if let url = navigationAction.request.url, handleBlankPage(url) {
            return .cancel
        }
        return .allow
    }
}
