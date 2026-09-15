import UIKit

final class AudioAttachmentView: UIControl {
    var onTap: (() -> Void)?
    var menuProvider: (() -> UIMenu?)?

    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let artistLabel = UILabel()
    private let durationLabel = UILabel()

    init() {
        super.init(frame: .zero)
        layer.cornerRadius = 8
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = Theme.accent
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 28).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 28).isActive = true
        titleLabel.font = .preferredFont(forTextStyle: .subheadline)
        titleLabel.textColor = Theme.text
        titleLabel.numberOfLines = 1
        artistLabel.font = .preferredFont(forTextStyle: .caption1)
        artistLabel.textColor = Theme.secondaryText
        artistLabel.numberOfLines = 1
        durationLabel.font = .monospacedDigitSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .caption1).pointSize, weight: .regular)
        durationLabel.textColor = Theme.secondaryText
        durationLabel.setContentHuggingPriority(.required, for: .horizontal)
        durationLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        let textStack = UIStackView(arrangedSubviews: [titleLabel, artistLabel])
        textStack.axis = .vertical
        textStack.spacing = 1
        let row = UIStackView(arrangedSubviews: [iconView, textStack, durationLabel])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
        ])
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        isContextMenuInteractionEnabled = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    func configure(with track: Track, isCurrent: Bool, isPlaying: Bool) {
        titleLabel.text = track.title
        artistLabel.text = track.artist
        durationLabel.text = track.formattedDuration
        iconView.image = UIImage(systemName: isCurrent && isPlaying ? "pause.circle.fill" : "play.circle.fill")
        titleLabel.textColor = isCurrent ? Theme.accent : Theme.text
        alpha = track.isAvailable ? 1 : 0.5
        backgroundColor = Theme.accent.withAlphaComponent(0.12)
    }

    override var isHighlighted: Bool {
        didSet {
            alpha = isHighlighted ? 0.6 : 1
        }
    }

    @objc private func tapped() {
        onTap?()
    }

    override func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard let menuProvider else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in menuProvider() }
    }
}
