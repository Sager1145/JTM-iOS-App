import Foundation
import RailPresentation
import Testing

/// JRM_FLIGHTY_UI_REFACTOR_SPEC.md §5.5, §8.4 and §8.8, as a decision table.
///
/// Every case below was reachable before this suite existed and none of them
/// was asserted: the rules lived in `RideStatusCenter.status(forTrainID:)`, a
/// method on a `@MainActor @Observable` object in the app target, which has no
/// test target under it. The three that matter most are the three that fail
/// *quietly* — each one degrades a specific, actionable state into a vaguer
/// one, and the map still draws:
///
///   * a store-wide load failure reported as `noRoute` would tell the reader
///     their journey has nothing to draw, when what actually happened is that
///     the route dataset would not load (§8.8);
///   * `unavailable(expected: 0)` reported as an unavailable route would put a
///     failure on a journey that never asked for a section;
///   * a partial solve that dropped its gap list would leave §8.4's "明確受影響
///     區間" with nothing to name.
struct RouteStatusResolverTests {

    static let gaps = [
        SectionGap(segmentIndex: 2, from: "新宿", to: "八王子"),
        SectionGap(segmentIndex: 5, from: "甲府", to: nil),
    ]

    /// The resolver's four inputs, with the three a case does not care about
    /// left at their quietest values.
    static func status(
        _ id: String = "t1",
        resolving: Set<String> = [],
        entries: [String: RouteStatusEntry] = [:],
        phase: RouteLoadPhase = .loaded
    ) -> RideRouteStatus {
        RouteStatusResolver.status(
            id: id, resolvingIDs: resolving, entries: entries, phase: phase)
    }

    // MARK: - §8.4 a rebuild in flight outranks the last solve

    @Test
    func aResolvingJourneyReportsResolvingWhateverElseIsKnown() {
        // Even with a finished, resolved entry and a loaded store: §8.4's
        // single-journey rebuild is happening now, and the recorded outcome
        // describes the solve it is replacing.
        let entries = ["t1": RouteStatusEntry(outcome: .resolved, drawnSegments: 4)]
        #expect(Self.status(resolving: ["t1"], entries: entries) == .resolving)
        #expect(Self.status(resolving: ["t1"], phase: .failed("boom")) == .resolving)
    }

    @Test
    func resolvingAnotherJourneyDoesNotAffectThisOne() {
        #expect(Self.status("t1", resolving: ["t2"], phase: .idle) == .unknown)
    }

    // MARK: - §5.5 no entry: the phase answers

    @Test
    func idleWithNoEntryIsUnknownRatherThanEmpty() {
        // Nothing has been asked yet. "No route" would be a claim about the
        // journey; "unknown" is a claim about what has been done so far.
        #expect(Self.status(phase: .idle) == .unknown)
    }

    @Test
    func loadingWithNoEntryIsStillBeingWorkedOn() {
        // Store-wide, so a journey nobody has reported on YET is not a journey
        // known to have nothing — it is one whose turn has not come.
        #expect(Self.status(phase: .loading) == .resolving)
    }

    @Test
    func loadedWithNoEntryIsNoRoute() {
        // The store finished and never reported this journey: no two adjacent
        // stops are marked ridden, so the solver was never asked.
        #expect(Self.status(phase: .loaded) == .noRoute)
    }

    /// §8.8 — the rule that is easiest to get backwards.
    @Test
    func aFailedStoreIsUnavailableWithItsMessageAndNeverNoRoute() {
        let status = Self.status(phase: .failed("route pack 404"))
        #expect(status == .unavailable(expected: 0, reason: "route pack 404"))
        // The distinction the rule exists for: a dataset that would not load
        // is not evidence about this journey's stops.
        #expect(status != .noRoute)
    }

    // MARK: - §5.5 an entry answers, and outranks the phase

    @Test
    func anEntryIsReadEvenWhileTheStoreReportsFailure() {
        // This journey solved before the store-wide failure; that solve is
        // still the truth about it.
        let entries = ["t1": RouteStatusEntry(outcome: .resolved, drawnSegments: 3)]
        #expect(Self.status(entries: entries, phase: .failed("later")) == .resolved(sections: 3))
    }

    @Test
    func resolvedCarriesItsDrawnSegmentCount() {
        let entries = ["t1": RouteStatusEntry(outcome: .resolved, drawnSegments: 6)]
        #expect(Self.status(entries: entries) == .resolved(sections: 6))
    }

