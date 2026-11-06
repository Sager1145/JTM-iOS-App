import Foundation
import Testing
import RailCore

struct ReviewedIwanumaRoutingTests {
    @Test("Reviewed Iwanuma identity boundary carries current Watari–Sendai over surveyed rail")
    func actualSourceBoundary() throws {
        let snapshot = try ReviewedCorridorFixtures.snapshot(history: true)
        let sourceSections = snapshot.sections
        let sections = sourceSections.filter { feature in
            feature.properties.operator == "東日本旅客鉄道"
                && ["常磐線", "東北線"].contains(feature.properties.lineName)
                && feature.lines.contains { line in
                    line.contains { coordinate in
                        coordinate.lon >= 140.78 && coordinate.lon <= 141.0
                            && coordinate.lat >= 38.01 && coordinate.lat <= 38.3
                    }
                }
        }
        #expect(!sections.isEmpty)

        let junction = try #require(snapshot.junctions.first {
            $0.id == "iwanuma-joban-tohoku"
        })
        let coordinate = Coordinate(lon: 140.86437, lat: 38.11279)
        #expect(junction.from.coordinate == coordinate)
        #expect(junction.to.coordinate == coordinate)
        #expect(!junction.evidence.isEmpty)

        // Dated from the official 常磐線 completion year (conservative
        // year-end bound), replacing the 2011 recovery evidence window.
        #expect(junction.validFrom == "1898-12-31")
        #expect(!RouteGraph.RailValidity.isValid(
            validFrom: junction.validFrom, validTo: junction.validTo, on: "1898-12-30"))
        #expect(RouteGraph.RailValidity.isValid(
            validFrom: junction.validFrom, validTo: junction.validTo, on: "2011-04-21"))

        let independent = RouteGraph.build(from: sections, policy: .physicalRailway)
        let joined = RouteGraph.build(from: sections, policy: .physicalRailway, junctions: [junction])
        #expect(joined.rejectedPhysicalJunctionIDs.isEmpty)
        // Both endpoints are outside Iwanuma's shared station memberships,
        // so endpoint snapping cannot substitute for the physical boundary.
        let forward = RouteSection(from: "亘理", to: "仙台",
                                   fromN02StationCode: "001259", toN02StationCode: "001182")
        let reverse = RouteSection(from: "仙台", to: "亘理",
                                   fromN02StationCode: "001182", toN02StationCode: "001259")
        var worker = ReviewedCorridorWorker(sections: sections, stations: snapshot.stations,
            junctions: [junction])
        func solve(_ reviewed: Bool, _ section: RouteSection) throws -> ReviewedCorridorWorker.Proof? {
            try worker.solve(reviewed: reviewed, section: section, company: "東日本旅客鉄道", date: "2026-10-03")
        }
        for section in [forward, reverse] {
            #expect(try solve(false, section) == nil)
            let solved = try #require(try solve(true, section))
            #expect(solved.coordinates == solved.rawPathKeys.compactMap { joined.nodes[$0] })
            var boundaries = 0
            var lines = Set<String>()
            for (from, to) in zip(solved.rawPathKeys, solved.rawPathKeys.dropFirst()) {
                let fromCoordinate = try #require(independent.nodes[from])
                let toCoordinate = try #require(independent.nodes[to])
                let edge = try #require(joined.adjacency[from]?.first { $0.to == to })
                #expect(edge.connector == nil)
                #expect(RouteGraph.RailValidity.isValid(
                    validFrom: edge.validFrom, validTo: edge.validTo, on: "2026-10-03"))
                if let boundary = edge.physicalJunction {
                    #expect(boundary.junction == junction)
                    #expect(edge.length == 0)
                    #expect(fromCoordinate == coordinate)
                    #expect(toCoordinate == coordinate)
                    boundaries += 1
                } else {
                    // Every ordinary rail hop already exists in the graph
                    // made solely from the history-applied source sections.
                    #expect(independent.adjacency[from]?.contains { $0 == edge } == true)
                    #expect(edge.operator == "東日本旅客鉄道")
                    lines.insert(edge.lineName)
                }
            }
            #expect(boundaries == 1)
            #expect(lines == ["常磐線", "東北線"])
        }
    }
}
