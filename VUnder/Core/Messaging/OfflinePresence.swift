import Foundation
import os

@MainActor
final class OfflinePresence {
    private let api: MessagesAPI
    private var pending: Task<Void, Never>?

    init(api: MessagesAPI) {
        self.api = api
    }

    func scheduleSetOffline() {
        pending?.cancel()
        pending = Task { [api] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            do {
                try await api.setOffline()
            } catch {
                Log.messages.error("set offline failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