    @Test
    func aResolvedRouteNeverReportsZeroSections() {
        // `max(drawnSegments, 1)`: a whole route drawn as "0 sections" reads
        // as a failure in the interface, which is the opposite of what
        // `.resolved` means.
        let entries = ["t1": RouteStatusEntry(outcome: .resolved, drawnSegments: 0)]
        #expect(Self.status(entries: entries) == .resolved(sections: 1))
    }

    /// §8.4 — the gaps travel all the way to the screen.
    @Test
    func partialKeepsEveryGapItWasGiven() {
        let entries = [
            "t1": RouteStatusEntry(
                outcome: .partial(solved: 4, expected: 6, unsolved: Self.gaps),
                drawnSegments: 4)
        ]
        #expect(
            Self.status(entries: entries)
                == .needsReview(solved: 4, expected: 6, gaps: Self.gaps))
    }

    @Test
    func unavailableExpectingNothingIsNoRoute() {
        // `expected == 0` is the store's spelling for "this journey asked for
        // nothing" — `solveMissing` skips a train whose canonical section list
        // is empty. Reporting that as a failed route puts a warning on a
        // journey where nothing went wrong.
        let entries = ["t1": RouteStatusEntry(outcome: .unavailable(expected: 0), drawnSegments: 0)]
        #expect(Self.status(entries: entries) == .noRoute)
    }

    @Test
    func unavailableExpectingSectionsIsAFailureWithNoRecordedReason() {
        // `reason: nil` is deliberate: the solver found no path, which the
        // card explains in the catalog's own words rather than from a value.
        let entries = ["t1": RouteStatusEntry(outcome: .unavailable(expected: 3), drawnSegments: 0)]
        #expect(Self.status(entries: entries) == .unavailable(expected: 3, reason: nil))
    }

    // MARK: - §5.6 / §8.4 what the states let a surface do

    @Test
    func onlyAWholeRouteMayBePlayedBack() {
        // Starting playback or a video export over a route that is not whole
        // would be a claim the data does not support.
        #expect(RideRouteStatus.resolved(sections: 2).blocksPlayback == false)
        for status: RideRouteStatus in [
            .unknown, .resolving, .noRoute,
            .needsReview(solved: 1, expected: 2, gaps: Self.gaps),
            .unavailable(expected: 2, reason: nil),
        ] {
            #expect(status.blocksPlayback, "\(status) must not be playable")
        }
    }

    @Test
    func successIsNotAPermanentBadge() {
        #expect(RideRouteStatus.resolved(sections: 2).isNoteworthy == false)
        #expect(RideRouteStatus.noRoute.isNoteworthy)
        #expect(RideRouteStatus.unavailable(expected: 1, reason: nil).isNoteworthy)
    }

    // MARK: - §11.1 the bridge to the display tier

    @Test
    func partialCollapsesToASolvedOverExpectedReasonWhenNoneIsGiven() {
        let status = RideRouteStatus.needsReview(solved: 4, expected: 6, gaps: Self.gaps)
        #expect(status.journeyRouteState() == .needsReview(reason: "4/6"))
        // An explicit reason wins — the caller has better words than a ratio.
        #expect(
            status.journeyRouteState(reason: "甲府—小淵沢")
                == .needsReview(reason: "甲府—小淵沢"))
    }

    @Test
    func anUnavailableRouteCarriesItsRecordedFailureAcross() {
        let status = RideRouteStatus.unavailable(expected: 0, reason: "route pack 404")
        #expect(status.journeyRouteState() == .unavailable(reason: "route pack 404"))
    }

    @Test
    func theOtherThreeStatesMapOneToOne() {
        #expect(RideRouteStatus.unknown.journeyRouteState() == .unknown)
        #expect(
            RideRouteStatus.resolving.journeyRouteState()
                == .resolving(completed: nil, total: nil))
        #expect(RideRouteStatus.resolved(sections: 9).journeyRouteState() == .resolved)
        // §5.5 keeps `noRoute` apart from `unavailable`, but §11.1's shape has
        // no fifth case: it arrives as an unavailable route with no reason.
        #expect(RideRouteStatus.noRoute.journeyRouteState() == .unavailable(reason: ""))
    }
}
