import Foundation
import Testing
@testable import RailCore

struct PendingRouteConfirmationTests {
    private func journey(sections: [RouteSection]? = nil) -> Train {
        Train(id: "pending_ride", number: "Local", origin: "東京", destination: "品川",
              routeSections: sections,
              stops: [Stop(name: "東京", n02StationCode: "003766", departure: "10:00", rideSegment: true),
                      Stop(name: "品川", n02StationCode: "004095", arrival: "10:30", rideSegment: true)],
              region: "jp", routeConfirmation: .pending)
    }

    @Test("A pending physical route survives archive and lenient import without forced sections")
    func pendingArchiveRoundTrip() throws {
        let original = journey()
        let exported = TrainValidation.normalizeExportTrain(original)
        #expect(exported.routeSections == [])
        let disk = try JSONDecoder().decode(Train.self, from: JSONEncoder().encode(exported))
        let imported = try TrainValidation.normalizeImportedTrain(StoreOperations.json(disk))
        #expect(imported.requiresRouteConfirmation)
        #expect(imported.stops == exported.stops)
        #expect(imported.routeSections == [])
        #expect(StoreOperations.json(imported)["route_confirmation"] == .string("pending"))
        #expect(TrainValidation.routeSectionsForSolving(for: imported).isEmpty)
        #expect(TokyoConventionalRouteInference.applying(to: imported) == imported)
    }

    @Test("Pending hints are archived without being used as geometry, and legacy routes keep solving")
    func pendingHintsAndLegacyRoute() throws {
        let hint = RouteSection(from: "東京", to: "品川", fromN02StationCode: "003766",
                                toN02StationCode: "004095", lineNames: ["東海道線"])
        let pending = journey(sections: [hint])
        let exported = TrainValidation.normalizeExportTrain(pending)
        #expect(exported.routeSections == [hint])
        #expect(TrainValidation.routeSectionsForSolving(for: pending).isEmpty)
        var legacy = pending
        legacy.routeConfirmation = nil
        #expect(!legacy.requiresRouteConfirmation)
        #expect(TrainValidation.routeSectionsForSolving(for: legacy).count == 1)
        #expect(StoreOperations.json(legacy)["route_confirmation"] == nil)
        let decoded = try JSONDecoder().decode(Train.self, from: JSONEncoder().encode(legacy))
        #expect(decoded.routeConfirmation == nil)
    }

    @Test("Only a confirmed whole journey clears pending, and undo restores the prior state")
    func wholeJourneyConfirmationAndUndo() throws {
        func choice(_ codes: [String]) -> RailwayRouteChoices.Choice {
            let sections = zip(codes, codes.dropFirst()).map {
                RouteSection(from: $0, to: $1, fromN02StationCode: $0, toN02StationCode: $1,
                             lineIDs: ["line"], sectionCodes: ["line@\($0):\($1)"])
            }
            return .init(lineIDs: ["line"], lineNames: [], operatorNames: [],
                         stations: codes.map { .init(code: $0, name: $0) },
                         sectionCodes: sections.flatMap { $0.sectionCodes ?? [] }, routeSections: sections)
        }
        let original = RailwayRouteEditing.preparing(Train(
            id: "pending_span", number: "Local", origin: "A", destination: "C",
            stops: ["A", "B", "C"].map { Stop(name: $0, n02StationCode: $0, rideSegment: true) },
            routeConfirmation: .pending))
        let partial = try #require(RailwayRouteEditing.plan(train: original, choice: choice(["A", "B"])))
        #expect(partial.updatedTrain.requiresRouteConfirmation)
        let whole = try #require(RailwayRouteEditing.plan(train: original, choice: choice(["A", "B", "C"])))
        #expect(whole.updatedTrain.routeConfirmation == .confirmed)
        #expect(try #require(whole.undo.restore(in: whole.updatedTrain)).requiresRouteConfirmation)
    }

    @Test("Unknown confirmation state cannot silently become a confirmed route on import")
    func invalidStatusRejected() throws {
        let original = StoreOperations.json(journey())
        let json = TrainValidation.JSON.object(.init(original.ownKeys.map { key in
            (key, key == "route_confirmation" ? .string("unknown") : original[key]!)
        }))
        #expect(throws: (any Error).self) { try TrainValidation.normalizeImportedTrain(json) }
    }
}
