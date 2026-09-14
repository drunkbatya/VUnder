import Foundation

enum QueueSource: Equatable {
    case myMusic
    case search(String)
    case saved
    case listened
    case playlist(Playlist)
    case recommendations
    case similar(Track)

    var title: String {
        switch self {
        case .myMusic: return "My music"
        case .search(let query): return "Search: \(query)"
        case .saved: return "Saved"
        case .listened: return "Listened"
        case .playlist(let playlist): return playlist.title
        case .recommendations: return "Recommendations"
        case .similar(let track): return "Similar to \(track.title)"
        }
    }
}
