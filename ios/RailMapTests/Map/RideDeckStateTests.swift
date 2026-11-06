import Foundation
import RailCore
import Testing

@testable import RailMap

@MainActor
struct RideDeckStateTests {

    private static func ride(_ id: String, color: String) -> RiddenRouteStore.DrawnRide {
        let train = Train(
            id: id, date: "2026-01-01", number: "1", origin: "A", destination: "B",
            stops: [Stop(name: "A", departure: "10:00"), Stop(name: "B", arrival: "11:00")])
        return RiddenRouteStore.DrawnRide(
            id: id, trainType: nil, country: "jp", colorHex: color, visible: true,
            segments: [], route: .resolved, stops: train.stops,
            daySpan: Dates.daySpan(train), geometryDigest: 0)
    }

    @Test("a change to an earlier duplicate id still changes the deck digest")
    func duplicateIDChangeMovesDeckDigest() {
        let before = RideDeckState().advanced(to: [
            Self.ride("dup", color: "#111111"), Self.ride("dup", color: "#222222"),
        ]).next
        let after = before.advanced(to: [
            Self.ride("dup", color: "#333333"), Self.ride("dup", color: "#222222"),
        ])
        #expect(after.change.ambiguous)
        #expect(after.next.deckDigest != before.deckDigest)
    }

    @Test("the same deck gives the same digest")
    func sameDeckSameDigest() {
        let rides = [Self.ride("a", color: "#111111"), Self.ride("b", color: "#222222")]
        let first = RideDeckState().advanced(to: rides).next
        let second = first.advanced(to: rides)
        #expect(second.next.deckDigest == first.deckDigest)
        #expect(second.change.isEmpty)
    }
}
