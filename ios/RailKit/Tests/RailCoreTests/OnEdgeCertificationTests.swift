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

    @Test("A terminal zero-length sibling is not a second traversed identity")
    func terminalJunctionSibling() {
        let north = Coordinate(lon: b.lon, lat: b.lat + 0.001)
        let sibling = RouteGraph.PhysicalJunction(
            id: "rail-other", from: .init(identity: identity(), coordinate: b),
            to: .init(identity: identity("Other"), coordinate: b), evidence: ["survey:reviewed"])
        let graph = RouteGraph.build(from: [rail([a, b]), rail([b, north], line: "Other")],
            junctions: [sibling])
        #expect(certify([a, b, b], graph: graph) == [key(a), key(b)])
        #expect(certify([a, b, b], graph: graph, lines: []) == [key(a), key(b)])
        let parallel = RouteGraph.build(
            from: [rail([a, b]), rail([a, b], line: "Other")], junctions: [sibling])
        #expect(certify([a, b, b], graph: parallel, lines: []) == nil)
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
            // Registered osmTrack tokyo-tokaido-shinkansen-shinagawa follows this stroke.
            ("品川", "東京", "004092", "003768", "東海道新幹線", "東海旅客鉄道", true),
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

    @Test("A pending marker between non-adjacent nodes follows the one identity walk")
    func multiEdgeOnEdgeMarker() {
        let mid = point(0.5)
        let graph = RouteGraph.build(from: [rail([a, mid, b])])
        #expect(certify([a, point(0.25), b], graph: graph) == [key(a), key(mid), key(b)])
        #expect(certify([a, point(0.25, north: 1.5), b], graph: graph) == nil)
        let far = Coordinate(lon: a.lon + 0.008, lat: a.lat)
        let steps = stride(from: 0.0, through: 0.008, by: 0.001).map {
            Coordinate(lon: a.lon + $0, lat: a.lat)
        }
        let long = RouteGraph.build(from: [rail(steps)])
        #expect(Geometry.distanceMeters(a, far) > 520)
        #expect(certify([a, point(0.05), far], graph: long) == nil)
        let other = RouteGraph.build(from: [
            rail([a, mid], line: "West"), rail([mid, b]),
        ])
        #expect(certify([a, point(0.25), b], graph: other) == nil)
    }

    @Test("Interior station anchors on 日豊線, 奥羽線, 鹿児島線 and 東北線 certify")
    func interiorStationAnchors() throws {
        let root = try PortFixtures.repositoryRoot()
        let pipeline = PhysicalEndpointTrimTests()
        let data = try pipeline.loadRealData(root: root)
        let cases: [(String, String, String, String, String, String, String)] = [
            ("杵築", "宇佐", "009303", "009217", "日豊線", "九州旅客鉄道", "2026-07-01"),
            ("杵築", "中津", "009303", "009013", "日豊線", "九州旅客鉄道", "2026-07-01"),
            ("重岡", "大分", "009707", "009479", "日豊線", "九州旅客鉄道", "2026-07-01"),
            ("重岡", "大分", "009707", "009479", "日豊線", "九州旅客鉄道", "2026-10-03"),
            ("大鰐温泉", "大館", "000618", "000660", "奥羽線", "東日本旅客鉄道", "2026-07-01"),
            ("香椎", "吉塚", "008931", "009002", "鹿児島線", "九州旅客鉄道", "2026-07-01"),
            ("香椎", "吉塚", "008931", "009002", "鹿児島線", "九州旅客鉄道", "2026-10-03"),
            ("大宮", "宇都宮", "002914", "002113", "東北線", "東日本旅客鉄道", "2026-07-01"),
            ("大宮", "宇都宮", "002914", "002113", "東北線", "東日本旅客鉄道", "1999-07-17"),
        ]
        for item in cases {
            let note = certifySpan(item, data: data, pipeline: pipeline)
            #expect(note == "ok", "\(item.0)→\(item.1) \(item.6): \(note)")
        }
    }

    @Test("赤羽, 新八代→八代 and 新青森→青森 source paths certify on their own edges")
    func akabaneAndShinkansenConventionalEnds() throws {
        let root = try PortFixtures.repositoryRoot()
        let pipeline = PhysicalEndpointTrimTests()
        let data = try pipeline.loadRealData(root: root)
        let cases: [(String, String, String, String, String, String, String)] = [
            ("新八代", "八代", "009869", "009872", "鹿児島線", "九州旅客鉄道", "2016-07-01"),
            ("新青森", "青森", "000531", "000527", "奥羽線", "東日本旅客鉄道", "2012-01-01"),
            ("赤羽", "川口", "003155", "003086", "東北線", "東日本旅客鉄道", "2026-07-01"),
            ("十条", "赤羽", "003218", "003155", "赤羽線", "東日本旅客鉄道", "2026-07-01"),
        ]
        for item in cases {
            let note = certifySpan(item, data: data, pipeline: pipeline)
            #expect(note == "ok", "\(item.0)→\(item.1) \(item.6): \(note)")
        }
    }

    private func certifySpan(
        _ item: (String, String, String, String, String, String, String),
        data: PhysicalEndpointTrimTests.RealData, pipeline: PhysicalEndpointTrimTests
    ) -> String {
        let section = RouteSection(from: item.0, to: item.1, fromN02StationCode: item.2,
            toN02StationCode: item.3, lineNames: [item.4], operatorNames: [item.5])
        guard let line = data.network.lines.first(where: { candidate in
            candidate.name == item.4 && candidate.operator == item.5
                && candidate.alignmentDirection == nil
                && candidate.intervals.contains { $0.fromStationCode == item.2 || $0.toStationCode == item.2 }
                && candidate.intervals.contains { $0.fromStationCode == item.3 || $0.toStationCode == item.3 }
        }) else { return "no-line" }
        // A sourced one-way bore (立石, 矢立峠) accepts only one station-order
        // direction. The anchors are the same joins either way.
        var source: RouteGeometry?
        for (from, to) in [(item.2, item.3), (item.3, item.2)] {
            guard let codes = intervalCodes(on: line, from: from, to: to) else { continue }
            let hints = RouteHints(requiredLineIDs: [line.lineId], sectionCodes: codes,
                fromStationCode: from, toStationCode: to)
            if let geometry = data.network.sourceGeometry(for: hints) {
                source = geometry
                break
            }
        }
        guard let source else { return "no-source" }
        let graph = pipeline.proofGraph(source.lines.flatMap { $0 }, store: data.graphStore)
        let lines = Set(section.lineNames ?? [])
        let operators = Set(section.operatorNames ?? [])
        guard let trimmed = source.lines.first, RouteSolver.trimmedToGraphNodes(
            line: trimmed, graph: graph, requiredLines: lines, requiredOperators: operators,
            rideDate: item.6) != nil || source.lines.count != 1 else {
            return "endpoint-trim vertices=\(source.lines.first?.count ?? 0)"
        }
        let keys = RouteSolver.verifiedSourcePath(source.lines, graph: graph,
            context: .init(rideDate: item.6), section: section)
        guard keys == nil else { return "ok" }
        return proofNote(source.lines, graph: graph)
    }

    private func intervalCodes(on line: RouteNetwork.Line, from: String, to: String) -> [String]? {
        let stations = line.compactLine?.stations.map(\.id) ?? []
        guard let start = stations.firstIndex(of: from), let end = stations.firstIndex(of: to),
              start != end else { return nil }
        let step = start < end ? 1 : -1
        var index = start
        var codes: [String] = []
        while index != end {
            let next = index + step
            let intervalIndex = min(index, next)
            guard line.intervals.indices.contains(intervalIndex) else { return nil }
            codes.append(line.intervals[intervalIndex].code)
            index = next
        }
        return codes
    }

    private func proofNote(_ lines: [[Coordinate]], graph: RouteGraph.Graph) -> String {
        var pendingBetween = 0
        var nonAdjacent = 0
        for line in lines {
            var previous: String?
            var pending = false
            for coordinate in line {
                let normalized = Grid.normalizeGraphCoord(coordinate)
                let nodes = RouteGraph.exactNodeKeys(normalized, in: graph)
                if nodes.isEmpty {
                    pending = true
                    continue
                }
                if let previous, !nodes.contains(where: { node in
                    graph.adjacency[previous]?.contains(where: { $0.to == node }) == true
                }) {
                    nonAdjacent += 1
                    if pending { pendingBetween += 1 }
                }
                previous = nodes.first
                pending = false
            }
        }
        return "proof-failed nonAdjacent=\(nonAdjacent) pendingBetweenNonAdjacent=\(pendingBetween)"
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
