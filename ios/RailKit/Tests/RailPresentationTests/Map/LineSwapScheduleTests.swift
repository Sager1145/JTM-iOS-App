import RailPresentation
import Testing

struct LineSwapScheduleTests {
    @Test func theFirstStagedSetStartsAndOnlyOneRunsAtATime() {
        var schedule = LineSwapSchedule()
        #expect(schedule.stage() == .start(baseSerial: 0))
        #expect(schedule.stage() == .none)
        #expect(schedule.stage() == .none)
        #expect(schedule.inFlightBase == 0)
    }

    @Test func theNewestStagedSetStartsAfterTheLandingIsApplied() {
        var schedule = LineSwapSchedule()
        _ = schedule.stage()
        _ = schedule.stage()
        _ = schedule.stage()
        #expect(schedule.landed(baseSerial: 0, duringGesture: false) == .apply)
        // One restart for the newest set, not one per staged update.
        #expect(schedule.applied() == .start(baseSerial: 1))
        #expect(schedule.landed(baseSerial: 1, duringGesture: false) == .apply)
        #expect(schedule.applied() == .none)
        #expect(schedule.inFlightBase == nil)
    }

    @Test func everyLandingAppliesSoContinuousArrivalsCannotStarveIt() {
        var schedule = LineSwapSchedule()
        var applied = 0
        _ = schedule.stage()
        for _ in 0..<20 {
            _ = schedule.stage()
            let base = schedule.inFlightBase ?? -1
            #expect(schedule.landed(baseSerial: base, duringGesture: false) == .apply)
            _ = schedule.applied()
            applied += 1
        }
        #expect(applied == 20)
        #expect(schedule.appliedSerial == 20)
    }

    @Test func aLandingDuringAGestureIsHeldAndAppliedWhenItEnds() {
        var schedule = LineSwapSchedule()
        _ = schedule.stage()
        #expect(schedule.landed(baseSerial: 0, duringGesture: true) == .hold)
        #expect(schedule.releaseHeld())
        // A set staged while held waits: still one in flight.
        #expect(schedule.stage() == .none)
        #expect(schedule.applied() == .start(baseSerial: 1))
        #expect(!schedule.releaseHeld())
    }

    @Test func aSynchronousApplyMakesTheInFlightLandingBeDiscarded() {
        var schedule = LineSwapSchedule()
        _ = schedule.stage()
        schedule.appliedSynchronously()
        #expect(schedule.landed(baseSerial: 0, duringGesture: false) == .discard(restart: .none))
        #expect(schedule.inFlightBase == nil)
        #expect(schedule.appliedSerial == 1)
    }

    @Test func aSetStagedAfterASynchronousApplyRestartsFromTheAppliedState() {
        var schedule = LineSwapSchedule()
        _ = schedule.stage()
        schedule.appliedSynchronously()
        #expect(schedule.stage() == .none)
        #expect(schedule.landed(baseSerial: 0, duringGesture: false) == .discard(restart: .start(baseSerial: 1)))
        #expect(schedule.inFlightBase == 1)
    }

    @Test func aSynchronousApplyDropsStagedSetsAndAHeldResult() {
        var schedule = LineSwapSchedule()
        _ = schedule.stage()
        _ = schedule.stage()
        #expect(schedule.landed(baseSerial: 0, duringGesture: true) == .hold)
        schedule.appliedSynchronously()
        #expect(!schedule.releaseHeld())
        #expect(!schedule.hasUnstarted)
        #expect(schedule.inFlightBase == nil)
        #expect(schedule.stage() == .start(baseSerial: 1))
    }

    @Test func anAbandonedComputationFreesTheSlotAndRestartsAStagedSet() {
        var schedule = LineSwapSchedule()
        _ = schedule.stage()
        _ = schedule.stage()
        #expect(schedule.abandoned() == .start(baseSerial: 0))
        #expect(schedule.abandoned() == .none)
        #expect(schedule.inFlightBase == nil)
    }
}
