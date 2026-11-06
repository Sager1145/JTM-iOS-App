#if DEBUG
import Foundation
import os

/// DEBUG-only, in-process copy of the app's signpost intervals.
///
/// Not a second timing system: it is fed by the same `begin`/`end` pairs
/// (`RailSignpost` in the app, `graph.build` here) that write to Instruments.
/// While inactive, `begin` is one lock-free load and returns `nil`, so the
/// instrumented code pays nothing extra. The developer panel and the test
/// control channel activate it to show recent durations.
public final class SignpostRecorder: @unchecked Sendable {
    public static let shared = SignpostRecorder(
        active: ProcessInfo.processInfo.environment["RAILMAP_SIGNPOST_RECORDER"] == "1")

    public struct Token: Sendable {
        let name: StaticString
        let start: ContinuousClock.Instant
    }

    public struct Entry: Sendable, Equatable {
        public var name: String
        public var milliseconds: Double
        public var endedAt: Date
    }

    public struct Aggregate: Sendable, Equatable {
        public var name: String
        public var count: Int
        public var lastMs: Double
        public var maxMs: Double
        public var totalMs: Double
        public var meanMs: Double { count == 0 ? 0 : totalMs / Double(count) }
    }

    private struct Storage {
        var entries: [Entry] = []
        var next = 0
        var aggregates: [String: Aggregate] = [:]
    }

    public let capacity: Int
    private let flag: OSAllocatedUnfairLock<Bool>
    private let storage = OSAllocatedUnfairLock(initialState: Storage())

    public init(active: Bool = false, capacity: Int = 400) {
        self.capacity = capacity
        flag = OSAllocatedUnfairLock(initialState: active)
    }

    public var isActive: Bool {
        get { flag.withLock { $0 } }
        set { flag.withLock { $0 = newValue } }
    }

    @inline(__always)
    public func begin(_ name: StaticString) -> Token? {
        guard isActive else { return nil }
        return Token(name: name, start: .now)
    }

    @inline(__always)
    public func end(_ token: Token?) {
        guard let token else { return }
        let elapsed = ContinuousClock.now - token.start
        let ms = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
        record(name: token.name.description, milliseconds: ms)
    }

    public func record(name: String, milliseconds: Double, at date: Date = Date()) {
        let entry = Entry(name: name, milliseconds: milliseconds, endedAt: date)
        storage.withLock { state in
            if state.entries.count < capacity {
                state.entries.append(entry)
            } else {
                state.entries[state.next] = entry
            }
            state.next = (state.next + 1) % capacity
            var aggregate = state.aggregates[name]
                ?? Aggregate(name: name, count: 0, lastMs: 0, maxMs: 0, totalMs: 0)
            aggregate.count += 1
            aggregate.lastMs = milliseconds
            aggregate.maxMs = max(aggregate.maxMs, milliseconds)
            aggregate.totalMs += milliseconds
            state.aggregates[name] = aggregate
        }
    }

    /// Newest first.
    public func recent(_ limit: Int = 50) -> [Entry] {
        storage.withLock { state in
            let ordered: [Entry]
            if state.entries.count < capacity {
                ordered = state.entries
            } else {
                ordered = Array(state.entries[state.next...] + state.entries[..<state.next])
            }
            return Array(ordered.suffix(limit).reversed())
        }
    }

    /// By name, most frequent first.
    public func aggregates() -> [Aggregate] {
        storage.withLock { Array($0.aggregates.values) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
    }

    public func aggregate(named name: String) -> Aggregate? {
        storage.withLock { $0.aggregates[name] }
    }

    public func reset() {
        storage.withLock { $0 = Storage() }
    }
}
#endif
