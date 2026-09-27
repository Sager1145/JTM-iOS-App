import XCTest
@testable import RailCore

final class TemporalRouteFastPathTests: XCTestCase {
    private let a = Coordinate(lon: 121, lat: 25)
    private let b = Coordinate(lon: 121.001, lat: 25.001)

    private func station(_ name: String, at coordinate: Coordinate,
                         from: String? = nil, to: String? = nil) -> Stations.Feature {
        var properties: [String: Stations.Value] = [
            "station_name": .string(name), "line_name": .string("L"),
            "operator": .string("O"), "n02_group_code": .string("G"),
        ]
        if let from { properties["valid_from"] = .string(from) }
        if let to { properties["valid_to"] = .string(to) }
        return Stations.Feature(properties: properties, geometry: .init(
            type: "Point", coordinates: .array([.number(coordinate.lon), .number(coordinate.lat)])))
    }

    private func section(from: String? = nil, to: String? = nil,
                         via: Coordinate? = nil) -> RouteGraph.SectionFeature {
        .init(properties: .init(lineName: "L", operator: "O", validFrom: from, validTo: to),
              lines: [via.map { [a, $0, b] } ?? [a, b]])
    }

    private func solve(_ sections: [RouteGraph.SectionFeature], date: String?,
                       stations: [Stations.Feature]? = nil, country: String = "tw",
                       reversed: Bool = false) -> RouteSolver.SolvedSection? {
        RouteSolver.solveOfficialInterval(
            .init(from: reversed ? "B" : "A", to: reversed ? "A" : "B", lineNames: ["L"]),
            segmentIndex: 0, train: .init(rideDate: date), country: country, allowedCodes: [],
            intervalIndex: .init(sections: sections),
            stations: .init(.init(features: stations ?? [station("A", at: a), station("B", at: b)])))
    }

    func testOfficialIntervalsChooseTheValidEraInBothDirections() {
        let old = section(to: "2020-01-01", via: .init(lon: 121.002, lat: 25))
        let current = section(from: "2020-01-01")
        for country in ["tw", "hk", "mo"] {
            for reversed in [false, true] {
                XCTAssertEqual(solve([old, current], date: "2019-12-31", country: country,
                                     reversed: reversed)?.coordinates,
                               reversed ? Array(old.lines[0].reversed()) : old.lines[0])
                for date: String? in ["2020-01-01", nil] {
                    XCTAssertEqual(solve([old, current], date: date, country: country,
                                         reversed: reversed)?.coordinates,
                                   reversed ? Array(current.lines[0].reversed()) : current.lines[0])
                }
            }
        }
    }

    func testOfficialIntervalsRespectOpeningAndClosingBounds() {
        let interval = section(from: "2010-01-01", to: "2020-01-01")
        XCTAssertNil(solve([interval], date: "2009-12-31"))
        XCTAssertNotNil(solve([interval], date: "2010-01-01"))
        XCTAssertNil(solve([interval], date: "2020-01-01"))
        XCTAssertNil(solve([interval], date: nil))
    }

    func testOfficialIntervalsFilterBothStationEndpoints() {
        for retiredName in ["A", "B"] {
            let stations = [station("A", at: a, to: retiredName == "A" ? "2020-01-01" : nil),
                            station("B", at: b, to: retiredName == "B" ? "2020-01-01" : nil)]
            XCTAssertNotNil(solve([section()], date: "2019-12-31", stations: stations))
            XCTAssertNil(solve([section()], date: "2020-01-01", stations: stations))
            XCTAssertNil(solve([section()], date: nil, stations: stations))
        }
    }

    private func connectorGraph(_ stations: [Stations.Feature]) -> RouteGraph.Graph {
        let graph = RouteGraph.build(from: [section()])
        graph.adjacency = [:]
        RouteSolver.addStationTransferConnectorEdges(graph: graph, stations: stations)
        return graph
    }

    func testColocatedRetiredAndCurrentMembershipsKeepCurrentTransfer() throws {
        let retired = station("A", at: a, to: "2020-01-01")
        let current = station("A", at: a, from: "2020-01-01")
        for memberships in [[retired, current], [current, retired]] {
            let graph = connectorGraph(memberships + [station("B", at: b)])
            let source = try XCTUnwrap(graph.nodes.first { $0.value == a }?.key)
            let target = try XCTUnwrap(graph.nodes.first { $0.value == b }?.key)
            for date: String? in ["2019-12-31", "2020-01-01", nil] {
                XCTAssertFalse(RouteSolver.dijkstra(
                    graph: graph, sourceCandidates: [.init(key: source, distance: 0)],
                    targetKeys: [target], train: .init(rideDate: date), allowedCodes: []).isEmpty)
            }
        }
    }

    func testNonOverlappingMembershipsDoNotCreateTransfer() {
        let graph = connectorGraph([station("A", at: a, to: "2020-01-01"),
                                    station("B", at: b, from: "2020-01-01")])
        XCTAssertTrue(graph.adjacency.values.flatMap { $0 }.isEmpty)
    }
}
