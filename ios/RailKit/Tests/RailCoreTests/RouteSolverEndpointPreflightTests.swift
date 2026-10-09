import Testing
@testable import RailCore

struct RouteSolverEndpointPreflightTests {
    private let start = Coordinate(lon: 139, lat: 35)
    private let middle = Coordinate(lon: 139.01, lat: 35)
    private let end = Coordinate(lon: 139.02, lat: 35)

    private var rail: [RouteGraph.SectionFeature] {
        [.init(properties: .init(
            lineName: "Rail", operator: "Operator", institutionTypeCode: "1"),
            lines: [[start, middle, end]])]
    }

    private func station(
        _ point: Coordinate, name: String, code: String, validTo: String? = nil
    ) -> Stations.Feature {
        var properties: [String: Stations.Value] = [
            "station_name": .string(name), "n02_station_code": .string(code),
            "line_name": .string("Rail"), "operator": .string("Operator"),
            "institution_type_code": .string("1"),
        ]
        if let validTo { properties["valid_to"] = .string(validTo) }
        return .init(properties: properties, geometry: .init(
            type: "Point", coordinates: .array([.number(point.lon), .number(point.lat)])))
    }

    private func stations(retiredFrom: Bool = false, retiredTo: Bool = false) -> Stations.Index {
        Stations.Index([
            station(start, name: "Start", code: "A", validTo: retiredFrom ? "2020-01-01" : nil),
            station(end, name: "End", code: "B", validTo: retiredTo ? "2020-01-01" : nil),
        ])
    }

    @Test("Retired endpoints reject before any graph build, dated or undated", arguments: [false, true])
    func retiredEndpointsDoNotBuildGraph(codeOnly: Bool) {
        let section = RouteSection(
            from: codeOnly ? nil : "Start", to: codeOnly ? "" : "End",
            fromN02StationCode: "A", toN02StationCode: "B")
        for rideDate: String? in [nil, "2020-01-01", "2021-01-01"] {
            for retireFrom in [false, true] {
                var builds = 0
                let store = RouteGraph.RouteGraphStore(sections: rail, augment: { _, _ in builds += 1 })
                let index = stations(retiredFrom: retireFrom, retiredTo: !retireFrom)
                let result = RouteSolver.solveSectionOnDemand(
                    section, segmentIndex: 0, train: .init(rideDate: rideDate), country: "jp",
                    graphStore: store, stations: index)
                #expect(result == nil)
                #expect(builds == 0)
            }
        }
    }

    @Test("Absent names, codes and endpoints reject before any graph build")
    func missingEndpointsDoNotBuildGraph() {
        let sections = [
            RouteSection(from: "Absent", to: "End"),
            RouteSection(from: "Start", to: "Absent"),
            RouteSection(from: nil, to: "End"),
            RouteSection(from: "Start", to: ""),
            RouteSection(from: nil, to: nil, fromN02StationCode: "Unknown", toN02StationCode: "B"),
            RouteSection(from: nil, to: nil, fromN02StationCode: "A", toN02StationCode: "Unknown"),
        ]
        for section in sections {
            var builds = 0
            let store = RouteGraph.RouteGraphStore(sections: rail, augment: { _, _ in builds += 1 })
            #expect(RouteSolver.solveSectionOnDemand(
                section, segmentIndex: 0, train: .init(), country: "jp",
                graphStore: store, stations: stations()) == nil)
            #expect(builds == 0)
        }
    }

    @Test("Viable named and code-only endpoints retain physical routing", arguments: [false, true])
    func viableEndpointsBuildEquivalentPhysicalRoute(codeOnly: Bool) throws {
        let section = RouteSection(
            from: codeOnly ? "" : "Start", to: codeOnly ? nil : "End",
            fromN02StationCode: "A", toN02StationCode: "B")
        let graph = RouteGraph.build(from: rail)
        let anchor = Coordinate(lon: start.lon, lat: start.lat + 0.0002)
        // A retired station remains viable before its exclusive closing date.
        for rideDate: String? in [nil, "2019-12-31"] {
            let index = stations(retiredFrom: rideDate != nil)
            let train = RouteSolver.TrainContext(rideDate: rideDate)
            let direct = try #require(RouteSolver.solveSection(
                section, segmentIndex: 3, train: train, country: "jp",
                graph: graph, stations: index, continuityAnchor: anchor))
            var builds = 0
            let store = RouteGraph.RouteGraphStore(sections: rail, augment: { _, _ in builds += 1 })
            let onDemand = try #require(RouteSolver.solveSectionOnDemand(
                section, segmentIndex: 3, train: train, country: "jp",
                graphStore: store, stations: index, continuityAnchor: anchor))
            #expect(builds > 0)
            #expect(onDemand.coordinates == direct.coordinates)
            #expect(onDemand.rawPathKeys == direct.rawPathKeys)
            #expect(onDemand.fromStationIndex == direct.fromStationIndex)
            #expect(onDemand.toStationIndex == direct.toStationIndex)
            #expect(onDemand.allowedInstitutionTypeCodes == direct.allowedInstitutionTypeCodes)
            #expect(onDemand.attemptIndex == direct.attemptIndex)
            #expect(onDemand.cost == direct.cost)
            #expect(onDemand.physicalLength == direct.physicalLength)
            #expect(!onDemand.coordinates.contains(anchor))
            for (from, to) in zip(onDemand.rawPathKeys, onDemand.rawPathKeys.dropFirst()) {
                #expect(graph.adjacency[from]?.contains { $0.to == to && $0.connector == nil } == true)
            }
        }
    }
}
