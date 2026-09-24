import Foundation
import Testing

@testable import RailCore

/// End-to-end coverage for ADR 0011's rail-history overlay
/// (`app/data/rail-history.json`) against the real Japanese solver package:
/// a retired line only routes a ride dated inside its validity window, and
/// an undated ride never uses retired track.
///
/// Follows `SonicRouteConstraintTests`'s data-loading and solve pattern, but
/// goes through `RouteGraph.RouteGraphStore` + `RouteSolver.solveSectionOnDemand`
/// (per `RiddenRouteStore.solveMissing`) because that is the path that
/// actually exercises the dated rail-history edges end to end.
/// `.serialized`: every case shares one `RouteGraph.RouteGraphStore`, whose
/// regional-graph cache is mutated in place by `solveSectionOnDemand` — the
/// default parallel execution corrupts that shared cache across threads
/// (observed as a segfault in the test process, not an assertion failure).
@Suite(.serialized)
struct RailHistoryPackageTests {
    struct Environment {
        let graphStore: RouteGraph.RouteGraphStore
        let stations: Stations.Index
        let overlay: RailHistoryOverlay
    }

    nonisolated(unsafe) static let environment: Environment = {
        let root = try! PortFixtures.repositoryRoot()
        var sections = try! RouteGraph.SectionFeatureCollection.load(
            contentsOf: root.appending(path: "app/data/rail-sections.json")
        ).features
        var stationFeatures = try! Stations.FeatureCollection.load(
            contentsOf: root.appending(path: "app/data/stations.json")
        ).features
        let overlay = try! RailHistoryOverlay.load(
            from: root.appending(path: "app/data/rail-history.json"))
        _ = RailHistory.apply(overlay, sections: &sections, stations: &stationFeatures)

        let stationCollection = Stations.FeatureCollection(features: stationFeatures)
        let stations = Stations.Index(stationCollection)
        let graphStore = RouteGraph.RouteGraphStore(sections: sections)
        graphStore.augment = { graph, _ in
            RouteSolver.addStationTransferConnectorEdges(
                graph: graph, stations: stationCollection.features)
        }
        return Environment(graphStore: graphStore, stations: stations, overlay: overlay)
    }()

    static func train(rideDate: String?) -> RouteSolver.TrainContext {
        RouteSolver.TrainContext(
            id: "rail-history-test", number: "", trainType: "", company: "",
            origin: "", destination: "", preferredLineNames: [], preferredOperatorNames: [],
            allowedInstitutionTypeCodes: nil, institutionFilterMode: "soft", rideDate: rideDate)
    }

    static func solve(
        _ from: String, _ to: String, lineName: String? = nil, rideDate: String?
    ) -> RouteSolver.SolvedSection? {
        let env = Self.environment
        let section = RouteSection(
            from: from, to: to, lineNames: lineName.map { [$0] })
        return RouteSolver.solveSectionOnDemand(
            section, segmentIndex: 0, train: Self.train(rideDate: rideDate), country: "jp",
            graphStore: env.graphStore, stations: env.stations, continuityAnchor: nil)
    }

    static func km(_ solved: RouteSolver.SolvedSection) -> Double {
        solved.physicalLength / 1000
    }

    static func withinTolerance(_ measured: Double, _ expected: Double, factor: Double = 0.25)
        -> Bool
    {
        abs(measured - expected) <= expected * factor
    }

    /// Nearest solved vertex to `point`, in metres.
    static func minDistanceMeters(_ point: Coordinate, path: [Coordinate]) -> Double {
        path.map { Geometry.distanceMeters(point, $0) }.min() ?? .infinity
    }

    /// `display_point` if present, else the geometry's first coordinate —
    /// good enough for both a `Point` station and a retired `LineString`
    /// section-style feature.
    static func firstCoordinate(_ feature: Stations.Feature) -> Coordinate? {
        if let pair = Stations.displayCoordinate(feature), let coordinate = Coordinate(pair: pair)
        {
            return coordinate
        }
        guard case .array(let coordinates)? = feature.geometry?.coordinates else { return nil }
        if coordinates.count == 2, case .number(let lon) = coordinates[0],
            case .number(let lat) = coordinates[1]
        {
            return Coordinate(lon: lon, lat: lat)
        }
        if case .array(let first)? = coordinates.first, first.count == 2,
            case .number(let lon) = first[0], case .number(let lat) = first[1]
        {
            return Coordinate(lon: lon, lat: lat)
        }
        return nil
    }

    // MARK: - 1. 石勝線 新夕張→夕張 (夕張支線, retired 2019-04-01)

    @Test func shintoyuubariToYuubariSolves2018() throws {
        let solved = try #require(Self.solve("新夕張", "夕張", lineName: "石勝線", rideDate: "2018-06-01"))
        #expect(Self.withinTolerance(Self.km(solved), 16.1))
    }

    @Test func shintoyuubariToYuubariNotSolvedAfterRetirement() throws {
        #expect(Self.solve("新夕張", "夕張", lineName: "石勝線", rideDate: "2019-04-01") == nil)
    }

