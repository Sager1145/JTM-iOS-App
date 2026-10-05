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
        var source: RouteNetwork.SourceGeometryCertification?
        for (from, to) in [(item.2, item.3), (item.3, item.2)] {
            guard let codes = intervalCodes(on: line, from: from, to: to) else { continue }
            let hints = RouteHints(requiredLineIDs: [line.lineId], sectionCodes: codes,
                fromStationCode: from, toStationCode: to)
            if let geometry = data.network.sourceCertification(for: hints) {
                source = geometry
                break
            }
        }
        guard let source else { return "no-source" }
        let graph = pipeline.proofGraph(source.geometry.lines.flatMap { $0 }, store: data.graphStore)
        let lines = Set(section.lineNames ?? [])
        let operators = Set(section.operatorNames ?? [])
        guard let trimmed = source.geometry.lines.first, RouteSolver.trimmedToGraphNodes(
            line: trimmed, graph: graph, requiredLines: lines, requiredOperators: operators,
            rideDate: item.6) != nil || source.geometry.lines.count != 1 else {
            return "endpoint-trim vertices=\(source.geometry.lines.first?.count ?? 0)"
        }
        let keys = RouteSolver.verifiedSourcePath(source.geometry.lines, graph: graph,
            context: .init(rideDate: item.6), section: section,
            displayRowNames: source.rowNames, anchorIndices: source.anchorIndices)
        guard keys == nil else { return "ok" }
        return proofNote(source.geometry.lines, graph: graph)
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

    @Test("A display-row name is the required line only when the first node carries it")
    func displayRowHint() {
        let points = [a, point(0.5), b]
        let both = RouteGraph.build(from: [
            rail([a, b], line: "奥羽線"), rail([a, b], line: "津軽線"),
        ])
        for row in ["奥羽線", "奥羽本線", "奥羽線-2", "奥羽線-2-p1"] {
            let keys = RouteSolver.verifiedSourcePath(
                [points], graph: both, context: .init(rideDate: "2026-10-03"),
                section: .init(), displayRowNames: [row])
            #expect(keys?.count == 2, "\(row)")
            #expect(lineNames(of: keys?.last, graph: both) == ["奥羽線"], "\(row)")
        }
        #expect(RouteSolver.verifiedSourcePath(
            [points], graph: both, context: .init(rideDate: "2026-10-03"),
            section: .init(), displayRowNames: ["架空線"]) == nil)
        let only = RouteGraph.build(from: [rail([a, b], line: "奥羽線")])
        let fallback = RouteSolver.verifiedSourcePath(
            [[a, b]], graph: only, context: .init(rideDate: "2026-10-03"),
            section: .init(), displayRowNames: ["架空線"])
        #expect(fallback?.count == 2)
        #expect(lineNames(of: fallback?.last, graph: only) == ["奥羽線"])
    }

    @Test("Interior anchors are skipped only up to a 520 m same-identity walk")
    func interiorAnchorSpan() {
        func east(_ meters: Double, north: Double = 0) -> Coordinate {
            let lat = 35.0
            return Coordinate(
                lon: 139 + meters / (6_371_000 * .pi / 180 * cos(lat * .pi / 180)),
                lat: lat + north / (6_371_000 * .pi / 180))
        }
        let near = RouteGraph.build(from: [rail([east(0), east(200)])])
        let off = east(100, north: 40)
        let on = east(100, north: 0.4)
        #expect(RouteSolver.verifiedPhysicalPathKeys(
            [east(0), off, east(200)], graph: near, rideDate: nil, anchorIndices: [1]) != nil)
        #expect(RouteSolver.verifiedPhysicalPathKeys(
            [east(0), off, east(200)], graph: near, rideDate: nil) == nil)
        #expect(RouteSolver.verifiedPhysicalPathKeys(
            [east(0), on, east(700)], graph: RouteGraph.build(from: [rail([east(0), east(700)])]),
            rideDate: nil, anchorIndices: [1]) != nil)
        let farNodes = stride(from: 0.0, through: 800, by: 200).map { east($0) }
        let far = RouteGraph.build(from: [rail(farNodes)])
        #expect(RouteSolver.verifiedPhysicalPathKeys(
            [farNodes[0], east(400, north: 40), farNodes[4]], graph: far, rideDate: nil,
            anchorIndices: [1]) == nil)
    }

    @Test("Display rows certify 新青森, 吉塚, 大分 and the station-anchor spans")
    func displayRowAnchors() throws {
        let root = try PortFixtures.repositoryRoot()
        let pipeline = PhysicalEndpointTrimTests()
        let data = try pipeline.loadRealData(root: root)
        let cases: [(String, String, String, String, String)] = [
            ("新青森", "青森", "奥羽線", "東日本旅客鉄道", "2012-03-16"),
            ("新青森", "青森", "奥羽線", "東日本旅客鉄道", "2026-10-03"),
            ("香椎", "吉塚", "鹿児島線", "九州旅客鉄道", "2026-10-03"),
            ("重岡", "大分", "日豊線", "九州旅客鉄道", "2026-10-03"),
            ("東京", "上野", "東北線", "東日本旅客鉄道", "2026-10-03"),
            ("弘前", "青森", "奥羽線", "東日本旅客鉄道", "2026-10-03"),
            ("杵築", "中津", "日豊線", "九州旅客鉄道", "2026-10-03"),
            ("熊本", "八代", "鹿児島線", "九州旅客鉄道", "2004-03-14"),
        ]
        for item in cases {
            let lineID = item.0 == "東京" ? "jp-東日本旅客鉄道-東北線-2" : nil
            let note = certifyNamed(item, lineID: lineID, data: data, pipeline: pipeline)
            #expect(note == "ok", "\(item.0)→\(item.1) \(item.4): \(note)")
        }
        let stitched = certifyStitched(
            ("伊予市", "向井原", "予讃線", "四国旅客鉄道"),
            ("向井原", "内子", "予讃線", "四国旅客鉄道"),
            branchID: "jp-四国旅客鉄道-予讃線-2", date: "2026-10-03",
            data: data, pipeline: pipeline)
        #expect(stitched == "ok", "\(stitched)")
    }

    @Test("The census path certifies 36-plus-3-blue 杵築→中津 on 2026-10-03")
    func censusKitsukiToNakatsu() throws {
        let root = try PortFixtures.repositoryRoot()
        let pipeline = PhysicalEndpointTrimTests()
        let data = try pipeline.loadRealData(root: root)
        let pattern = try #require(TrainServicePatterns.patterns.first {
            $0.id == "36-plus-3-blue-oita-hakata"
        })
        let day = "2026-10-03"
        let applied = TrainServicePatterns.apply(pattern, to: Train(
            id: pattern.id, date: day, number: "", origin: "", destination: "", stops: []))
        let train = TrainValidation.normalizeExportTrain(applied, country: "jp")
        let sections = StoreOperations.rideRouteSections(for: train)
        let index = try #require(sections.firstIndex { $0.from == "杵築" && $0.to == "中津" })
        let section = sections[index]
        let context = RouteSolver.TrainContext(
            id: train.id, number: train.number, trainType: train.trainType ?? "",
            company: train.company ?? "", origin: train.origin, destination: train.destination,
            preferredLineNames: train.routePolicy?.preferredLineNames ?? [],
            preferredOperatorNames: train.routePolicy?.preferredOperatorNames ?? [],
            allowedInstitutionTypeCodes: train.routePolicy?.allowedInstitutionTypeCodes,
            institutionFilterMode: train.routePolicy?.institutionFilterMode ?? "soft",
            rideDate: day)
        let allowedCodes = RouteGraph.allowedInstitutionTypeCodes(.init(
            trainType: context.trainType, company: context.company,
            preferredLineNames: context.preferredLineNames,
            preferredOperatorNames: context.preferredOperatorNames,
            allowedInstitutionTypeCodes: context.allowedInstitutionTypeCodes,
            institutionFilterMode: context.institutionFilterMode), country: "jp")
        let inferred = RouteSolver.inferStationSections(
            sections, resolver: data.resolver, network: data.network, eligibility: data.eligibility,
            allowedCodes: allowedCodes, hard: context.institutionFilterMode == "hard")
        let useSource = section.sectionCodes?.isEmpty == false || inferred.hints[index] != nil
        let keys: [String]?
        if useSource {
            var hints = inferred.hints[index] ?? RouteHints(
                requiredLineIDs: section.lineIDs ?? [], sectionCodes: section.sectionCodes ?? [],
                fromStationCode: section.fromN02StationCode, toStationCode: section.toN02StationCode)
            hints.fromStationCode = data.eligibility.stationCode(hints.fromStationCode) ?? hints.fromStationCode
            hints.toStationCode = data.eligibility.stationCode(hints.toStationCode) ?? hints.toStationCode
            let certified = try #require(data.network.sourceCertification(for: hints))
            let graph = pipeline.proofGraph(certified.geometry.lines.flatMap { $0 }, store: data.graphStore)
            keys = RouteSolver.verifiedSourcePath(
                certified.geometry.lines, graph: graph, context: context, section: section,
                displayRowNames: certified.rowNames, anchorIndices: certified.anchorIndices)
        } else {
            let solved = try #require(RouteSolver.solveSectionOnDemand(
                section, segmentIndex: index, train: context, country: "jp",
                graphStore: data.graphStore, stations: data.stations, traversalPolicy: .physicalRail))
            var cache = RouteProjectionCache()
            let hints = RouteHints(
                requiredLineNames: (section.lineNames ?? []).map(Optional.some),
                preferredLineNames: context.preferredLineNames.map(Optional.some),
                requiredOperatorNames: (section.operatorNames ?? []).map(Optional.some),
                preferredOperatorNames: context.preferredOperatorNames.map(Optional.some),
                requiredLineIDs: section.lineIDs ?? [], sectionCodes: section.sectionCodes ?? [],
                fromStationCode: section.fromN02StationCode, toStationCode: section.toN02StationCode)
            let canonical = data.network.canonicalizeRouteFeature(
                RouteFeature(geometry: .lineString(solved.coordinates), hints: hints),
                continueFrom: nil, cache: &cache)
            let codes = try #require(canonical?.matchedSectionCodes)
            var matchedHints = hints
            matchedHints.sectionCodes = codes
            matchedHints.requiredLineIDs = canonical?.displayLineIds ?? []
            let certified = try #require(data.network.sourceCertification(for: matchedHints))
            let graph = pipeline.proofGraph(certified.geometry.lines.flatMap { $0 }, store: data.graphStore)
            keys = RouteSolver.verifiedSourcePath(
                certified.geometry.lines, graph: graph, context: context, section: section,
                displayRowNames: certified.rowNames, anchorIndices: certified.anchorIndices)
        }
        #expect(keys != nil, "useSource=\(useSource) 杵築→中津 census path")
    }

    private func lineNames(of key: String?, graph: RouteGraph.Graph) -> Set<String> {
        guard let key else { return [] }
        return graph.nodeMeta[key]?.lineNames ?? []
    }

    private func certifyNamed(
        _ item: (String, String, String, String, String), lineID: String?,
        data: PhysicalEndpointTrimTests.RealData, pipeline: PhysicalEndpointTrimTests
    ) -> String {
        guard let line = data.network.lines.first(where: { candidate in
            if let lineID { return candidate.lineId == lineID }
            return candidate.name == item.2 && candidate.operator == item.3
                && candidate.alignmentDirection == nil
                && candidate.compactLine?.stations.contains { $0.name == item.0 } == true
                && candidate.compactLine?.stations.contains { $0.name == item.1 } == true
        }) else { return "no-line" }
        return certifyLine(line, from: item.0, to: item.1, date: item.4,
            expectLine: item.2, data: data, pipeline: pipeline)
    }

    private func certifyStitched(
        _ first: (String, String, String, String), _ second: (String, String, String, String),
        branchID: String, date: String,
        data: PhysicalEndpointTrimTests.RealData, pipeline: PhysicalEndpointTrimTests
    ) -> String {
        func row(_ item: (String, String, String, String), id: String?) -> RouteNetwork.Line? {
            data.network.lines.first { candidate in
                if let id { return candidate.lineId == id }
                return candidate.name == item.2 && candidate.operator == item.3
                    && candidate.alignmentDirection == nil
                    && candidate.compactLine?.stations.contains { $0.name == item.0 } == true
                    && candidate.compactLine?.stations.contains { $0.name == item.1 } == true
            }
        }
        guard let start = row(first, id: nil), let branch = row(second, id: branchID) else { return "no-line" }
        guard let fromCode = start.compactLine?.stations.first(where: { $0.name == first.0 })?.id,
              let midStart = start.compactLine?.stations.first(where: { $0.name == first.1 })?.id,
              let midEnd = branch.compactLine?.stations.first(where: { $0.name == second.0 })?.id,
              let toCode = branch.compactLine?.stations.first(where: { $0.name == second.1 })?.id,
              let head = intervalCodes(on: start, from: fromCode, to: midStart),
              let tail = intervalCodes(on: branch, from: midEnd, to: toCode) else { return "no-codes" }
        let hints = RouteHints(requiredLineIDs: [start.lineId, branch.lineId],
            sectionCodes: head + tail, fromStationCode: fromCode, toStationCode: toCode)
        guard let source = data.network.sourceCertification(for: hints) else { return "no-source" }
        let graph = pipeline.proofGraph(source.geometry.lines.flatMap { $0 }, store: data.graphStore)
        let keys = RouteSolver.verifiedSourcePath(
            source.geometry.lines, graph: graph, context: .init(rideDate: date),
            section: .init(), displayRowNames: source.rowNames, anchorIndices: source.anchorIndices)
        guard let keys else { return proofNote(source.geometry.lines, graph: graph) }
        let terminal = lineNames(of: keys.last, graph: graph)
        guard terminal.contains("予讃線") else { return "terminal \(terminal)" }
        return "ok"
    }

    private func certifyLine(
        _ line: RouteNetwork.Line, from: String, to: String, date: String, expectLine: String,
        data: PhysicalEndpointTrimTests.RealData, pipeline: PhysicalEndpointTrimTests
    ) -> String {
        guard let fromCode = line.compactLine?.stations.first(where: { $0.name == from })?.id,
              let toCode = line.compactLine?.stations.first(where: { $0.name == to })?.id else {
            return "no-station"
        }
        var source: RouteNetwork.SourceGeometryCertification?
        for (start, end) in [(fromCode, toCode), (toCode, fromCode)] {
            guard let codes = intervalCodes(on: line, from: start, to: end) else { continue }
            let hints = RouteHints(requiredLineIDs: [line.lineId], sectionCodes: codes,
                fromStationCode: start, toStationCode: end)
            if let geometry = data.network.sourceCertification(for: hints) {
                source = geometry
                break
            }
        }
        guard let source else { return "no-source" }
        let graph = pipeline.proofGraph(source.geometry.lines.flatMap { $0 }, store: data.graphStore)
        let keys = RouteSolver.verifiedSourcePath(
            source.geometry.lines, graph: graph, context: .init(rideDate: date),
            section: .init(), displayRowNames: source.rowNames, anchorIndices: source.anchorIndices)
        guard let keys, let last = keys.last else {
            return proofNote(source.geometry.lines, graph: graph)
        }
        let terminal = lineNames(of: last, graph: graph)
        guard terminal.contains(expectLine) else { return "terminal \(terminal)" }
        return "ok"
    }
}
