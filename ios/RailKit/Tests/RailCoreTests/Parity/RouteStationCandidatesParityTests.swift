import Foundation
import Testing

@testable import RailCore

/// Station geometry snapping from `app-route-solver.js`, over the complete
/// shipped Hong Kong and Macao graphs and station collections.
struct RouteStationCandidatesParityTests {
    struct Fixture: Decodable {
        struct Hints: Decodable {
            let preferredLines: [String]
            let preferredOperators: [String]
            let requiredLines: [String]
            let requiredOperators: [String]
            let requirePreferredInstitution: Bool
        }
        struct Candidate: Decodable {
            let key: String
            let distance: Double
            let score: Double
            let hasPreferredInstitution: Bool
            let stationIndex: Int
        }
        struct Probe: Decodable {
            let stationIndex: Int
            let allowedCodes: [String]
            let baseHints: Hints
            let base: [Candidate]
            let preferredHints: Hints
            let preferred: [Candidate]
            let strictHints: Hints
            let strict: [Candidate]
        }
        struct Collection: Decodable {
            let stationIndices: [Int]
            let hints: Hints
            let allowedCodes: [String]
            let result: [Candidate]
        }
        struct CountryCase: Decodable {
            let country: String
            let graphNodeCount: Int
            let probes: [Probe]
            let collection: Collection
        }
        let cases: [CountryCase]
    }

    static func fixture() throws -> Fixture {
        let fixture = try PortFixtures.decode(Fixture.self, "route-station-candidates.json")
        try #require(fixture.cases.count == 2 && Set(fixture.cases.map(\.country)) == ["mo", "hk"],
                     "Station-candidate parity requires both Macao and Hong Kong")
        for item in fixture.cases {
            try #require(!item.probes.isEmpty, "\(item.country) station probes are missing")
            try #require(!item.collection.stationIndices.isEmpty,
                         "\(item.country) station collection inputs are missing")
        }
        return fixture
    }

    static func dataURL(_ base: String, _ country: String) throws -> URL {
        try PortFixtures.repositoryRoot().appending(path: "app/data/\(base)-\(country).json")
    }

    static func hints(_ value: Fixture.Hints) -> RouteSolver.SegmentHints {
        .init(
            preferredLines: Set(value.preferredLines),
            preferredOperators: Set(value.preferredOperators),
            requiredLines: Set(value.requiredLines),
            requiredOperators: Set(value.requiredOperators),
            requirePreferredInstitution: value.requirePreferredInstitution)
    }

    static func expect(
        _ actual: [RouteSolver.StationNodeCandidate],
        _ expected: [Fixture.Candidate],
        _ label: String
    ) {
        #expect(actual.count == expected.count, "\(label) candidate count")
        for (left, right) in zip(actual, expected) {
            #expect(left.key == right.key, "\(label) key")
            #expect(left.stationIndex == right.stationIndex, "\(label) station")
            #expect(left.hasPreferredInstitution == right.hasPreferredInstitution, "\(label) institution")
            #expect(left.distance.ulpDistance(to: right.distance) <= 2, "\(label) distance")
            #expect(left.score.ulpDistance(to: right.score) <= 4, "\(label) score")
        }
    }

    @Test func graphNodeCandidates() throws {
        for item in try Self.fixture().cases {
            let sections = try RouteGraph.SectionFeatureCollection.load(
                contentsOf: Self.dataURL("rail-sections", item.country)).features
            let stationCollection = try Stations.FeatureCollection.load(
                contentsOf: Self.dataURL("stations", item.country))
            let stations = Stations.Index(stationCollection)
            let graph = RouteGraph.build(from: sections, policy: .coordinateParity)
            #expect(graph.nodeCount == item.graphNodeCount)

            for probe in item.probes {
                Self.expect(
                    RouteSolver.stationCandidateGraphNodes(
                        stationIndex: probe.stationIndex, stations: stations, graph: graph,
                        hints: Self.hints(probe.baseHints), allowedCodes: probe.allowedCodes),
                    probe.base, "\(item.country)/\(probe.stationIndex)/base")
                Self.expect(
                    RouteSolver.stationCandidateGraphNodes(
                        stationIndex: probe.stationIndex, stations: stations, graph: graph,
                        hints: Self.hints(probe.preferredHints), allowedCodes: probe.allowedCodes),
                    probe.preferred, "\(item.country)/\(probe.stationIndex)/preferred")
                Self.expect(
                    RouteSolver.stationCandidateGraphNodes(
                        stationIndex: probe.stationIndex, stations: stations, graph: graph,
                        hints: Self.hints(probe.strictHints), allowedCodes: probe.allowedCodes),
                    probe.strict, "\(item.country)/\(probe.stationIndex)/strict")
            }

            let collection = item.collection
            Self.expect(
                RouteSolver.collectStationCandidateGraphNodes(
                    stationIndices: collection.stationIndices,
                    stations: stations,
                    graph: graph,
                    hints: Self.hints(collection.hints),
                    allowedCodes: collection.allowedCodes),
                collection.result, "\(item.country)/collection")
        }
    }
}

