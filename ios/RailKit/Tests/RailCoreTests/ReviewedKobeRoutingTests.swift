import Foundation
import Testing
@testable import RailCore

struct ReviewedKobeRoutingTests {
    @Test("The reviewed Kobe boundary joins the Tokaido and San'yo lines for through trains", arguments: ["2026-10-03", "1990-07-01"])
    func tokaidoSanyoThroughKobe(rideDate: String) throws {
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
                && ["東海道線", "山陽線"].contains(feature.properties.lineName)
                && feature.lines.contains { line in
                    line.contains { coordinate in
                        coordinate.lon >= 135.13 && coordinate.lon <= 135.2
                            && coordinate.lat >= 34.64 && coordinate.lat <= 34.7
                    }
                }
        }
        #expect(!sections.isEmpty)
        let stations = Stations.Index(.init(features: stationFeatures))
        let registry = try PhysicalRailJunctionRegistry(data: Data(
            contentsOf: data.appendingPathComponent("physical-rail-junctions.json")))
        let junctions = registry.junctions(for: "jp").filter { $0.id == "west-kobe" }
        let kobe = try #require(junctions.first)
        #expect(junctions.count == 1)
        #expect(kobe.from.coordinate == Coordinate(lon: 135.17838, lat: 34.68057))
        #expect(kobe.from.coordinate == kobe.to.coordinate)
        #expect(!kobe.evidence.isEmpty)
        // Dating rule (2026-10-04): the link is as old as both rows, so no lower bound.
        #expect(kobe.validFrom == nil)

        let independent = RouteGraph.build(from: sections, policy: .physicalRailway)
        let joined = RouteGraph.build(from: sections, policy: .physicalRailway, junctions: junctions)
        #expect(joined.rejectedPhysicalJunctionIDs.isEmpty)

        func solve(_ graph: RouteGraph.Graph, _ section: RouteSection) -> RouteSolver.SolvedSection? {
            RouteSolver.solveSection(section, segmentIndex: 0,
                train: .init(company: "西日本旅客鉄道", rideDate: rideDate),
                country: "jp", graph: graph, stations: stations)
        }
        // 元町 → 兵庫 and 三ノ宮 → 新長田 pass 神戸, where 東海道線 ends and
        // 山陽線 begins. Without the boundary neither interval exists.
        for (from, fromCode, to, toCode) in [
            ("元町", "007160", "兵庫", "007298"),
            ("三ノ宮", "007105", "新長田", "007386")
        ] {
            for section in [
                RouteSection(from: from, to: to, fromN02StationCode: fromCode, toN02StationCode: toCode),
                RouteSection(from: to, to: from, fromN02StationCode: toCode, toN02StationCode: fromCode)
            ] {
                #expect(solve(independent, section) == nil)
                let solved = try #require(solve(joined, section))
                var boundaries = 0
                var lines = Set<String>()
                for (from, to) in zip(solved.rawPathKeys, solved.rawPathKeys.dropFirst()) {
                    let edge = try #require(joined.adjacency[from]?.first { $0.to == to })
                    #expect(edge.connector == nil)
                    if let boundary = edge.physicalJunction {
                        #expect(boundary.junction == kobe)
                        #expect(edge.length == 0)
                        boundaries += 1
                    } else {
                        #expect(edge.operator == "西日本旅客鉄道")
                        lines.insert(edge.lineName)
                    }
                }
                #expect(boundaries == 1)
                #expect(lines == ["東海道線", "山陽線"])
            }
        }
    }
}
