import Foundation
import Testing
@testable import RailCore

struct ReviewedHimejiRoutingTests {
    @Test("The reviewed Himeji connector joins the San'yo and Bantan lines", arguments: ["2026-10-03", "1990-07-01"])
    func sanyoBantanThroughHimeji(rideDate: String) throws {
        let data = try PortFixtures.repositoryRoot().appendingPathComponent("app/data")
        var sourceSections = try RouteGraph.SectionFeatureCollection.load(
            contentsOf: data.appendingPathComponent("rail-sections.json")).features
        var stationFeatures = try Stations.FeatureCollection.load(
            contentsOf: data.appendingPathComponent("stations.json")).features
        let overlay = try RailHistoryOverlay.load(
            from: data.appendingPathComponent("rail-history.json"))
        _ = RailHistory.apply(overlay, sections: &sourceSections, stations: &stationFeatures)
        let sections = sourceSections.filter { feature in
            feature.properties.operator == "西日本旅客鉄道"
                && ["山陽線", "播但線"].contains(feature.properties.lineName)
                && feature.lines.contains { line in
                    line.contains { coordinate in
                        coordinate.lon >= 134.6 && coordinate.lon <= 134.8
                            && coordinate.lat >= 34.78 && coordinate.lat <= 34.88
                    }
                }
        }
        #expect(!sections.isEmpty)
        let stations = Stations.Index(.init(features: stationFeatures))
        let registry = try PhysicalRailJunctionRegistry(data: Data(
            contentsOf: data.appendingPathComponent("physical-rail-junctions.json")))
        let junctions = registry.junctions(for: "jp").filter { $0.id == "west-himeji-sanyo-bantan" }
        let himeji = try #require(junctions.first)
        #expect(junctions.count == 1)
        #expect(himeji.kind == .osmConnector)
        #expect(himeji.from.coordinate == Coordinate(lon: 134.692862, lat: 34.826493))
        #expect(himeji.to.coordinate == Coordinate(lon: 134.70054, lat: 34.82813))
        // Dating rule (2026-10-04): the link is as old as both rows, so no lower bound.
        #expect(himeji.validFrom == nil)
        #expect(!himeji.evidence.isEmpty)

        let independent = RouteGraph.build(from: sections, policy: .physicalRailway)
        let joined = RouteGraph.build(from: sections, policy: .physicalRailway, junctions: junctions)
        #expect(joined.rejectedPhysicalJunctionIDs.isEmpty)

        func solve(_ graph: RouteGraph.Graph, _ section: RouteSection) -> RouteSolver.SolvedSection? {
            RouteSolver.solveSection(section, segmentIndex: 0,
                train: .init(company: "西日本旅客鉄道", rideDate: rideDate),
                country: "jp", graph: graph, stations: stations)
        }
        // A train from the west (英賀保) runs straight through the turnout
        // east of 姫路 onto 播但線. はまかぜ's stop-at-姫路 continuity is
        // covered by the express display census.
        for section in [
            RouteSection(from: "英賀保", to: "京口", fromN02StationCode: "006573", toN02StationCode: "006477"),
            RouteSection(from: "京口", to: "英賀保", fromN02StationCode: "006477", toN02StationCode: "006573")
        ] {
            #expect(solve(independent, section) == nil)
            let solved = try #require(solve(joined, section))
            // 英賀保–姫路 3.7 km plus 姫路–京口 1.8 km, entered east of the platforms.
            #expect(solved.physicalLength < 7_000)
            var connector = 0
            var lines = Set<String>()
            for (from, to) in zip(solved.rawPathKeys, solved.rawPathKeys.dropFirst()) {
                let edge = try #require(joined.adjacency[from]?.first { $0.to == to })
                if let boundary = edge.physicalJunction {
                    #expect(boundary.junction == himeji)
                    connector += 1
                } else {
                    #expect(edge.operator == "西日本旅客鉄道")
                    lines.insert(edge.lineName)
                }
            }
            #expect(connector > 0)
            #expect(lines.isSubset(of: ["山陽線", "播但線"]))
            #expect(lines.contains("播但線"))
        }
    }
}
