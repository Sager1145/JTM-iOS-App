import Foundation

/// When one route load may apply its partial ride lists to the map.
///
/// The first non-empty partial applies at once, so a cold launch still shows
/// its first journeys immediately. Later ones within ``interval`` replace each
/// other and the newest is applied when it ends. An empty partial never counts:
/// it applies nothing and must not use up the apply-at-once slot. A partial
/// marked `immediate` (the selected trip's first solved route) bypasses the
/// interval. The clock is passed in so the rule is testable.
public struct PartialPublicationThrottle: Sendable {
    public static let interval: Duration = .seconds(5)

    public enum Action: Equatable, Sendable {
        /// Nothing to apply; no state changes.
        case skip
        /// Apply this partial now (any held one is dropped).
        case applyNow
        /// Hold it and apply the newest held one after this long.
        case scheduleFlush(after: Duration)
        /// A flush is already scheduled: just replace the held partial.
        case replacePending
    }

    private var lastApplied: Duration?
    private var flushScheduled = false

    public init() {}

    public mutating func offer(isEmpty: Bool, immediate: Bool, now: Duration) -> Action {
        if isEmpty { return .skip }
        if immediate || (!flushScheduled && lastApplied.map({ now - $0 >= Self.interval }) ?? true) {
            lastApplied = now
            flushScheduled = false
            return .applyNow
        }
        if flushScheduled { return .replacePending }
        flushScheduled = true
        return .scheduleFlush(after: Self.interval - (now - (lastApplied ?? now)))
    }

    /// The held partial was applied (flush or explicit apply-pending).
    public mutating func appliedPending(now: Duration) {
        lastApplied = now
        flushScheduled = false
    }

    /// The held partial was dropped.
    public mutating func cancelPending() { flushScheduled = false }
}
