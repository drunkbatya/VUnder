import UIKit

final class ChatInputBar: UIView, UITextViewDelegate {
    static let maxAttachments = 10

    var onSend: ((String) -> Void)?
    var onAttach: (() -> Void)?

    private let textView = UITextView()
    private let placeholder = UILabel()
    private let attachButton = UIButton(type: .system)
    private let sendButton = UIButton(type: .system)
    private let attachmentsStack = UIStackView()
    private var textHeight: NSLayoutConstraint?

    private(set) var attachments: [Track] = []

    init() {
        super.init(frame: .zero)
        backgroundColor = Theme.background
        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        attachmentsStack.axis = .vertical
        attachmentsStack.spacing = 4
        attachmentsStack.isHidden = true

        textView.font = .preferredFont(forTextStyle: .body)
        textView.textColor = Theme.text
        textView.backgroundColor = Theme.groupedBackground
        textView.layer.cornerRadius = 16
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        textView.delegate = self
        textView.isScrollEnabled = false
        placeholder.text = "Message"
        placeholder.font = .preferredFont(forTextStyle: .body)
        placeholder.textColor = .placeholderText
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        textView.addSubview(placeholder)

        attachButton.setImage(UIImage(systemName: "music.note.list"), for: .normal)
        attachButton.addTarget(self, action: #selector(attach), for: .touchUpInside)
        sendButton.setImage(UIImage(systemName: "arrow.up.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 28)), for: .normal)
        sendButton.addTarget(self, action: #selector(send), for: .touchUpInside)
        for button in [attachButton, sendButton] {
            button.setContentHuggingPriority(.required, for: .horizontal)
            button.widthAnchor.constraint(equalToConstant: 36).isActive = true
            button.heightAnchor.constraint(equalToConstant: 36).isActive = true
        }

        let inputRow = UIStackView(arrangedSubviews: [attachButton, textView, sendButton])
        inputRow.axis = .horizontal
        inputRow.alignment = .bottom
        inputRow.spacing = 6
        let column = UIStackView(arrangedSubviews: [attachmentsStack, inputRow])
        column.axis = .vertical
        column.spacing = 6
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        let height = textView.heightAnchor.constraint(equalToConstant: 36)
        textHeight = height
        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            column.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            column.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            column.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            height,
            placeholder.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 15),
            placeholder.topAnchor.constraint(equalTo: textView.topAnchor, constant: 8),
        ])
        updateSendState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    func addAttachments(_ tracks: [Track]) {
        for track in tracks where !attachments.contains(where: { $0.isSame(as: track) }) && attachments.count < ChatInputBar.maxAttachments {
            attachments.append(track)
        }
        rebuildAttachmentRows()
    }

    func clear() {
        textView.text = ""
        attachments = []
        rebuildAttachmentRows()
        textViewDidChange(textView)
    }

    var text: String {
        textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func rebuildAttachmentRows() {
        for view in attachmentsStack.arrangedSubviews {
            attachmentsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for (index, track) in attachments.enumerated() {
            attachmentsStack.addArrangedSubview(AttachmentChip(title: "\(track.artist) - \(track.title)") { [weak self] in
                self?.removeAttachment(at: index)
            })
        }
        attachmentsStack.isHidden = attachments.isEmpty
        attachButton.isEnabled = attachments.count < ChatInputBar.maxAttachments
        updateSendState()
    }

    private func removeAttachment(at index: Int) {
        guard attachments.indices.contains(index) else { return }
        attachments.remove(at: index)
        rebuildAttachmentRows()
    }

    func textViewDidChange(_ textView: UITextView) {
        placeholder.isHidden = !textView.text.isEmpty
        let fitting = textView.sizeThatFits(CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude)).height
        let height = min(max(36, fitting), 120)
        textHeight?.constant = height
        textView.isScrollEnabled = fitting > 120
        updateSendState()
    }

    private func updateSendState() {
        sendButton.isEnabled = !text.isEmpty || !attachments.isEmpty
    }

    @objc private func send() {
        onSend?(text)
    }

    @objc private func attach() {
        onAttach?()
    }
}

private final class AttachmentChip: UIView {
    private let onRemove: () -> Void

    init(title: String, onRemove: @escaping () -> Void) {
        self.onRemove = onRemove
        super.init(frame: .zero)
        let icon = UIImageView(image: UIImage(systemName: "music.note"))
        icon.tintColor = Theme.accent
        icon.setContentHuggingPriority(.required, for: .horizontal)
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = Theme.text
        label.lineBreakMode = .byTruncatingMiddle
        label.text = title
        let removeButton = UIButton(type: .system)
        removeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        removeButton.tintColor = Theme.secondaryText
        removeButton.setContentHuggingPriority(.required, for: .horizontal)
        removeButton.addTarget(self, action: #selector(remove), for: .touchUpInside)
        let row = UIStackView(arrangedSubviews: [icon, label, removeButton])
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    @objc private func remove() {
        onRemove()
    }
}
