import Foundation
import Testing
@testable import RailCore

struct RailwayRouteInferenceTests {
    @Test("Every authored intermediate stop anchors its own shortest leg")
    func anchors() throws {
        let package = try fixture([
            line("direct", ["A", "D"], [1]),
            line("anchored", ["A", "B", "C", "D"], [1, 1, 3]),
        ])
        let choice = try #require(RailwayRouteInference.choice(in: train(["A", "C", "D"]), package: package))
        #expect(choice.stations.map(\.code) == ["A", "B", "C", "D"])
        #expect(choice.routeSections.count == 3)
        #expect(choice.sectionCodes == ["anchored@A:B", "anchored@B:C", "anchored@C:D"])
    }

    @Test("Different line families connect only through identical station codes")
    func differentFamilies() throws {
        let package = try fixture([
            line("first", ["A", "B"], [2]), line("second", ["B", "C"], [3]),
        ])
        let choice = try #require(RailwayRouteInference.choice(in: train(["A", "C"]), package: package))
        #expect(choice.lineIDs == ["first", "second"])
        #expect(choice.stations.map(\.code) == ["A", "B", "C"])
        #expect(choice.routeSections.map { $0.lineIDs ?? [] } == [["first"], ["second"]])
    }

    @Test("Physical segment mileage chooses the shortest competing alignment deterministically")
    func shortest() throws {
        let short = line("z-short", ["A", "X", "D"], [1, 1])
        let long = line("a-long", ["A", "Y", "D"], [3, 3])
        for rows in [[short, long], [long, short]] {
            let choice = try #require(RailwayRouteInference.choice(in: train(["A", "D"]), package: fixture(rows)))
            #expect(choice.lineIDs == ["z-short"])
            #expect(choice.stations.map(\.code) == ["A", "X", "D"])
        }
    }

    @Test("Unresolved and disconnected stops do not produce proposals or proximity transfers")
    func unresolved() throws {
        let package = try fixture([line("a", ["A", "B"], [1]), line("b", ["X", "D"], [1])])
        #expect(RailwayRouteInference.choice(in: train(["A", "D"]), package: package) == nil)
        #expect(RailwayRouteInference.choice(in: train(["A", "missing"]), package: package) == nil)
        var draft = train(["A", "B"])
        draft.stops[1].n02StationCode = nil
        #expect(RailwayRouteInference.choice(in: draft, package: package) == nil)
    }

    @Test("Source traversal direction is enforced")
    func direction() throws {
        var forward = line("forward", ["A", "B", "C"], [1, 1])
        forward["permittedTraversal"] = "forward"
        let package = try fixture([forward])
        #expect(RailwayRouteInference.choice(in: train(["A", "C"]), package: package)?.stations.map(\.code) == ["A", "B", "C"])
        #expect(RailwayRouteInference.choice(in: train(["C", "A"]), package: package) == nil)
    }

    @Test("Repeated station occurrences cannot skip physical intervals")
    func occurrences() throws {
        var forward = line("repeat", ["A", "B", "C", "B", "D"], [1, 1, 1, 1])
        forward["permittedTraversal"] = "forward"
        var branch = line("branch", ["B", "X"], [10])
        branch["permittedTraversal"] = "forward"
        let choice = try #require(RailwayRouteInference.choice(in: train(["A", "B", "D"]), package: fixture([forward, branch])))
        #expect(choice.stations.map(\.code) == ["A", "B", "C", "B", "D"])
        #expect(choice.sectionCodes == ["repeat@A:B", "repeat@B:C~1", "repeat@B:C~2", "repeat@B:D"])
    }

    @Test("Explicit sections and feasible preferred lines override competing alignments")
    func hints() throws {
        let package = try fixture([
            line("short", ["A", "X", "D"], [1, 1]),
            line("preferred", ["A", "Y", "D"], [3, 3]),
        ])
        var draft = train(["A", "D"])
        draft.routePolicy = RoutePolicy(preferredLineNames: ["preferred"])
        #expect(RailwayRouteInference.choice(in: draft, package: package)?.lineIDs == ["preferred"])
        draft.routePolicy = nil
        draft.routeSections = [RouteSection(fromN02StationCode: "A", toN02StationCode: "D", lineIDs: ["preferred"])]
        #expect(RailwayRouteInference.choice(in: draft, package: package)?.lineIDs == ["preferred"])
        draft.routeSections?[0].lineIDs = ["missing"]
        #expect(RailwayRouteInference.choice(in: draft, package: package) == nil)
    }

    @Test("Source line boundaries absent from passenger calls remain ordered route constraints")
    func nonCallBoundary() throws {
        let package = try fixture([
            line("first", ["A", "P", "X"], [2, 2]),
            line("second", ["X", "Q", "B"], [2, 2]),
            line("shortcut", ["A", "B"], [1]),
        ])
        var draft = train(["A", "P", "B"])
        draft.routeSections = [
            RouteSection(fromN02StationCode: "A", toN02StationCode: "X", lineIDs: ["first"]),
            RouteSection(fromN02StationCode: "X", toN02StationCode: "B", lineIDs: ["second"]),
        ]
        let before = draft
        let choice = try #require(RailwayRouteInference.choice(in: draft, package: package))
        #expect(choice.lineIDs == ["first", "second"])
        #expect(choice.stations.map(\.code) == ["A", "P", "X", "Q", "B"])
        #expect(choice.sectionCodes == ["first@A:P", "first@P:X", "second@Q:X", "second@B:Q"])
        #expect(draft == before)
        #expect(draft.stops.map(\.n02StationCode) == ["A", "P", "B"])
    }

