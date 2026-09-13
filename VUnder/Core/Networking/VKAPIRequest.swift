import Foundation

struct VKAPIRequest {
    enum Authorization {
        case session
        case token(String)
        case none
    }

    static let defaultVersion = "5.81"
    static let authVersion = "5.272"
    static let audioVersion = "5.87"

    var method: String
    var version: String
    var agent: VKClientIdentity.AppVersion
    var authorization: Authorization
    var parameters: [(String, String)]
    var includesDeviceID: Bool

    init(
        method: String,
        version: String = VKAPIRequest.defaultVersion,
        agent: VKClientIdentity.AppVersion = .general,
        authorization: Authorization = .session,
        parameters: [(String, String)] = [],
        includesDeviceID: Bool = false
    ) {
        self.method = method
        self.version = version
        self.agent = agent
        self.authorization = authorization
        self.parameters = parameters
        self.includesDeviceID = includesDeviceID
    }

    static func auth(_ method: String, token: String? = nil, parameters: [(String, String)]) -> VKAPIRequest {
        VKAPIRequest(
            method: method,
            version: authVersion,
            agent: .auth,
            authorization: token.map { .token($0) } ?? .session,
            parameters: parameters + [("api_id", VKClientIdentity.clientID)],
            includesDeviceID: true
        )
    }

    static func audio(_ method: String, parameters: [(String, String)]) -> VKAPIRequest {
        VKAPIRequest(method: method, version: audioVersion, agent: .audio, parameters: parameters)
    }

    var usesBearerHeader: Bool {
        version == VKAPIRequest.authVersion
    }
}
