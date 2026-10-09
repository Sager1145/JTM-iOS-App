import XCTest

@testable import RailCore

/// ADR 0011: dated validity on solver edges, the ride date in the solver's
/// Dijkstra, and the ride date / history revision in the route cache key.
final class RailValidityTests: XCTestCase {
    private typealias Validity = RouteGraph.RailValidity

    private struct CodedHistoryEnvironment {
        let graphStore: RouteGraph.RouteGraphStore
        let stations: Stations.Index
    }

    nonisolated(unsafe) private static let codedHistoryEnvironment: CodedHistoryEnvironment = {
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
        let collection = Stations.FeatureCollection(features: stationFeatures)
        let registry = try! PhysicalRailJunctionRegistry(data: Data(contentsOf:
            root.appending(path: "app/data/physical-rail-junctions.json")))
        // Match the production physical graph: reviewed junctions, no passenger
        // transfer augmentation. Legacy browser audits retain their own graph.
        let graphStore = RouteGraph.RouteGraphStore(
            sections: sections, policy: .physicalRailway,
            junctions: registry.junctions(for: "jp"),
            cachePolicy: .bounded(maximumNodes: 100_000))
        return CodedHistoryEnvironment(
            graphStore: graphStore, stations: Stations.Index(collection))
    }()

    // MARK: - (a) isValid truth table

    func testUndatedRideUsesOnlyEdgesWithoutValidTo() {
        XCTAssertTrue(Validity.isValid(validFrom: nil, validTo: nil, on: nil))
        XCTAssertTrue(Validity.isValid(validFrom: "2000-01-01", validTo: nil, on: nil))
        XCTAssertFalse(Validity.isValid(validFrom: nil, validTo: "2020-01-01", on: nil))
        XCTAssertFalse(Validity.isValid(validFrom: "2000-01-01", validTo: "2020-01-01", on: nil))
    }

    func testDatedRideUsesHalfOpenInterval() {
        let from = "2000-01-01"
        let to = "2020-01-01"
        XCTAssertFalse(Validity.isValid(validFrom: from, validTo: to, on: "1999-12-31"))
        XCTAssertTrue(Validity.isValid(validFrom: from, validTo: to, on: "2000-01-01"),
                      "day == validFrom is valid")
        XCTAssertTrue(Validity.isValid(validFrom: from, validTo: to, on: "2019-12-31"))
        XCTAssertFalse(Validity.isValid(validFrom: from, validTo: to, on: "2020-01-01"),
                       "day == validTo is invalid")
        XCTAssertTrue(Validity.isValid(validFrom: nil, validTo: nil, on: "2020-01-01"))
        XCTAssertTrue(Validity.isValid(validFrom: nil, validTo: to, on: "1900-01-01"))
        XCTAssertFalse(Validity.isValid(validFrom: from, validTo: nil, on: "1999-12-31"))
    }

    func testGarbageRideDateBehavesAsUndated() {
        for garbage in ["", "garbage", "abc", "2019/12/31", " 2019-12-31", "31/12/2019"] {
            XCTAssertEqual(
                Validity.isValid(validFrom: nil, validTo: "2020-01-01", on: garbage),
                Validity.isValid(validFrom: nil, validTo: "2020-01-01", on: nil), garbage)
            XCTAssertEqual(
                Validity.isValid(validFrom: "2000-01-01", validTo: nil, on: garbage),
                Validity.isValid(validFrom: "2000-01-01", validTo: nil, on: nil), garbage)
        }
    }

    /// Shape-only rule (JS parity): "2019-13-45" is plain ISO shape, so it is
    /// dated and compares as a string.
    func testShapeValidRideDateIsDatedEvenIfNotACalendarDay() {
        XCTAssertTrue(Validity.isValid(validFrom: nil, validTo: "2020-01-01", on: "2019-13-45"))
        XCTAssertFalse(Validity.isValid(validFrom: nil, validTo: "2019-12-31", on: "2019-13-45"))
        XCTAssertFalse(Validity.isValid(validFrom: "2020-01-01", validTo: nil, on: "2019-13-45"))
    }

    func testEmptyStringBoundsBehaveAsNil() {
        XCTAssertTrue(Validity.isValid(validFrom: "", validTo: "", on: nil))
        XCTAssertTrue(Validity.isValid(validFrom: "", validTo: "", on: "2019-12-31"))
        XCTAssertTrue(Validity.isValid(validFrom: nil, validTo: "", on: nil))
        XCTAssertFalse(Validity.isValid(validFrom: "", validTo: "2020-01-01", on: nil))
    }

    // MARK: - Station transfer connectors carry the stations' validity

