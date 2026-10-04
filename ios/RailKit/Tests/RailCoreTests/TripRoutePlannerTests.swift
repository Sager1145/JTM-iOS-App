import Foundation
import Testing
@testable import RailCore

struct TripRoutePlannerTests {
    @Test("A single line reports its intermediate stations and distance")
    func singleLine() throws {
        let package = try fixture([line("one", ["A", "M", "B"], distance: 2)])
        let corridors = try corridors(package, from: "A", to: "B")
        #expect(corridors.count == 1)
        #expect(corridors[0].junctions.isEmpty)
        #expect(corridors[0].passStationCount == 1)
        #expect(corridors[0].distanceKm == 4)
        #expect(corridors[0].id == corridors[0].choice.id)
        #expect(corridors[0].lineNames == ["one"])
        #expect(corridors[0].operatorNames == ["Operator"])
    }

    @Test("JR conventional lines continue across company boundaries")
    func jrNetwork() throws {
        let package = try fixture([line("first", ["A", "B"], operatorName: "One"),
                                   line("second", ["B", "C"], operatorName: "Two")])
        let corridor = try #require(corridors(package, from: "A", to: "C").first)
        #expect(corridor.junctions.count == 1)
        #expect(corridor.junctions.first?.link == .network)
        #expect(corridor.junctions.first?.stationCode == "B")
        #expect(corridor.junctions.first?.stationName == "B")
        #expect(corridor.junctions.first?.fromLineID == "first")
        #expect(corridor.junctions.first?.toLineID == "second")
    }

    @Test("Same-operator subway lines require a through-service record")
    func subwayDisconnected() throws {
        let package = try fixture([line("first", ["A", "B"], kind: "subway"),
                                   line("second", ["B", "C"], kind: "subway")])
        guard case .disconnected(let junctions) = plan(package, from: "A", to: "C") else {
            Issue.record("Expected disconnected subway lines")
            return
        }
        #expect(junctions.count == 1)
        #expect(junctions.first?.link == TripConnectivity.Link.none)
        #expect(junctions.first?.stationCode == "B")
    }

