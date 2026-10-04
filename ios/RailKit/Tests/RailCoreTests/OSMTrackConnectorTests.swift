import Foundation
import Testing
@testable import RailCore

struct OSMTrackConnectorTests {
    private func point(_ east: Double, _ north: Double = 0) -> Coordinate {
        Coordinate(
            lon: 139 + east / (111_320 * cos(35 * .pi / 180)),
            lat: 35 + north / 111_320)
    }

    private func identity(_ line: String) -> RouteGraph.TrackIdentity {
        .init(operatorName: "Operator", lineName: line, railwayClassCode: "")
    }

    private func rail(_ points: [Coordinate], line: String) -> RouteGraph.SectionFeature {
        .init(properties: .init(lineName: line, operator: "Operator", institutionTypeCode: "1"),
              lines: [points])
    }

    private func key(_ p: Coordinate, _ line: String) -> String {
        RouteGraph.physicalNodeKey(p, identity: identity(line))
    }

    private func source(_ ways: [Int] = [1]) -> RouteGraph.PhysicalJunction.Source {
        .init(provider: "OpenStreetMap", license: "ODbL-1.0", ways: ways,
              retrieved: "2026-10-04", cache: "Japan-Train-Map/outputs/osm-basemap-cache")
    }

    /// West runs `westStart`…0. The connector path is at `path` metres. East runs `eastStart`…`eastEnd`.
    private func connector(
        westStart: Double = -1_490, path: [Double] = [20, 320], eastStart: Double = 340,
        eastEnd: Double = 1_830, evidence: [String] = ["way 1"], validFrom: String? = nil,
        validTo: String? = nil, attachFrom: Double = 20, attachTo: Double = 20,
        fromLine: String = "West", toLine: String = "East"
    ) -> RouteGraph.Graph {
        let pathPoints = path.map { point($0) }
        let junction = RouteGraph.PhysicalJunction(
            id: "link",
            from: .init(identity: identity(fromLine), coordinate: point(0)),
            to: .init(identity: identity(toLine), coordinate: point(eastStart)),
            evidence: evidence, validFrom: validFrom, validTo: validTo, kind: .osmConnector,
            path: pathPoints, source: source(),
            attachMeters: .init(from: attachFrom, to: attachTo))
        return RouteGraph.build(from: [
            rail([point(westStart), point(0)], line: fromLine),
            rail([point(eastStart), point(eastEnd)], line: toLine),
        ], junctions: [junction])
    }

