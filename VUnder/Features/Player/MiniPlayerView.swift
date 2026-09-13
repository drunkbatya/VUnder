import UIKit

final class MiniPlayerView: UIView {
    static let height: CGFloat = 56

    var onTap: (() -> Void)?
    var onPlayPause: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?

    private let titleLabel = UILabel()
    private let artistLabel = UILabel()
    private let previousButton = UIButton(type: .system)
    private let playButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let progressView = UIProgressView(progressViewStyle: .bar)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.groupedBackground
        titleLabel.font = .preferredFont(forTextStyle: .subheadline)
        titleLabel.textColor = Theme.text
        artistLabel.font = .preferredFont(forTextStyle: .caption1)
        artistLabel.textColor = Theme.secondaryText
        previousButton.setImage(UIImage(systemName: "backward.fill"), for: .normal)
        playButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        nextButton.setImage(UIImage(systemName: "forward.fill"), for: .normal)
        previousButton.addTarget(self, action: #selector(previousTapped), for: .touchUpInside)
        playButton.addTarget(self, action: #selector(playPause), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)
        for button in [previousButton, playButton, nextButton] {
            button.widthAnchor.constraint(equalToConstant: 44).isActive = true
            button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        }
        let textStack = UIStackView(arrangedSubviews: [titleLabel, artistLabel])
        textStack.axis = .vertical
        let row = UIStackView(arrangedSubviews: [textStack, previousButton, playButton, nextButton])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 4
        row.translatesAutoresizingMaskIntoConstraints = false
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.progressTintColor = Theme.accent
        addSubview(progressView)
        addSubview(row)
        NSLayoutConstraint.activate([
            progressView.topAnchor.constraint(equalTo: topAnchor),
            progressView.leadingAnchor.constraint(equalTo: leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
        ])
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    func update(track: Track?, state: PlaybackState) {
        titleLabel.text = track?.title
        artistLabel.text = track?.artist
        let playing = state == .playing || state == .loading
        playButton.setImage(UIImage(systemName: playing ? "pause.fill" : "play.fill"), for: .normal)
    }

    func update(progress: PlaybackProgress) {
        progressView.progress = progress.duration > 0 ? Float(progress.position / progress.duration) : 0
    }

    @objc private func tapped() {
        onTap?()
    }

    @objc private func playPause() {
        onPlayPause?()
    }

    @objc private func nextTapped() {
        onNext?()
    }

    @objc private func previousTapped() {
        onPrevious?()
    }
}
