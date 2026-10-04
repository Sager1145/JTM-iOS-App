import Foundation
import Testing
@testable import RailCore

@Suite(.serialized)
struct OnEdgeCertificationTests {
    private let a = Coordinate(lon: 139, lat: 35)
    private let b = Coordinate(lon: 139.002, lat: 35)

    private func point(_ fraction: Double, north meters: Double = 0) -> Coordinate {
        Coordinate(lon: a.lon + (b.lon - a.lon) * fraction,
                   lat: a.lat + meters / (6_371_000 * .pi / 180))
    }

    private func identity(_ line: String = "Rail") -> RouteGraph.TrackIdentity {
        .init(operatorName: "Operator", lineName: line, railwayClassCode: "")
    }

    private func key(_ coordinate: Coordinate, line: String = "Rail") -> String {
        RouteGraph.physicalNodeKey(coordinate, identity: identity(line))
    }

    private func rail(_ points: [Coordinate], line: String = "Rail",
                      validFrom: String? = nil, validTo: String? = nil) -> RouteGraph.SectionFeature {
        .init(properties: .init(lineName: line, operator: "Operator", institutionTypeCode: "1",
            validFrom: validFrom, validTo: validTo), lines: [points])
    }

    private func certify(_ points: [Coordinate], graph: RouteGraph.Graph,
                         lines: Set<String> = ["Rail"], date: String? = "2026-07-01") -> [String]? {
        RouteSolver.verifiedPhysicalPathKeys(points, graph: graph, rideDate: date,
            requiredLines: lines, requiredOperators: ["Operator"])
    }

    @Test("A station marker 0.05 m off an edge adds no physical key")
    func onEdgeMarker() {
        let graph = RouteGraph.build(from: [rail([a, b])])
        #expect(certify([a, point(0.5, north: 0.05), b], graph: graph) == [key(a), key(b)])
        #expect(certify([a, point(0.25), point(0.75), b], graph: graph) == [key(a), key(b)])
    }

    @Test("One grid unit of rounding uses only a reachable valid edge")
    func roundedNode() {
        let rounded = Coordinate(lon: b.lon + 0.00001, lat: b.lat)
        let graph = RouteGraph.build(from: [rail([a, b])])
        #expect(Geometry.distanceMeters(rounded, b) < 1)
        #expect(certify([a, rounded], graph: graph) == [key(a), key(b)])
        #expect(certify([a, rounded], graph: graph, lines: ["Other"]) == nil)
        let closed = RouteGraph.build(from: [rail([a, b], validFrom: "2027-01-01")])
        #expect(certify([a, rounded], graph: closed) == nil)
    }

