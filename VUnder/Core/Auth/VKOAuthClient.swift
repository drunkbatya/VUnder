import Foundation
import os

struct TokenGrant {
    enum Kind: String {
        case password
        case withoutPassword = "without_password"
        case phoneConfirmation = "phone_confirmation_sid"
    }

    var kind: Kind
    var login: String
    var password: String
    var sid: String
    var anonymousToken: String
    var captcha: (sid: String, key: String)?
}

final class VKOAuthClient: Sendable {
    private let urlSession: URLSession
    private let store: SessionStore

    init(store: SessionStore) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForRequest = 30
        urlSession = URLSession(configuration: configuration)
        self.store = store
    }

    func anonymousToken() async throws -> String {
        let json = try await post("get_anonym_token", parameters: [
            ("client_secret", VKClientIdentity.clientSecret),
            ("client_id", VKClientIdentity.clientID),
            ("v", VKAPIRequest.authVersion),
            ("lang", VKClientIdentity.language),
            ("https", "1"),
            ("app_id", VKClientIdentity.clientID),
            ("device_id", store.deviceID),
        ])
        if let token = json.string("token") {
            return token
        }
        throw AuthFailure(message: json.string("error_description") ?? json.string("error") ?? "anonymous token unavailable")
    }

    func token(_ grant: TokenGrant) async throws -> OAuthTokenResponse {
        var parameters: [(String, String)] = [
            ("grant_type", grant.kind.rawValue),
            ("scope", "all"),
            ("client_id", VKClientIdentity.clientID),
            ("client_secret", VKClientIdentity.clientSecret),
            ("username", grant.login),
            ("password", grant.kind == .withoutPassword ? "" : grant.password),
            ("2fa_supported", "1"),
            ("libverify_support", "1"),
            ("device_trusted_hash_support", "1"),
            ("supported_ways", "push,email"),
            ("flow_type", "tg_flow"),
            ("sak_version", "1.142"),
            ("sid", grant.sid),
            ("anonymous_token", grant.anonymousToken),
            ("v", VKAPIRequest.authVersion),
            ("https", "1"),
            ("api_id", VKClientIdentity.clientID),
            ("lang", VKClientIdentity.language),
            ("device_id", store.deviceID),
        ]
        if let captcha = grant.captcha {
            parameters.append(("captcha_sid", captcha.sid))
            parameters.append(("captcha_key", captcha.key))
        }
        return OAuthTokenResponse(try await post("token", parameters: parameters))
    }

    private func post(_ path: String, parameters: [(String, String)]) async throws -> JSONObject {
        var request = URLRequest(url: URL(string: "https://\(VKClientIdentity.oauthHost)/\(path)")!)
        request.httpMethod = "POST"
        request.setValue(VKClientIdentity.userAgent(.auth), forHTTPHeaderField: "User-Agent")
        request.setValue("new", forHTTPHeaderField: "x-vk-android-client")
        request.setValue("nowhere", forHTTPHeaderField: "x-screen")
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = FormEncoding.body(parameters)
        Log.auth.debug("-> oauth/\(path, privacy: .public) \(LogRedaction.parameters(parameters), privacy: .public)")
        let (data, urlResponse) = try await urlSession.data(for: request)
        let status = (urlResponse as? HTTPURLResponse)?.statusCode ?? 0
        guard let json = JSONObject(data: data) else {
            Log.auth.error("<- oauth/\(path, privacy: .public) http=\(status, privacy: .public) malformed body \(data.count, privacy: .public) bytes")
            throw AuthFailure(message: "malformed oauth response for \(path)")
        }
        Log.auth.debug("<- oauth/\(path, privacy: .public) http=\(status, privacy: .public) \(LogRedaction.json(json), privacy: .public)")
        return json
    }
}
