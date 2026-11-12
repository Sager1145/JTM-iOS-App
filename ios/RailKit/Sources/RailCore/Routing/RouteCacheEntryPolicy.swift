import Foundation

/// What the stored route entry for one trip says to do on a load.
///
/// A trip that cannot be solved is stored too, with its reason, under the same
/// key and resource revision as a solved one. A later launch then does not
/// solve it again; only Repair does, and Repair keeps every solved entry.
public enum RouteCacheEntryPolicy {
    public enum Decision: Equatable, Sendable {
        /// The entry has drawable geometry: use it, whatever the mode.
        case reuseSolved
        /// The entry records that the trip could not be solved: keep that answer.
        case reuseFailure
        /// No usable entry, or a failure Repair was asked to retry: solve.
        case solve
    }

    /// An entry without geometry and without a stored failure is an older or
    /// damaged file and is solved as before.
    public static func decide(
        hasDrawableSegments: Bool, storedFailure: String?, retryFailures: Bool
    ) -> Decision {
        if hasDrawableSegments { return .reuseSolved }
        guard storedFailure != nil else { return .solve }
        return retryFailures ? .solve : .reuseFailure
    }

    /// What to write after a solve.
    public enum StoreOutcome: Equatable, Sendable {
        case solved
        case failure(reason: String)
        case skip
    }

    /// A solved ride is stored. A ride without geometry is stored as a failure
    /// only when it is the solver's definite answer: no resource warning, which
    /// covers a missing timetable, a missing revision and an input that did not
    /// load in this run (all transient), so the next load retries those.
    public static func storeOutcome(
        drawnSegments: Int, hasResourceWarnings: Bool,
        expectedSections: Int, physicalGapCount: Int
    ) -> StoreOutcome {
        if drawnSegments > 0 { return .solved }
        if hasResourceWarnings { return .skip }
        return .failure(reason: failureReason(
            expectedSections: expectedSections, physicalGapCount: physicalGapCount))
    }

    /// The short reason kept beside a failed entry.
    static func failureReason(expectedSections: Int, physicalGapCount: Int) -> String {
        physicalGapCount > 0
            ? "no route: \(physicalGapCount) of \(expectedSections) sections unproven"
            : "no route: \(expectedSections) sections unsolved"
    }
}
