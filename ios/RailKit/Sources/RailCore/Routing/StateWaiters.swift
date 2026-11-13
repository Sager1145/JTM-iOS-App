import Foundation

/// Internal observability for actors: callers await the state transition that
/// satisfies a condition instead of polling, so a wait ends exactly when the
/// owning actor publishes the matching state, however loaded the scheduler is.
///
/// The owner keeps this in its isolated state, calls `add` synchronously inside
/// `withCheckedThrowingContinuation` from an isolated method, calls `publish` after
/// every mutation a condition can observe, and forwards cancellation to `cancel`
/// through a `Task` hop. That hop runs after `add` on the same actor, so a
/// cancellation can never be delivered before its waiter is registered.
struct StateWaiters<State> {
    private struct Waiter {
        let condition: @Sendable (State) -> Bool
        let continuation: CheckedContinuation<Void, any Error>
    }

    private var pending: [UUID: Waiter] = [:]

    /// Resumes at once when `current` already satisfies the condition; otherwise parks it.
    mutating func add(
        _ id: UUID,
        current: State,
        condition: @escaping @Sendable (State) -> Bool,
        continuation: CheckedContinuation<Void, any Error>
    ) {
        if condition(current) {
            continuation.resume()
        } else {
            pending[id] = Waiter(condition: condition, continuation: continuation)
        }
    }

    /// A no-op when the waiter was already resumed.
    mutating func cancel(_ id: UUID) {
        pending.removeValue(forKey: id)?.continuation.resume(throwing: CancellationError())
    }

    mutating func publish(_ state: State) {
        guard !pending.isEmpty else { return }
        for (id, waiter) in pending where waiter.condition(state) {
            pending.removeValue(forKey: id)
            waiter.continuation.resume()
        }
    }
}
