import Foundation
import Network
import os

final class NetworkMonitor: @unchecked Sendable {
    static let didChange = Notification.Name("NetworkMonitor.didChange")

    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var connected = true
    private var expensive = false

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let isConnected = path.status == .satisfied
            lock.lock()
            let changed = connected != isConnected
            connected = isConnected
            expensive = path.isExpensive
            lock.unlock()
            if changed {
                Log.app.info("network \(isConnected ? "reachable" : "unreachable", privacy: .public)")
                NotificationCenter.default.post(name: NetworkMonitor.didChange, object: self)
            }
        }
        monitor.start(queue: DispatchQueue(label: "NetworkMonitor"))
    }

    var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return connected
    }

    var isExpensive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return expensive
    }
}

struct OfflineError: Error, LocalizedError {
    var errorDescription: String? {
        "No internet connection"
    }
}
