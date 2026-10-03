import Foundation
import Testing

@testable import RailCore

struct RouteSectionSolveParityTests {
    struct Fixture: Decodable {
        struct Train: Decodable {
            let id: String
            let number: String
            let trainType: String
            let company: String
            let origin: String
            let destination: String
            let preferredLineNames: [String]
            let preferredOperatorNames: [String]
            let allowedInstitutionTypeCodes: [String]?
            let institutionFilterMode: String
        }
        struct Connectors: Decodable { let directedCount: Int; let digest: String }
        struct Pair: Decodable { let from: Double; let to: Double }
        struct Properties: Decodable {
            let allowed_institution_type_codes: [String]
            let preferred_line_names: [String]
            let required_line_names: [String]
            let required_operator_names: [String]
            let preferred_operator_names: [String]
            let solve_mode: String
            let require_preferred_institution: Bool
            let used_institution_type_codes: [String]
            let path_coordinate_count: Int
            let raw_path_coordinate_count: Int
            let snap_distance_m: Pair
            let physical_length_m: Double
            let raw_physical_length_m: Double
            let cost: Double
            // Only `solveSection`'s own attempts set this — `solveOfficialInterval`
            // (`officialSolved` below) never does, so it's optional here.
            let solve_attempt_index: Int?
        }
        struct Geometry: Decodable { let coordinates: [[Double]] }
        struct Feature: Decodable { let properties: Properties; let geometry: Geometry }
        struct Solve: Decodable {
            let section: RouteSection
            let continuityAnchor: [Double]?
            let feature: Feature?
        }
        struct CountryCase: Decodable {
            let country: String
            let train: Train
            let graphNodeCount: Int
            let connectors: Connectors
            let solved: [Solve]
            let officialSolved: [Solve]
        }
        let cases: [CountryCase]
    }

    static func fixture() throws -> Fixture {
        try PortFixtures.decode(Fixture.self, "route-section-solve.json")
    }

    static func url(_ base: String, _ country: String) throws -> URL {
        try PortFixtures.repositoryRoot().appending(path: "app/data/\(base)-\(country).json")
    }

    static func context(_ value: Fixture.Train) -> RouteSolver.TrainContext {
        .init(
            id: value.id, number: value.number, trainType: value.trainType,
            company: value.company, origin: value.origin, destination: value.destination,
            preferredLineNames: value.preferredLineNames,
            preferredOperatorNames: value.preferredOperatorNames,
            allowedInstitutionTypeCodes: value.allowedInstitutionTypeCodes,
            institutionFilterMode: value.institutionFilterMode)
    }

    static func jsSorted(_ values: [String]) -> [String] {
        values.sorted { Array($0.utf16).lexicographicallyPrecedes(Array($1.utf16)) }
    }

    static func connectorSummary(_ graph: RouteGraph.Graph) -> (Int, String) {
        var lines: [String] = []
        for (from, edges) in graph.adjacency {
            for edge in edges {
                guard let connector = edge.connector else { continue }
                lines.append([
                    from, edge.to,
                    connector.institutionTypeCodes.joined(separator: ","),
                    connector.stationName, connector.groupCode,
                ].joined(separator: "|"))
            }
        }
        lines = jsSorted(lines)
        return (lines.count, RouteGraph.keyDigest(lines.joined(separator: "\n")))
    }

    struct DirectedPair: Hashable {
        let from: String
        let to: String
    }

    /// Classify the golden geometry against actual input edges, independently
    /// of the solver outcome. A parallel surveyed rail edge makes a segment
    /// legal; only a pair served exclusively by passenger connectors is retired.
    static func passengerOnlyPairs(_ graph: RouteGraph.Graph) -> Set<DirectedPair> {
        var pairs = Set<DirectedPair>()
        for (from, edges) in graph.adjacency {
            let railTargets = Set(edges.filter { $0.connector == nil }.map(\.to))
            for edge in edges where edge.connector != nil && !railTargets.contains(edge.to) {
                pairs.insert(DirectedPair(from: from, to: edge.to))
            }
        }
        return pairs
    }

