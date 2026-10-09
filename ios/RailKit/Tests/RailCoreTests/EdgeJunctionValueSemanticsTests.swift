import Foundation
import Testing
@testable import RailCore

struct EdgeJunctionValueSemanticsTests {
    // The same registry records used by ReviewedHimejiRoutingTests and
    // ReviewedUtazuRoutingTests, including their surveyed geometry and dates.
    private func junction(_ id: String) throws -> RouteGraph.PhysicalJunctionEdge {
        let data = try Data(contentsOf: PortFixtures.repositoryRoot().appending(
            path: "app/data/physical-rail-junctions.json"))
        let registry = try PhysicalRailJunctionRegistry(data: data)
        return .init(junction: try #require(registry.junctions(for: "jp").first { $0.id == id }),
                     institutionTypeCodes: ["1", "2"])
    }

    private func edge(_ payload: RouteGraph.PhysicalJunctionEdge) -> RouteGraph.Edge {
        .init(to: RouteGraph.physicalNodeKey(payload.junction.to.coordinate,
                                           identity: payload.junction.to.identity),
              length: 12.5, institutionTypeCode: "1", railwayClassCode: "11",
              lineName: payload.junction.to.identity.lineName,
              operator: payload.junction.to.identity.operatorName,
              connector: .init(institutionTypeCodes: ["1", "2"],
                               stationName: payload.junction.station ?? "",
                               groupCode: payload.junction.stationCode ?? ""),
              physicalJunction: payload, validFrom: "1988-04-10", validTo: "2027-01-01",
              historyIDs: ["ex.edge", "a"], temporalKind: .relocatedOld)
    }

    @Test("Copied edges replace and clear reviewed junctions independently")
    func independentCopies() throws {
        let himeji = try junction("west-himeji-sanyo-bantan")
        let utazu = try junction("utazu-honshi-bisan-yosan-eastern-bypass")
        let original = edge(himeji)
        #expect(original.to == RouteGraph.physicalNodeKey(
            himeji.junction.to.coordinate, identity: himeji.junction.to.identity))
        #expect(original.length == 12.5)
        #expect(original.institutionTypeCode == "1")
        #expect(original.railwayClassCode == "11")
        #expect(original.lineName == himeji.junction.to.identity.lineName)
        #expect(original.operator == himeji.junction.to.identity.operatorName)
        #expect(original.connector == .init(institutionTypeCodes: ["1", "2"],
                                           stationName: himeji.junction.station ?? "",
                                           groupCode: himeji.junction.stationCode ?? ""))
        #expect(original.validFrom == "1988-04-10")
        #expect(original.validTo == "2027-01-01")
        #expect(original.historyIDs == ["ex.edge", "a"])
        #expect(original.temporalKind == .relocatedOld)
        var replacement = original
        replacement.physicalJunction = utazu
        #expect(original.physicalJunction == himeji)
        #expect(replacement.physicalJunction == utazu)
        #expect(replacement != original)

        var cleared = original
        cleared.physicalJunction = nil
        #expect(cleared.physicalJunction == nil)
        #expect(original.physicalJunction == himeji)
        #expect(replacement.physicalJunction == utazu)
        #expect(cleared != original)

        // Restoring only the payload proves every other edge field survived.
        replacement.physicalJunction = himeji
        cleared.physicalJunction = himeji
        #expect(replacement == original)
        #expect(cleared == original)
    }

    @Test("Separately initialized and assigned boxes compare by complete junction value")
    func valueEquality() throws {
        let himeji = try junction("west-himeji-sanyo-bantan")
        let first = edge(himeji)
        var second = edge(try junction("west-himeji-sanyo-bantan"))
        #expect(first == second)
        second.physicalJunction = himeji
        #expect(first == second)
        second.physicalJunction = .init(junction: himeji.junction, institutionTypeCodes: ["1"])
        #expect(first != second)
        second.physicalJunction = try junction("utazu-honshi-bisan-yosan-eastern-bypass")
        #expect(first != second)
        #expect(first.physicalJunction?.junction == himeji.junction)
    }

    @Test("The original memberwise argument order and omitted payload defaults remain valid")
    func initializerDefaults() {
        let edge = RouteGraph.Edge(to: "node", length: 1, institutionTypeCode: "1",
                                   railwayClassCode: "11", lineName: "line", operator: "operator",
                                   connector: nil)
        #expect(edge.physicalJunction == nil)
        #expect(edge.validFrom == nil)
        #expect(edge.validTo == nil)
        #expect(edge.historyIDs.isEmpty)
        #expect(edge.temporalKind == .current)
        let omittedConnector = RouteGraph.Edge(
            to: "node", length: 1, institutionTypeCode: "1", railwayClassCode: "11",
            lineName: "line", operator: "operator")
        #expect(omittedConnector == edge)
        var copy = edge
        copy.physicalJunction = nil
        #expect(copy == edge)
    }
}