    @Test("Station points outside the one metre corridor fail", arguments: [1.5, 5.0, 25.0])
    func offEdgeMarker(meters: Double) {
        #expect(certify([a, point(0.5, north: meters), b],
            graph: RouteGraph.build(from: [rail([a, b])])) == nil)
    }

    @Test("A node on another identity cannot be treated as a pending marker", arguments: [0.0, 4.0])
    func parallelIdentity(offset: Double) {
        let marker = Grid.normalizeGraphCoord(point(0.5, north: offset))
        let graph = RouteGraph.build(from: [rail([a, b]),
            rail([point(0, north: offset), marker, point(1, north: offset)], line: "Other")])
        #expect(certify([a, marker, b], graph: graph) == nil)
    }

    @Test("Pending points cannot ride connector, junction, or date-invalid edges")
    func excludedEdges() throws {
        for kind in ["connector", "junction", "future", "expired"] {
            let graph = RouteGraph.build(from: [rail([a, b])])
            var edge = try #require(graph.adjacency[key(a)]?.first { $0.to == key(b) })
            switch kind {
            case "connector":
                edge.connector = .init(institutionTypeCodes: ["1"], stationName: "Station", groupCode: "group")
            case "junction":
                edge.physicalJunction = .init(junction: .init(id: "reviewed",
                    from: .init(identity: identity(), coordinate: a),
                    to: .init(identity: identity(), coordinate: b), evidence: ["survey:reviewed"]),
                    institutionTypeCodes: ["1"])
            case "future": edge.validFrom = "2027-01-01"
            default: edge.validTo = "2025-12-31"
            }
            graph.adjacency[key(a)] = [edge]
            #expect(certify([a, point(0.5), b], graph: graph) == nil, "\(kind)")
        }
    }

    @Test("Pending points cannot cross a zero-length reviewed identity junction")
    func pendingJunctionPrefix() {
        let graph = RouteGraph.build(from: [rail([point(-1), a], line: "West"), rail([a, b])],
            junctions: [.init(id: "west-rail", from: .init(identity: identity("West"), coordinate: a),
                to: .init(identity: identity(), coordinate: a), evidence: ["survey:reviewed"])])
        #expect(certify([point(-1), a, point(0.5), b], graph: graph, lines: []) == nil)
    }

    @Test("Pending projections stay inside the edge and in forward order")
    func projectionOrder() {
        let graph = RouteGraph.build(from: [rail([a, b])])
        for points in [[a, point(0.75), point(0.25), b], [a, point(-0.1), b],
                       [a, point(1.1), b], [a, point(0.5)]] {
            #expect(certify(points, graph: graph) == nil)
        }
    }

    @Test("Coincident identities stay ambiguous without a line hint")
    func coincidentIdentities() {
        let graph = RouteGraph.build(from: [rail([a, b]), rail([a, b], line: "Other")])
        #expect(certify([a, point(0.5), b], graph: graph, lines: []) == nil)
        #expect(certify([a, point(0.5), b], graph: graph) == [key(a), key(b)])
    }

    @Test("Real source paths certify via 岐阜羽島, 吉富 and 石川, including 芦原温泉 rounding")
    func realSourcePaths() throws {
        let root = try PortFixtures.repositoryRoot()
        let pipeline = PhysicalEndpointTrimTests()
        let data = try pipeline.loadRealData(root: root)
        let cases = [
            ("名古屋", "京都", "005456", "006083", "東海道新幹線", "東海旅客鉄道", true),
            ("中津", "宇島", "009013", "008981", "日豊線", "九州旅客鉄道", true),
            ("弘前", "大鰐温泉", "000586", "000618", "奥羽線", "東日本旅客鉄道", true),
            ("芦原温泉", "福井", "010178", "010179", "北陸新幹線", "西日本旅客鉄道", true),
            ("品川", "東京", "004092", "003768", "東海道新幹線", "東海旅客鉄道", false),
        ]
        for (from, to, fromCode, toCode, line, operatorName, expected) in cases {
            let section = RouteSection(from: from, to: to, fromN02StationCode: fromCode,
                toN02StationCode: toCode, lineNames: [line], operatorNames: [operatorName])
            let inferred = RouteSolver.inferStationSections([section], resolver: data.resolver,
                network: data.network, eligibility: data.eligibility, allowedCodes: ["1", "2"], hard: false)
            let hints = try #require(inferred.hints[0], "\(from)→\(to)")
            let source = try #require(data.network.sourceGeometry(for: hints), "\(from)→\(to)")
            let graph = pipeline.proofGraph(source.lines.flatMap { $0 }, store: data.graphStore)
            let keys = RouteSolver.verifiedSourcePath(source.lines, graph: graph,
                context: .init(rideDate: "2026-07-01"), section: section)
            #expect((keys != nil) == expected, "\(from)→\(to)")
        }
    }

    @Test("Real 筑豊線 segment 5 remains unproven")
    func chikuhoSegment() throws {
        let root = try PortFixtures.repositoryRoot()
        let pipeline = PhysicalEndpointTrimTests()
        let data = try pipeline.loadRealData(root: root)
        let package = try DisplayParts.LoadedPackage.load(contentsOf: root.appending(path: "app/public/rail/jp-2025.json"))
        let line = try #require(package.package.lines.first { $0.name == "筑豊線" })
        try #require(line.segments.count > 5)
        let operatorName = try #require(line.operator)
        let coordinates = line.segments[5].coordinates
        let graph = pipeline.proofGraph(coordinates, store: data.graphStore)
        #expect(RouteSolver.verifiedSourcePath([coordinates], graph: graph,
            context: .init(rideDate: "2026-07-01"),
            section: .init(lineNames: [line.name], operatorNames: [operatorName])) == nil)
    }
}
