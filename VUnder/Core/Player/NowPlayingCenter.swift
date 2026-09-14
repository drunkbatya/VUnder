import Foundation
import MediaPlayer
import UIKit

@MainActor
final class NowPlayingCenter {
    private unowned let player: PlayerService
    private var artwork: MPMediaItemArtwork?
    private var artworkTrack: Track?
    private var artworkTask: Task<Void, Never>?

    init(player: PlayerService) {
        self.player = player
        registerCommands()
    }

    func trackDidChange() {
        artwork = nil
        artworkTask?.cancel()
        guard let track = player.current else {
            update()
            return
        }
        artworkTrack = track
        update()
        artworkTask = Task { [weak self] in
            guard let image = await ImageLoader.shared.cover(for: track), !Task.isCancelled else { return }
            guard let self, artworkTrack == track else { return }
            artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            update()
        }
    }

    func update() {
        let center = MPNowPlayingInfoCenter.default()
        guard let track = player.current else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyPlaybackDuration: player.progress.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player.progress.position,
            MPNowPlayingInfoPropertyPlaybackRate: player.state == .playing ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        center.nowPlayingInfo = info
        center.playbackState = player.state == .playing ? .playing : .paused
    }

    private func registerCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            self?.player.resume()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.player.pause()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.player.togglePlayPause()
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.player.next()
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.player.previous()
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.player.seek(to: event.positionTime)
            return .success
        }
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
    }
}
