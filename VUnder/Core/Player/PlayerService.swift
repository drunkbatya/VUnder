import AVFoundation
import Foundation
import os

@MainActor
final class PlayerService {
    static let stateDidChange = Notification.Name("PlayerService.stateDidChange")
    static let progressDidChange = Notification.Name("PlayerService.progressDidChange")

    private(set) var queue: [Track] = []
    private(set) var currentIndex: Int?
    private(set) var source: QueueSource?
    private var order: [Int] = []
    private(set) var state: PlaybackState = .idle
    private(set) var progress: PlaybackProgress = .zero

    var localFileURL: ((Track) -> URL?)?

    private let audioAPI: AudioAPI
    private let library: TrackLibrary
    private let settings: AppSettings
    private let network: NetworkMonitor
    private let player = AVPlayer()
    private var nowPlaying: NowPlayingCenter?
    private var statusObservation: NSKeyValueObservation?
    private var rateObservation: NSKeyValueObservation?
    private var timeObserver: Any?
    private var itemObservers: [NSObjectProtocol] = []
    private var loadTask: Task<Void, Never>?
    private var retriedFreshURL = false
    private var listenRecorded = false

    init(audioAPI: AudioAPI, library: TrackLibrary, settings: AppSettings, network: NetworkMonitor) {
        self.audioAPI = audioAPI
        self.library = library
        self.settings = settings
        self.network = network
        player.automaticallyWaitsToMinimizeStalling = true
        nowPlaying = NowPlayingCenter(player: self)
        observePlayer()
        observeAudioSession()
    }

    var current: Track? {
        currentIndex.map { queue[$0] }
    }

    var isPlaying: Bool {
        state == .playing || state == .loading
    }

    var shuffleEnabled: Bool {
        settings.shuffle
    }

    var repeatMode: RepeatMode {
        settings.repeatMode
    }

    func play(_ track: Track, in tracks: [Track], source: QueueSource?) {
        queue = tracks
        self.source = source
        currentIndex = tracks.firstIndex(of: track) ?? 0
        rebuildOrder()
        startCurrent()
    }

    var orderedQueue: [Track] {
        order.map { queue[$0] }
    }

    var currentOrderPosition: Int? {
        orderPosition
    }

    func playQueueItem(at position: Int) {
        guard order.indices.contains(position) else { return }
        currentIndex = order[position]
        startCurrent()
    }

    func moveQueueItem(from: Int, to: Int) {
        guard order.indices.contains(from), order.indices.contains(to), from != to else { return }
        let index = order.remove(at: from)
        order.insert(index, at: to)
        Log.player.info("queue move \(from, privacy: .public) -> \(to, privacy: .public)")
        NotificationCenter.default.post(name: PlayerService.stateDidChange, object: self)
    }

    func removeQueueItem(at position: Int) {
        guard order.indices.contains(position), order[position] != currentIndex else { return }
        let removedIndex = order.remove(at: position)
        queue.remove(at: removedIndex)
        order = order.map { $0 > removedIndex ? $0 - 1 : $0 }
        if let index = currentIndex, index > removedIndex {
            currentIndex = index - 1
        }
        Log.player.info("queue remove at \(position, privacy: .public), left \(self.queue.count, privacy: .public)")
        NotificationCenter.default.post(name: PlayerService.stateDidChange, object: self)
    }

    func playNext(_ track: Track) {
        insertIntoQueue(track, afterCurrent: true)
    }

    func addToQueue(_ track: Track) {
        insertIntoQueue(track, afterCurrent: false)
    }

    private func insertIntoQueue(_ track: Track, afterCurrent: Bool) {
        guard let position = orderPosition else {
            play(track, in: [track], source: nil)
            return
        }
        if let existing = queue.firstIndex(where: { $0.isSame(as: track) }), let existingPosition = order.firstIndex(of: existing) {
            guard existing != currentIndex else { return }
            order.remove(at: existingPosition)
            let target = afterCurrent ? (order.firstIndex(of: currentIndex ?? 0) ?? 0) + 1 : order.count
            order.insert(existing, at: target)
        } else {
            queue.append(track)
            let newIndex = queue.count - 1
            order.insert(newIndex, at: afterCurrent ? position + 1 : order.count)
        }
        Log.player.info("queue \(afterCurrent ? "play next" : "add", privacy: .public) \(track.storageID, privacy: .public), size \(self.queue.count, privacy: .public)")
        NotificationCenter.default.post(name: PlayerService.stateDidChange, object: self)
    }

