import UIKit

final class PlayerContainerViewController: UIViewController {
    var onJumpToTrack: ((Track, QueueSource) -> Void)?

    private let content: UIViewController
    private let player: PlayerService
    private let fileInfoProvider: TrackFileInfoProvider
    private let miniPlayer = MiniPlayerView()
    private var miniPlayerBottom: NSLayoutConstraint?
    private var observers: [NSObjectProtocol] = []

    init(content: UIViewController, player: PlayerService, fileInfoProvider: TrackFileInfoProvider) {
        self.content = content
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
        addChild(content)
        content.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content.view)
        content.didMove(toParent: self)
        miniPlayer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(miniPlayer)
        let bottom = miniPlayer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        miniPlayerBottom = bottom
        NSLayoutConstraint.activate([
            content.view.topAnchor.constraint(equalTo: view.topAnchor),
            content.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            miniPlayer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            miniPlayer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            miniPlayer.heightAnchor.constraint(equalToConstant: MiniPlayerView.height),
            bottom,
        ])
        miniPlayer.onTap = { [weak self] in self?.openPlayer() }
        miniPlayer.onPlayPause = { [weak self] in self?.player.togglePlayPause() }
        miniPlayer.onNext = { [weak self] in self?.player.next() }
        miniPlayer.onPrevious = { [weak self] in self?.player.previous() }
        observers.append(NotificationCenter.default.addObserver(forName: PlayerService.stateDidChange, object: player, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.stateChanged() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: PlayerService.progressDidChange, object: player, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.miniPlayer.update(progress: self.player.progress) }
        })
        stateChanged()
    }

    private func stateChanged() {
        let visible = player.current != nil
        miniPlayer.update(track: player.current, state: player.state)
        miniPlayer.isHidden = !visible
        content.additionalSafeAreaInsets.bottom = visible ? MiniPlayerView.height : 0
    }

    private func openPlayer() {
        guard player.current != nil else { return }
        let controller = PlayerViewController(player: player, fileInfoProvider: fileInfoProvider)
        controller.onJumpToTrack = { [weak self] track, source in
            self?.dismiss(animated: true) {
                self?.onJumpToTrack?(track, source)
            }
        }
        present(controller, animated: true)
    }
}
