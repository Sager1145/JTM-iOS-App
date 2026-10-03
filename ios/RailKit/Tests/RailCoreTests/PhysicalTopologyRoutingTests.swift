import Foundation
import Testing
@testable import RailCore

struct PhysicalTopologyRoutingTests {
    private let a = Coordinate(lon: 139, lat: 35)
    private let b = Coordinate(lon: 139.02, lat: 35)
    private let c = Coordinate(lon: 139.0205, lat: 35)
    private let d = Coordinate(lon: 139.04, lat: 35)

    private func rail(_ points: [Coordinate], line: String = "Rail") -> RouteGraph.SectionFeature {
        .init(properties: .init(lineName: line, operator: "Operator", institutionTypeCode: "1"), lines: [points])
    }

    private func station(_ point: Coordinate, code: String, name: String, group: String? = nil,
                         line: String = "Rail") -> Stations.Feature {
        var properties: [String: Stations.Value] = [
            "n02_station_code": .string(code), "station_name": .string(name),
            "line_name": .string(line), "operator": .string("Operator"),
            "institution_type_code": .string("1"),
        ]
        if let group { properties["n02_group_code"] = .string(group) }
        return .init(properties: properties, geometry: .init(type: "Point", coordinates: .array([.number(point.lon), .number(point.lat)])))
    }

    private func key(_ point: Coordinate, in graph: RouteGraph.Graph) throws -> String {
        try #require(graph.nodes.first(where: { $0.value == Grid.normalizeGraphCoord(point) })?.key)
    }

    private func solve(_ graph: RouteGraph.Graph, policy: RouteSolver.TraversalPolicy = .physicalRail,
                       hints: RouteSolver.SegmentHints = .init()) throws -> [RouteSolver.SolvedTarget] {
        RouteSolver.dijkstra(graph: graph, sourceCandidates: [.init(key: try key(a, in: graph), distance: 0)],
                             targetKeys: [try key(d, in: graph)], train: .init(), allowedCodes: ["1"],
                             hints: hints, traversalPolicy: policy)
    }

    @Test("Same-name proximity is a passenger relation, not connected track")
    func sameNameCannotConnectRail() throws {
        let graph = RouteGraph.build(from: [rail([a, b], line: "West"), rail([c, d], line: "East")])
        RouteSolver.addStationTransferConnectorEdges(graph: graph, stations: [
            station(b, code: "B", name: "Central", line: "West"),
            station(c, code: "C", name: "Central", line: "East"),
        ])
        #expect(graph.adjacency.values.flatMap { $0 }.contains { $0.connector != nil })
        #expect(try solve(graph).isEmpty)
        #expect(!(try solve(graph, policy: .passengerTransfers)).isEmpty)
    }

    @Test("An explicit shared station group does not prove rail connectivity")
    func sameGroupCannotConnectRail() throws {
        let graph = RouteGraph.build(from: [rail([a, b], line: "West"), rail([c, d], line: "East")])
        RouteSolver.addStationTransferConnectorEdges(graph: graph, stations: [
            station(b, code: "B", name: "West platform", group: "shared", line: "West"),
            station(c, code: "C", name: "East platform", group: "shared", line: "East"),
        ])
        #expect(!(try solve(graph, policy: .passengerTransfers)).isEmpty)
        #expect(try solve(graph).isEmpty)
        let defaultResult = RouteSolver.dijkstra(
            graph: graph, sourceCandidates: [.init(key: try key(a, in: graph), distance: 0)],
            targetKeys: [try key(d, in: graph)], train: .init(), allowedCodes: ["1"])
        #expect(defaultResult.isEmpty)
    }

    @Test("Explicit source rail geometry remains traversable under line and operator requirements")
    func explicitRailIsConnected() throws {
        let graph = RouteGraph.build(from: [rail([a, b, c, d])])
        let result = try #require(solve(graph, hints: .init(requiredLines: ["Rail"], requiredOperators: ["Operator"])).first)
        #expect(result.edges.count == 3)
        #expect(result.edges.allSatisfy { $0.connector == nil })
    }

