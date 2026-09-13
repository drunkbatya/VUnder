import UIKit

final class TrackCell: UITableViewCell {
    static let reuseIdentifier = "TrackCell"

    private let titleLabel = UILabel()
    private let artistLabel = UILabel()
    private let durationLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = Theme.background
        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.textColor = Theme.text
        artistLabel.font = .preferredFont(forTextStyle: .subheadline)
        artistLabel.textColor = Theme.secondaryText
        durationLabel.font = .monospacedDigitSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .subheadline).pointSize, weight: .regular)
        durationLabel.textColor = Theme.secondaryText
        durationLabel.setContentHuggingPriority(.required, for: .horizontal)
        durationLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let textStack = UIStackView(arrangedSubviews: [titleLabel, artistLabel])
        textStack.axis = .vertical
        textStack.spacing = 2
        let rowStack = UIStackView(arrangedSubviews: [textStack, durationLabel])
        rowStack.axis = .horizontal
        rowStack.alignment = .center
        rowStack.spacing = 12
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rowStack)
        NSLayoutConstraint.activate([
            rowStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            rowStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            rowStack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            rowStack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    func configure(with track: Track, isCurrent: Bool) {
        titleLabel.text = track.title
        artistLabel.text = track.artist
        durationLabel.text = track.formattedDuration
        let alpha: CGFloat = track.isAvailable ? 1 : 0.4
        titleLabel.alpha = alpha
        artistLabel.alpha = alpha
        titleLabel.textColor = isCurrent ? Theme.accent : Theme.text
        titleLabel.font = isCurrent ? .preferredFont(forTextStyle: .headline) : .preferredFont(forTextStyle: .body)
    }
}
