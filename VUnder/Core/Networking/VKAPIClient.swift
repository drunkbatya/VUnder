import Foundation
import os

actor VKAPIClient {
    private let urlSession: URLSession
    private let store: SessionStore
    private var refreshTask: Task<String, Error>?
    private weak var challengeHandler: VKAPIChallengeHandling?

    init(urlSession: URLSession, store: SessionStore) {
        self.urlSession = urlSession
        self.store = store
    }

    func setChallengeHandler(_ handler: VKAPIChallengeHandling?) {
        challengeHandler = handler
    }

    func call(_ request: VKAPIRequest) async throws -> JSONObject {
        try await call(request, captcha: nil, retriedAfterRefresh: false)
    }

    func response(_ request: VKAPIRequest) async throws -> JSONObject {
        let json = try await call(request)
        guard let response = json.object("response") else {
            throw VKAPIError.malformedResponse(method: request.method)
        }
        return response
    }

    func decode<T: Decodable>(_ type: T.Type, from request: VKAPIRequest) async throws -> T {
        let json = try await call(request)
        guard let response = json.raw["response"] else {
            throw VKAPIError.malformedResponse(method: request.method)
        }
        let data = try JSONSerialization.data(withJSONObject: response, options: [.fragmentsAllowed])
        return try JSONDecoder().decode(type, from: data)
    }

    private func call(_ request: VKAPIRequest, captcha: (sid: String, key: String)?, retriedAfterRefresh: Bool) async throws -> JSONObject {
        let session = store.session
        var parameters: [(String, String)] = [
            ("v", request.version),
            ("lang", VKClientIdentity.language),
            ("https", "1"),
        ]
        parameters += request.parameters
        if request.includesDeviceID {
            parameters.append(("device_id", store.deviceID))
        }
        if let captcha {
            parameters.append(("captcha_sid", captcha.sid))
            parameters.append(("captcha_key", captcha.key))
        }

        var accessToken: String?
        var signingSecret: String?
        switch request.authorization {
        case .session:
            if let session {
                accessToken = session.accessToken
                signingSecret = session.exchangeToken
            } else {
                parameters.append(("api_id", VKClientIdentity.clientID))
            }
        case .token(let token):
            accessToken = token
        case .none:
            break
        }
        if let accessToken, !parameters.contains(where: { $0.0 == "access_token" }) {
            parameters.append(("access_token", accessToken))
        }
        if let signingSecret, accessToken != nil {
            parameters.append(("sig", VKAPIClient.signature(method: request.method, parameters: parameters, secret: signingSecret)))
        }

        let bearer = request.usesBearerHeader ? parameters.first(where: { $0.0 == "access_token" })?.1 : nil
        let bodyParameters = bearer == nil ? parameters : parameters.filter { $0.0 != "access_token" }

        var urlRequest = URLRequest(url: URL(string: "https://\(VKClientIdentity.apiHost)/method/\(request.method)")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(VKClientIdentity.userAgent(request.agent), forHTTPHeaderField: "User-Agent")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("new", forHTTPHeaderField: "x-vk-android-client")
        urlRequest.setValue("nowhere", forHTTPHeaderField: "x-screen")
        urlRequest.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        if let bearer {
            urlRequest.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.httpBody = FormEncoding.body(bodyParameters)

        Log.api.debug("-> \(request.method, privacy: .public) \(LogRedaction.parameters(bodyParameters), privacy: .public) bearer=\(bearer != nil, privacy: .public)")
        let startedAt = Date()
        let (data, urlResponse) = try await urlSession.data(for: urlRequest)
        let elapsed = Int(Date().timeIntervalSince(startedAt) * 1000)
        let status = (urlResponse as? HTTPURLResponse)?.statusCode ?? 0
        guard let json = JSONObject(data: data) else {
            Log.api.error("<- \(request.method, privacy: .public) http=\(status, privacy: .public) \(elapsed, privacy: .public)ms malformed body \(data.count, privacy: .public) bytes")
            throw VKAPIError.malformedResponse(method: request.method)
        }
        guard let errorJSON = json.object("error") else {
            Log.api.debug("<- \(request.method, privacy: .public) http=\(status, privacy: .public) \(elapsed, privacy: .public)ms \(data.count, privacy: .public) bytes")
            return json
        }
        let error = VKAPIErrorResponse(errorJSON)
        Log.api.error("<- \(request.method, privacy: .public) http=\(status, privacy: .public) \(elapsed, privacy: .public)ms error \(error.code, privacy: .public): \(error.message, privacy: .public)")

        if error.isExpiredToken, case .session = request.authorization, let session, !retriedAfterRefresh {
            if let current = store.session, current.accessToken != session.accessToken {
                Log.api.notice("access token already refreshed elsewhere, retrying \(request.method, privacy: .public)")
            } else {
                Log.api.notice("access token expired, refreshing before retrying \(request.method, privacy: .public)")
                _ = try await refreshAccessToken(expired: session.accessToken)
            }
            return try await call(request, captcha: captcha, retriedAfterRefresh: true)
        }
        if error.code == 14, let sid = error.captchaSID, let imageURL = error.captchaImageURL {
            Log.api.notice("captcha required for \(request.method, privacy: .public) sid=\(sid, privacy: .public)")
            guard let handler = challengeHandler else { throw VKAPIError.api(error) }
            let key = try await handler.solveCaptcha(imageURL: imageURL)
            return try await call(request, captcha: (sid, key), retriedAfterRefresh: retriedAfterRefresh)
        }
        if error.code == 17, let redirectURL = error.redirectURL {
            Log.api.notice("validation required for \(request.method, privacy: .public) url=\(redirectURL.absoluteString, privacy: .public)")
            guard let handler = challengeHandler else { throw VKAPIError.api(error) }
            try await handler.completeValidation(url: redirectURL)
            return try await call(request, captcha: captcha, retriedAfterRefresh: retriedAfterRefresh)
        }
        throw VKAPIError.api(error)
    }

    private func refreshAccessToken(expired: String) async throws -> String {
        if let refreshTask {
            return try await refreshTask.value
        }
        let task = Task<String, Error> {
            guard let session = self.store.session else { throw VKAPIError.sessionExpired }
            if session.accessToken != expired {
                return session.accessToken
            }
            do {
                let token = try await self.requestRefreshedToken(exchangeToken: session.exchangeToken)
                self.store.updateAccessToken(token)
                Log.api.notice("access token refreshed")
                return token
            } catch VKAPIError.api(let response) {
                Log.api.error("token refresh rejected \(response.code, privacy: .public): \(response.message, privacy: .public), clearing session")
                self.store.clear()
                throw VKAPIError.sessionExpired
            } catch {
                Log.api.error("token refresh failed: \(error.localizedDescription, privacy: .public), keeping session")
                throw error
            }
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func requestRefreshedToken(exchangeToken: String) async throws -> String {
        var request = VKAPIRequest.auth("auth.refreshTokens", parameters: [
            ("client_id", VKClientIdentity.clientID),
            ("client_secret", VKClientIdentity.clientSecret),
            ("exchange_tokens", exchangeToken),
            ("active_index", "0"),
            ("scope", "all"),
            ("initiator", "expired_token"),
        ])
        request.authorization = .none
        let json = try await call(request, captcha: nil, retriedAfterRefresh: true)
        let response = json.object("response")
        let success = response?.objects("success").first
        guard let token = success?.object("access_token")?.string("token"), !token.isEmpty else {
            Log.api.error("token refresh response without token: \(LogRedaction.json(json), privacy: .public) errors=\(response?.objects("errors").map(LogRedaction.json).joined(separator: "; ") ?? "none", privacy: .public)")
            throw VKAPIError.malformedResponse(method: request.method)
        }
        Log.api.info("token refresh expires_in=\(success?.object("access_token")?.int("expires_in") ?? 0, privacy: .public)")
        return token
    }

    nonisolated static func signature(method: String, parameters: [(String, String)], secret: String) -> String {
        let query = parameters.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
        return MD5.hex("/method/\(method)?\(query)\(secret)")
    }
}
