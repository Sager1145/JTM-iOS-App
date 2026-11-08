import Foundation
import RailCore
import Testing

@testable import RailMap

/// Editing a trip note must not look like a changed trip to the route store:
/// notes are drawn from the map snapshot, never from solved routes, so a
/// note save that re-solved the route would be pure cost.
struct TripNoteSolverInputTests {

    private static func train(notes: [TripNote]?) -> Train {
        var train = Train(
            id: "t", date: "2026-08-28", number: "1", origin: "A", destination: "B",
            stops: [Stop(name: "A", departure: "10:00", stopType: "origin", rideSegment: true),
                    Stop(name: "B", arrival: "11:00", stopType: "destination", rideSegment: true)],
            region: "jp")
        train.tripNotes = notes
        return train
    }

    @Test("solver input ignores trip notes")
    func notesAreNotSolverInput() {
        let note = TripNote(id: "n", category: "c", text: "t",
                            anchor: .coordinate(Coordinate(lon: 139, lat: 35)))
        let plain = Self.train(notes: nil)
        let annotated = Self.train(notes: [note])
        #expect(plain != annotated)
        #expect(RiddenRouteStore.solverInput(annotated) == plain)
        #expect(RiddenRouteStore.solverInput(plain) == plain)
    }
}
