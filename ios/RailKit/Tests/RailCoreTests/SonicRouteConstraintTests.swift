import Foundation
import Testing

@testable import RailCore

/// Regression coverage for `RouteSolver.inferSectionRouteConstraints`'s ソニック
/// handling: the 日豊線 requirement must only apply when BOTH endpoints of the
/// section are on the 日豊線 corridor east of 小倉. West of 小倉 (黒崎, 戸畑,
/// 博多) the train runs on 鹿児島線, so those legs must still solve.
@Suite(.serialized)
struct SonicRouteConstraintTests {
    struct Environment {
        let graphStore: RouteGraph.RouteGraphStore
        let stations: Stations.Index
    }

    // Each solve owns its inputs and memoized graphs only for that call.
    // Serial cases avoid overlapping national input decoding in other runners.
    static func environment() -> Environment {
        let root = try! PortFixtures.repositoryRoot()
        let sections = try! RouteGraph.SectionFeatureCollection.load(
            contentsOf: root.appending(path: "app/data/rail-sections.json")).features
        let stationCollection = try! Stations.FeatureCollection.load(
            contentsOf: root.appending(path: "app/data/stations.json"))
        let stations = Stations.Index(stationCollection)
        let registry = try! PhysicalRailJunctionRegistry(data: Data(contentsOf:
            root.appending(path: "app/data/physical-rail-junctions.json")))
        let graphStore = RouteGraph.RouteGraphStore(
            sections: sections, policy: .physicalRailway,
            junctions: registry.junctions(for: "jp"),
            cachePolicy: .bounded(maximumNodes: 100_000))
        return Environment(graphStore: graphStore, stations: stations)
    }

    static let train = RouteSolver.TrainContext(
        id: "sonic-test", number: "ソニック", trainType: "特急",
        company: "九州旅客鉄道", origin: "博多", destination: "大分",
        preferredLineNames: [], preferredOperatorNames: [],
        allowedInstitutionTypeCodes: nil, institutionFilterMode: "soft")

    static func solve(_ from: String, _ to: String) -> RouteSolver.SolvedSection? {
        let env = Self.environment()
        let section = RouteSection(from: from, to: to)
        return RouteSolver.solveSectionOnDemand(
            section, segmentIndex: 0, train: Self.train, country: "jp",
            graphStore: env.graphStore, stations: env.stations,
            continuityAnchor: nil, traversalPolicy: .physicalRail)
    }

    @Test func kurosakiToKokuraSolves() throws {
        let solved = try #require(Self.solve("黒崎", "小倉"))
        #expect(solved.physicalLength >= 10_000 && solved.physicalLength <= 16_000)
    }

    @Test func hakataToKokuraSolves() throws {
        #expect(Self.solve("博多", "小倉") != nil)
    }

    @Test func kokuraToOitaSolvesOnNippoLine() throws {
        let solved = try #require(Self.solve("小倉", "大分"))
        #expect(solved.hints.requiredLines.contains("日豊線"))
    }

    @Test func oitaToKokuraSolves() throws {
        #expect(Self.solve("大分", "小倉") != nil)
    }
}
