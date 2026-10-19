/// Orders persistence operations across suspension points. A failed operation
/// reports to its caller without preventing the next operation from running.
/// RideLibrary owns snapshot coalescing and result publication; this queue owns
/// only execution order, including reads, backups, restores and deletions.
@MainActor
final class RidePersistenceQueue {
    private var tail: Task<Void, Never>?

    @discardableResult
    func enqueue<Value: Sendable>(
        _ work: @escaping @Sendable () async throws -> Value
    ) -> Task<Value, Error> {
        let previous = tail
        let operation = Task<Value, Error> {
            await previous?.value
            return try await work()
        }
        tail = Task { _ = await operation.result }
        return operation
    }
}
