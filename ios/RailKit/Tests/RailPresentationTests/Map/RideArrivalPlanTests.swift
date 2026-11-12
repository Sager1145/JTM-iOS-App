import RailPresentation
import Testing

struct RideArrivalPlanTests {
    private func facts(
        ready: Bool = true, base: Bool = true, changed: Int = 3, ambiguous: Bool = false,
        chain: Bool = false, lines: Bool = false, selection: Bool = false,
        pending: Bool = false, inputs: Bool = false
    ) -> RideArrivalPlan.Facts {
        .init(mapReady: ready, incrementalBaseCurrent: base, changedRideCount: changed,
              changeAmbiguous: ambiguous, changedRidesNeedNetworkChain: chain,
              changedRidesMissingLines: lines, selectionChanged: selection,
              matchesPending: pending, matchedNetworkInputsChanged: inputs)
    }

    @Test func firstRidesOnAStillCameraTakeOneFullBuildThenNothingMore() {
        #expect(RideArrivalPlan.decide(facts(base: false)) == .fullRebuild)
    }

    @Test func moreRidesOnAStillCameraAddIncrementally() {
        #expect(RideArrivalPlan.decide(facts()) == .incrementalAdd)
    }

    @Test func newRidesWithoutLinesBuildOnlyTheirLinesNeverAFullRebuild() {
        #expect(RideArrivalPlan.decide(facts(lines: true)) == .prepareLinesThenIncrementalAdd)
    }

    @Test func aMissingNetworkChainIsTheOnlyRideCauseOfAFullRebuild() {
        #expect(RideArrivalPlan.decide(facts(chain: true, lines: true)) == .fullRebuild)
    }

    @Test func ridesBeforeTheMapIsReadyWaitForIt() {
        #expect(RideArrivalPlan.decide(facts(ready: false, base: false)) == .deferUntilMapReady)
        #expect(RideArrivalPlan.decide(facts(ready: false, changed: 0)) == .nothing)
    }

    @Test func aLoadCompletingWithNothingNewRebuildsNothing() {
        #expect(RideArrivalPlan.decide(facts(changed: 0)) == .nothing)
    }

    @Test func aLoadCompletingWithMatchesWaitingAppliesThemIncrementally() {
        #expect(RideArrivalPlan.decide(facts(changed: 2, pending: true)) == .incrementalAdd)
        #expect(RideArrivalPlan.decide(facts(changed: 0, pending: true, inputs: true)) == .fullRebuild)
    }

    @Test func aSelectionChangeIsNeverAnIncrementalAdd() {
        #expect(RideArrivalPlan.decide(facts(selection: true)) == .fullRebuild)
        #expect(RideArrivalPlan.decide(facts(changed: 0, selection: true)) == .fullRebuild)
    }

    @Test func anAmbiguousChangeRebuilds() {
        #expect(RideArrivalPlan.decide(facts(ambiguous: true)) == .fullRebuild)
    }

    @Test func tenPublicationsCostAtMostOneFullRebuild() {
        var base = false
        var full = 0
        for _ in 0..<10 {
            switch RideArrivalPlan.decide(facts(base: base, lines: true)) {
            case .fullRebuild: full += 1; base = true
            default: break
            }
        }
        #expect(full == 1)
    }
}
