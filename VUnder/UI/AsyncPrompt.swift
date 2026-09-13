import Foundation

@MainActor
final class AsyncPrompt<Value> {
    private var continuation: CheckedContinuation<Value, Error>?

    func wait() async throws -> Value {
        cancel()
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func fulfill(_ value: Value) {
        continuation?.resume(returning: value)
        continuation = nil
    }

    func fail(_ error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func cancel() {
        fail(CancellationError())
    }

    var isWaiting: Bool {
        continuation != nil
    }
}
