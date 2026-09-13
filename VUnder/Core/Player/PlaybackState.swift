import Foundation

enum PlaybackState: Equatable {
    case idle
    case loading
    case playing
    case paused
}

struct PlaybackProgress: Equatable {
    var position: TimeInterval
    var duration: TimeInterval

    static let zero = PlaybackProgress(position: 0, duration: 0)
}
