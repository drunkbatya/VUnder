import Foundation

struct IssuedToken {
    let accessToken: String
    let userID: Int64
    let trustedHash: String?
}

enum OAuthTokenResponse {
    case issued(IssuedToken)
    case processing
    case captcha(sid: String, imageURL: URL)
    case validation(url: URL)
    case failure(String)

    init(_ json: JSONObject) {
        if json.has("processing") {
            self = .processing
            return
        }
        if let accessToken = json.string("access_token"), let userID = json.int64("user_id") {
            self = .issued(IssuedToken(accessToken: accessToken, userID: userID, trustedHash: json.string("trusted_hash")))
            return
        }
        guard json.has("error") else {
            self = .failure("unexpected token response")
            return
        }
        let errorObject = json.object("error")
        let errorName = json.string("error") ?? ""
        let details = errorObject ?? json
        let code = errorObject?.int("error_code") ?? 0
        if code == 14 || errorName == "need_captcha",
           let sid = details.string("captcha_sid"),
           let imageURL = details.string("captcha_img").flatMap(URL.init) {
            self = .captcha(sid: sid, imageURL: imageURL)
            return
        }
        if code == 17 || errorName == "need_validation",
           let url = details.string("redirect_uri").flatMap(URL.init) {
            self = .validation(url: url)
            return
        }
        let description = json.string("error_description")
            ?? errorObject?.string("error_msg")
            ?? details.object("ban_info")?.string("message")
        self = .failure(description.map { "\(errorName.isEmpty ? "error" : errorName): \($0)" } ?? (errorName.isEmpty ? "error \(code)" : errorName))
    }
}
