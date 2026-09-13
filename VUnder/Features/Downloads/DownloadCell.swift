import UIKit

final class DownloadCell: UITableViewCell {
    static let reuseIdentifier = "DownloadCell"

    var onCancel: (() -> Void)?

    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let cancelButton = UIButton(type: .system)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = Theme.background
        selectionStyle = .none
        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.textColor = Theme.text
        titleLabel.numberOfLines = 2
        statusLabel.font = .preferredFont(forTextStyle: .caption1)
        statusLabel.textColor = Theme.secondaryText
        statusLabel.numberOfLines = 2
        progressView.progressTintColor = Theme.accent
        cancelButton.setImage(UIImage(systemName: "xmark.circle"), for: .normal)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        cancelButton.widthAnchor.constraint(equalToConstant: 44).isActive = true
        cancelButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
        let textStack = UIStackView(arrangedSubviews: [titleLabel, statusLabel, progressView])
        textStack.axis = .vertical
        textStack.spacing = 4
        let row = UIStackView(arrangedSubviews: [textStack, cancelButton])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            row.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    func configure(with job: DownloadCenter.Job) {
        titleLabel.text = "\(job.track.artist) - \(job.track.title)"
        cancelButton.isHidden = job.state.isFinished
        progressView.isHidden = true
        switch job.state {
        case .queued:
            statusLabel.text = "\(job.kind.title): waiting"
        case .running(let fraction):
            statusLabel.text = "\(job.kind.title): downloading" + (fraction.map { " \(Int($0 * 100))%" } ?? "")
            progressView.isHidden = false
            progressView.progress = Float(fraction ?? 0)
        case .done(let url):
            switch job.kind {
            case .cache: statusLabel.text = "Saved offline"
            case .musicFolder: statusLabel.text = "Saved to Music/\(url?.lastPathComponent ?? "")"
            case .saveTo: statusLabel.text = "Ready to save"
            }
        case .failed(let message):
            statusLabel.text = "\(job.kind.title): failed. \(message)"
        case .cancelled:
            statusLabel.text = "\(job.kind.title): cancelled"
        }
    }

    @objc private func cancelTapped() {
        onCancel?()
    }
}