    private func connectorEdges(validTo: String?) -> [RouteGraph.Edge] {
        let graph = RouteGraph.build(from: [
            RouteGraph.SectionFeature(
                properties: RouteGraph.SectionProperties(lineName: "L1", operator: "O"),
                lines: [[Coordinate(lon: 135.0, lat: 35.0), Coordinate(lon: 135.02, lat: 35.0)]]),
            RouteGraph.SectionFeature(
                properties: RouteGraph.SectionProperties(lineName: "L2", operator: "O"),
                lines: [[Coordinate(lon: 135.001, lat: 35.001), Coordinate(lon: 135.001, lat: 35.02)]]),
        ])
        func station(_ lon: Double, _ lat: Double, validTo: String?) -> Stations.Feature {
            var feature = Stations.Feature(
                properties: [
                    "station_name": .string("S"), "n02_group_code": .string("G1"),
                ],
                geometry: Stations.Geometry(
                    type: "Point", coordinates: .array([.number(lon), .number(lat)])))
            if let validTo { feature.properties["valid_to"] = .string(validTo) }
            return feature
        }
        RouteSolver.addStationTransferConnectorEdges(
            graph: graph,
            stations: [station(135.0, 35.0, validTo: validTo), station(135.001, 35.001, validTo: nil)])
        return graph.adjacency.values.flatMap { $0 }.filter { $0.connector != nil }
    }

    func testConnectorEdgesCarryStationValidTo() {
        let dated = connectorEdges(validTo: "2020-01-01")
        XCTAssertFalse(dated.isEmpty)
        XCTAssertTrue(dated.allSatisfy { $0.validTo == "2020-01-01" }, "\(dated.map(\.validTo))")
        let undated = connectorEdges(validTo: nil)
        XCTAssertFalse(undated.isEmpty)
        XCTAssertTrue(undated.allSatisfy { $0.validTo == nil && $0.validFrom == nil })
    }

    // MARK: - (b) Dijkstra honours the ride date

    /// A-B-C in a line, plus a shortcut A-C retired on 2020-01-01.
    private func makeGraph() -> RouteGraph.Graph {
        let graph = RouteGraph.Graph(cellSize: 0.01)
        graph.nodes = [
            "A": Coordinate(lon: 135.000, lat: 35.000),
            "B": Coordinate(lon: 135.005, lat: 35.005),
            "C": Coordinate(lon: 135.010, lat: 35.000),
        ]
        func edge(_ to: String, _ length: Double, validTo: String? = nil) -> RouteGraph.Edge {
            RouteGraph.Edge(
                to: to, length: length, institutionTypeCode: "", railwayClassCode: "",
                lineName: "", operator: "", connector: nil, validFrom: nil, validTo: validTo)
        }
        graph.adjacency = [
            "A": [edge("B", 600), edge("C", 900, validTo: "2020-01-01")],
            "B": [edge("A", 600), edge("C", 600)],
            "C": [edge("B", 600), edge("A", 900, validTo: "2020-01-01")],
        ]
        return graph
    }

    private func path(on rideDate: String?) -> [String]? {
        let solved = RouteSolver.dijkstra(
            graph: makeGraph(),
            sourceCandidates: [RouteSolver.Candidate(key: "A", distance: 0)],
            targetKeys: ["C"],
            train: RouteSolver.TrainPolicy(rideDate: rideDate),
            allowedCodes: [])
        return solved.first?.pathKeys
    }

    func testRideBeforeRetirementTakesShortcut() {
        XCTAssertEqual(path(on: "2019-12-31"), ["A", "C"])
    }

    func testRideOnRetirementDayAvoidsShortcut() {
        XCTAssertEqual(path(on: "2020-01-01"), ["A", "B", "C"])
    }

    func testUndatedRideAvoidsShortcut() {
        XCTAssertEqual(path(on: nil), ["A", "B", "C"])
    }

