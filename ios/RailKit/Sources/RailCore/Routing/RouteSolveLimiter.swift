import Foundation

/// Bounds concurrent route work across stores, including work still winding down after cancellation.
public actor RouteSolveLimiter {
    // Serialize production solves across stores to prioritize memory. A permit
    // stays held until the operation exits, so cancelled work cannot overlap
    // its replacement while its graph is still in use.
    public static let shared = RouteSolveLimiter(limit: 1)

    private struct Waiter {
        let ticket: UUID
        let continuation: CheckedContinuation<Void, any Error>
    }

    private let limit: Int
    private var activeCount = 0
    private var waiters: [Waiter] = []

    public init(limit: Int) {
        precondition(limit > 0, "Route solve concurrency must be positive")
        self.limit = limit
    }

    // Internal observability also lets tests synchronize on actual queue admission.
    var queuedPermitCount: Int { waiters.count }

    /// Runs the operation outside this actor's executor and holds its permit until it exits.
    public nonisolated func withPermit<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        try await acquire()
        do {
            try Task.checkCancellation()
            let result = try await operation()
            await release()
            return result
        } catch {
            await release()
            throw error
        }
    }

    private func acquire() async throws {
        let ticket = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                if activeCount < limit {
                    activeCount += 1
                    continuation.resume()
                } else {
                    waiters.append(Waiter(ticket: ticket, continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(ticket) }
        }
    }

    private func cancelWaiter(_ ticket: UUID) {
        guard let index = waiters.firstIndex(where: { $0.ticket == ticket }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }

    private func release() {
        if waiters.isEmpty {
            activeCount -= 1
        } else {
            // Transfer the existing permit, so a cancelled running operation cannot free it early.
            waiters.removeFirst().continuation.resume()
        }
    }
}
