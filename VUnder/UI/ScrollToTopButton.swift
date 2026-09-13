import UIKit

final class ScrollToTopButton: UIButton {
    private weak var scrollView: UIScrollView?

    init(scrollView: UIScrollView) {
        self.scrollView = scrollView
        super.init(frame: .zero)
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: "arrow.up", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold))
        configuration.baseBackgroundColor = Theme.accent
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .capsule
        self.configuration = configuration
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 44).isActive = true
        heightAnchor.constraint(equalToConstant: 44).isActive = true
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: 2)
        isHidden = true
        addTarget(self, action: #selector(scrollToTop), for: .touchUpInside)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    func attach(to container: UIView) {
        container.addSubview(self)
        NSLayoutConstraint.activate([
            trailingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            bottomAnchor.constraint(equalTo: container.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])
    }

    func scrollViewDidScroll() {
        guard let scrollView else { return }
        let offset = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        let shouldShow = offset > scrollView.bounds.height
        guard shouldShow != !isHidden else { return }
        isHidden = !shouldShow
    }

    @objc private func scrollToTop() {
        guard let scrollView else { return }
        scrollView.setContentOffset(CGPoint(x: 0, y: -scrollView.adjustedContentInset.top), animated: true)
    }
}