    static func coordinatePairs(_ coordinates: [Coordinate]) -> Set<DirectedPair> {
        Set(zip(coordinates, coordinates.dropFirst()).map {
            DirectedPair(from: Grid.coordKey($0.0), to: Grid.coordKey($0.1))
        })
    }

    static func expectedUsesPassengerConnector(
        _ feature: Fixture.Feature, pairs: Set<DirectedPair>
    ) -> Bool {
        !coordinatePairs(feature.geometry.coordinates.compactMap(Coordinate.init(pair:)))
            .isDisjoint(with: pairs)
    }

    /// A successful alternative must consist of actual non-connector graph
    /// edges, and its displayed geometry must not reproduce a retired pair.
    static func expectRailGeometry(
        _ solved: RouteSolver.SolvedSection?, graph: RouteGraph.Graph,
        passengerPairs: Set<DirectedPair>, label: String
    ) {
        guard let solved else { return }
        #expect(!solved.coordinates.isEmpty, "\(label) empty successful geometry")
        #expect(!solved.rawPathKeys.isEmpty, "\(label) successful graph path")
        for (from, to) in zip(solved.rawPathKeys, solved.rawPathKeys.dropFirst()) {
            #expect(graph.adjacency[from]?.contains(where: { $0.to == to && $0.connector == nil }) == true,
                    "\(label) path segment must have surveyed rail: \(from)→\(to)")
        }
        let graphCoordinates = solved.rawPathKeys.compactMap { graph.nodes[$0] }
        #expect(solved.coordinates == graphCoordinates, "\(label) geometry must retain the surveyed path")
        let forbiddenPairs = coordinatePairs(solved.coordinates).intersection(passengerPairs)
        let containsNoPassengerSegment = forbiddenPairs.isEmpty
        #expect(containsNoPassengerSegment,
                "\(label) must not draw passenger-only connectors: \(forbiddenPairs)")
    }

    /// The preserved JS goldens describe historical station-marker completion.
    /// Apply that public compatibility helper only when comparing pure-rail
    /// legacy rows; the actual solver geometry is checked independently above.
    static func legacyDisplayCoordinates(
        _ solved: RouteSolver.SolvedSection, stations: Stations.Index,
        continuityAnchor: Coordinate?
    ) -> [Coordinate] {
        var coordinates = RouteSolver.completeRouteEndpointCoordinates(
            solved.coordinates,
            fromStation: stations.features[solved.fromStationIndex],
            toStation: stations.features[solved.toStationIndex])
        if let continuityAnchor, let first = coordinates.first,
           Geometry.distanceMeters(continuityAnchor, first) <= 60 {
            if Geometry.distanceMeters(continuityAnchor, first) <= 0.25 {
                coordinates[0] = continuityAnchor
            } else {
                coordinates.insert(continuityAnchor, at: 0)
            }
        }
        return coordinates
    }

    static func roundedHundredth(_ value: Double) -> Double {
        JSNumber.round(value * 100) / 100
    }

    @Test func completeSectionSolves() throws {
        let fixture = try Self.fixture()
        var railGoldenRows = 0
        var retiredGoldenRows: [String] = []
        for item in fixture.cases {
            let sections = try RouteGraph.SectionFeatureCollection.load(
                contentsOf: Self.url("rail-sections", item.country)).features
            let stationCollection = try Stations.FeatureCollection.load(
                contentsOf: Self.url("stations", item.country))
            let stations = Stations.Index(stationCollection)
            let graph = RouteGraph.build(from: sections, policy: .coordinateParity)
            #expect(graph.nodeCount == item.graphNodeCount)
            RouteSolver.addStationTransferConnectorEdges(
                graph: graph, stations: stationCollection.features)
            let summary = Self.connectorSummary(graph)
            #expect(summary.0 == item.connectors.directedCount, "\(item.country) connector count")
            #expect(summary.1 == item.connectors.digest, "\(item.country) connector digest")
            let passengerPairs = Self.passengerOnlyPairs(graph)

            for (segmentIndex, expected) in item.solved.enumerated() {
                let actual = RouteSolver.solveSection(
                    expected.section,
                    segmentIndex: segmentIndex,
                    train: Self.context(item.train), country: item.country,
                    graph: graph, stations: stations,
                    continuityAnchor: expected.continuityAnchor.flatMap(Coordinate.init(pair:)))
                if let feature = expected.feature,
                   Self.expectedUsesPassengerConnector(feature, pairs: passengerPairs) {
                    let label = "\(item.country)/\(segmentIndex)"
                    retiredGoldenRows.append(label)
                    // The coordinate golden is preserved as evidence of the
                    // old walking hop, but is no longer a drawable rail answer.
                    Self.expectRailGeometry(actual, graph: graph, passengerPairs: passengerPairs, label: label)
                    if let actual {
                        #expect(actual.coordinates != feature.geometry.coordinates.compactMap(Coordinate.init(pair:)),
                                "\(label) must not reproduce the legacy passenger route")
                    }
                    let passengerDrawable = RouteSolver.solveSection(
                        expected.section, segmentIndex: segmentIndex,
                        train: Self.context(item.train), country: item.country,
                        graph: graph, stations: stations,
                        continuityAnchor: expected.continuityAnchor.flatMap(Coordinate.init(pair:)),
                        traversalPolicy: .passengerTransfers)
                    Self.expectRailGeometry(passengerDrawable, graph: graph,
                                           passengerPairs: passengerPairs, label: "\(label) passenger traversal")
                    continue
                }
                railGoldenRows += 1
                if expected.feature == nil {
                    #expect(actual == nil)
                    continue
                }
                let feature = try #require(expected.feature)
                let solved = try #require(actual)
                Self.expectRailGeometry(solved, graph: graph, passengerPairs: passengerPairs,
                                       label: "\(item.country)/\(segmentIndex) pure rail")
                let expectedCoordinates = feature.geometry.coordinates.compactMap(Coordinate.init(pair:))
                let legacyCoordinates = Self.legacyDisplayCoordinates(
                    solved, stations: stations,
                    continuityAnchor: expected.continuityAnchor.flatMap(Coordinate.init(pair:)))
                #expect(legacyCoordinates == expectedCoordinates, "\(item.country)/\(segmentIndex) legacy geometry")
                #expect(legacyCoordinates.count == feature.properties.path_coordinate_count)
                #expect(solved.rawPathKeys.count == feature.properties.raw_path_coordinate_count)
                #expect(Set(solved.allowedInstitutionTypeCodes)
                        == Set(feature.properties.allowed_institution_type_codes))
                #expect(solved.usedInstitutionTypeCodes == feature.properties.used_institution_type_codes)
                #expect(solved.hints.preferredLines == Set(feature.properties.preferred_line_names))
                #expect(solved.hints.requiredLines == Set(feature.properties.required_line_names))
                #expect(solved.hints.requiredOperators == Set(feature.properties.required_operator_names))
                #expect(solved.hints.preferredOperators == Set(feature.properties.preferred_operator_names))
                #expect(solved.hints.solveMode == feature.properties.solve_mode)
                #expect(solved.hints.requirePreferredInstitution
                        == feature.properties.require_preferred_institution)
                #expect(Self.roundedHundredth(solved.snapFrom)
                        == feature.properties.snap_distance_m.from)
                #expect(Self.roundedHundredth(solved.snapTo)
                        == feature.properties.snap_distance_m.to)
                #expect(Self.roundedHundredth(solved.physicalLength) == Self.roundedHundredth(solved.rawPhysicalLength))
                #expect(Self.roundedHundredth(RouteSolver.pathLength(for: legacyCoordinates))
                        == feature.properties.physical_length_m)
                #expect(Self.roundedHundredth(solved.rawPhysicalLength)
                        == feature.properties.raw_physical_length_m)
                #expect(Self.roundedHundredth(solved.cost) == feature.properties.cost)
                if let expectedAttemptIndex = feature.properties.solve_attempt_index {
                    #expect(solved.attemptIndex == expectedAttemptIndex)
                }
            }

            let officialIndex = RouteSolver.OfficialIntervalIndex(sections: sections)
            for (segmentIndex, expected) in item.officialSolved.enumerated() {
                let feature = try #require(expected.feature)
                let actual = RouteSolver.solveOfficialInterval(
                    expected.section, segmentIndex: segmentIndex,
                    train: Self.context(item.train), country: item.country,
                    allowedCodes: feature.properties.allowed_institution_type_codes,
                    intervalIndex: officialIndex, stations: stations,
                    continuityAnchor: expected.continuityAnchor.flatMap(Coordinate.init(pair:)))
                let solved = try #require(actual)
                #expect(solved.coordinates
                        == feature.geometry.coordinates.compactMap(Coordinate.init(pair:)),
                        "\(item.country)/\(segmentIndex) official geometry")
                #expect(solved.rawPathKeys.count == feature.properties.raw_path_coordinate_count)
                #expect(solved.hints.preferredLines == Set(feature.properties.preferred_line_names))
                #expect(solved.hints.requiredLines == Set(feature.properties.required_line_names))
                #expect(solved.hints.requiredOperators == Set(feature.properties.required_operator_names))
                #expect(solved.hints.preferredOperators == Set(feature.properties.preferred_operator_names))
                #expect(solved.hints.solveMode == feature.properties.solve_mode)
                #expect(solved.usedInstitutionTypeCodes == feature.properties.used_institution_type_codes)
                #expect(Self.roundedHundredth(solved.physicalLength)
                        == feature.properties.physical_length_m)
                #expect(Self.roundedHundredth(solved.cost) == feature.properties.cost)
            }

            let graphStore = RouteGraph.RouteGraphStore(sections: sections, policy: .coordinateParity)
            graphStore.augment = { regionalGraph, bbox in
                let features = bbox.map { box in
                    stationCollection.features.filter { feature in
                        guard let pair = Stations.displayCoordinate(feature),
                              let coordinate = Coordinate(pair: pair) else { return false }
                        return coordinate.lon >= box.minX && coordinate.lon <= box.maxX
                            && coordinate.lat >= box.minY && coordinate.lat <= box.maxY
                    }
                } ?? stationCollection.features
                RouteSolver.addStationTransferConnectorEdges(
                    graph: regionalGraph, stations: features)
            }
            for (segmentIndex, expected) in item.solved.enumerated() {
                let actual = RouteSolver.solveSectionOnDemand(
                    expected.section, segmentIndex: segmentIndex,
                    train: Self.context(item.train), country: item.country,
                    graphStore: graphStore, stations: stations,
                    continuityAnchor: expected.continuityAnchor.flatMap(Coordinate.init(pair:)))
                guard let feature = expected.feature else {
                    #expect(actual == nil)
                    continue
                }
                if Self.expectedUsesPassengerConnector(feature, pairs: passengerPairs) {
                    Self.expectRailGeometry(actual, graph: graph, passengerPairs: passengerPairs,
                                           label: "\(item.country)/\(segmentIndex) on-demand")
                    if let actual {
                        #expect(actual.coordinates != feature.geometry.coordinates.compactMap(Coordinate.init(pair:)),
                                "regional geometry must not reproduce a legacy passenger route")
                    }
                    continue
                }
                let solved = try #require(actual)
                Self.expectRailGeometry(solved, graph: graph, passengerPairs: passengerPairs,
                                       label: "\(item.country)/\(segmentIndex) on-demand pure rail")
                let legacyCoordinates = Self.legacyDisplayCoordinates(
                    solved, stations: stations,
                    continuityAnchor: expected.continuityAnchor.flatMap(Coordinate.init(pair:)))
                #expect(legacyCoordinates
                        == feature.geometry.coordinates.compactMap(Coordinate.init(pair:)),
                        "\(item.country)/\(segmentIndex) regional legacy geometry")
            }
        }
        #expect(railGoldenRows + retiredGoldenRows.count == fixture.cases.reduce(0) { $0 + $1.solved.count })
        #expect(railGoldenRows > 0)
        print("SECTION CONTRACT: \(railGoldenRows) exact rail rows; \(retiredGoldenRows.count) retired passenger rows [" + retiredGoldenRows.joined(separator: ",") + "]")
    }
}
