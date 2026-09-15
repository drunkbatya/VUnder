import UIKit

struct MessageCellContent {
    var senderName: String?
    var text: String
    var attachments: [MessageAttachment]
    var outgoing: Bool
    var footer: String
    var failed: Bool
}

final class MessageCell: UITableViewCell {
    static let reuseIdentifier = "MessageCell"

    var onTapTrack: ((Track) -> Void)?
    var trackMenu: ((Track) -> UIMenu?)?
    var onTapVoice: ((VoiceMessage) -> Void)?
    var isCurrentTrack: ((Track) -> Bool)?
    var isMusicPlaying: (() -> Bool)?
    var isVoicePlaying: ((VoiceMessage) -> Bool)?

    private let bubble = UIView()
    private let stack = UIStackView()
    private let senderLabel = UILabel()
    private let bodyLabel = UILabel()
    private let footerLabel = UILabel()
    private var leading: NSLayoutConstraint?
    private var trailing: NSLayoutConstraint?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = Theme.background
        selectionStyle = .none
        bubble.layer.cornerRadius = 14
        bubble.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bubble)
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        bubble.addSubview(stack)
        senderLabel.font = .preferredFont(forTextStyle: .caption1)
        senderLabel.textColor = Theme.accent
        bodyLabel.font = .preferredFont(forTextStyle: .body)
        bodyLabel.textColor = Theme.text
        bodyLabel.numberOfLines = 0
        footerLabel.font = .preferredFont(forTextStyle: .caption2)
        footerLabel.textColor = Theme.secondaryText
        footerLabel.textAlignment = .right
        let leading = bubble.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor)
        let trailing = bubble.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor)
        self.leading = leading
        self.trailing = trailing
        NSLayoutConstraint.activate([
            bubble.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 3),
            bubble.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -3),
            bubble.widthAnchor.constraint(lessThanOrEqualTo: contentView.layoutMarginsGuide.widthAnchor, multiplier: 0.8),
            bubble.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
            stack.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -6),
            stack.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -10),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    func configure(with content: MessageCellContent) {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        leading?.isActive = !content.outgoing
        trailing?.isActive = content.outgoing
        bubble.backgroundColor = content.outgoing ? Theme.accent.withAlphaComponent(0.22) : Theme.groupedBackground
        if let sender = content.senderName {
            senderLabel.text = sender
            stack.addArrangedSubview(senderLabel)
        }
        if !content.text.isEmpty {
            bodyLabel.text = content.text
            stack.addArrangedSubview(bodyLabel)
        }
        for attachment in content.attachments {
            switch attachment {
            case .audio(let track):
                let view = AudioAttachmentView()
                view.configure(with: track, isCurrent: isCurrentTrack?(track) ?? false, isPlaying: isMusicPlaying?() ?? false)
                view.onTap = { [weak self] in self?.onTapTrack?(track) }
                view.menuProvider = { [weak self] in self?.trackMenu?(track) }
                stack.addArrangedSubview(view)
            case .voice(let voice):
                let view = VoiceAttachmentView()
                view.configure(with: voice, isPlaying: isVoicePlaying?(voice) ?? false)
                view.onTap = { [weak self] in self?.onTapVoice?(voice) }
                stack.addArrangedSubview(view)
            case .other(let type):
                let label = UILabel()
                label.font = .preferredFont(forTextStyle: .caption1)
                label.textColor = Theme.secondaryText
                label.text = "[\(type)]"
                stack.addArrangedSubview(label)
            }
        }
        footerLabel.text = content.footer
        footerLabel.textColor = content.failed ? .systemRed : Theme.secondaryText
        stack.addArrangedSubview(footerLabel)
    }
}

final class DayHeaderCell: UITableViewCell {
    static let reuseIdentifier = "DayHeaderCell"

    private let label = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = Theme.background
        selectionStyle = .none
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textColor = Theme.secondaryText
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    func configure(with date: Date) {
        label.text = MessageDates.dayTitle(date)
    }
}