    func testPinnedDijkstraCannotSettleConnectorOnlyShortcut() throws {
        let graph = RouteGraph.Graph(cellSize: 1)
        graph.nodes = [
            "A": Coordinate(lon: 0, lat: 0),
            "B": Coordinate(lon: 1, lat: 0),
            "C": Coordinate(lon: 0.5, lat: 0),
        ]
        func connector(_ to: String, _ length: Double) -> RouteGraph.Edge {
            RouteGraph.Edge(
                to: to, length: length, institutionTypeCode: "", railwayClassCode: "",
                lineName: "", operator: "", connector: .init())
        }
        func rail(_ to: String, _ length: Double) -> RouteGraph.Edge {
            RouteGraph.Edge(
                to: to, length: length, institutionTypeCode: "1", railwayClassCode: "11",
                lineName: "Opening Line", operator: "Opening Operator", connector: nil,
                validFrom: "2009-12-23", validTo: nil)
        }
        graph.adjacency = [
            "A": [connector("B", 1), rail("C", 100)],
            "B": [],
            "C": [connector("B", 100)],
        ]
        let pinnedHints = RouteSolver.SegmentHints(
            requiredLines: ["Opening Line"])
        func solve(_ date: String?, hints: RouteSolver.SegmentHints? = nil,
                   target: String = "B",
                   policy: RouteSolver.TraversalPolicy = .passengerTransfers) -> [RouteSolver.SolvedTarget]
        {
            RouteSolver.dijkstra(
                graph: graph,
                sourceCandidates: [.init(key: "A", distance: 0)],
                targetKeys: [target], train: .init(rideDate: date),
                allowedCodes: ["1"], hints: hints ?? pinnedHints, traversalPolicy: policy)
        }

        XCTAssertTrue(solve("2009-12-22").isEmpty)
        let opened = try XCTUnwrap(solve("2009-12-23").first)
        XCTAssertEqual(opened.pathKeys, ["A", "C", "B"])
        XCTAssertTrue(opened.edges.contains { $0.connector == nil })

        let operatorPinned = RouteSolver.SegmentHints(
            requiredOperators: ["Opening Operator"])
        XCTAssertTrue(solve("2009-12-22", hints: operatorPinned).isEmpty)
        XCTAssertEqual(
            try XCTUnwrap(solve("2009-12-23", hints: operatorPinned).first).pathKeys,
            ["A", "C", "B"])

        let unconstrained = RouteSolver.SegmentHints()
        XCTAssertEqual(
            try XCTUnwrap(solve("2009-12-23", hints: unconstrained).first).pathKeys,
            ["A", "B"])
        XCTAssertEqual(
            try XCTUnwrap(solve(
                "2009-12-23", hints: unconstrained, target: "A").first).pathKeys,
            ["A"])

        // Passenger routing above still requires a real matching rail edge
        // before a pinned result can settle. Physical routing cannot reach B
        // through either passenger connector, with or without route hints.
        XCTAssertTrue(solve("2009-12-23", policy: .physicalRail).isEmpty)
        XCTAssertTrue(solve("2009-12-23", hints: operatorPinned, policy: .physicalRail).isEmpty)
        XCTAssertTrue(solve("2009-12-23", hints: unconstrained, policy: .physicalRail).isEmpty)
        XCTAssertTrue(solve("2009-12-22", target: "C", policy: .physicalRail).isEmpty)
        XCTAssertEqual(
            try XCTUnwrap(solve("2009-12-23", target: "C", policy: .physicalRail).first).pathKeys,
            ["A", "C"])
    }

    // MARK: - (c) cache key

    private func cacheKey(rideDate: String?, historyRevision: String?,
                          cacheVersion: String = RouteGraph.routeSolverCacheVersion) -> String? {
        RouteGraph.solveContext(
            train: RouteGraph.CacheKeyTrain(),
            routeSections: [RouteGraph.RouteSection(from: "東京", to: "大阪")],
            country: "jp",
            cacheVersion: cacheVersion,
            rideDate: rideDate,
            historyRevision: historyRevision)?.cacheKey
    }

    func testCacheKeyCarriesDateHistoryAndVersion() throws {
        let a = try XCTUnwrap(cacheKey(rideDate: "2019-12-31", historyRevision: "r1"))
        let b = try XCTUnwrap(cacheKey(rideDate: "2020-01-01", historyRevision: "r1"))
        let c = try XCTUnwrap(cacheKey(rideDate: "2019-12-31", historyRevision: "r2"))
        XCTAssertNotEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertTrue(a.hasPrefix("solver:27|"), a)
        XCTAssertEqual(RouteGraph.routeSolverCacheVersion, "27")
        XCTAssertEqual(RouteGraph.routeDrawnCacheVersion, "29")
        XCTAssertTrue(a.contains("|date:2019-12-31|history:r1"), a)
        let undated = try XCTUnwrap(cacheKey(rideDate: nil, historyRevision: nil))
        XCTAssertTrue(undated.contains("|date:none|history:none"), undated)
    }

