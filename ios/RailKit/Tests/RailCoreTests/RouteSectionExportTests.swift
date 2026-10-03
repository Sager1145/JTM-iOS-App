import Foundation
import Testing
@testable import RailCore

struct RouteSectionExportTests {
    private func train(_ codes: [String], _ sections: [RouteSection]) -> Train {
        Train(id: "boundary_export", date: "2026-07-27", number: "Test", origin: codes.first!,
              destination: codes.last!, routeSections: sections,
              stops: codes.enumerated().map { index, code in
                  Stop(name: code, n02StationCode: code, arrival: index == codes.count - 1 ? "10:30" : nil,
                       departure: index == 0 ? "10:00" : nil,
                       stopType: index == 0 ? "origin" : index == codes.count - 1 ? "destination" : "passenger_stop")
              })
    }
    private func section(_ from: String, _ to: String, _ line: String = "source") -> RouteSection {
        RouteSection(from: from, to: to, fromN02StationCode: from, toN02StationCode: to,
                     lineNames: [line], operatorNames: ["JR東日本"], lineIDs: [line],
                     sectionCodes: [line + "@" + [from, to].sorted().joined(separator: ":")])
    }
    private func reopen(_ train: Train) throws -> Train {
        let saved = TrainValidation.normalizeExportTrain(train)
        let bytes = try JSONEncoder().encode(saved)
        let disk = try JSONDecoder().decode(Train.self, from: bytes)
        return try TrainValidation.normalizeImportedTrain(StoreOperations.json(disk))
    }

    @Test("Saving and reopening preserves verified boundaries without adding passing calls")
    func sourceBoundariesRoundTrip() throws {
        let original = train(["A", "B"], [section("A", "X", "first"), section("X", "B", "second")])
        let imported = try TrainValidation.normalizeImportedTrain(StoreOperations.json(original))
        let reopened = try reopen(imported)
        #expect(reopened.stops == TrainValidation.normalizeExportTrain(imported).stops)
        #expect(reopened.stops.map(\.name) == ["A", "B"])
        #expect(reopened.routeSections == original.routeSections)
        #expect(try reopen(reopened).routeSections == original.routeSections)
    }

    @Test("A complete boundary chain consumes repeated passenger visits separately")
    func repeatedVisits() throws {
        let original = train(["A", "P", "A", "B"], [section("A", "X"), section("X", "P"),
            section("P", "Y"), section("Y", "A"), section("A", "B")])
        #expect(try reopen(original).routeSections == original.routeSections)
        let skipped = train(["A", "P", "P", "B"], [section("A", "X"), section("X", "P"), section("P", "B")])
        #expect(TrainValidation.normalizeExportTrain(skipped).routeSections?.count == 3)
        #expect(TrainValidation.normalizeExportTrain(skipped).routeSections?.first?.lineIDs == nil)
    }

    @Test("Earlier passages of a future call or destination do not consume that recorded visit")
    func earlierNonCallPassages() throws {
        let future = train(["A", "B", "C"], [section("A", "C"), section("C", "B"), section("B", "C")])
        #expect(try reopen(future).routeSections == future.routeSections)
        let destination = train(["A", "B"], [section("A", "B"), section("B", "X"), section("X", "B")])
        #expect(try reopen(destination).routeSections == destination.routeSections)
    }

    @Test("Incomplete, discontinuous, out of order and conflicting-code chains use adjacent fallback")
    func invalidChains() {
        let cases: [([String], [RouteSection])] = [
            (["A", "P", "B"], [section("A", "X"), section("X", "B")]),
            (["A", "B"], [section("A", "X"), section("Y", "B")]),
            (["A", "P", "Q", "B"], [section("A", "Q"), section("Q", "P"), section("P", "B")]),
        ]
        for (codes, sections) in cases {
            let exported = TrainValidation.normalizeExportTrain(train(codes, sections))
            #expect(exported.routeSections?.count == codes.count - 1)
            #expect(exported.routeSections?.first?.toN02StationCode == codes[1])
        }
        var wrongIdentity = section("X", "B")
        wrongIdentity.fromN02StationCode = "different-X"
        let exported = TrainValidation.normalizeExportTrain(train(["A", "B"], [section("A", "X"), wrongIdentity]))
        #expect(exported.routeSections?.count == 1)
        #expect(exported.routeSections?.first?.lineIDs == nil)
    }

    @Test("Applying a route then undoing and saving restores source boundaries and clocks")
    func undoThenSave() throws {
        let original = RailwayRouteEditing.preparing(train(["A", "B"], [section("A", "X"), section("X", "B")]))
        let selected = [section("A", "Y"), section("Y", "B")]
        let choice = RailwayRouteChoices.Choice(lineIDs: ["source"], lineNames: ["source"],
            operatorNames: ["JR東日本"], stations: ["A", "Y", "B"].map { .init(code: $0, name: $0) },
            sectionCodes: selected.flatMap { $0.sectionCodes ?? [] }, routeSections: selected)
        let plan = try #require(RailwayRouteEditing.plan(train: original, choice: choice,
            fromVisitID: original.stops.first?.routeEditing?.visitID,
            toVisitID: original.stops.last?.routeEditing?.visitID))
        let restored = try #require(plan.undo.restore(in: plan.updatedTrain))
        let reopened = try reopen(restored)
        #expect(reopened.routeSections == original.routeSections)
        #expect(reopened.stops.map(\.name) == ["A", "B"])
        #expect(reopened.stops.first?.departure == "10:00")
        #expect(reopened.stops.last?.arrival == "10:30")
    }
}
