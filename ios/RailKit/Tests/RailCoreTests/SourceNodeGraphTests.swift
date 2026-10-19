import Foundation
import Testing
@testable import RailCore

struct SourceNodeGraphTests {
    private let west = Coordinate(lon: 139, lat: 35)
    private let crossing = Coordinate(lon: 139.001, lat: 35)
    private let east = Coordinate(lon: 139.002, lat: 35)

    private func rail(_ points: [Coordinate], ids: [String], line: String = "Rail") -> RouteGraph.SectionFeature {
        .init(properties: .init(lineName: line, operator: "Operator", institutionTypeCode: "1"),
              lines: [points], sourceNodeIDs: [ids])
    }

    @Test("Distinct original nodes cannot weld on the coordinate grid; full and regional compilers agree")
    func distinctNodes() {
        let sections = [rail([west, crossing], ids: ["west", "crossing-west"]),
                        rail([crossing, east], ids: ["crossing-east", "east"])]
        let graph = RouteGraph.build(from: sections)
        #expect(graph.nodes.count == 4)
        let store = RouteGraph.RouteGraphStore(sections: sections)
        let regional = store.regionalGraph(for: .init(minX: 138.9, minY: 34.9, maxX: 139.1, maxY: 35.1))
        #expect(regional.nodes.keys.sorted() == graph.nodes.keys.sorted())
        #expect(store.fullGraph().nodes.keys.sorted() == graph.nodes.keys.sorted())
        #expect(graph.resolvedPhysicalCoordinateKey(RouteGraph.physicalNodeKey(crossing,
            identity: sections[0].physicalTrackIdentity)) == nil)
        // Explicit coordinate parity retains the historical grid behavior.
        #expect(RouteGraph.build(from: sections, policy: .coordinateParity).nodes.count == 3)
    }

    @Test("An original shared node joins one identity, never distinct track identities")
    func sharedNode() throws {
        let sections = [rail([west, crossing], ids: ["west", "shared"]),
                        rail([crossing, east], ids: ["shared", "east"]),
                        rail([crossing, east], ids: ["shared", "east"], line: "Other")]
        let graph = RouteGraph.build(from: sections)
        #expect(graph.nodes.count == 5)
        let key = try #require(graph.resolvedPhysicalCoordinateKey(RouteGraph.physicalNodeKey(crossing,
            identity: sections[0].physicalTrackIdentity)))
        #expect(graph.adjacency[key]?.count == 2)
        #expect(graph.adjacency[key]?.allSatisfy { $0.lineName == "Rail" } == true)
    }

    @Test("Source IDs decode intact and malformed explicit tables fail instead of coordinate fallback")
    func decoding() throws {
        func decode(_ ids: Any) throws -> RouteGraph.SectionFeature {
            let payload: [String: Any] = ["properties": ["operator": "Operator", "line_name": "Rail", "source_node_ids": ids],
                "geometry": ["type": "LineString", "coordinates": [[139.0,35.0],[139.001,35.0]]]]
            return try JSONDecoder().decode(RouteGraph.SectionFeature.self,
                from: JSONSerialization.data(withJSONObject: payload))
        }
        #expect(try decode([["a", "b"]]).sourceNodeIDs == [["a", "b"]])
        let malformed: [Any] = [NSNull(), [], [["a"]], [["", "b"]], [[1, 2]], ["not-a-line"], [["a", "b"], ["extra"]]]
        for ids in malformed {
            #expect(throws: (any Error).self) { try decode(ids) }
        }
    }

    @Test("Reviewed coordinate junctions require unique source nodes")
    func reviewedJunction() throws {
        var sections = [rail([west, crossing], ids: ["west", "a"]),
                        rail([crossing, east], ids: ["b", "east"], line: "Other")]
        let junction = RouteGraph.PhysicalJunction(id: "reviewed",
            from: .init(identity: sections[0].physicalTrackIdentity, coordinate: crossing),
            to: .init(identity: sections[1].physicalTrackIdentity, coordinate: crossing),
            evidence: ["https://operator.example/physical-junction"])
        let connected = RouteGraph.build(from: sections, junctions: [junction])
        #expect(connected.rejectedPhysicalJunctionIDs.isEmpty)
        let fromKey = try #require(connected.nodes.first { $0.value == west }?.key)
        let toKey = try #require(connected.nodes.first { $0.value == east }?.key)
        #expect(RouteSolver.physicalBoundaryIsProven(from: fromKey, to: toKey, graph: connected, rideDate: nil))
        #expect(connected.adjacency.values.flatMap { $0 }.filter { $0.physicalJunction != nil }.count == 2)
        sections.append(rail([crossing, east], ids: ["other-a", "other-east"]))
        let ambiguous = RouteGraph.build(from: sections, junctions: [junction])
        #expect(ambiguous.rejectedPhysicalJunctionIDs == ["reviewed"])
        #expect(ambiguous.adjacency.values.flatMap { $0 }.allSatisfy { $0.physicalJunction == nil })
    }
}
