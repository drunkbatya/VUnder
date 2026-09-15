import AVFoundation
import Foundation
import os

@MainActor
final class VoicePlayer {
    static let stateDidChange = Notification.Name("VoicePlayer.stateDidChange")

    var pauseMusic: (() -> Void)?

    private(set) var current: VoiceMessage?
    private(set) var isPlaying = false
    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?

    func toggle(_ voice: VoiceMessage) {
        if current == voice, let player {
            if isPlaying {
                player.pause()
                isPlaying = false
            } else {
                player.play()
                isPlaying = true
            }
            notify()
            return
        }
        guard let urlString = voice.mp3URL, let url = URL(string: urlString) else {
            Log.messages.error("voice \(voice.storageID, privacy: .public) has no url")
            return
        }
        stop()
        pauseMusic?()
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": VKClientIdentity.userAgent(.general)]])
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.stop() }
        }
        self.player = player
        current = voice
        isPlaying = true
        Log.messages.info("voice play \(voice.storageID, privacy: .public)")
        player.play()
        notify()
    }

    func isPlaying(_ voice: VoiceMessage) -> Bool {
        isPlaying && current == voice
    }

    func stop() {
        player?.pause()
        player = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        current = nil
        isPlaying = false
        notify()
    }

    private func notify() {
        NotificationCenter.default.post(name: VoicePlayer.stateDidChange, object: self)
    }
}
