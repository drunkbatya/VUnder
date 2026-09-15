import UIKit

final class AvatarView: UIView {
    static let size: CGFloat = 44

    private let imageView = UIImageView()
    private let initialsLabel = UILabel()
    private var loadTask: Task<Void, Never>?
    private var shownURL: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.accent
        clipsToBounds = true
        imageView.contentMode = .scaleAspectFill
        imageView.translatesAutoresizingMaskIntoConstraints = false
        initialsLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        initialsLabel.textColor = .white
        initialsLabel.textAlignment = .center
        initialsLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(initialsLabel)
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            initialsLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            initialsLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthAnchor.constraint(equalToConstant: AvatarView.size),
            heightAnchor.constraint(equalToConstant: AvatarView.size),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width / 2
    }

    func configure(name: String, photoURL: String?) {
        initialsLabel.text = AvatarView.initials(name)
        loadTask?.cancel()
        loadTask = nil
        guard let photoURL, let url = URL(string: photoURL) else {
            imageView.image = nil
            shownURL = nil
            return
        }
        if shownURL == photoURL, imageView.image != nil {
            return
        }
        imageView.image = nil
        shownURL = photoURL
        loadTask = Task { [weak self] in
            let image = await ImageLoader.shared.image(url: url)
            guard let self, !Task.isCancelled, shownURL == photoURL else { return }
            imageView.image = image
        }
    }

    private static func initials(_ name: String) -> String {
        name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}
