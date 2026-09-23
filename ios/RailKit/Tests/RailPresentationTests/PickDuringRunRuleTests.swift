import Testing

@testable import RailPresentation

struct PickDuringRunRuleTests {

    @Test
    func withNoRunOnScreenAPickIsAPick() {
        #expect(PickDuringRunRule.resolve(runOnScreen: false, filming: false) == .proceed)
    }

    @Test
    func aPickDuringARunStopsTheRunAndKeepsThePick() {
        #expect(
            PickDuringRunRule.resolve(runOnScreen: true, filming: false)
                == .stopRunThenProceed)
    }

    @Test
    func aPickDuringAFilmIsDeclinedWhole() {
        #expect(PickDuringRunRule.resolve(runOnScreen: true, filming: true) == .decline)
    }

    @Test
    func filmingWithoutARunOnScreenDoesNotDeclineAPick() {
        // Not a reachable state — a film is a run — but the rule must not turn
        // a stale flag into a dead map.
        #expect(PickDuringRunRule.resolve(runOnScreen: false, filming: true) == .proceed)
    }
}
