import Foundation
import Testing
@testable import RailCore

struct ReviewedChayamachiRoutingTests {
    @Test("Reviewed Kojima operator boundary retains the continuous surveyed bridge railway")
    func actualKojimaOperatorBoundary() throws {
        let data = try PortFixtures.repositoryRoot().appendingPathComponent("app/data")
        let sections = try RouteGraph.SectionFeatureCollection.load(
            contentsOf: data.appendingPathComponent("rail-sections.json")).features.filter {
                $0.properties.lineName == "本四備讃線"
                    && ["西日本旅客鉄道", "四国旅客鉄道"].contains($0.properties.operator)
            }
        let stations = Stations.Index(try Stations.FeatureCollection.load(
            contentsOf: data.appendingPathComponent("stations.json")).features)
        let registry = try PhysicalRailJunctionRegistry(data: Data(
            contentsOf: data.appendingPathComponent("physical-rail-junctions.json")))
        let junction = try #require(registry.junctions(for: "jp").first {
            $0.id == "kojima-honshi-bisan-operator-boundary"
        })
        let independent = RouteGraph.build(from: sections)
        let joined = RouteGraph.build(from: sections, junctions: [junction])
        #expect(joined.rejectedPhysicalJunctionIDs.isEmpty)
        let forward = RouteSection(from: "茶屋町", to: "宇多津",
                                   fromN02StationCode: "007663", toN02StationCode: "008252")
        let reverse = RouteSection(from: "宇多津", to: "茶屋町",
                                   fromN02StationCode: "008252", toN02StationCode: "007663")
        func solve(_ graph: RouteGraph.Graph, _ section: RouteSection,
                   _ date: String) -> RouteSolver.SolvedSection? {
            RouteSolver.solveSection(section, segmentIndex: 0,
                train: .init(company: "西日本旅客鉄道/四国旅客鉄道", rideDate: date),
                country: "jp", graph: graph, stations: stations)
        }
        for section in [forward, reverse] {
            #expect(solve(independent, section, "2026-10-03") == nil)
            #expect(solve(joined, section, "1988-04-09") == nil)
            for day in ["1988-04-10", "2026-10-03"] {
                let solved = try #require(solve(joined, section, day))
                #expect(solved.coordinates == solved.rawPathKeys.compactMap { joined.nodes[$0] })
                var boundaries = 0
                var operators = Set<String>()
                for (from, to) in zip(solved.rawPathKeys, solved.rawPathKeys.dropFirst()) {
                    let edge = try #require(joined.adjacency[from]?.first { $0.to == to })
                    #expect(edge.connector == nil)
                    if let boundary = edge.physicalJunction {
                        #expect(boundary.junction.id == junction.id)
                        #expect(edge.length == 0)
                        #expect(joined.nodes[from] == joined.nodes[to])
                        boundaries += 1
                    } else {
                        #expect(edge.lineName == "本四備讃線")
                        operators.insert(edge.operator)
                    }
                }
                #expect(boundaries == 1)
                #expect(operators == ["西日本旅客鉄道", "四国旅客鉄道"])
            }
        }
    }

    @Test("Reviewed Chayamachi line boundary connects surveyed rail only after opening")
    func actualSurveyedBoundary() throws {
        let root = try PortFixtures.repositoryRoot()
        let data = root.appendingPathComponent("app/data")
        let sections = try RouteGraph.SectionFeatureCollection.load(
            contentsOf: data.appendingPathComponent("rail-sections.json")).features.filter {
                $0.properties.operator == "西日本旅客鉄道"
                    && ["宇野線", "本四備讃線"].contains($0.properties.lineName)
            }
        #expect(!sections.isEmpty)
        let stations = Stations.Index(try Stations.FeatureCollection.load(
            contentsOf: data.appendingPathComponent("stations.json")).features)
        let registry = try PhysicalRailJunctionRegistry(data: Data(
            contentsOf: data.appendingPathComponent("physical-rail-junctions.json")))
        let junction = try #require(registry.junctions(for: "jp").first {
            $0.id == "chayamachi-uno-honshi-bisan"
        })
        let independent = RouteGraph.build(from: sections, policy: .physicalRailway)
        let joined = RouteGraph.build(from: sections, policy: .physicalRailway, junctions: [junction])
        #expect(joined.rejectedPhysicalJunctionIDs.isEmpty)
        let route = RouteSection(from: "岡山", to: "児島",
                                 fromN02StationCode: "007310", toN02StationCode: "007919")
        let reverse = RouteSection(from: "児島", to: "岡山",
                                   fromN02StationCode: "007919", toN02StationCode: "007310")
        func solve(_ graph: RouteGraph.Graph, date: String,
                   section: RouteSection) -> RouteSolver.SolvedSection? {
            RouteSolver.solveSection(section, segmentIndex: 0,
                train: .init(company: "西日本旅客鉄道/四国旅客鉄道", rideDate: date),
                country: "jp", graph: graph, stations: stations)
        }
        for section in [route, reverse] {
          #expect(solve(independent, date: "2026-10-03", section: section) == nil)
          #expect(solve(joined, date: "1988-03-19", section: section) == nil)
          for date in ["1988-03-20", "2026-10-03"] {
            let solved = try #require(solve(joined, date: date, section: section))
            #expect(solved.coordinates == solved.rawPathKeys.compactMap { joined.nodes[$0] })
            var junctionCount = 0
            var lines = Set<String>()
            for (from, to) in zip(solved.rawPathKeys, solved.rawPathKeys.dropFirst()) {
                let edge = try #require(joined.adjacency[from]?.first { $0.to == to })
                #expect(edge.connector == nil)
                if let boundary = edge.physicalJunction {
                    #expect(boundary.junction.id == junction.id)
                    #expect(edge.length == 0)
                    #expect(joined.nodes[from] == joined.nodes[to])
                    junctionCount += 1
                } else {
                    lines.insert(edge.lineName)
                }
            }
            #expect(junctionCount == 1)
            #expect(lines == ["宇野線", "本四備讃線"])
          }
        }
    }
}
