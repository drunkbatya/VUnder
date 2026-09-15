import Foundation

enum Peer {
    static let chatBase: Int64 = 2_000_000_000

    static func isChat(_ peerID: Int64) -> Bool {
        peerID >= chatBase
    }

    static func isGroup(_ peerID: Int64) -> Bool {
        peerID < 0
    }
}
