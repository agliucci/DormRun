import Foundation

/// In-process fan-out so customer tracking can consume the runner's live GPS.
actor RunnerLocationHub {
    static let shared = RunnerLocationHub()

    private var latestByOrder: [String: RunnerLocation] = [:]
    private var listeners: [UUID: AsyncStream<RunnerLocation>.Continuation] = [:]

    func publish(_ location: RunnerLocation) {
        if let orderId = location.orderId {
            latestByOrder[orderId] = location
        }
        for continuation in listeners.values {
            continuation.yield(location)
        }
    }

    func stream(orderId: String) -> AsyncStream<RunnerLocation> {
        AsyncStream { continuation in
            let id = UUID()
            listeners[id] = continuation
            if let latest = latestByOrder[orderId] {
                continuation.yield(latest)
            }
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeListener(id) }
            }
        }
    }

    private func removeListener(_ id: UUID) {
        listeners[id] = nil
    }
}
