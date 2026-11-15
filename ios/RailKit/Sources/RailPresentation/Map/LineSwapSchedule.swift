import Foundation

/// The bookkeeping of the map's line-set swap, which computes the next line
/// set's junction state and line inputs on a worker and applies the whole
/// set to the map in one main-actor turn.
///
/// Pure and map-free. The coordinator keeps the staged payload; this value
/// decides when a computation starts, whether a landed result applies, is held
/// for the end of a gesture, or is discarded, and counts applied sets
/// (`appliedSerial`) so a result computed from an older applied state is never
/// installed over a newer one.
public struct LineSwapSchedule: Equatable, Sendable {
    /// Number of line sets installed so far. A computation is based on one value.
    public private(set) var appliedSerial = 0
    /// The base serial of the computation in flight (running, or landed and held).
    public private(set) var inFlightBase: Int?
    /// A newer set is staged and no computation has started for it.
    public private(set) var hasUnstarted = false
    /// A result landed during a gesture and waits for it to end.
    public private(set) var isHolding = false

    public init() {}

    public enum Start: Equatable, Sendable {
        case none
        /// Start computing the newest staged set from the state at `baseSerial`.
        case start(baseSerial: Int)
    }

    public enum Landing: Equatable, Sendable {
        /// Install it now.
        case apply
        /// Keep it until ``releaseHeld()``.
        case hold
        /// Computed from a state that is no longer the applied one; drop it and
        /// (when a newer set is staged) start again from the applied state.
        case discard(restart: Start)
    }

    /// A newer line set was staged. Only one computation runs at a time; the
    /// newest staged set starts when the current one has landed.
    public mutating func stage() -> Start {
        guard inFlightBase == nil else {
            hasUnstarted = true
            return .none
        }
        hasUnstarted = false
        inFlightBase = appliedSerial
        return .start(baseSerial: appliedSerial)
    }

    /// The computation for `baseSerial` finished.
    public mutating func landed(baseSerial: Int, duringGesture: Bool) -> Landing {
        guard baseSerial == appliedSerial else {
            inFlightBase = nil
            isHolding = false
            return .discard(restart: restartIfStaged())
        }
        if duringGesture {
            isHolding = true
            return .hold
        }
        return .apply
    }

    /// The computation ended without a result (cancelled).
    public mutating func abandoned() -> Start {
        inFlightBase = nil
        isHolding = false
        return restartIfStaged()
    }

    /// The landed result was installed. Starts the newest staged set, if any.
    public mutating func applied() -> Start {
        appliedSerial += 1
        inFlightBase = nil
        isHolding = false
        return restartIfStaged()
    }

    /// The gesture ended; true when a held result waits to be installed.
    public func releaseHeld() -> Bool { isHolding }

    /// A line set was installed synchronously (era, ride-date or day change).
    /// Everything staged is superseded and a computation in flight is stale: it
    /// still occupies the worker until it lands and is then discarded.
    public mutating func appliedSynchronously() {
        appliedSerial += 1
        hasUnstarted = false
        if isHolding {
            isHolding = false
            inFlightBase = nil
        }
    }

    private mutating func restartIfStaged() -> Start {
        guard hasUnstarted else { return .none }
        hasUnstarted = false
        inFlightBase = appliedSerial
        return .start(baseSerial: appliedSerial)
    }
}
