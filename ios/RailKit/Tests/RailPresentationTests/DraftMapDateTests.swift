import Foundation
import RailCore
import RailPresentation
import Testing

@Suite("Draft map service-date alignment")
struct DraftMapDateTests {
    @Test func dateOnlyEditPublishesDistinctMapContextWithoutMovingPins() {
        let pins = [DraftStopPin(
            occurrenceID: UUID(), name: "終点", stopType: "destination",
            timeText: "25:03", dayOffset: 1, latitude: 35, longitude: 135)]
        let old = DraftMapPins.snapshot(revision: 1, pins: pins, networkRideDate: "2024-03-31")
        let new = DraftMapPins.snapshot(revision: 2, pins: pins, networkRideDate: "2024-04-01")
        #expect(old != new)
        #expect(DraftMapPins.diff(from: old, to: new).isEmpty)
        #expect(old.networkRideDate == "2024-03-31")
        #expect(new.networkRideDate == "2024-04-01")
        #expect(!RouteGraph.RailValidity.isValid(
            validFrom: nil, validTo: "2024-04-01", on: new.networkRideDate))
    }

    @Test func nextDayClockDoesNotShiftTheHistoricalNetworkDay() {
        let pin = DraftStopPin(
            occurrenceID: UUID(), name: "終点", stopType: "destination",
            timeText: "25:03", dayOffset: 1, latitude: nil, longitude: nil)
        let snapshot = DraftMapPins.snapshot(
            revision: 1, pins: [pin], networkRideDate: "2024-03-31")
        #expect(snapshot.networkRideDate == "2024-03-31")
        #expect(RouteGraph.RailValidity.isValid(
            validFrom: nil, validTo: "2024-04-01", on: snapshot.networkRideDate))
    }

    @Test func removingDraftDateRestoresCurrentNetworkPredicate() {
        let snapshot = DraftMapPins.snapshot(revision: 2, pins: [], networkRideDate: nil)
        #expect(snapshot.networkRideDate == nil)
        #expect(!RouteGraph.RailValidity.isValid(
            validFrom: nil, validTo: "2024-04-01", on: snapshot.networkRideDate))
    }
}