    @Test func shintoyuubariToYuubariNotSolvedUndated() throws {
        #expect(Self.solve("新夕張", "夕張", lineName: "石勝線", rideDate: nil) == nil)
    }

    // MARK: - 2. 留萌線 深川→増毛 (増毛延伸区間, retired 2016-12-05)

    @Test func fukagawaToMashikeSolves2015() throws {
        let solved = try #require(Self.solve("深川", "増毛", lineName: "留萌線", rideDate: "2015-06-01"))
        #expect(Self.withinTolerance(Self.km(solved), 66.8))
    }

    @Test func fukagawaToMashikeNotSolved2020() throws {
        #expect(Self.solve("深川", "増毛", lineName: "留萌線", rideDate: "2020-06-01") == nil)
    }

    // MARK: - 3. 高千穂線 延岡→高千穂 (retired 2008)

    @Test func nobeokaToTakachihoSolves2004() throws {
        let solved = try #require(
            Self.solve("延岡", "高千穂", lineName: "高千穂線", rideDate: "2004-06-01"))
        #expect(Self.withinTolerance(Self.km(solved), 50.0))
    }

    // MARK: - 4. 大船渡線 気仙沼→盛 (BRT replaced, still in overlay as of ride date)

    @Test func kesennumaToSakariSolves2019() throws {
        let solved = try #require(
            Self.solve("気仙沼", "盛", rideDate: "2019-06-01"))
        #expect(Self.withinTolerance(Self.km(solved), 43.7))
    }

    // MARK: - 5. 日高線 鵡川→様似 (retired 2021-04-01)

    @Test func mukawaToSamaniSolves2020() throws {
        let solved = try #require(
            Self.solve("鵡川", "様似", lineName: "日高線", rideDate: "2020-06-01"))
        #expect(Self.withinTolerance(Self.km(solved), 116))
    }

    // MARK: - 6. 常磐線 相馬→亘理 (old inland alignment via 新地, replaced 2016-12-10)

    /// The old coastal alignment (retired 2016-12-10) must splice into the
    /// undated track at both ends; the inland alignment is dated
    /// valid_from 2016-12-10, so a 2010 ride can only take the old one.
    @Test func somaToWatariSolvesOldAlignment2010() throws {
        let solved = try #require(
            Self.solve("相馬", "亘理", lineName: "常磐線", rideDate: "2010-06-01"))
        #expect(Self.withinTolerance(Self.km(solved), 34))

        let oldShinchi = try #require(
            Self.environment.overlay.stations.first {
                Stations.stationName($0) == "新地"
                    && $0.properties["valid_to"]?.jsString == "2016-12-10"
            })
        let oldPoint = try #require(Self.firstCoordinate(oldShinchi))
        #expect(Self.minDistanceMeters(oldPoint, path: solved.coordinates) <= 300)
    }

    @Test func somaToWatariSolvesNewAlignment2020() throws {
        let solved = try #require(
            Self.solve("相馬", "亘理", lineName: "常磐線", rideDate: "2020-06-01"))

        let currentShinchi = try #require(
            Self.environment.stations.features.first {
                Stations.stationName($0) == "新地" && Stations.stationLineName($0) == "常磐線"
                    && ($0.properties["valid_to"]?.jsString.isEmpty ?? true)
            })
        let currentPoint = try #require(Self.firstCoordinate(currentShinchi))
        #expect(Self.minDistanceMeters(currentPoint, path: solved.coordinates) <= 300)
    }

    // MARK: - 7. 留萌線 深川→石狩沼田 (remaining stub, retired 2026-04-01)

    @Test func fukagawaToIshikariNumataNotSolvedAfterRetirement() throws {
        #expect(Self.solve("深川", "石狩沼田", lineName: "留萌線", rideDate: "2026-07-01") == nil)
    }

    @Test func fukagawaToIshikariNumataSolvesBeforeRetirement() throws {
        let solved = try #require(
            Self.solve("深川", "石狩沼田", lineName: "留萌線", rideDate: "2026-03-01"))
        #expect(Self.withinTolerance(Self.km(solved), 14.4))
    }

    // MARK: - Joins land on the right railway (review of the builder)

    /// 屋代線 must splice into しなの鉄道 at 屋代, not into 北陸新幹線 47 m away.
    @Test func yashiroToSuzakaSolves2011() throws {
        let solved = try #require(
            Self.solve("屋代", "須坂", lineName: "屋代線", rideDate: "2011-06-01"))
        #expect(Self.withinTolerance(Self.km(solved), 24.4))
    }

    /// 江差線 must meet the 在来線 at 木古内, not 北海道新幹線 (opened 2016).
    @Test func kikonaiToEsashiSolves2013() throws {
        let solved = try #require(
            Self.solve("木古内", "江差", lineName: "江差線", rideDate: "2013-06-01"))
        #expect(Self.withinTolerance(Self.km(solved), 42.1))
    }
}