    func testLegacyCoordinateCacheVersionsAreExplicitAndDistinctFromPhysicalDefaults() throws {
        XCTAssertEqual(RouteGraph.legacyCoordinateSolverCacheVersion, "25")
        XCTAssertEqual(RouteGraph.legacyCoordinateDrawnCacheVersion, "26")
        XCTAssertNotEqual(RouteGraph.legacyCoordinateSolverCacheVersion, RouteGraph.routeSolverCacheVersion)
        XCTAssertNotEqual(RouteGraph.legacyCoordinateDrawnCacheVersion, RouteGraph.routeDrawnCacheVersion)
        let physical = try XCTUnwrap(cacheKey(rideDate: "2019-12-31", historyRevision: "r1"))
        let coordinate = try XCTUnwrap(cacheKey(
            rideDate: "2019-12-31", historyRevision: "r1",
            cacheVersion: RouteGraph.legacyCoordinateSolverCacheVersion))
        XCTAssertTrue(coordinate.hasPrefix("solver:25|"), coordinate)
        XCTAssertTrue(coordinate.contains("|date:2019-12-31|history:r1"), coordinate)
        XCTAssertNotEqual(coordinate, physical)
    }

    // MARK: - Endpoint station candidates honour the ride date

    func testEndpointStationCandidatesAreFilteredByRideDate() {
        func station(_ name: String, validTo: String?) -> Stations.Feature {
            var feature = Stations.Feature(
                properties: ["station_name": .string(name)],
                geometry: Stations.Geometry(
                    type: "Point", coordinates: .array([.number(141.6), .number(43.8)])))
            if let validTo { feature.properties["valid_to"] = .string(validTo) }
            return feature
        }
        let index = Stations.Index(Stations.FeatureCollection(features: [
            station("増毛", validTo: "2016-12-05"), station("留萌", validTo: nil),
        ]))
        func kept(_ date: String?) -> [Int] {
            RouteSolver.filterStationCandidatesByRideDate([0, 1], in: index, rideDate: date)
        }
        XCTAssertEqual(kept("2016-12-04"), [0, 1])
        XCTAssertEqual(kept("2016-12-05"), [1])
        XCTAssertEqual(kept(nil), [1])
    }

    func testStationDedupePreservesDisjointHistoricalServicePeriods() {
        func station(_ service: [String?]) -> Stations.Feature {
            Stations.Feature(
                properties: [
                    "station_name": .string("静内"),
                    "line_name": .string("日高線"),
                    "operator": .string("北海道旅客鉄道"),
                    "service_validity": .array(service.map { value in
                        value.map(Stations.Value.string) ?? .null
                    }),
                ],
                geometry: Stations.Geometry(
                    type: "LineString",
                    coordinates: .array([
                        .array([.number(142.36108), .number(42.33623)]),
                        .array([.number(142.3599), .number(42.33679)]),
                    ])))
        }
        let index = Stations.Index(Stations.FeatureCollection(features: [
            station([nil, "2015-01-08"]),
            station(["2015-01-27", "2015-03-01"]),
        ]))
        let candidates = index.candidateIndices(for: .name("静内"))
        XCTAssertEqual(candidates, [0, 1])
        XCTAssertEqual(
            RouteSolver.filterStationCandidatesByRideDate(
                candidates, in: index, rideDate: "2015-02-01"),
            [1])
    }

    func testCodedDonanEndpointsResolvePreTransferStationVariants() throws {
        let environment = Self.codedHistoryEnvironment
        defer { environment.graphStore.invalidate() }
        for (name, code) in [("五稜郭", "000440"), ("木古内", "000478")] {
            let candidates = environment.stations.candidateIndices(
                for: .stop(.init(name: name, n02StationCode: code)))
            let dated = RouteSolver.filterStationCandidatesByRideDate(
                candidates, in: environment.stations, rideDate: "2016-03-25")
            XCTAssertTrue(dated.contains { index in
                let feature = environment.stations.features[index]
                return Stations.stationCode(feature) == code
                    && Stations.stationLineName(feature) == "江差線"
                    && Stations.stationOperator(feature) == "北海道旅客鉄道"
            }, "\(name) must keep its surveyed code on the pre-transfer variant")
        }
        let section = RouteSection(
            from: "五稜郭", to: "木古内",
            fromN02StationCode: "000440", toN02StationCode: "000478",
            lineNames: ["江差線"])
        let train = RouteSolver.TrainContext(
            id: "coded-donan-history", number: "", trainType: "", company: "JR北海道",
            origin: "五稜郭", destination: "木古内", preferredLineNames: ["江差線"],
            preferredOperatorNames: ["北海道旅客鉄道"],
            allowedInstitutionTypeCodes: ["2"], institutionFilterMode: "soft",
            rideDate: "2016-03-25")
        let solved = try XCTUnwrap(RouteSolver.solveSectionOnDemand(
            section, segmentIndex: 0, train: train, country: "jp",
            graphStore: environment.graphStore, stations: environment.stations,
            continuityAnchor: nil))
        XCTAssertEqual(solved.hints.requiredLines, Set(["江差線"]))
        XCTAssertGreaterThan(solved.physicalLength / 1000, 25)
        XCTAssertLessThan(solved.physicalLength / 1000, 50)
    }
}
