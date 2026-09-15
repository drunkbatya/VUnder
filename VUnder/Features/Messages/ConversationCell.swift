import UIKit

final class ConversationCell: UITableViewCell {
    static let reuseIdentifier = "ConversationCell"

    private let avatar = AvatarView()
    private let titleLabel = UILabel()
    private let previewLabel = UILabel()
    private let dateLabel = UILabel()
    private let unreadLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = Theme.background
        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.textColor = Theme.text
        previewLabel.font = .preferredFont(forTextStyle: .subheadline)
        previewLabel.textColor = Theme.secondaryText
        previewLabel.lineBreakMode = .byTruncatingTail
        dateLabel.font = .preferredFont(forTextStyle: .caption1)
        dateLabel.textColor = Theme.secondaryText
        dateLabel.setContentHuggingPriority(.required, for: .horizontal)
        dateLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        unreadLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        unreadLabel.textColor = .white
        unreadLabel.backgroundColor = Theme.accent
        unreadLabel.textAlignment = .center
        unreadLabel.layer.cornerRadius = 10
        unreadLabel.clipsToBounds = true
        unreadLabel.translatesAutoresizingMaskIntoConstraints = false
        unreadLabel.heightAnchor.constraint(equalToConstant: 20).isActive = true
        unreadLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 20).isActive = true

        let topRow = UIStackView(arrangedSubviews: [titleLabel, dateLabel])
        topRow.axis = .horizontal
        topRow.spacing = 8
        let bottomRow = UIStackView(arrangedSubviews: [previewLabel, unreadLabel])
        bottomRow.axis = .horizontal
        bottomRow.spacing = 8
        bottomRow.alignment = .center
        let textStack = UIStackView(arrangedSubviews: [topRow, bottomRow])
        textStack.axis = .vertical
        textStack.spacing = 2
        let rowStack = UIStackView(arrangedSubviews: [avatar, textStack])
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

    func configure(with conversation: Conversation, pending: String?) {
        avatar.configure(name: conversation.title, photoURL: conversation.photoURL)
        titleLabel.text = conversation.title
        if let pending {
            previewLabel.text = "Sending: \(pending)"
        } else if let last = conversation.lastMessage {
            previewLabel.text = last.out ? "You: \(last.previewText)" : last.previewText
        } else {
            previewLabel.text = ""
        }
        dateLabel.text = conversation.lastMessage.map { MessageDates.short($0.date) } ?? ""
        unreadLabel.isHidden = conversation.unreadCount == 0
        unreadLabel.text = " \(conversation.unreadCount) "
    }
}
