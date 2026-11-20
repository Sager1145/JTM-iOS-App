import Foundation

/// Caps how often an opacity fade may invalidate renderers. Every alpha write
/// to a raster renderer redraws its visible tiles, so a fade on a 120 Hz
/// display costs twice what it does at 60 Hz for no visible gain. The display
/// link also asks for at most 60 Hz; this rule is the guarantee when the
/// system ignores that request. A fade's start and end are computed from
/// timestamps, so a skipped tick delays nothing by more than one 60 Hz frame.
public struct FadeTickThrottle: Equatable, Sendable {
    public static let maximumRate: Double = 60
    /// Display-link timestamps jitter; this much slack keeps true 60 Hz
    /// ticks (16.67 ms apart) from being dropped.
    public static let jitterSlack: TimeInterval = 0.001
    public static var minimumInterval: TimeInterval { 1 / maximumRate - jitterSlack }

    private var lastAdmitted: TimeInterval?

    public init() {}

    /// True when a tick at `timestamp` should invalidate renderers.
    public mutating func admit(_ timestamp: TimeInterval) -> Bool {
        if let last = lastAdmitted, timestamp - last < Self.minimumInterval { return false }
        lastAdmitted = timestamp
        return true
    }

    /// Forget the last tick, so the next fade's first tick is admitted.
    public mutating func reset() { lastAdmitted = nil }
}
