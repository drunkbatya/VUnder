import Foundation

struct Session: Codable, Equatable {
    let userID: Int64
    var accessToken: String
    var exchangeToken: String
}