    @Test("Non-call boundaries cannot discard an authored stop or relax a known line chain")
    func boundaryAnchorConflict() throws {
        let package = try fixture([
            line("first", ["A", "X"], [1]), line("second", ["X", "B"], [1]),
            line("other", ["A", "P", "B"], [1, 1]),
        ])
        var draft = train(["A", "P", "B"])
        draft.routeSections = [
            RouteSection(fromN02StationCode: "A", toN02StationCode: "X", lineIDs: ["first"]),
            RouteSection(fromN02StationCode: "X", toN02StationCode: "B", lineIDs: ["second"]),
        ]
        #expect(RailwayRouteInference.choice(in: draft, package: package) == nil)
    }

    @Test("High speed eligibility and service exceptions prevent incompatible physical proposals")
    func eligibility() throws {
        var high = line("high", ["A", "D"], [1])
        high["kind"] = "high_speed"
        var suspended = line("suspended", ["A", "D"], [0.1])
        suspended["serviceStatus"] = "suspended"
        let package = try fixture([high, suspended, line("ordinary", ["A", "B", "D"], [2, 2])])
        #expect(RailwayRouteInference.choice(in: train(["A", "D"]), package: package)?.lineIDs == ["ordinary"])
        var draft = train(["A", "D"])
        draft.trainType = "shinkansen"
        #expect(RailwayRouteInference.choice(in: draft, package: package)?.lineIDs == ["high"])
    }

    @Test("Applying and undoing an inferred route restores exact non-call source boundaries and clocks")
    func boundaryUndo() throws {
        let package = try fixture([
            line("first", ["A", "P", "X"], [1, 1]),
            line("second", ["X", "Q", "B"], [1, 1]),
        ])
        var draft = train(["A", "P", "B"])
        draft.stops[0].departure = "10:00"
        draft.stops[1].arrival = "10:10"
        draft.stops[1].departure = "10:12"
        draft.stops[2].arrival = "10:30"
        draft.routeSections = [
            RouteSection(fromN02StationCode: "A", toN02StationCode: "X", lineIDs: ["first"]),
            RouteSection(fromN02StationCode: "X", toN02StationCode: "B", lineIDs: ["second"]),
        ]
        let original = RailwayRouteEditing.preparing(draft)
        let choice = try #require(RailwayRouteInference.choice(in: original, package: package))
        let plan = try #require(RailwayRouteEditing.plan(train: original, choice: choice,
            fromVisitID: original.stops.first?.routeEditing?.visitID,
            toVisitID: original.stops.last?.routeEditing?.visitID))
        #expect(!plan.requiresConfirmation)
        #expect(plan.updatedTrain.stops.map(\.name) == ["A", "P", "X", "Q", "B"])
        #expect(plan.updatedTrain.stops[1].arrival == "10:10")
        #expect(plan.updatedTrain.stops[1].departure == "10:12")
        #expect(plan.updatedTrain.stops[2].stopType == "pass_through")
        #expect(plan.updatedTrain.stops[2].arrival == nil)
        #expect(plan.undo.restore(in: plan.updatedTrain) == original)
    }

    @Test("Published JR operator labels match their physical package company identities")
    func operatorAlias() throws {
        var row = line("joban", ["A", "X", "B"], [1, 1])
        row["operator"] = "東日本旅客鉄道"
        let package = try fixture([row])
        var draft = train(["A", "B"])
        draft.routeSections = [RouteSection(fromN02StationCode: "A", toN02StationCode: "B",
            operatorNames: ["JR東日本"], lineIDs: ["joban"])]
        draft.routePolicy = RoutePolicy(preferredOperatorNames: ["JR東日本"])
        #expect(RailwayRouteInference.choice(in: draft, package: package)?.stations.map(\.code) == ["A", "X", "B"])
        draft.routeSections?[0].operatorNames = ["JR東海"]
        #expect(RailwayRouteInference.choice(in: draft, package: package) == nil)
    }

    private func train(_ codes: [String]) -> Train {
        Train(id: "draft", number: "Draft", origin: codes.first!, destination: codes.last!,
              stops: codes.map { Stop(name: $0, n02StationCode: $0) })
    }

    private func line(_ id: String, _ codes: [String], _ distances: [Double]) -> [String: Any] {
        ["id": id, "name": id, "operator": "Operator", "rank": 3,
         "stations": codes.enumerated().map { [$0.element, $0.element, Double($0.offset), 0] as [Any] },
         "segments": distances.enumerated().map {
             [$0.element, 0, [[Double($0.offset), 0], [Double($0.offset + 1), 0]]] as [Any]
         }]
    }

    private func fixture(_ lines: [[String: Any]]) throws -> CompactPackage {
        try JSONDecoder().decode(CompactPackage.self, from: JSONSerialization.data(withJSONObject: [
            "format": "compact-v1", "version": "test", "country": "jp", "lines": lines]))
    }
}
