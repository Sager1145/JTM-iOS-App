import Foundation
import Testing
@testable import RailCore

struct ReviewedIwanumaRoutingTests {
    @Test("Reviewed Iwanuma identity boundary carries current Watari–Sendai over surveyed rail")
    func actualSourceBoundary() throws {
        let data = try PortFixtures.repositoryRoot().appendingPathComponent("app/data")
        var sourceSections = try RouteGraph.SectionFeatureCollection.load(
            contentsOf: data.appendingPathComponent("rail-sections.json")).features
        var stationFeatures = try Stations.FeatureCollection.load(
            contentsOf: data.appendingPathComponent("stations.json")).features
        let overlay = try RailHistoryOverlay.load(
            from: data.appendingPathComponent("rail-history.json"))
        _ = RailHistory.apply(overlay, sections: &sourceSections, stations: &stationFeatures)

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
        let stations = Stations.Index(.init(features: stationFeatures))
        let registry = try PhysicalRailJunctionRegistry(data: Data(
            contentsOf: data.appendingPathComponent("physical-rail-junctions.json")))
        let junction = try #require(registry.junctions(for: "jp").first {
            $0.id == "iwanuma-joban-tohoku"
        })
        let coordinate = Coordinate(lon: 140.86437, lat: 38.11279)
        #expect(junction.from.coordinate == coordinate)
        #expect(junction.to.coordinate == coordinate)
        #expect(!junction.evidence.isEmpty)

        // This is the first accepted evidence date, not the original opening
        // of the junction. Check the boundary's window directly: a current
        // route must not imply that all its surveyed geometry existed in 2011.
        #expect(junction.validFrom == "2011-04-21")
        #expect(!RouteGraph.RailValidity.isValid(
            validFrom: junction.validFrom, validTo: junction.validTo, on: "2011-04-20"))
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
        func solve(_ graph: RouteGraph.Graph, _ section: RouteSection) -> RouteSolver.SolvedSection? {
            RouteSolver.solveSection(section, segmentIndex: 0,
                train: .init(company: "東日本旅客鉄道", rideDate: "2026-10-03"),
                country: "jp", graph: graph, stations: stations)
        }
        for section in [forward, reverse] {
            #expect(solve(independent, section) == nil)
            let solved = try #require(solve(joined, section))
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