    @Test("Parallel corridors are ordered by distance and company selection is enforced")
    func parallelCorridors() throws {
        let package = try fixture([line("long", ["A", "X", "B"], distance: 3, operatorName: "Long"),
                                   line("short", ["A", "Y", "B"], operatorName: "Short")])
        let found = try corridors(package, from: "A", to: "B")
        #expect(found.count == 2)
        #expect(found.map(\.distanceKm) == [2, 6])
        #expect(found.map { $0.choice.lineIDs } == [["short"], ["long"]])
        let preferred = TripRoutePlanner.plan(package: package,
            request: .init(originCode: "A", destinationCode: "B", operatorName: "Long"))
        #expect(preferred == .corridors([found[1]]))
        #expect(TripRoutePlanner.plan(package: package,
            request: .init(originCode: "A", destinationCode: "B", operatorName: "Unknown")) == .noCompanyRoute("Unknown"))
    }

    @Test("Different private operators require a catalog continuation, including junction aliases")
    func privateAndThroughService() throws {
        let package = try fixture([line("first", ["A", "B"], kind: "private", operatorName: "One"),
                                   line("second", ["B", "C"], kind: "private", operatorName: "Two")])
        guard case .disconnected(let junctions) = plan(package, from: "A", to: "C") else {
            Issue.record("Expected disconnected private lines")
            return
        }
        #expect(junctions.count == 1)
        #expect(junctions.first?.link == TripConnectivity.Link.none)
        let pattern = try #require(JapanThroughServices.patterns.first { $0.legs.count >= 2 })
        let realPair = try fixture([
            line(pattern.legs[0].lineID, ["A", "B"], kind: "private", operatorName: "One"),
            line(pattern.legs[1].lineID, ["B", "C"], kind: "private", operatorName: "Two")])
        for code in [pattern.legs[0].toStationCode, "alias-junction"] {
            #expect(TripConnectivity.link(from: realPair.lines[0], to: realPair.lines[1],
                                          atStationCode: code) == .throughService)
            #expect(TripConnectivity.link(from: realPair.lines[1], to: realPair.lines[0],
                                          atStationCode: code) == .throughService)
        }
    }

    @Test("Same and isolated stations have distinct outcomes")
    func endpoints() throws {
        let package = try fixture([line("one", ["A", "B"]), line("isolated", ["C"])])
        #expect(plan(package, from: "A", to: "A") == .sameStation)
        #expect(plan(package, from: "A", to: "C") == .noRoute)
    }

    @Test("Nil continuation preserves the existing ranking fixture and wrapper choices")
    func nilContinuationRegression() throws {
        let package = try fixture([line("direct", ["A", "D"], distance: 5),
                                   line("first", ["A", "B"]), line("second", ["B", "D"]),
                                   line("equal", ["A", "C", "D"])])
        let baseline = LocalJourneySearch.search(package: package, originCode: "A", destinationCode: "D")
        let explicitNil = LocalJourneySearch.search(package: package, originCode: "A", destinationCode: "D",
                                                    continuation: nil)
        #expect(explicitNil.choices == baseline.choices)
        #expect(explicitNil.choices.map(\.lineIDs) == [["equal"], ["first", "second"], ["direct"]])
        #expect(explicitNil.isTruncated == baseline.isTruncated)
        #expect(explicitNil.topologyIsComplete == baseline.topologyIsComplete)
        #expect(LocalJourneySearch.choices(package: package, originCode: "A", destinationCode: "D",
                                           continuation: nil) == baseline.choices)
        let blocked = LocalJourneySearch.choices(package: package, originCode: "A", destinationCode: "D",
                                                 continuation: { _, _, _ in false })
        #expect(blocked.map(\.lineIDs) == [["equal"], ["direct"]])
    }

    @Test("Endpoint line hints prevent falling back to a shared JR route")
    func endpointLineHints() throws {
        let package = try fixture([
            line("subway-a", ["A", "M", "B"], kind: "subway"),
            line("subway-b", ["A", "M", "B"], kind: "subway"),
            line("jr", ["A", "B"])])
        #expect(try !corridors(package, from: "A", to: "B").isEmpty)
        let outcome = TripRoutePlanner.plan(package: package, request: .init(
            originCode: "A", destinationCode: "B",
            originLineID: "subway-a", destinationLineID: "subway-b"))
        guard case .disconnected = outcome else {
            Issue.record("Expected disconnected hinted subway lines")
            return
        }
    }

    @Test("A hinted direct line ranks ahead of a shorter connecting route")
    func directLineFirst() throws {
        var direct = line("direct", ["A", "J", "X", "B"], distance: 5)
        direct["segments"] = [[1, 0, [[0, 0], [1, 0]]],
                              [5, 0, [[1, 0], [2, 0]]],
                              [5, 0, [[2, 0], [3, 0]]]]
        let package = try fixture([direct, line("shortcut", ["J", "Y", "B"])])
        let outcome = TripRoutePlanner.plan(package: package, request: .init(
            originCode: "A", destinationCode: "B", originLineID: "direct"))
        guard case .corridors(let found) = outcome else {
            Issue.record("Expected direct and connecting corridors")
            return
        }
        #expect(found.count == 2)
        #expect(found.first?.choice.lineIDs == ["direct"])
        #expect(found.map(\.distanceKm) == [11, 3])
    }

    @Test("Corridors sharing at least eighty percent of station keys collapse")
    func nearDuplicates() throws {
        let package = try fixture([
            line("short", ["A", "M", "N", "P", "B"]),
            line("long", ["A", "M", "N", "Q", "B"], distance: 2),
            line("distinct", ["A", "X", "Y", "Z", "B"])])
        let found = try corridors(package, from: "A", to: "B")
        #expect(found.map { $0.choice.lineIDs } == [["distinct"], ["short"]])
    }

    @Test("Existing package station IDs take precedence over request aliases")
    func aliases() throws {
        let package = try fixture([line("one", ["A", "M", "B"])])
        let outcome = TripRoutePlanner.plan(package: package, request: .init(
            originCode: "external", destinationCode: "B",
            stationAliases: ["external": "A", "A": "wrong"], originLineID: "one"))
        guard case .corridors(let found) = outcome else {
            Issue.record("Expected aliased endpoint route")
            return
        }
        #expect(found.first?.choice.stations.first?.code == "external")
    }

    private func plan(_ package: CompactPackage, from: String, to: String) -> TripRoutePlanner.Outcome {
        TripRoutePlanner.plan(package: package, request: .init(originCode: from, destinationCode: to))
    }

    private func corridors(_ package: CompactPackage, from: String, to: String) throws -> [TripRoutePlanner.Corridor] {
        let outcome = plan(package, from: from, to: to)
        guard case .corridors(let values) = outcome else {
            Issue.record("Expected corridors, got \(outcome)")
            return []
        }
        return values
    }

    private func line(_ id: String, _ codes: [String], distance: Double = 1,
                      kind: String = "jr_conventional", operatorName: String = "Operator") -> [String: Any] {
        ["id": id, "name": id, "operator": operatorName, "rank": 3, "kind": kind,
         "stations": codes.enumerated().map { [$0.element, $0.element, Double($0.offset), 0] as [Any] },
         "segments": (0..<(codes.count - 1)).map {
             [distance, 0, [[Double($0), 0], [Double($0 + 1), 0]]] as [Any]
         }]
    }

    private func fixture(_ lines: [[String: Any]]) throws -> CompactPackage {
        let data = try JSONSerialization.data(withJSONObject: [
            "format": "compact-v1", "version": "test", "country": "jp", "lines": lines])
        return try JSONDecoder().decode(CompactPackage.self, from: data)
    }
}


extension TripRoutePlannerTests {
    @Test("A named JR corridor spans company line IDs and precedes shorter alternatives")
    func namedCorridorAcrossCompanies() throws {
        var first = line("A1", ["O", "J"], operatorName: "East")
        var last = line("A2", ["J", "K", "D"], distance: 5, operatorName: "West")
        first["name"] = "Main"
        last["name"] = "Main"
        let package = try fixture([first, last,
            line("B", ["J", "X", "Y"]), line("C", ["Y", "D"]),
            line("shortcut", ["J", "Z", "W", "K"])])
        let outcome = TripRoutePlanner.plan(package: package, request: .init(
            originCode: "O", destinationCode: "D", originLineID: "A1", destinationLineID: "A2"))
        guard case .corridors(let found) = outcome else {
            Issue.record("Expected hinted named corridor")
            return
        }
        #expect(found.first?.choice.lineIDs == ["A1", "A2"])
        #expect(found.first?.lineNames == ["Main"])
        #expect(found.first?.operatorNames == ["East", "West"])
        #expect(found.contains { $0.distanceKm < (found.first?.distanceKm ?? 0) })
        #expect(found.allSatisfy { $0.choice.routeSections.first?.lineIDs == ["A1"]
            && $0.choice.routeSections.last?.lineIDs == ["A2"] })
    }
}