    func replace(_ track: Track, with replacement: Track) {
        var replaced = false
        for index in queue.indices where queue[index].isSame(as: track) {
            queue[index] = replacement
            replaced = true
        }
        guard replaced else { return }
        Log.player.info("queue replace \(track.storageID, privacy: .public) -> \(replacement.storageID, privacy: .public)")
        NotificationCenter.default.post(name: PlayerService.stateDidChange, object: self)
    }

    func toggleShuffle() {
        settings.shuffle.toggle()
        rebuildOrder()
        Log.player.info("shuffle \(self.settings.shuffle, privacy: .public)")
        NotificationCenter.default.post(name: PlayerService.stateDidChange, object: self)
    }

    func cycleRepeatMode() {
        settings.repeatMode = settings.repeatMode.next
        Log.player.info("repeat \(self.settings.repeatMode.rawValue, privacy: .public)")
        NotificationCenter.default.post(name: PlayerService.stateDidChange, object: self)
    }

    private func rebuildOrder() {
        guard !queue.isEmpty else {
            order = []
            return
        }
        let indices = Array(queue.indices)
        guard settings.shuffle, let index = currentIndex else {
            order = indices
            return
        }
        order = [index] + indices.filter { $0 != index }.shuffled()
    }

    private var orderPosition: Int? {
        currentIndex.flatMap { order.firstIndex(of: $0) }
    }

    var upcoming: Track? {
        guard let position = orderPosition, position + 1 < order.count else { return nil }
        return queue[order[position + 1]]
    }

    func togglePlayPause() {
        switch state {
        case .playing, .loading:
            pause()
        case .paused:
            resume()
        case .idle:
            if current != nil {
                startCurrent()
            }
        }
    }

    func pause() {
        player.pause()
        setState(.paused)
    }

    func resume() {
        guard player.currentItem != nil else {
            startCurrent()
            return
        }
        activateSession()
        player.play()
        setState(.playing)
    }

    func next() {
        advance(automatic: false)
    }

    private func advance(automatic: Bool) {
        guard let position = orderPosition else { return }
        if automatic, settings.repeatMode == .one {
            seek(to: 0)
            resume()
            return
        }
        var nextPosition = position + 1
        if nextPosition >= order.count {
            guard settings.repeatMode == .all else {
                Log.player.info("queue finished")
                stop()
                return
            }
            nextPosition = 0
        }
        currentIndex = order[nextPosition]
        startCurrent()
    }

    func previous() {
        guard let position = orderPosition else { return }
        if progress.position > 3 || position == 0 {
            seek(to: 0)
            return
        }
        currentIndex = order[position - 1]
        startCurrent()
    }

