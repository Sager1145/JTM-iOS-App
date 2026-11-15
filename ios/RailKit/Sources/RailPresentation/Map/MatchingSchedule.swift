import Foundation

/// When trip-to-line matching starts after a change request. Pure, so the
/// debounce rules are testable on the host.
///
/// Requests closer together than ``burstWindow`` are one burst (a route load's
/// partial publishes, or regions streaming in); a burst waits for ``debounce``
/// of quiet, but never longer than ``maxWait`` from the burst's first match.
/// A load's FINAL publish has nothing more to coalesce, so it starts at once
/// (map-lock run 3, finding E: the 1.17 s debounce sat in front of the last
/// match before warm trips drew).
public enum MatchingSchedule {
    public static let burstWindow: Double = 1.5
    public static let debounce: Double = 1.0
    public static let maxWait: Double = 5.0

    public enum Start: Equatable, Sendable {
        case now
        case after(seconds: Double)
    }

    /// - Parameters:
    ///   - sinceLastRequest: seconds since the previous request, nil for the first.
    ///   - sinceBurstStart: seconds since the burst's last match started, nil for none.
    ///   - loadJustFinished: the route load finished with this publish.
    public static func decide(
        sinceLastRequest: Double?, sinceBurstStart: Double?, loadJustFinished: Bool
    ) -> Start {
        if loadJustFinished { return .now }
        guard let sinceLastRequest, sinceLastRequest < burstWindow else { return .now }
        let remaining = maxWait - (sinceBurstStart ?? 0)
        return .after(seconds: max(0, min(debounce, remaining)))
    }
}
