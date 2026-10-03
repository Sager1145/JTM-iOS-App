import Foundation
import Testing
@testable import RailCore

struct ReviewedShiojiriRoutingTests {
    @Test("Current Enrei approach continues onto surveyed Shinonoi rail at Shiojiri")
    func actualSourceBoundary() throws {
        let data = try PortFixtures.repositoryRoot().appendingPathComponent("app/data")
        let sections = try RouteGraph.SectionFeatureCollection.load(
            contentsOf: data.appendingPathComponent("rail-sections.json")).features.filter {
                $0.properties.operator == "東日本旅客鉄道"
                    && ["中央線", "篠ノ井線"].contains($0.properties.lineName)
            }
        let stations = Stations.Index(try Stations.FeatureCollection.load(
            contentsOf: data.appendingPathComponent("stations.json")).features)
        let registry = try PhysicalRailJunctionRegistry(data: Data(
            contentsOf: data.appendingPathComponent("physical-rail-junctions.json")))
        let junction = try #require(registry.junctions(for: "jp").first { $0.id == "shiojiri-chuo-shinonoi" })
        let independent = RouteGraph.build(from: sections)
        let joined = RouteGraph.build(from: sections, junctions: [junction])
        #expect(joined.rejectedPhysicalJunctionIDs.isEmpty)
        let forward = RouteSection(from: "上諏訪", to: "松本",
                                   fromN02StationCode: "002706", toN02StationCode: "002506")
        let reverse = RouteSection(from: "松本", to: "上諏訪",
                                   fromN02StationCode: "002506", toN02StationCode: "002706")
        func solve(_ graph: RouteGraph.Graph, _ section: RouteSection,
                   _ date: String) -> RouteSolver.SolvedSection? {
            RouteSolver.solveSection(section, segmentIndex: 0,
                train: .init(company: "東日本旅客鉄道", rideDate: date),
                country: "jp", graph: graph, stations: stations)
        }
        for section in [forward, reverse] {
            #expect(solve(independent, section, "2026-10-03") == nil)
            #expect(solve(joined, section, "1983-07-04") == nil)
            for day in ["1983-07-05", "2026-10-03"] {
                let solved = try #require(solve(joined, section, day))
                #expect(solved.coordinates == solved.rawPathKeys.compactMap { joined.nodes[$0] })
                var boundaries = 0
                var lines = Set<String>()
                for (from, to) in zip(solved.rawPathKeys, solved.rawPathKeys.dropFirst()) {
                    let edge = try #require(joined.adjacency[from]?.first { $0.to == to })
                    #expect(edge.connector == nil)
                    if let boundary = edge.physicalJunction {
                        #expect(boundary.junction.id == junction.id)
                        #expect(edge.length == 0)
                        #expect(joined.nodes[from] == joined.nodes[to])
                        boundaries += 1
                    } else {
                        lines.insert(edge.lineName)
                    }
                }
                #expect(boundaries == 1)
                #expect(lines == ["中央線", "篠ノ井線"])
            }
        }
    }
}