    @Test("A passenger connector cannot bypass required physical line hints")
    func requiredHintsRejectTransfers() {
        let connector = RouteGraph.Edge(to: "other", length: 10, institutionTypeCode: "", railwayClassCode: "",
                                        lineName: "", operator: "", connector: .init(institutionTypeCodes: ["1"], stationName: "Central", groupCode: "shared"))
        let hints = RouteSolver.SegmentHints(requiredLines: ["Rail"], requiredOperators: ["Operator"])
        #expect(!RouteSolver.edgeMatchesRequiredHints(connector, hints: hints))
        #expect(RouteSolver.edgeMatchesRequiredHints(connector, hints: hints, traversalPolicy: .passengerTransfers))
    }

    @Test("Passenger graph paths never become drawable railway geometry")
    func passengerPathIsNotDrawable() throws {
        let graph = RouteGraph.build(from: [rail([a, b]), rail([c, d])])
        let platforms = [station(b, code: "B", name: "Central", group: "shared"),
                         station(c, code: "C", name: "Central", group: "shared")]
        RouteSolver.addStationTransferConnectorEdges(graph: graph, stations: platforms)
        #expect(!(try solve(graph, policy: .passengerTransfers)).isEmpty)
        let index = Stations.Index(platforms + [station(a, code: "A", name: "Start"), station(d, code: "D", name: "End")])
        let section = RouteSection(from: "Start", to: "End", fromN02StationCode: "A", toN02StationCode: "D")
        #expect(RouteSolver.solveSection(section, segmentIndex: 0, train: .init(), country: "jp", graph: graph,
                                        stations: index, traversalPolicy: .passengerTransfers) == nil)
        #expect(RouteSolver.solveSection(section, segmentIndex: 0, train: .init(), country: "jp", graph: graph,
                                        stations: index) == nil)
    }
    @Test("Off-track station markers and continuity anchors never add railway geometry")
    func displacedStationDisplayCannotInventRail() throws {
        let sections = [rail([a, b, c, d])]
        let startDisplay = Coordinate(lon: a.lon, lat: a.lat + 0.0003)
        let endDisplay = Coordinate(lon: d.lon, lat: d.lat + 0.0003)
        let anchor = Coordinate(lon: a.lon, lat: a.lat + 0.0002)
        let stations = Stations.Index([
            station(startDisplay, code: "A", name: "Start"),
            station(endDisplay, code: "D", name: "End"),
        ])
        let section = RouteSection(from: "Start", to: "End", fromN02StationCode: "A", toN02StationCode: "D")
        let graph = RouteGraph.build(from: sections)
        let direct = try #require(RouteSolver.solveSection(
            section, segmentIndex: 0, train: .init(), country: "jp",
            graph: graph, stations: stations, continuityAnchor: anchor))
        let store = RouteGraph.RouteGraphStore(sections: sections)
        let regional = try #require(RouteSolver.solveSectionOnDemand(
            section, segmentIndex: 0, train: .init(), country: "jp",
            graphStore: store, stations: stations, continuityAnchor: anchor))
        for solved in [direct, regional] {
            #expect(solved.coordinates == [a, b, c, d])
            #expect(solved.coordinates == solved.rawPathKeys.compactMap { graph.nodes[$0] })
            #expect(!solved.coordinates.contains(startDisplay))
            #expect(!solved.coordinates.contains(endDisplay))
            #expect(!solved.coordinates.contains(anchor))
            for (from, to) in zip(solved.rawPathKeys, solved.rawPathKeys.dropFirst()) {
                let hasSurveyedEdge = graph.adjacency[from]?.contains {
                    $0.to == to && $0.connector == nil
                } == true
                #expect(hasSurveyedEdge, "Every drawable segment must retain a surveyed rail edge")
            }
            #expect(solved.physicalLength == solved.rawPhysicalLength)
        }
    }

    private var west: RouteGraph.TrackIdentity { .init(operatorName: "Operator", lineName: "West", railwayClassCode: "") }
    private var east: RouteGraph.TrackIdentity { .init(operatorName: "Operator", lineName: "East", railwayClassCode: "") }

    private func junction(evidence: [String] = ["survey:fixture-junction"], validTo: String? = nil,
                          target: Coordinate? = nil) -> RouteGraph.PhysicalJunction {
        .init(id: "surveyed-junction", from: .init(identity: west, coordinate: b),
              to: .init(identity: east, coordinate: target ?? b), evidence: evidence,
              validFrom: "2020-01-01", validTo: validTo)
    }

    @Test("Coincident vertices on different lines do not create a physical junction")
    func coincidentLinesStayIndependent() throws {
        let sections = [rail([a, b], line: "West"), rail([b, d], line: "East")]
        let physical = RouteGraph.build(from: sections, policy: .physicalRailway)
        #expect(physical.nodes.count == 4)
        #expect(try solve(physical).isEmpty)
        let parity = RouteGraph.build(from: sections, policy: .coordinateParity)
        #expect(parity.nodes.count == 3)
        #expect(!(try solve(parity)).isEmpty)
    }

    @Test("Only an evidenced, existing, same-coordinate junction connects lines; dates and required hints still apply")
    func evidencedJunctionRespectsDatesAndHints() throws {
        let graph = RouteGraph.build(from: [rail([a, b], line: "West"), rail([b, d], line: "East")],
                                     policy: .physicalRailway, junctions: [junction(validTo: "2022-01-01")])
        func dated(_ day: String, hints: RouteSolver.SegmentHints = .init()) throws -> [RouteSolver.SolvedTarget] {
            RouteSolver.dijkstra(graph: graph, sourceCandidates: [.init(key: try key(a, in: graph), distance: 0)],
                                 targetKeys: [try key(d, in: graph)], train: .init(rideDate: day), allowedCodes: ["1"], hints: hints)
        }
        let accepted = try #require(dated("2021-01-01").first)
        let joins = accepted.edges.filter { $0.physicalJunction != nil }
        #expect(joins.count == 1)
        #expect(joins.first?.length == 0)
        #expect(accepted.edges.allSatisfy { $0.connector == nil })
        #expect(try dated("2019-12-31").isEmpty)
        #expect(try dated("2022-01-01").isEmpty)
        #expect(try dated("2021-01-01", hints: .init(requiredLines: ["West"])).isEmpty)
        #expect(!(try dated("2021-01-01", hints: .init(requiredLines: ["West", "East"], requiredOperators: ["Operator"]))).isEmpty)
    }

    @Test("Missing evidence, missing endpoints and gaps cannot manufacture rail")
    func invalidJunctionsAreReportedAndRejected() throws {
        let sections = [rail([a, b], line: "West"), rail([b, d], line: "East")]
        for invalid in [junction(evidence: []), junction(evidence: ["  "]), junction(target: c)] {
            let graph = RouteGraph.build(from: sections, junctions: [invalid])
            #expect(graph.rejectedPhysicalJunctionIDs == [invalid.id])
            #expect(try solve(graph).isEmpty)
        }
        let graph = RouteGraph.build(from: [rail([a, b], line: "West"), rail([c, d], line: "East")],
                                     junctions: [junction()])
        #expect(graph.rejectedPhysicalJunctionIDs == ["surveyed-junction"])
        #expect(try solve(graph).isEmpty)
    }

    @Test("Full and regional graphs use the same physical policy and explicit junctions")
    func regionalAndFullTopologyAgree() throws {
        let sections = [rail([a, b], line: "West"), rail([b, d], line: "East")]
        let store = RouteGraph.RouteGraphStore(sections: sections, policy: .physicalRailway, junctions: [junction()])
        let bbox = RouteGraph.BBox(minX: 138.99, minY: 34.99, maxX: 139.05, maxY: 35.01)
        let full = try #require(solve(store.fullGraph()).first)
        let local = try #require(solve(store.regionalGraph(for: bbox, routeSolveInProgress: true)).first)
        #expect(full.pathKeys == local.pathKeys)
        #expect(full.edges == local.edges)
        let isolated = RouteGraph.RouteGraphStore(sections: sections, policy: .physicalRailway)
        #expect(try solve(isolated.fullGraph()).isEmpty)
        #expect(try solve(isolated.regionalGraph(for: bbox, routeSolveInProgress: true)).isEmpty)
    }

    @Test("Level and track identity isolate coincident geometry within a line")
    func levelAndTrackIdentityArePhysicalBoundaries() throws {
        let first = RouteGraph.SectionFeature(properties: .init(lineName: "Rail", operator: "Operator", level: "0", trackID: "surface"), lines: [[a, b]])
        let second = RouteGraph.SectionFeature(properties: .init(lineName: "Rail", operator: "Operator", level: "-1", trackID: "tunnel"), lines: [[b, d]])
        #expect(try solve(RouteGraph.build(from: [first, second])).isEmpty)
    }

    @Test("Source level and track identifiers survive decoding into physical identity")
    func sourceTrackIdentityDecodes() throws {
        let json = #"{"type":"Feature","properties":{"line_name":"Rail","operator":"Operator","railway_class_code":"11","level":-1,"track_id":"tunnel"},"geometry":{"type":"LineString","coordinates":[[139,35],[139.02,35]]}}"#
        let section = try JSONDecoder().decode(RouteGraph.SectionFeature.self, from: Data(json.utf8))
        #expect(section.properties.trackIdentity == .init(operatorName: "Operator", lineName: "Rail", railwayClassCode: "11", level: "-1", trackID: "tunnel"))
    }

    @Test("Missing line or operator identity cannot merge coincident source features")
    func missingIdentityUsesStableGeometry() throws {
        for properties in [RouteGraph.SectionProperties(lineName: "", operator: "Operator"),
                           RouteGraph.SectionProperties(lineName: "Rail", operator: ""),
                           RouteGraph.SectionProperties()] {
            let first = RouteGraph.SectionFeature(properties: properties, lines: [[a, b]])
            let second = RouteGraph.SectionFeature(properties: properties, lines: [[b, d]])
            #expect(first.physicalTrackIdentity != second.physicalTrackIdentity)
            let full = RouteGraph.build(from: [first, second])
            #expect(full.nodes.count == 4)
            #expect(try solve(full).isEmpty)
            let reordered = RouteGraph.build(from: [second, first])
            #expect(Set(full.nodes.keys) == Set(reordered.nodes.keys))
            let store = RouteGraph.RouteGraphStore(sections: [first, second])
            let regional = store.regionalGraph(for: .init(minX: 138.99, minY: 34.99, maxX: 139.05, maxY: 35.01), routeSolveInProgress: true)
            #expect(Set(store.fullGraph().nodes.keys) == Set(regional.nodes.keys))
            #expect(try solve(regional).isEmpty)
            let firstOnly = RouteGraph.build(from: [first])
            #expect(Set(firstOnly.nodes.keys).isSubset(of: Set(full.nodes.keys)))
            let inside = RouteSolver.dijkstra(graph: firstOnly, sourceCandidates: [.init(key: try key(a, in: firstOnly), distance: 0)],
                                              targetKeys: [try key(b, in: firstOnly)], train: .init(), allowedCodes: [])
            #expect(inside.count == 1)
        }
    }

    @Test("An explicit source track identity can join its own fragments without names")
    func explicitSourceIdentityConnectsFragments() throws {
        let properties = RouteGraph.SectionProperties(sourceID: "surveyed-track-17")
        let graph = RouteGraph.build(from: [.init(properties: properties, lines: [[a, b]]),
                                          .init(properties: properties, lines: [[b, d]])])
        #expect(!(try solve(graph)).isEmpty)
    }

    @Test("Physical component cache excludes walking and includes reviewed junctions")
    func componentMembershipUsesOnlyPhysicalEdges() throws {
        let graph = RouteGraph.build(from: [rail([a, b], line: "West"), rail([c, d], line: "East")])
        RouteSolver.addStationTransferConnectorEdges(graph: graph, stations: [
            station(b, code: "B", name: "Central", line: "West"),
            station(c, code: "C", name: "Central", line: "East"),
        ])
        let components = try #require(graph.physicalRailComponents())
        #expect(components[try key(a, in: graph)] != components[try key(d, in: graph)])
        #expect(try solve(graph).isEmpty)
        #expect(!(try solve(graph, policy: .passengerTransfers)).isEmpty)

        let joined = RouteGraph.build(from: [rail([a, b], line: "West"), rail([b, d], line: "East")],
                                      junctions: [junction(validTo: "2022-01-01")])
        let joinedComponents = try #require(joined.physicalRailComponents())
        #expect(joinedComponents[try key(a, in: joined)] == joinedComponents[try key(d, in: joined)])
        // The component deliberately remains joined outside the junction's
        // validity; the existing dated/hint tests prove Dijkstra still rejects it.
    }

    @Test("Same-count nested adjacency replacement invalidates cached components")
    func nestedAdjacencyMutationRebuildsComponents() throws {
        let graph = RouteGraph.build(from: [rail([a, b]), rail([c, d])])
        let start = try key(a, in: graph)
        let middle = try key(c, in: graph)
        let original = try #require(graph.adjacency[start]?.first)
        let nodeCount = graph.nodes.count
        let edgeCount = graph.adjacency.values.reduce(0) { $0 + $1.count }
        #expect(try solve(graph).isEmpty)
        graph.adjacency[start]![0].to = middle
        #expect(graph.nodes.count == nodeCount)
        #expect(graph.adjacency.values.reduce(0) { $0 + $1.count } == edgeCount)
        #expect(!(try solve(graph)).isEmpty)
        graph.adjacency[start]![0] = original
        #expect(try solve(graph).isEmpty)

        graph.nodes["new-isolated-node"] = a
        #expect(try #require(graph.physicalRailComponents())["new-isolated-node"] != nil)
        graph.nodes.removeValue(forKey: "new-isolated-node")
        #expect(try #require(graph.physicalRailComponents())["new-isolated-node"] == nil)
    }

    @Test("One-way rail and adjacency keys absent from node metadata cannot cause false rejection")
    func weakComponentsAreOnlyAReachabilitySuperset() throws {
        let graph = RouteGraph.build(from: [])
        graph.adjacency["source"] = [.init(to: "target", length: 1, institutionTypeCode: "1",
                                           railwayClassCode: "", lineName: "Rail", operator: "Operator", connector: nil)]
        let components = try #require(graph.physicalRailComponents())
        #expect(components["source"] == components["target"])
        let forward = RouteSolver.dijkstra(graph: graph, sourceCandidates: [.init(key: "source", distance: 0)],
                                          targetKeys: ["target"], train: .init(), allowedCodes: ["1"])
        let reverse = RouteSolver.dijkstra(graph: graph, sourceCandidates: [.init(key: "target", distance: 0)],
                                          targetKeys: ["source"], train: .init(), allowedCodes: ["1"])
        #expect(forward.count == 1)
        #expect(reverse.isEmpty)
        let institution = RouteSolver.dijkstra(graph: graph, sourceCandidates: [.init(key: "source", distance: 0)],
                                              targetKeys: ["target"], train: .init(institutionFilterMode: "hard"), allowedCodes: ["2"])
        #expect(institution.isEmpty)
    }

    @Test("Cancelled component construction never publishes a partial cache")
    func cancelledComponentsAreRecomputed() throws {
        let points = (0..<1024).map { Coordinate(lon: 139 + Double($0) * 0.00001, lat: 35) }
        let graph = RouteGraph.build(from: [rail(points)])
        var cancellationChecks = 0
        let cancelled = graph.physicalRailComponents {
            cancellationChecks += 1
            return cancellationChecks == 2
        }
        #expect(cancelled == nil)
        #expect(cancellationChecks == 2)
        var retryChecks = 0
        let complete = try #require(graph.physicalRailComponents {
            retryChecks += 1
            return false
        })
        #expect(retryChecks > 2)
        #expect(complete.count == graph.nodes.count)
        #expect(complete[try key(points[0], in: graph)] == complete[try key(points[1023], in: graph)])
        var cachedChecks = 0
        #expect(graph.physicalRailComponents {
            cachedChecks += 1
            return false
        } == complete)
        #expect(cachedChecks == 1)
        #expect(graph.physicalRailComponents(isCancelled: { true }) == nil)
    }

}
