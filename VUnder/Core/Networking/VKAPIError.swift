import Foundation

struct VKAPIErrorResponse {
    let code: Int
    let message: String
    let captchaSID: String?
    let captchaImageURL: URL?
    let redirectURL: URL?

    init(_ json: JSONObject) {
        code = json.int("error_code") ?? -1
        message = json.string("error_msg") ?? json.string("error_text") ?? ""
        captchaSID = json.string("captcha_sid")
        captchaImageURL = json.string("captcha_img").flatMap(URL.init)
        redirectURL = json.string("redirect_uri").flatMap(URL.init)
    }

    var isExpiredToken: Bool {
        (code == 5 && message.contains("expired")) || code == 1117
    }

    var isWrongCode: Bool {
        (code & ~(1 << 30)) == 8
    }
}

enum VKAPIError: Error, LocalizedError {
    case api(VKAPIErrorResponse)
    case malformedResponse(method: String)
    case sessionExpired
    case challengeUnavailable

    var errorDescription: String? {
        switch self {
        case .api(let response):
            return "\(response.message) (code \(response.code))"
        case .malformedResponse(let method):
            return "Malformed response for \(method)"
        case .sessionExpired:
            return "Session expired"
        case .challengeUnavailable:
            return "Verification required but no handler is available"
        }
    }
}
