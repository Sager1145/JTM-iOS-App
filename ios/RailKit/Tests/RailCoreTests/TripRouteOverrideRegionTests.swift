import Foundation
import Testing
@testable import RailCore

/// "Continue anyway" stays regional, and the search keeps its shortest-first
/// order and equal-cost tie order (fewer row changes, then fewer hops).
struct TripRouteOverrideRegionTests {
    @Test("Continue anyway changes rows at a shared code only near the chosen stations")
    func overrideIsRegional() throws {
        // A(0,0) → D(1,0). The only bare shared code, X, lies 10° away.
        let far = try fixture([
            line("out", [("A", 0, 0), ("X", 10, 0)]),
            line("back", [("X", 10, 0), ("D", 1, 0)]),
        ])
        var request = TripRoutePlanner.Request(originCode: "A", destinationCode: "D")
        request.allowUnverifiedConnections = true
        if case .corridors = TripRoutePlanner.plan(package: far, request: request, rideDate: nil,
                                                    patterns: [], connectors: []) {
            Issue.record("A shared code far outside the trip's region must not join rows")
        }
        // The same shape with X between the two stations still joins on override.
        let near = try fixture([
            line("out", [("A", 0, 0), ("X", 0.5, 0.1)]),
            line("back", [("X", 0.5, 0.1), ("D", 1, 0)]),
        ])
        guard case .corridors(let found) = TripRoutePlanner.plan(
            package: near, request: request, rideDate: nil, patterns: [], connectors: []) else {
            Issue.record("Continue anyway should still join rows inside the region"); return
        }
        #expect(found.first?.junctions.first?.link == TripConnectivity.Link.none)
        // Without the override the bare code never joins.
        request.allowUnverifiedConnections = false
        if case .corridors = TripRoutePlanner.plan(package: near, request: request, rideDate: nil,
                                                    patterns: [], connectors: []) {
            Issue.record("A bare shared code must not join rows without the override")
        }
    }

    @Test("Goal-directed search keeps shortest-first order on a synthetic fork")
    func searchOrder() throws {
        // Two parallel routes A→D; the shorter one (via B) must come first even
        // though its first hop points away from D.
        let package = try fixture([
            line("short", [("A", 0, 0), ("B", 0, 0.2), ("D", 1, 0)], kilometres: [30, 90]),
            line("long", [("A", 0, 0), ("C", 0.5, 0), ("D", 1, 0)], kilometres: [70, 70]),
        ])
        let result = LocalJourneySearch.search(package: package, originCode: "A", destinationCode: "D")
        #expect(result.choices.map(\.lineIDs) == [["short"], ["long"]])
    }

    @Test("Equal-length routes keep the old tie order: fewer row changes, then fewer hops")
    func equalCostTies() throws {
        // Every route A→D is exactly 100 km, so only the tie-breakers decide.
        let package = try fixture([
            line("transfer-1", [("A", 0, 0), ("C", 0.4, -0.1)], kilometres: [50]),
            line("transfer-2", [("C", 0.4, -0.1), ("D", 0.8, 0)], kilometres: [50]),
            line("three-hops", [("A", 0, 0), ("E", 0.2, 0.1), ("F", 0.4, 0.1), ("D", 0.8, 0)],
                 kilometres: [25, 25, 50]),
            line("two-hops", [("A", 0, 0), ("B", 0.4, 0.05), ("D", 0.8, 0)], kilometres: [50, 50]),
        ])
        let result = LocalJourneySearch.search(package: package, originCode: "A", destinationCode: "D",
                                               continuation: { _, _, _ in true })
        #expect(result.choices.map(\.lineIDs) == [["two-hops"], ["three-hops"], ["transfer-1", "transfer-2"]])
    }

    private func line(_ id: String, _ stations: [(String, Double, Double)],
                      kilometres: [Double]? = nil) -> [String: Any] {
        ["id": id, "name": id, "operator": "Operator-\(id)", "rank": 3, "kind": "jr_conventional",
         "stations": stations.map { [$0.0, $0.0, $0.1, $0.2] as [Any] },
         "segments": (0..<(stations.count - 1)).map { index -> [Any] in
             let a = stations[index], b = stations[index + 1]
             let chord = Geometry.distanceMeters(Coordinate(lon: a.1, lat: a.2),
                                                 Coordinate(lon: b.1, lat: b.2)) / 1000
             return [kilometres?[index] ?? chord, 0, [[a.1, a.2], [b.1, b.2]]]
         }]
    }

    private func fixture(_ lines: [[String: Any]]) throws -> CompactPackage {
        let data = try JSONSerialization.data(withJSONObject: [
            "format": "compact-v1", "version": "test", "country": "jp", "lines": lines])
        return try JSONDecoder().decode(CompactPackage.self, from: data)
    }
}
