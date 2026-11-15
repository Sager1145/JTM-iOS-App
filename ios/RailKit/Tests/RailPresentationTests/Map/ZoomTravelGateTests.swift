import Testing
import RailPresentation

@Suite("ZoomTravelGate")
struct ZoomTravelGateTests {
    @Test func travellingWindowStaysBelowTheSettleTimer() {
        #expect(ZoomTravel.travellingWindow < 0.12)
    }

    @Test func travellingOnlyWhileTheLastZoomChangeIsFresh() {
        var t = ZoomTravel()
        #expect(!t.isTravelling(at: 0))
        t.note(zoom: 10, at: 0)
        t.note(zoom: 9.9, at: 0.05)
        #expect(t.isTravelling(at: 0.05))
        #expect(t.isTravelling(at: 0.14))
        #expect(!t.isTravelling(at: 0.16))
        #expect(!t.isTravelling(at: 0.5))
    }

    @Test func noiseIsNotTravel() {
        var t = ZoomTravel()
        t.note(zoom: 10, at: 0)
        t.note(zoom: 10.0004, at: 0.05)
        #expect(!t.isTravelling(at: 0.05))
    }

    @Test func stoppedCancelsAnotherLevelEvenWhenInstalledDoesNotCoverView() {
        #expect(!GeometryPreparationGate.inFlightCanInstall(
            rectCoversView: true, stopped: true, isRequestedLevel: false))
        #expect(GeometryPreparationGate.inFlightCanInstall(
            rectCoversView: true, stopped: false, isRequestedLevel: false))
    }
}
