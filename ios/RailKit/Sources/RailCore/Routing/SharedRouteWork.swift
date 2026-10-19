import Foundation

/// Shares cold work for identical keys and retains a bounded LRU of successful values.
///
/// Keys must include every input that changes the result, including resource generation.
/// The owner's operation should acquire `RouteSolveLimiter` inside this call: subscribers
/// must join before acquiring a permit. Cancellation detaches one subscriber immediately;
/// the producer is cancelled only when its last subscriber leaves (or `clear()` is called).
/// A cancelled producer may still wind down while a replacement waits for its permit.
public actor SharedRouteWork<Key: Hashable & Sendable, Value: Sendable> {
    public struct Snapshot: Sendable, Equatable {
        public let inFlightCount: Int
        public let subscriberCount: Int
        public let cachedEntryCount: Int
        public let retainedCost: Int
        public let startedOperationCount: Int
        public let joinedRequestCount: Int
        public let cacheHitCount: Int
        public let completedOperationCount: Int
    }

    // onCancel must mark cancellation synchronously, before actor delivery. This also
    // prevents a completion racing the cancellation message from caching abandoned work.
    private final class CancellationTicket: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }

        func cancel() {
            lock.lock()
            cancelled = true
            lock.unlock()
        }
    }

    private struct Subscriber {
        let ticket: CancellationTicket
        let continuation: CheckedContinuation<Value, any Error>
    }

    private struct InFlight {
        let token: UUID
        let producer: Task<Void, Never>
        var subscribers: [UUID: Subscriber]
    }

    private struct Cached {
        let value: Value
        let cost: Int
        var access: UInt64
    }

    private let maxEntries: Int
    private let maxCost: Int
    private let cost: @Sendable (Value) -> Int?
    private var inFlight: [Key: InFlight] = [:]
    private var cache: [Key: Cached] = [:]
    private var retainedCost = 0
    private var access: UInt64 = 0
    private var startedOperationCount = 0
    private var joinedRequestCount = 0
    private var cacheHitCount = 0
    private var completedOperationCount = 0

    /// `cost` returns an estimated retained cost, or nil to decline admission (for
    /// example, for an empty route). Zero capacities disable retention, not sharing.
    public init(
        maxEntries: Int,
        maxCost: Int,
        cost: @escaping @Sendable (Value) -> Int? = { _ in 1 }
    ) {
        precondition(maxEntries >= 0 && maxCost >= 0, "Cache capacities must be nonnegative")
        self.maxEntries = maxEntries
        self.maxCost = maxCost
        self.cost = cost
    }

    /// The first subscriber supplies the operation; equal concurrent keys join it.
    /// All operations supplied for one key must therefore have equivalent results.
    public nonisolated func value(
        for key: Key,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let subscriberID = UUID()
        let ticket = CancellationTicket()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let value = try await subscribe(key, id: subscriberID, ticket: ticket, operation: operation)
            try Task.checkCancellation()
            return value
        } onCancel: {
            ticket.cancel()
            Task { await self.cancelSubscriber(key, id: subscriberID) }
        }
    }

    public func snapshot() -> Snapshot {
        Snapshot(
            inFlightCount: inFlight.count,
            subscriberCount: inFlight.values.reduce(0) { $0 + $1.subscribers.count },
            cachedEntryCount: cache.count,
            retainedCost: retainedCost,
            startedOperationCount: startedOperationCount,
            joinedRequestCount: joinedRequestCount,
            cacheHitCount: cacheHitCount,
            completedOperationCount: completedOperationCount
        )
    }

    /// Drops retained values and cancels all current subscribers and producers.
    /// New requests can start immediately; old completions cannot affect them.
    /// Lifetime counters are preserved for instrumentation.
    public func clear() {
        cache.removeAll()
        retainedCost = 0
        let abandoned = inFlight
        inFlight.removeAll()
        for entry in abandoned.values {
            entry.producer.cancel()
            for subscriber in entry.subscribers.values {
                subscriber.continuation.resume(throwing: CancellationError())
            }
        }
    }

    private func subscribe(
        _ key: Key,
        id: UUID,
        ticket: CancellationTicket,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try Task.checkCancellation()
        guard !ticket.isCancelled else { throw CancellationError() }
        if var cached = cache[key] {
            access &+= 1
            cached.access = access
            cache[key] = cached
            cacheHitCount += 1
            return cached.value
        }
        return try await withCheckedThrowingContinuation { continuation in
            guard !ticket.isCancelled else {
                continuation.resume(throwing: CancellationError())
                return
            }
            let subscriber = Subscriber(ticket: ticket, continuation: continuation)
            if var entry = inFlight[key] {
                // Cancellation delivery is asynchronous. Do not attach a new request
                // to abandoned work just because its cancellation message is queued.
                let cancelledIDs = entry.subscribers.compactMap { $0.value.ticket.isCancelled ? $0.key : nil }
                for cancelledID in cancelledIDs {
                    entry.subscribers.removeValue(forKey: cancelledID)?.continuation.resume(throwing: CancellationError())
                }
                if entry.subscribers.isEmpty {
                    inFlight.removeValue(forKey: key)
                    entry.producer.cancel()
                } else {
                    entry.subscribers[id] = subscriber
                    inFlight[key] = entry
                    joinedRequestCount += 1
                    return
                }
            }
            let token = UUID()
            let producer = Task.detached(priority: Task.currentPriority) {
                let result: Result<Value, any Error>
                do {
                    try Task.checkCancellation()
                    let value = try await operation()
                    try Task.checkCancellation()
                    result = .success(value)
                } catch {
                    result = .failure(error)
                }
                await self.complete(key, token: token, result: result)
            }
            inFlight[key] = InFlight(token: token, producer: producer, subscribers: [id: subscriber])
            startedOperationCount += 1
        }
    }

    private func cancelSubscriber(_ key: Key, id: UUID) {
        guard var entry = inFlight[key], let subscriber = entry.subscribers.removeValue(forKey: id) else { return }
        if entry.subscribers.isEmpty {
            inFlight.removeValue(forKey: key)
            entry.producer.cancel()
        } else {
            inFlight[key] = entry
        }
        subscriber.continuation.resume(throwing: CancellationError())
    }

    private func complete(_ key: Key, token: UUID, result: Result<Value, any Error>) {
        completedOperationCount += 1
        guard let entry = inFlight[key], entry.token == token else { return }
        inFlight.removeValue(forKey: key)
        let interested = entry.subscribers.values.filter { !$0.ticket.isCancelled }
        if !interested.isEmpty, case let .success(value) = result {
            retain(value, for: key)
        }
        for subscriber in entry.subscribers.values {
            if subscriber.ticket.isCancelled {
                subscriber.continuation.resume(throwing: CancellationError())
            } else {
                subscriber.continuation.resume(with: result)
            }
        }
    }

    private func retain(_ value: Value, for key: Key) {
        guard maxEntries > 0, maxCost > 0, let valueCost = cost(value),
              valueCost >= 0, valueCost <= maxCost else { return }
        // Subtraction avoids overflowing when a caller supplies a very large cost.
        while cache.count >= maxEntries || retainedCost > maxCost - valueCost {
            guard let oldest = cache.min(by: { $0.value.access < $1.value.access }) else { break }
            retainedCost -= oldest.value.cost
            cache.removeValue(forKey: oldest.key)
        }
        access &+= 1
        cache[key] = Cached(value: value, cost: valueCost, access: access)
        retainedCost += valueCost
    }
}
