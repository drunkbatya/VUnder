import Foundation

@MainActor
protocol VKAPIChallengeHandling: AnyObject, Sendable {
    func solveCaptcha(imageURL: URL) async throws -> String
    func completeValidation(url: URL) async throws
}