    func seek(to position: TimeInterval) {
        let time = CMTime(seconds: position, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        progress.position = position
        NotificationCenter.default.post(name: PlayerService.progressDidChange, object: self)
        nowPlaying?.update()
    }

    func stop() {
        loadTask?.cancel()
        player.pause()
        player.replaceCurrentItem(with: nil)
        progress = .zero
        setState(.idle)
    }

    private func startCurrent() {
        guard let track = current else { return }
        loadTask?.cancel()
        retriedFreshURL = false
        listenRecorded = false
        progress = PlaybackProgress(position: 0, duration: TimeInterval(track.duration))
        setState(.loading)
        Log.player.info("start \(track.fullID, privacy: .public) \(track.artist, privacy: .public) - \(track.title, privacy: .public)")
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let url = try await resolveURL(for: track)
                guard !Task.isCancelled, current == track else { return }
                guard let url else {
                    Log.player.error("no url for \(track.fullID, privacy: .public), skipping")
                    next()
                    return
                }
                load(url: url, for: track)
            } catch {
                guard !Task.isCancelled else { return }
                Log.player.error("url resolve failed for \(track.fullID, privacy: .public): \(error.localizedDescription, privacy: .public)")
                if error is OfflineError {
                    nextCached()
                } else {
                    setState(.paused)
                }
            }
        }
    }

    private func nextCached() {
        guard let position = orderPosition, let locator = localFileURL else {
            stop()
            return
        }
        guard let nextIndex = order.dropFirst(position + 1).first(where: { locator(queue[$0]) != nil }) else {
            Log.player.info("no cached tracks ahead in queue, stopping")
            stop()
            return
        }
        Log.player.info("offline, skipping to cached track at \(nextIndex, privacy: .public)")
        currentIndex = nextIndex
        startCurrent()
    }

    private func resolveURL(for track: Track) async throws -> URL? {
        if let local = localFileURL?(track) {
            Log.player.info("playing local file for \(track.fullID, privacy: .public)")
            return local
        }
        guard network.isConnected else {
            throw OfflineError()
        }
        if let url = track.url, let remote = URL(string: url) {
            return remote
        }
        retriedFreshURL = true
        return try await audioAPI.freshURL(for: track).flatMap(URL.init)
    }

    private func load(url: URL, for track: Track) {
        let asset: AVURLAsset
        if url.isFileURL {
            asset = AVURLAsset(url: url)
        } else {
            asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": VKClientIdentity.userAgent(.general)]])
        }
        let item = AVPlayerItem(asset: asset)
        observe(item: item, track: track)
        activateSession()
        player.replaceCurrentItem(with: item)
        player.play()
        nowPlaying?.trackDidChange()
    }

    private func observe(item: AVPlayerItem, track: Track) {
        itemObservers.forEach(NotificationCenter.default.removeObserver)
        itemObservers = []
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                self?.itemStatusChanged(item, track: track)
            }
        }
        itemObservers.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                Log.player.info("finished \(track.fullID, privacy: .public)")
                self.advance(automatic: true)
            }
        })
        itemObservers.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] notification in
            guard let self else { return }
            MainActor.assumeIsolated {
                let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                self.playbackFailed(track: track, error: error)
            }
        })
    }

    private func itemStatusChanged(_ item: AVPlayerItem, track: Track) {
        guard current == track else { return }
        switch item.status {
        case .readyToPlay:
            let duration = item.duration.seconds
            if duration.isFinite, duration > 0 {
                progress.duration = duration
            }
            Log.player.info("ready \(track.fullID, privacy: .public) duration=\(Int(self.progress.duration), privacy: .public)")
            nowPlaying?.update()
        case .failed:
            playbackFailed(track: track, error: item.error)
        default:
            break
        }
    }

    private func playbackFailed(track: Track, error: Error?) {
        Log.player.error("playback failed \(track.fullID, privacy: .public): \(error?.localizedDescription ?? "unknown", privacy: .public)")
        guard network.isConnected else {
            nextCached()
            return
        }
        guard !retriedFreshURL else {
            next()
            return
        }
        retriedFreshURL = true
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                guard let url = try await audioAPI.freshURL(for: track).flatMap(URL.init), !Task.isCancelled, current == track else {
                    next()
                    return
                }
                load(url: url, for: track)
            } catch {
                guard !Task.isCancelled else { return }
                setState(.paused)
            }
        }
    }

    private func observePlayer() {
        rateObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                guard let self, current != nil else { return }
                switch player.timeControlStatus {
                case .playing:
                    setState(.playing)
                    recordListenIfNeeded()
                case .waitingToPlayAtSpecifiedRate:
                    setState(.loading)
                case .paused:
                    if state == .playing {
                        setState(.paused)
                    }
                @unknown default:
                    break
                }
            }
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, time.seconds.isFinite else { return }
                self.progress.position = time.seconds
                NotificationCenter.default.post(name: PlayerService.progressDidChange, object: self)
            }
        }
    }

    private func observeAudioSession() {
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.handleInterruption(notification)
            }
        }
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            guard let self else { return }
            MainActor.assumeIsolated {
                let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap { AVAudioSession.RouteChangeReason(rawValue: $0) }
                if reason == .oldDeviceUnavailable, self.isPlaying {
                    Log.player.info("audio route lost, pausing")
                    self.pause()
                }
            }
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        switch type {
        case .began:
            Log.player.info("audio interruption began")
            if isPlaying {
                pause()
            }
        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            Log.player.info("audio interruption ended resume=\(options.contains(.shouldResume), privacy: .public)")
            if options.contains(.shouldResume), state == .paused {
                resume()
            }
        @unknown default:
            break
        }
    }

    private func activateSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            Log.player.error("audio session activation failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func recordListenIfNeeded() {
        guard !listenRecorded, let track = current, settings.historyEnabled else { return }
        listenRecorded = true
        Task { [library] in
            do {
                try await library.recordListen(track)
            } catch {
                Log.player.error("listen record failed for \(track.fullID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func setState(_ newState: PlaybackState) {
        guard state != newState else { return }
        state = newState
        NotificationCenter.default.post(name: PlayerService.stateDidChange, object: self)
        nowPlaying?.update()
    }
}
