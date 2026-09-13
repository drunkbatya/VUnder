import UIKit

final class PlayerViewController: UIViewController {
    var onJumpToTrack: ((Track, QueueSource) -> Void)?

    private let player: PlayerService
    private let fileInfoProvider: TrackFileInfoProvider
    private let artworkView = UIImageView()
    private let titleLabel = UILabel()
    private let artistLabel = UILabel()
    private let fileInfoLabel = UILabel()
    private var fileInfoTask: Task<Void, Never>?
    private let slider = UISlider()
    private let elapsedLabel = UILabel()
    private let remainingLabel = UILabel()
    private let playButton = UIButton(type: .system)
    private let shuffleButton = UIButton(type: .system)
    private let repeatButton = UIButton(type: .system)
    private let queueButton = UIButton(type: .system)
    private let jumpButton = UIButton(type: .system)
    private var observers: [NSObjectProtocol] = []
    private var artworkTask: Task<Void, Never>?
    private var shownTrack: Track?

    init(player: PlayerService, fileInfoProvider: TrackFileInfoProvider) {
        self.player = player
        self.fileInfoProvider = fileInfoProvider
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        buildLayout()
        observers.append(NotificationCenter.default.addObserver(forName: PlayerService.stateDidChange, object: player, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.stateChanged() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: PlayerService.progressDidChange, object: player, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.progressChanged() }
        })
        stateChanged()
        progressChanged()
    }

    private func buildLayout() {
        artworkView.contentMode = .scaleAspectFit
        artworkView.backgroundColor = Theme.groupedBackground
        artworkView.layer.cornerRadius = 8
        artworkView.clipsToBounds = true
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = Theme.text
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2
        artistLabel.font = .preferredFont(forTextStyle: .subheadline)
        artistLabel.textColor = Theme.secondaryText
        artistLabel.textAlignment = .center
        fileInfoLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        fileInfoLabel.textColor = Theme.secondaryText
        fileInfoLabel.textAlignment = .center
        for label in [elapsedLabel, remainingLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            label.textColor = Theme.secondaryText
        }
        remainingLabel.textAlignment = .right
        slider.addTarget(self, action: #selector(sliderReleased), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        slider.addTarget(self, action: #selector(sliderMoved), for: .valueChanged)

        let previousButton = UIButton(type: .system)
        previousButton.setImage(UIImage(systemName: "backward.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 28)), for: .normal)
        previousButton.addTarget(self, action: #selector(previousTapped), for: .touchUpInside)
        playButton.setImage(UIImage(systemName: "play.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 40)), for: .normal)
        playButton.addTarget(self, action: #selector(playPause), for: .touchUpInside)
        let nextButton = UIButton(type: .system)
        nextButton.setImage(UIImage(systemName: "forward.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 28)), for: .normal)
        nextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)
        for button in [previousButton, playButton, nextButton] {
            button.widthAnchor.constraint(equalToConstant: 72).isActive = true
            button.heightAnchor.constraint(equalToConstant: 72).isActive = true
        }
        shuffleButton.setImage(UIImage(systemName: "shuffle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20)), for: .normal)
        shuffleButton.addTarget(self, action: #selector(toggleShuffle), for: .touchUpInside)
        repeatButton.addTarget(self, action: #selector(cycleRepeat), for: .touchUpInside)
        queueButton.setImage(UIImage(systemName: "list.bullet", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20)), for: .normal)
        queueButton.addTarget(self, action: #selector(openQueue), for: .touchUpInside)
        jumpButton.setImage(UIImage(systemName: "arrow.turn.up.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20)), for: .normal)
        jumpButton.addTarget(self, action: #selector(jumpToTrack), for: .touchUpInside)
        for button in [shuffleButton, repeatButton, queueButton, jumpButton] {
            button.widthAnchor.constraint(equalToConstant: 56).isActive = true
            button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        }
        let modes = UIStackView(arrangedSubviews: [shuffleButton, repeatButton, queueButton, jumpButton])
        modes.spacing = 24
        let modesRow = UIView()
        modes.translatesAutoresizingMaskIntoConstraints = false
        modesRow.addSubview(modes)
        NSLayoutConstraint.activate([
            modes.centerXAnchor.constraint(equalTo: modesRow.centerXAnchor),
            modes.topAnchor.constraint(equalTo: modesRow.topAnchor),
            modes.bottomAnchor.constraint(equalTo: modesRow.bottomAnchor),
        ])

        let times = UIStackView(arrangedSubviews: [elapsedLabel, remainingLabel])
        times.distribution = .fillEqually
        let controls = UIStackView(arrangedSubviews: [previousButton, playButton, nextButton])
        controls.spacing = 24
        let controlsRow = UIView()
        controls.translatesAutoresizingMaskIntoConstraints = false
        controlsRow.addSubview(controls)
        NSLayoutConstraint.activate([
            controls.centerXAnchor.constraint(equalTo: controlsRow.centerXAnchor),
            controls.topAnchor.constraint(equalTo: controlsRow.topAnchor),
            controls.bottomAnchor.constraint(equalTo: controlsRow.bottomAnchor),
        ])
        let stack = FormControls.stack([artworkView, titleLabel, artistLabel, fileInfoLabel, slider, times, controlsRow, modesRow], spacing: 12)
        stack.setCustomSpacing(24, after: artworkView)
        stack.setCustomSpacing(4, after: titleLabel)
        stack.setCustomSpacing(4, after: artistLabel)
        stack.setCustomSpacing(24, after: fileInfoLabel)
        stack.setCustomSpacing(4, after: slider)
        stack.setCustomSpacing(24, after: times)
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 32),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            artworkView.heightAnchor.constraint(equalTo: artworkView.widthAnchor),
        ])
    }

    private func stateChanged() {
        guard let track = player.current else {
            dismiss(animated: true)
            return
        }
        titleLabel.text = track.title
        artistLabel.text = track.artist
        let symbol = player.isPlaying ? "pause.fill" : "play.fill"
        playButton.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 40)), for: .normal)
        if shownTrack != track {
            shownTrack = track
            loadArtwork(track)
            loadFileInfo(track)
        }
        shuffleButton.tintColor = player.shuffleEnabled ? Theme.accent : Theme.secondaryText
        let repeatSymbol = player.repeatMode == .one ? "repeat.1" : "repeat"
        repeatButton.setImage(UIImage(systemName: repeatSymbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 20)), for: .normal)
        repeatButton.tintColor = player.repeatMode == .off ? Theme.secondaryText : Theme.accent
        queueButton.tintColor = Theme.secondaryText
        jumpButton.tintColor = Theme.secondaryText
        jumpButton.isEnabled = player.source != nil
    }

    @objc private func openQueue() {
        present(UINavigationController(rootViewController: QueueViewController(player: player)), animated: true)
    }

    @objc private func jumpToTrack() {
        guard let track = player.current, let source = player.source else { return }
        onJumpToTrack?(track, source)
    }

    @objc private func toggleShuffle() {
        player.toggleShuffle()
    }

    @objc private func cycleRepeat() {
        player.cycleRepeatMode()
    }

    private func loadArtwork(_ track: Track) {
        artworkTask?.cancel()
        artworkView.image = UIImage(systemName: "music.note")
        guard let url = track.coverURL.flatMap(URL.init) else { return }
        artworkTask = Task { [weak self] in
            let image = await ImageLoader.shared.image(for: url)
            guard let self, !Task.isCancelled, shownTrack == track, let image else { return }
            artworkView.image = image
        }
    }

    private func loadFileInfo(_ track: Track) {
        fileInfoTask?.cancel()
        fileInfoLabel.text = " "
        fileInfoTask = Task { [weak self] in
            let info = await self?.fileInfoProvider.info(for: track)
            guard let self, !Task.isCancelled, shownTrack == track else { return }
            fileInfoLabel.text = info?.formatted ?? " "
        }
    }

    private func progressChanged() {
        guard !slider.isTracking else { return }
        let progress = player.progress
        slider.maximumValue = Float(max(progress.duration, 1))
        slider.value = Float(progress.position)
        updateTimeLabels(position: progress.position, duration: progress.duration)
    }

    private func updateTimeLabels(position: TimeInterval, duration: TimeInterval) {
        elapsedLabel.text = PlayerViewController.format(position)
        remainingLabel.text = "-" + PlayerViewController.format(max(duration - position, 0))
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    @objc private func sliderMoved() {
        updateTimeLabels(position: TimeInterval(slider.value), duration: player.progress.duration)
    }

    @objc private func sliderReleased() {
        player.seek(to: TimeInterval(slider.value))
    }

    @objc private func playPause() {
        player.togglePlayPause()
    }

    @objc private func nextTapped() {
        player.next()
    }

    @objc private func previousTapped() {
        player.previous()
    }
}
