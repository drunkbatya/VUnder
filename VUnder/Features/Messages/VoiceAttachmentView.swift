import UIKit

final class VoiceAttachmentView: UIControl {
    var onTap: (() -> Void)?

    private let iconView = UIImageView()
    private let label = UILabel()

    init() {
        super.init(frame: .zero)
        layer.cornerRadius = 8
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = Theme.accent
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 28).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 28).isActive = true
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = Theme.text
        let row = UIStackView(arrangedSubviews: [iconView, label])
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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    func configure(with voice: VoiceMessage, isPlaying: Bool) {
        iconView.image = UIImage(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
        label.text = "Voice message \(voice.formattedDuration)"
        alpha = voice.mp3URL == nil ? 0.5 : 1
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
}