struct RecordedStationSourceAnchorTests {
    private func station(
        line: String = "Rail", code: String = "CN-12306-KMM", group: String = "official-group",
        anchor: Stations.Value? = .number(6_682_022_862)
    ) -> Stations.Feature {
        var properties: [String: Stations.Value] = [
            "station_name": .string("Shared"), "n02_station_code": .string(code),
            "n02_group_code": .string(group), "line_name": .string(line),
            "line_id": .string("rail"), "operator": .string("Operator"),
            "railway_class_code": .string("12"), "institution_type_code": .string("4"),
        ]
        properties["source_anchor_node_id"] = anchor
        return .init(properties: properties, geometry: .init(
            type: "Point", coordinates: .array([.number(139), .number(35.0001)])))
    }

    private func graph() -> RouteGraph.Graph {
        RouteGraph.build(from: [
            .init(properties: .init(lineName: "Rail", operator: "Operator", institutionTypeCode: "4",
                                   railwayClassCode: "12", trackID: "rail"),
                  lines: [[.init(lon: 139, lat: 35), .init(lon: 139.001, lat: 35)]],
                  sourceNodeIDs: [["osm-node-6682022862", "osm-node-2"]]),
            .init(properties: .init(lineName: "Metro", operator: "Operator", institutionTypeCode: "4",
                                   railwayClassCode: "12", trackID: "metro"),
                  lines: [[.init(lon: 139, lat: 35.0001), .init(lon: 139.001, lat: 35.0001)]],
                  sourceNodeIDs: [["osm-node-6682022862", "osm-node-4"]]),
        ])
    }

    @Test("A recorded station anchor binds only its surveyed source node and track beside disconnected metro")
    func recordedAnchorBindsExactSourceNodeAndTrack() throws {
        let graph = graph()
        let candidates = RouteSolver.stationCandidateGraphNodes(
            stationIndex: 0, stations: Stations.Index([station()]), graph: graph)
        let candidate = try #require(candidates.first)
        #expect(candidates.count == 1)
        #expect(candidate.key.hasSuffix("@source-node:osm-node-6682022862"))
        #expect(graph.nodeMeta[candidate.key]?.lineNames == ["Rail"])
        #expect(graph.nodes[candidate.key] == Coordinate(lon: 139, lat: 35))
    }

    @Test("Missing or invalid recorded anchors cannot fall back to a nearby railway")
    func missingRecordedAnchorsStayUnresolved() {
        for anchor: Stations.Value in [.number(999), .null, .string(""), .bool(false)] {
            #expect(RouteSolver.stationCandidateGraphNodes(
                stationIndex: 0, stations: Stations.Index([station(anchor: anchor)]), graph: graph()).isEmpty)
        }
        var missingLine = station()
        missingLine.properties.removeValue(forKey: "line_id")
        #expect(RouteSolver.stationCandidateGraphNodes(
            stationIndex: 0, stations: Stations.Index([missingLine]), graph: graph()).isEmpty)
    }

    @Test("Station records without a recorded anchor retain legacy nearby candidates")
    func unanchoredStationsRetainLegacySnapping() {
        let graph = graph()
        let candidates = RouteSolver.stationCandidateGraphNodes(
            stationIndex: 0, stations: Stations.Index([station(anchor: nil)]), graph: graph)
        #expect(candidates.contains { graph.nodeMeta[$0.key]?.lineNames.contains("Metro") == true })
    }

    @Test("Coded anchored endpoints keep explicit station groups and reject unrelated namesakes")
    func anchoredEndpointExpansionPreservesExplicitIdentity() {
        let index = Stations.Index([
            station(), station(line: "Branch", code: "sibling-code"),
            station(line: "Metro", code: "metro-code", group: "metro-group"),
        ])
        #expect(RouteSolver.exactSourceCodeIndices("CN-12306-KMM", in: index) == [0])
    }

    @Test("Only CN solve contexts change for the recorded source anchor policy")
    func sourceAnchorCacheRevisionIsLimitedToCN() throws {
        let sections = [RouteGraph.RouteSection(from: "Start", to: "End")]
        let unchanged = try #require(RegistryIdentityTestGate.withProvider({ region in
            RegistryIdentity(bundle: RegistryBundle(region: region, run: 1))
        }) {
            RouteGraph.solveContext(train: .init(), routeSections: sections, country: "jp")
        })
        let oldCNKey = unchanged.cacheKey + "|source-anchor:1"
        for country in ["cn", "CN"] {
            let cn = try #require(RegistryIdentityTestGate.withProvider({ region in
                RegistryIdentity(bundle: RegistryBundle(region: region, run: 1))
            }) {
                RouteGraph.solveContext(train: .init(), routeSections: sections, country: country)
            })
            #expect(cn.cacheKey.hasSuffix("|source-anchor:1"))
            #expect(cn.cacheKey.contains("|source-display-identity:1"))
            #expect(cn.cacheKey != oldCNKey)
            #expect(cn.cacheKey.replacingOccurrences(of: "|source-display-identity:1", with: "") == oldCNKey)
        }
        for country in ["jp", "tw", "kr", "hk", "mo"] {
            let context = try #require(RegistryIdentityTestGate.withProvider({ region in
                RegistryIdentity(bundle: RegistryBundle(region: region, run: 1))
            }) {
                RouteGraph.solveContext(train: .init(), routeSections: sections, country: country)
            })
            #expect(!context.cacheKey.contains("|source-anchor:"))
            #expect(!context.cacheKey.contains("|source-display-identity:"))
            #expect(context.cacheKey == unchanged.cacheKey)
        }
    }
}
