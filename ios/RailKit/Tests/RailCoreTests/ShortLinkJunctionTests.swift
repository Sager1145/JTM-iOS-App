import Foundation
import Testing
@testable import RailCore

struct ShortLinkJunctionTests {
    private func point(_ meters: Double) -> Coordinate {
        Coordinate(lon: 139 + meters / (111_320 * cos(35 * .pi / 180)), lat: 35)
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

    /// West ends at 0 m, East starts at `gap` m.
    private func graph(gap: Double, evidence: [String] = ["surveyed"], validFrom: String? = nil,
                       validTo: String? = nil, toCoordinate: Coordinate? = nil,
                       kind: RouteGraph.PhysicalJunction.Kind = .shortLink) -> RouteGraph.Graph {
        let west = rail([point(-500), point(0)], line: "West")
        let east = rail([point(gap), point(gap + 500)], line: "East")
        let junction = RouteGraph.PhysicalJunction(
            id: "link",
            from: .init(identity: identity("West"), coordinate: point(0)),
            to: .init(identity: identity("East"), coordinate: toCoordinate ?? point(gap)),
            evidence: evidence, validFrom: validFrom, validTo: validTo, kind: kind)
        return RouteGraph.build(from: [west, east], junctions: [junction])
    }

    private func proven(_ g: RouteGraph.Graph, date: String? = nil) -> Bool {
        RouteSolver.physicalBoundaryIsProven(
            from: key(point(-500), "West"), to: key(point(520), "East"), graph: g, rideDate: date)
    }

    @Test("A 20 m reviewed link between two identities is proven and continues")
    func twentyMeterLink() {
        let g = graph(gap: 20)
        #expect(g.rejectedPhysicalJunctionIDs.isEmpty)
        #expect(RouteSolver.physicalBoundaryIsProven(
            from: key(point(0), "West"), to: key(point(20), "East"), graph: g, rideDate: nil))
        #expect(RouteSolver.physicalContinuationPath(
            from: key(point(0), "West"), to: key(point(20), "East"), graph: g, rideDate: nil)?.count == 2)
        let edge = g.adjacency[key(point(0), "West")]?.first { $0.physicalJunction != nil }
        #expect(abs((edge?.length ?? 0) - 20) < 0.5)
    }

    @Test("A 31 m link is rejected by the loader")
    func thirtyOneMeterLink() {
        let g = graph(gap: 31)
        #expect(g.rejectedPhysicalJunctionIDs == ["link"])
        #expect(proven(g) == false)
    }

    @Test("A link without evidence is rejected")
    func noEvidence() {
        #expect(graph(gap: 20, evidence: []).rejectedPhysicalJunctionIDs == ["link"])
        #expect(graph(gap: 20, evidence: [" "]).rejectedPhysicalJunctionIDs == ["link"])
    }

    @Test("A link outside its validity dates is not traversed")
    func dateInvalid() {
        let g = graph(gap: 20, validFrom: "2020-01-01", validTo: "2021-01-01")
        #expect(g.rejectedPhysicalJunctionIDs.isEmpty)
        #expect(proven(g, date: "2022-06-01") == false)
        #expect(RouteSolver.physicalContinuationPath(
            from: key(point(0), "West"), to: key(point(20), "East"), graph: g, rideDate: "2022-06-01") == nil)
    }

    @Test("sameIdentitySpan never crosses a link")
    func sameIdentityNeverCrosses() {
        let g = graph(gap: 20)
        #expect(RouteSolver.sameIdentitySpan(
            from: key(point(0), "West"), to: key(point(20), "East"), graph: g, date: nil) == false)
    }

    @Test("Link endpoints that are not existing vertices are rejected")
    func nonVertexEndpoint() {
        #expect(graph(gap: 20, toCoordinate: point(10)).rejectedPhysicalJunctionIDs == ["link"])
    }

    @Test("A zeroLength junction with distinct coordinates stays rejected")
    func zeroLengthStillStrict() {
        #expect(graph(gap: 20, kind: .zeroLength).rejectedPhysicalJunctionIDs == ["link"])
    }

    @Test("Real registry loads with no rejected entries")
    func realRegistry() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("app/data/physical-rail-junctions.json")
        let registry = try PhysicalRailJunctionRegistry(data: Data(contentsOf: url))
        let all = Localization.supportedCountries.flatMap { registry.junctions(for: $0) }
        #expect(all.count == 159)
        #expect(all.filter { $0.kind == .zeroLength }.count == 148)
        #expect(all.filter { $0.kind == .shortLink }.count == 2)
    }
}