    @Test("A 300 m OSM connector with 20 m stubs is one boundary hop")
    func connectorOneHop() {
        let graph = connector()
        #expect(graph.rejectedPhysicalJunctionIDs.isEmpty)
        #expect(RouteSolver.physicalBoundaryIsProven(
            from: key(point(-1_490), "West"), to: key(point(1_830), "East"),
            graph: graph, rideDate: nil))
        let joined = RouteSolver.physicalContinuationPath(
            from: key(point(0), "West"), to: key(point(340), "East"), graph: graph, rideDate: nil)
        let connectorKey = RouteGraph.physicalNodeKey(
            point(20), identity: RouteGraph.PhysicalJunction.osmConnectorIdentity("link"))
        #expect(joined?.count == 4)
        #expect(joined?.contains(connectorKey) == true)
        #expect(joined?.first == key(point(0), "West"))
        #expect(joined?.last == key(point(340), "East"))
        let solved = RouteSolver.dijkstra(
            graph: graph, sourceCandidates: [.init(key: key(point(0), "West"), distance: 0)],
            targetKeys: [key(point(340), "East")], train: .init(), allowedCodes: [])
        let route = solved.first
        #expect(route?.pathKeys == joined)
        let length = route?.edges.reduce(0.0) { $0 + $1.length } ?? 0
        #expect(abs(length - 340) < 5)
        let coordinates = route?.pathKeys.compactMap { graph.nodes[$0] } ?? []
        #expect(coordinates.count == route?.pathKeys.count)
        #expect(coordinates.contains(Grid.normalizeGraphCoord(point(320))))
    }

    @Test("A 60 m OSM stub is rejected")
    func stubTooLong() {
        let graph = connector(path: [60, 200], eastStart: 220, eastEnd: 400, attachFrom: 60)
        #expect(graph.rejectedPhysicalJunctionIDs == ["link"])
        #expect(graph.rejectedPhysicalJunctionReasons.contains { $0.contains("attach") })
    }

    @Test("An OSM connector longer than 1500 m is rejected")
    func totalTooLong() {
        let graph = connector(westStart: -100, path: [20, 2_020], eastStart: 2_040, eastEnd: 2_200)
        #expect(graph.rejectedPhysicalJunctionIDs == ["link"])
        #expect(graph.rejectedPhysicalJunctionReasons.contains { $0.contains("1500") })
    }

    @Test("An OSM connector without evidence is rejected")
    func noEvidence() {
        #expect(connector(evidence: []).rejectedPhysicalJunctionIDs == ["link"])
        #expect(connector(evidence: [" "]).rejectedPhysicalJunctionIDs == ["link"])
    }

    @Test("An OSM connector outside its validity dates is not traversed")
    func dateInvalid() {
        let graph = connector(validFrom: "2020-01-01", validTo: "2021-01-01")
        #expect(graph.rejectedPhysicalJunctionIDs.isEmpty)
        #expect(RouteSolver.physicalBoundaryIsProven(
            from: key(point(-1_490), "West"), to: key(point(1_830), "East"),
            graph: graph, rideDate: "2020-06-01"))
        #expect(!RouteSolver.physicalBoundaryIsProven(
            from: key(point(-1_490), "West"), to: key(point(1_830), "East"),
            graph: graph, rideDate: "2022-06-01"))
        #expect(RouteSolver.physicalContinuationPath(
            from: key(point(0), "West"), to: key(point(340), "East"),
            graph: graph, rideDate: "2022-06-01") == nil)
        let solved = RouteSolver.dijkstra(
            graph: graph, sourceCandidates: [.init(key: key(point(0), "West"), distance: 0)],
            targetKeys: [key(point(340), "East")], train: .init(rideDate: "2022-06-01"),
            allowedCodes: [])
        #expect(solved.isEmpty)
    }

    @Test("sameIdentitySpan does not enter an OSM connector")
    func sameIdentityNeverEnters() {
        let graph = connector()
        let connectorKey = RouteGraph.physicalNodeKey(
            point(20), identity: RouteGraph.PhysicalJunction.osmConnectorIdentity("link"))
        #expect(!RouteSolver.sameIdentitySpan(
            from: key(point(0), "West"), to: key(point(340), "East"), graph: graph, date: nil))
        #expect(!RouteSolver.sameIdentitySpan(
            from: key(point(0), "West"), to: connectorKey, graph: graph, date: nil))
    }

    @Test("Display geometry on an OSM track certifies on that identity")
    func trackCertifies() {
        let (graph, display) = track()
        #expect(graph.rejectedPhysicalJunctionIDs.isEmpty)
        let keys = RouteSolver.verifiedPhysicalPathKeys(
            display, graph: graph, rideDate: nil,
            requiredLines: ["Tokaido"], requiredOperators: ["Operator"])
        #expect(keys?.count == display.count)
        #expect(keys?.contains(key(point(250, 40), "Tokaido")) == true)
    }

    @Test("A 3 km OSM track with stubs within 50 m is accepted")
    func longTrackAccepted() {
        let end = 3_000.0
        let attach = 20.0
        let from = point(0)
        let to = point(end)
        let path = [point(attach), point(1_500), point(end - attach)]
        let junction = RouteGraph.PhysicalJunction(
            id: "track",
            from: .init(identity: identity("Tokaido"), coordinate: from),
            to: .init(identity: identity("Tokaido"), coordinate: to),
            evidence: ["way 9"], kind: .osmTrack, path: path, source: source([9]),
            attachMeters: .init(from: attach, to: attach))
        let graph = RouteGraph.build(from: [
            rail([from, to], line: "Tokaido"),
        ], junctions: [junction])
        #expect(graph.rejectedPhysicalJunctionIDs.isEmpty)
    }

    @Test("A 60 m OSM track attach is rejected")
    func trackAttachTooLong() {
        #expect(track(attach: 60).0.rejectedPhysicalJunctionIDs == ["track"])
    }

    @Test("An OSM track with a different to-identity is rejected")
    func trackIdentityMismatch() {
        let graph = track(toLine: "Sanyo").0
        #expect(graph.rejectedPhysicalJunctionIDs == ["track"])
        #expect(graph.rejectedPhysicalJunctionReasons.contains { $0.contains("identity mismatch") })
    }

    @Test("The registry decodes osmConnector path, source and attach")
    func decodesConnector() throws {
        let json = """
        {"format":"jtm-physical-rail-junctions-v1","junctions":[{
          "id":"c","region":"jp","kind":"osmConnector",
          "from":{"identity":{"operatorName":"A","lineName":"West","railwayClassCode":"11"},"coordinate":[139,35]},
          "to":{"identity":{"operatorName":"B","lineName":"East","railwayClassCode":"11"},"coordinate":[139.01,35]},
          "path":[[139.001,35],[139.009,35]],
          "source":{"provider":"OpenStreetMap","license":"ODbL-1.0","ways":[42],"retrieved":"2026-10-04","cache":"Japan-Train-Map/outputs/osm-basemap-cache"},
          "attachMeters":{"from":20,"to":18},
          "evidence":["way 42"]
        }]}
        """
        let registry = try PhysicalRailJunctionRegistry(data: Data(json.utf8))
        let junction = try #require(registry.junctions(for: "jp").first)
        #expect(junction.kind == .osmConnector)
        #expect(junction.path?.count == 2)
        #expect(junction.source?.provider == "OpenStreetMap")
        #expect(junction.source?.license == "ODbL-1.0")
        #expect(junction.source?.ways == [42])
        #expect(junction.source?.cache == "Japan-Train-Map/outputs/osm-basemap-cache")
        #expect(junction.attachMeters == .init(from: 20, to: 18))
    }

    @Test("Real registry loads with rejected == []")
    func realRegistry() throws {
        let data = try PortFixtures.repositoryRoot().appending(path: "app/data")
        let registry = try PhysicalRailJunctionRegistry(
            data: Data(contentsOf: data.appending(path: "physical-rail-junctions.json")))
        var features = try RouteGraph.SectionFeatureCollection.load(
            contentsOf: data.appending(path: "rail-sections.json")).features
        var stations = try Stations.FeatureCollection.load(
            contentsOf: data.appending(path: "stations.json")).features
        let overlay = try RailHistoryOverlay.load(from: data.appending(path: "rail-history.json"))
        _ = RailHistory.apply(overlay, sections: &features, stations: &stations)
        let junctions = Localization.supportedCountries.flatMap { registry.junctions(for: $0) }
        let graph = RouteGraph.build(from: features, junctions: junctions)
        #expect(graph.rejectedPhysicalJunctionIDs == [])
    }

    @Test("A terminus within 300 m of the station group is a dead end")
    func terminusWithin300() {
        let graph = terminusGraph(stationNorth: 100)
        #expect(graph.rejectedPhysicalJunctionIDs.isEmpty)
        let terminal = key(point(400), "Tokaido")
        #expect(graph.adjacency[terminal]?.count == 1)
        #expect(graph.nodes[key(point(800), "Tokaido")] == nil)
    }

    @Test("A terminus beyond 300 m of the station group is rejected")
    func terminusBeyond300() {
        let graph = terminusGraph(stationNorth: 350)
        #expect(graph.rejectedPhysicalJunctionIDs == ["track"])
        #expect(graph.rejectedPhysicalJunctionReasons.contains { $0.contains("300") })
    }

    @Test("A terminus from-attach beyond 50 m is rejected")
    func terminusAttachTooLong() {
        let graph = terminusGraph(stationNorth: 100, pathEast: [60, 200, 400], attachFrom: 60)
        #expect(graph.rejectedPhysicalJunctionIDs == ["track"])
        #expect(graph.rejectedPhysicalJunctionReasons.contains { $0.contains("attach") })
    }

    @Test("A non-continuous terminus path is rejected")
    func terminusPathNotContinuous() {
        let graph = terminusGraph(stationNorth: 0, pathEast: [20, 100, 2_500], attachFrom: 20,
                                  stationEast: 2_500)
        #expect(graph.rejectedPhysicalJunctionIDs == ["track"])
        #expect(graph.rejectedPhysicalJunctionReasons.contains { $0.contains("path is not continuous") })
    }

    @Test("The registry decodes a terminus and rejects any other end")
    func decodesTerminus() throws {
        let registry = try PhysicalRailJunctionRegistry(data: Data(terminusJSON(end: "to").utf8))
        let junction = try #require(registry.junctions(for: "jp").first)
        #expect(junction.terminus == .init(
            end: .to, station: "東京", stationCode: "003766",
            coordinate: Coordinate(lon: 139.009, lat: 35)))
        #expect(throws: PhysicalRailJunctionRegistry.RegistryError.unsupportedTerminus) {
            try PhysicalRailJunctionRegistry(data: Data(terminusJSON(end: "from").utf8))
        }
    }

    private func terminusJSON(end: String) -> String {
        """
        {"format":"jtm-physical-rail-junctions-v1","junctions":[{
          "id":"t","region":"jp","kind":"osmTrack",
          "from":{"identity":{"operatorName":"A","lineName":"Tokaido","railwayClassCode":"11"},"coordinate":[139,35]},
          "to":{"identity":{"operatorName":"A","lineName":"Tokaido","railwayClassCode":"11"},"coordinate":[139.01,35]},
          "path":[[139.001,35],[139.009,35]],
          "attachMeters":{"from":0,"to":0},
          "terminus":{"end":"\(end)","station":"東京","stationCode":"003766","coordinate":[139.009,35]},
          "evidence":["way 1"]
        }]}
        """
    }

    private func terminusGraph(
        stationNorth: Double, pathEast: [Double] = [20, 200, 400], attachFrom: Double = 20,
        stationEast: Double = 400
    ) -> RouteGraph.Graph {
        let path = pathEast.map { point($0) }
        let station = point(stationEast, stationNorth)
        let junction = RouteGraph.PhysicalJunction(
            id: "track",
            from: .init(identity: identity("Tokaido"), coordinate: point(0)),
            to: .init(identity: identity("Tokaido"), coordinate: path[path.count - 1]),
            evidence: ["way 9"], kind: .osmTrack, path: path, source: source([9]),
            attachMeters: .init(from: attachFrom, to: 0),
            terminus: .init(end: .to, station: "東京", stationCode: "003766", coordinate: station))
        return RouteGraph.build(from: [
            rail([point(-200), point(0)], line: "Tokaido"),
        ], junctions: [junction])
    }

    @Test("A zeroLength endpoint that is only an osmTrack path vertex is rejected in either order")
    func zeroLengthOnOsmTrackVertexRejectedInEitherOrder() {
        let westStart = point(0)
        let westEnd = point(400)
        let pathVertex = point(200)
        let features = [
            rail([westStart, westEnd], line: "West"),
            rail([pathVertex, point(200, 300)], line: "East"),
        ]
        let track = RouteGraph.PhysicalJunction(
            id: "track",
            from: .init(identity: identity("West"), coordinate: westStart),
            to: .init(identity: identity("West"), coordinate: westEnd),
            evidence: ["way 9"], kind: .osmTrack,
            path: [point(20), pathVertex, point(380)], source: source([9]),
            attachMeters: .init(from: 20, to: 20))
        let zero = RouteGraph.PhysicalJunction(
            id: "zero",
            from: .init(identity: identity("West"), coordinate: pathVertex),
            to: .init(identity: identity("East"), coordinate: pathVertex),
            evidence: ["survey"], kind: .zeroLength)
        for junctions in [[track, zero], [zero, track]] {
            let graph = RouteGraph.build(from: features, junctions: junctions)
            #expect(graph.rejectedPhysicalJunctionIDs.contains("zero"))
            #expect(!graph.rejectedPhysicalJunctionIDs.contains("track"))
            #expect(graph.rejectedPhysicalJunctionReasons.contains {
                $0.hasPrefix("zero:") && $0.contains("existing vertex")
            })
        }
    }

    private func track(
        attach: Double = 20, toLine: String = "Tokaido", evidence: [String] = ["way 9"]
    ) -> (RouteGraph.Graph, [Coordinate]) {
        let end = 500.0
        let from = point(0)
        let to = point(end)
        let path = [point(attach, 30), point(250, 40), point(end - attach, 30)]
        var features = [rail([from, to], line: "Tokaido")]
        if toLine != "Tokaido" {
            features.append(rail([to, point(end + 200)], line: toLine))
        }
        let junction = RouteGraph.PhysicalJunction(
            id: "track",
            from: .init(identity: identity("Tokaido"), coordinate: from),
            to: .init(identity: identity(toLine), coordinate: to),
            evidence: evidence, kind: .osmTrack, path: path, source: source([9]),
            attachMeters: .init(from: attach, to: attach))
        let graph = RouteGraph.build(from: features, junctions: [junction])
        return (graph, [from] + path + [to])
    }
}
