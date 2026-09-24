import XCTest

@testable import RailCore

/// ADR 0011: dated validity on solver edges, the ride date in the solver's
/// Dijkstra, and the ride date / history revision in the route cache key.
final class RailValidityTests: XCTestCase {
    private typealias Validity = RouteGraph.RailValidity

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

    // MARK: - (c) cache key

    private func cacheKey(rideDate: String?, historyRevision: String?) -> String? {
        RouteGraph.solveContext(
            train: RouteGraph.CacheKeyTrain(),
            routeSections: [RouteGraph.RouteSection(from: "東京", to: "大阪")],
            country: "jp",
            rideDate: rideDate,
            historyRevision: historyRevision)?.cacheKey
    }

    func testCacheKeyCarriesDateHistoryAndVersion() throws {
        let a = try XCTUnwrap(cacheKey(rideDate: "2019-12-31", historyRevision: "r1"))
        let b = try XCTUnwrap(cacheKey(rideDate: "2020-01-01", historyRevision: "r1"))
        let c = try XCTUnwrap(cacheKey(rideDate: "2019-12-31", historyRevision: "r2"))
        XCTAssertNotEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertTrue(a.contains("solver:21"), a)
        XCTAssertEqual(RouteGraph.routeSolverCacheVersion, "21")
        XCTAssertTrue(a.contains("|date:2019-12-31|history:r1"), a)
        let undated = try XCTUnwrap(cacheKey(rideDate: nil, historyRevision: nil))
        XCTAssertTrue(undated.contains("|date:none|history:none"), undated)
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
}
