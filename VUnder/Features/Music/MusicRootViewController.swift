import UIKit

final class MusicRootViewController: UIViewController {
    private let segments = UISegmentedControl(items: ["My music", "General"])
    private let pages: [UIViewController]
    private var current: UIViewController?

    init(myMusic: UIViewController, general: UIViewController) {
        pages = [myMusic, general]
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        segments.selectedSegmentIndex = 0
        segments.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        navigationItem.titleView = segments
        show(pages[0])
    }

    @objc private func segmentChanged() {
        show(pages[segments.selectedSegmentIndex])
    }

    private func show(_ controller: UIViewController) {
        guard controller !== current else { return }
        if let current {
            current.willMove(toParent: nil)
            current.view.removeFromSuperview()
            current.removeFromParent()
        }
        addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controller.view)
        NSLayoutConstraint.activate([
            controller.view.topAnchor.constraint(equalTo: view.topAnchor),
            controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        controller.didMove(toParent: self)
        current = controller
        navigationItem.leftBarButtonItem = controller.navigationItem.leftBarButtonItem
        navigationItem.rightBarButtonItem = controller.navigationItem.rightBarButtonItem
    }
}
