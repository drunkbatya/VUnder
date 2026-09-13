import Foundation
import os

final class VKAuthFlow: Sendable {
    private let oauth: VKOAuthClient
    private let endpoints: VKAuthEndpoints
    private let store: SessionStore

    init(oauth: VKOAuthClient, endpoints: VKAuthEndpoints, store: SessionStore) {
        self.oauth = oauth
        self.endpoints = endpoints
        self.store = store
    }

    func signIn(login: String, interaction: AuthInteraction) async throws -> AccountProfile {
        Log.auth.info("sign in started login=\(login, privacy: .private(mask: .hash)) trusted_hash=\(self.store.trustedHash != nil, privacy: .public)")
        let anonymousToken = try await oauth.anonymousToken()
        let account = try await endpoints.validateAccount(login: login, anonymousToken: anonymousToken, trustedHash: store.trustedHash)
        Log.auth.info("account validated flow=\(account.flowName, privacy: .public) method=\(account.verificationMethod ?? "none", privacy: .public) sid=\(!account.sid.isEmpty, privacy: .public)")
        guard !account.sid.isEmpty else {
            throw AuthFailure(message: account.flowName == "need_registration" ? "Account not found: \(login)" : "Account validation failed: \(account.flowName)")
        }

        var sid = account.sid
        var codeConfirmed = false
        var canSkipPassword = false
        if let method = account.verificationMethod, !method.isEmpty, method != "password" {
            var challenge = OneTimeCodeChallenge(method: method, sid: sid, anonymousToken: anonymousToken, endpoints: endpoints)
            while true {
                let code = try await interaction.requestOneTimeCode(challenge)
                do {
                    let verification = try await endpoints.checkOneTimeCode(sid: sid, code: code, method: method, anonymousToken: anonymousToken)
                    sid = verification.sid
                    canSkipPassword = verification.canSkipPassword
                    codeConfirmed = true
                    Log.auth.info("one-time code accepted can_skip_password=\(canSkipPassword, privacy: .public)")
                    break
                } catch VKAPIError.api(let response) {
                    Log.auth.notice("one-time code rejected code=\(response.code, privacy: .public) message=\(response.message, privacy: .public)")
                    challenge = challenge.failed(response.isWrongCode ? "Wrong code" : response.message)
                }
            }
        }

        var password = ""
        if !canSkipPassword {
            password = try await interaction.requestPassword(login: login)
        }

        var grant = TokenGrant(
            kind: canSkipPassword ? .withoutPassword : (codeConfirmed ? .phoneConfirmation : .password),
            login: login,
            password: password,
            sid: sid,
            anonymousToken: anonymousToken,
            captcha: nil
        )

        Log.auth.info("requesting token grant=\(grant.kind.rawValue, privacy: .public)")
        let issued = try await requestToken(&grant, interaction: interaction)
        Log.auth.info("token issued user_id=\(issued.userID, privacy: .public) trusted_hash=\(issued.trustedHash != nil, privacy: .public)")
        if let trustedHash = issued.trustedHash {
            store.trustedHash = trustedHash
        }
        let exchangeToken = try await endpoints.exchangeToken(accessToken: issued.accessToken)
        Log.auth.info("exchange token received")
        store.session = Session(userID: issued.userID, accessToken: issued.accessToken, exchangeToken: exchangeToken)
        do {
            let profile = try await endpoints.currentProfile()
            Log.auth.info("signed in as user_id=\(profile.id, privacy: .public)")
            return profile
        } catch {
            Log.auth.error("profile request failed after sign in: \(error.localizedDescription, privacy: .public)")
            store.clear()
            throw error
        }
    }

    private func requestToken(_ grant: inout TokenGrant, interaction: AuthInteraction) async throws -> IssuedToken {
        var processingPolls = 0
        while true {
            switch try await oauth.token(grant) {
            case .issued(let token):
                return token
            case .processing:
                Log.auth.debug("token endpoint is processing, poll \(processingPolls + 1, privacy: .public)")
                processingPolls += 1
                guard processingPolls <= 120 else { throw AuthFailure(message: "Confirmation timed out") }
                try await Task.sleep(nanoseconds: 1_000_000_000)
            case .captcha(let sid, let imageURL):
                Log.auth.notice("token endpoint requires captcha sid=\(sid, privacy: .public)")
                let key = try await interaction.requestCaptcha(imageURL: imageURL)
                grant.captcha = (sid, key)
            case .validation(let url):
                Log.auth.notice("token endpoint requires validation url=\(url.absoluteString, privacy: .public)")
                let outcome = try await interaction.requestWebValidation(url: url)
                guard let accessToken = outcome.accessToken, let userID = outcome.userID else {
                    throw AuthFailure(message: "Validation cancelled")
                }
                return IssuedToken(accessToken: accessToken, userID: userID, trustedHash: nil)
            case .failure(let message):
                Log.auth.error("token endpoint failed: \(message, privacy: .public)")
                throw AuthFailure(message: message)
            }
        }
    }
}
