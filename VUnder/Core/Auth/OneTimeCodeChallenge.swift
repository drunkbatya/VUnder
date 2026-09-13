import Foundation
import os

final class OneTimeCodeChallenge: @unchecked Sendable {
    let method: String
    let failureMessage: String?
    private let sid: String
    private let anonymousToken: String
    private let endpoints: VKAuthEndpoints

    init(method: String, sid: String, anonymousToken: String, endpoints: VKAuthEndpoints, failureMessage: String? = nil) {
        self.method = method
        self.sid = sid
        self.anonymousToken = anonymousToken
        self.endpoints = endpoints
        self.failureMessage = failureMessage
    }

    var deliversAutomatically: Bool {
        method == "sms" || method == "callreset"
    }

    func failed(_ message: String) -> OneTimeCodeChallenge {
        OneTimeCodeChallenge(method: method, sid: sid, anonymousToken: anonymousToken, endpoints: endpoints, failureMessage: message)
    }

    func send() async throws -> OneTimeCodeDelivery {
        var deliveryMethod = method
        if !deliversAutomatically {
            let available = try await endpoints.verificationMethods(sid: sid, anonymousToken: anonymousToken)
            Log.auth.info("verification methods available: \(available.joined(separator: ","), privacy: .public)")
            deliveryMethod = available.contains("sms") ? "sms" : (available.contains("callreset") ? "callreset" : "sms")
        }
        let delivery = try await endpoints.sendOneTimeCode(method: deliveryMethod, sid: sid, anonymousToken: anonymousToken)
        Log.auth.info("one-time code sent via \(deliveryMethod, privacy: .public) to \(delivery.phoneMask ?? "?", privacy: .public) code_length=\(delivery.codeLength, privacy: .public)")
        return delivery
    }
}
