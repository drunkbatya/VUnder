import AVFoundation
import Foundation
import os

@MainActor
final class PlayerService {
    static let stateDidChange = Notification.Name("PlayerService.stateDidChange")
    static let progressDidChange = Notification.Name("PlayerService.progressDidChange")

    private(set) var queue: [Track] = []
    private(set) var currentIndex: Int?
    private(set) var state: PlaybackState = .idle
    private(set) var progress: PlaybackProgress = .zero

    var localFileURL: ((Track) -> URL?)?

    private let audioAPI: AudioAPI
    private let library: TrackLibrary
    private let settings: AppSettings
    private let player = AVPlayer()
    private var nowPlaying: NowPlayingCenter?
    private var statusObservation: NSKeyValueObservation?
    private var rateObservation: NSKeyValueObservation?
    private var timeObserver: Any?
    private var itemObservers: [NSObjectProtocol] = []
    private var loadTask: Task<Void, Never>?
    private var retriedFreshURL = false
    private var listenRecorded = false

    init(audioAPI: AudioAPI, library: TrackLibrary, settings: AppSettings) {
        self.audioAPI = audioAPI
        self.library = library
        self.settings = settings
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

    func play(_ track: Track, in tracks: [Track]) {
        queue = tracks
        currentIndex = tracks.firstIndex(of: track) ?? 0
        startCurrent()
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
        guard let index = currentIndex else { return }
        guard index + 1 < queue.count else {
            Log.player.info("queue finished")
            stop()
            return
        }
        currentIndex = index + 1
        startCurrent()
    }

    func previous() {
        guard let index = currentIndex else { return }
        if progress.position > 3 || index == 0 {
            seek(to: 0)
            return
        }
        currentIndex = index - 1
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
                setState(.paused)
            }
        }
    }

    private func resolveURL(for track: Track) async throws -> URL? {
        if let local = localFileURL?(track) {
            Log.player.info("playing local file for \(track.fullID, privacy: .public)")
            return local
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
                self.next()
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
