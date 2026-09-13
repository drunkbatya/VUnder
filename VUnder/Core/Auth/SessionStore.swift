import Foundation
import os
import KeychainAccess

final class SessionStore: @unchecked Sendable {
    static let sessionDidChange = Notification.Name("SessionStore.sessionDidChange")

    private enum Key {
        static let session = "session"
        static let trustedHash = "trusted_hash"
        static let deviceID = "device_id"
    }

    private let keychain: Keychain
    private let lock = NSLock()
    private var cachedSession: Session??

    init(service: String) {
        keychain = Keychain(service: service).accessibility(.afterFirstUnlock)
    }

    var session: Session? {
        get {
            lock.lock()
            defer { lock.unlock() }
            if let cached = cachedSession {
                return cached
            }
            let loaded = keychain[data: Key.session].flatMap { try? JSONDecoder().decode(Session.self, from: $0) }
            cachedSession = .some(loaded)
            return loaded
        }
        set {
            lock.lock()
            cachedSession = .some(newValue)
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                keychain[data: Key.session] = data
            } else {
                keychain[data: Key.session] = nil
            }
            lock.unlock()
            if let newValue {
                Log.session.info("session saved user_id=\(newValue.userID, privacy: .public)")
            } else {
                Log.session.info("session cleared")
            }
            NotificationCenter.default.post(name: SessionStore.sessionDidChange, object: self)
        }
    }

    var trustedHash: String? {
        get { keychain[Key.trustedHash] }
        set { keychain[Key.trustedHash] = newValue }
    }

    var deviceID: String {
        lock.lock()
        defer { lock.unlock() }
        if let existing = keychain[Key.deviceID] {
            return existing
        }
        let generated = VKClientIdentity.makeDeviceID()
        keychain[Key.deviceID] = generated
        Log.session.info("device id generated \(generated, privacy: .public)")
        return generated
    }

    func updateAccessToken(_ token: String) {
        guard var current = session else { return }
        current.accessToken = token
        session = current
    }

    func clear() {
        session = nil
        trustedHash = nil
    }
}
