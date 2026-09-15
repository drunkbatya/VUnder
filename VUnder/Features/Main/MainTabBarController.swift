import UIKit

final class MainTabBarController: UITabBarController {
    var onJumpToTrack: ((Track, QueueSource) -> Void)?
    var membership: ((Track) -> LibraryMembership)?
    var onToggleLibrary: ((Track, Bool, PlayerViewController) -> Void)?
    var onShareTrack: ((Track) -> Void)?

    private let player: PlayerService
    private let fileInfoProvider: TrackFileInfoProvider
    private let miniPlayer = MiniPlayerView()
    private var observers: [NSObjectProtocol] = []

    init(music: UIViewController, messages: UIViewController, settings: UIViewController, player: PlayerService, fileInfoProvider: TrackFileInfoProvider) {
        self.player = player
        self.fileInfoProvider = fileInfoProvider
        super.init(nibName: nil, bundle: nil)
        music.tabBarItem = UITabBarItem(title: "Music", image: UIImage(systemName: "music.note"), tag: 0)
        messages.tabBarItem = UITabBarItem(title: "Messages", image: UIImage(systemName: "bubble.left.and.bubble.right"), tag: 1)
        settings.tabBarItem = UITabBarItem(title: "Settings", image: UIImage(systemName: "gearshape"), tag: 2)
        viewControllers = [music, messages, settings]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = Theme.background
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        miniPlayer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(miniPlayer)
        NSLayoutConstraint.activate([
            miniPlayer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            miniPlayer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            miniPlayer.heightAnchor.constraint(equalToConstant: MiniPlayerView.height),
            miniPlayer.bottomAnchor.constraint(equalTo: tabBar.topAnchor),
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

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        view.bringSubviewToFront(miniPlayer)
    }

    func setMessagesBadge(_ count: Int) {
        viewControllers?[1].tabBarItem.badgeValue = count > 0 ? String(count) : nil
    }

    private func stateChanged() {
        let visible = player.current != nil
        miniPlayer.update(track: player.current, state: player.state)
        miniPlayer.isHidden = !visible
        for child in viewControllers ?? [] {
            child.additionalSafeAreaInsets.bottom = visible ? MiniPlayerView.height : 0
        }
    }

    private func openPlayer() {
        guard player.current != nil else { return }
        let controller = PlayerViewController(player: player, fileInfoProvider: fileInfoProvider)
        controller.onJumpToTrack = { [weak self] track, source in
            self?.dismiss(animated: true) {
                self?.onJumpToTrack?(track, source)
            }
        }
        controller.membership = membership
        controller.onToggleLibrary = onToggleLibrary
        controller.onShare = { [weak self] track in
            self?.dismiss(animated: true) {
                self?.onShareTrack?(track)
            }
        }
        present(controller, animated: true)
    }
}
