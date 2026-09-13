import Foundation

struct WebValidationOutcome {
    let accessToken: String?
    let secret: String?
    let userID: Int64?
}

@MainActor
protocol AuthInteraction: AnyObject {
    func requestOneTimeCode(_ challenge: OneTimeCodeChallenge) async throws -> String
    func requestPassword(login: String) async throws -> String
    func requestCaptcha(imageURL: URL) async throws -> String
    func requestWebValidation(url: URL) async throws -> WebValidationOutcome
}
