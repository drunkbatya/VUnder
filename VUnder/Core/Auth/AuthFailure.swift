import Foundation

struct AuthFailure: Error, LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}
