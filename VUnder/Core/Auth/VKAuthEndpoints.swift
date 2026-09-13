import Foundation

struct AccountValidation {
    let sid: String
    let flowName: String
    let verificationMethod: String?
}

struct OneTimeCodeDelivery {
    let phoneMask: String?
    let codeLength: Int
}

struct OneTimeCodeVerification {
    let sid: String
    let canSkipPassword: Bool
}

struct AccountProfile: Decodable {
    let id: Int64
    let firstName: String
    let lastName: String
    let photo: String?

    enum CodingKeys: String, CodingKey {
        case id
        case firstName = "first_name"
        case lastName = "last_name"
        case photo = "photo_100"
    }
}

final class VKAuthEndpoints: Sendable {
    private let api: VKAPIClient

    init(api: VKAPIClient) {
        self.api = api
    }

    func validateAccount(login: String, anonymousToken: String, trustedHash: String?) async throws -> AccountValidation {
        var parameters: [(String, String)] = [
            ("login", login),
            ("force_password", "0"),
            ("passkey_supported", "0"),
            ("supported_ways", "callreset,codegen,email,reserve_code,password,push,sms"),
            ("flow_type", "auth_without_password"),
            ("sak_version", "1.112"),
        ]
        if let trustedHash {
            parameters.append(("accounts_trusted_hashes", trustedHash))
        }
        let response = try await api.response(.auth("auth.validateAccount", token: anonymousToken, parameters: parameters))
        let flowName = response.string("flow_name") ?? ""
        var method = response.object("next_step")?.string("verification_method")
        if flowName == "need_password",
           response.object("next_step")?.bool("has_another_verification_methods") == true,
           response.strings("flow_names").contains("password") {
            method = "password"
        }
        return AccountValidation(sid: response.string("sid") ?? "", flowName: flowName, verificationMethod: method)
    }

    func sendOneTimeCode(method: String, sid: String, anonymousToken: String) async throws -> OneTimeCodeDelivery {
        let apiMethod = method == "callreset" ? "ecosystem.sendOtpCallReset" : "ecosystem.sendOtpSms"
        let response = try await api.response(.auth(apiMethod, token: anonymousToken, parameters: [("sid", sid)]))
        return OneTimeCodeDelivery(
            phoneMask: response.string("info"),
            codeLength: method == "callreset" ? (response.int("code_length") ?? 6) : 0
        )
    }

    func verificationMethods(sid: String, anonymousToken: String) async throws -> [String] {
        let response = try await api.response(.auth("ecosystem.getVerificationMethods", token: anonymousToken, parameters: [("sid", sid)]))
        return response.objects("methods").compactMap { $0.string("name") }
    }

    func checkOneTimeCode(sid: String, code: String, method: String, anonymousToken: String) async throws -> OneTimeCodeVerification {
        let response = try await api.response(.auth("ecosystem.checkOtp", token: anonymousToken, parameters: [
            ("sid", sid),
            ("code", code),
            ("verification_method", method),
        ]))
        guard let newSID = response.string("sid") else {
            throw VKAPIError.malformedResponse(method: "ecosystem.checkOtp")
        }
        return OneTimeCodeVerification(sid: newSID, canSkipPassword: response.bool("can_skip_password"))
    }

    func exchangeToken(accessToken: String) async throws -> String {
        let response = try await api.response(.auth("auth.getExchangeToken", token: accessToken, parameters: [
            ("create_common_token", "1"),
            ("create_tier_tokens", "0"),
        ]))
        guard let token = response.objects("users_exchange_tokens").first?.string("common_token") else {
            throw VKAPIError.malformedResponse(method: "auth.getExchangeToken")
        }
        return token
    }

    func currentProfile() async throws -> AccountProfile {
        let profiles = try await api.decode([AccountProfile].self, from: VKAPIRequest(method: "users.get", parameters: [
            ("fields", "photo_100"),
        ]))
        guard let profile = profiles.first else {
            throw VKAPIError.malformedResponse(method: "users.get")
        }
        return profile
    }
}
