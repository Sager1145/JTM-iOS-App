import Foundation
import Testing
@testable import RailCore

struct AstramClassSeamTests {
    @Test("Astram surveyed class seam needs its explicit dated junction")
    func evidencedAstramClassSeam() throws {
        let south = Coordinate(lon: 132.45718, lat: 34.39377)
        let seam = Coordinate(lon: 132.45805, lat: 34.39636)
        let middle = Coordinate(lon: 132.4581, lat: 34.39651)
        let north = Coordinate(lon: 132.45829, lat: 34.39705)
        let operatorName = "広島高速交通"
        let lineName = "広島新交通1号線"
        func identity(_ code: String) -> RouteGraph.TrackIdentity {
            .init(operatorName: operatorName, lineName: lineName, railwayClassCode: code)
        }
        // Exact MLIT N02 feature4016 and feature4030 geometry, including the
        // different N02 railway classes on the same continuous passenger line.
        let dataRoot = try PortFixtures.repositoryRoot().appending(path: "app/data")
        let raw = try RouteGraph.SectionFeatureCollection.load(contentsOf:
            dataRoot.appending(path: "rail-sections.json")).features
        let sections = raw.filter { feature in
            feature.properties.operator == operatorName && feature.properties.lineName == lineName &&
            (feature.lines == [[south, seam]] || feature.lines == [[seam, middle, north]])
        }
        #expect(sections.count == 2)

        let southKey = RouteGraph.physicalNodeKey(south, identity: identity("16"))
        let northKey = RouteGraph.physicalNodeKey(north, identity: identity("24"))
        let seam16 = RouteGraph.physicalNodeKey(seam, identity: identity("16"))
        let seam24 = RouteGraph.physicalNodeKey(seam, identity: identity("24"))
        let absent = RouteGraph.build(from: sections, policy: .physicalRailway)
        #expect(seam16 != seam24)
        #expect(absent.nodes[seam16] != nil && absent.nodes[seam24] != nil)
        #expect(!RouteSolver.physicalBoundaryIsProven(from: seam16, to: seam24,
                graph: absent, rideDate: "2026-10-10"))
        #expect(RouteSolver.verifiedPhysicalPathKeys([south, seam, middle, north],
                graph: absent, rideDate: "2026-10-10", requiredLines: [lineName],
                requiredOperators: [operatorName]) == nil)
        let registry = try PhysicalRailJunctionRegistry(data: Data(contentsOf:
            dataRoot.appending(path: "physical-rail-junctions.json")))
        let junction = try #require(registry.junctions(for: "jp").first {
            $0.id == "astram-kencho-class16-class24"
        })
        #expect(junction.from.identity == identity("16"))
        #expect(junction.to.identity == identity("24"))
        #expect(junction.from.coordinate == seam && junction.to.coordinate == seam)
        #expect(junction.validFrom == "1994-08-20")
        let linked = RouteGraph.build(from: sections, policy: .physicalRailway, junctions: [junction])
        #expect(linked.rejectedPhysicalJunctionIDs.isEmpty)
        #expect(RouteSolver.physicalBoundaryIsProven(from: seam16, to: seam24,
                graph: linked, rideDate: "2026-10-10"))
        let keys = try #require(RouteSolver.verifiedPhysicalPathKeys([south, seam, middle, north],
                graph: linked, rideDate: "2026-10-10", requiredLines: [lineName],
                requiredOperators: [operatorName]))
        #expect(keys.first == southKey && keys.last == northKey)
        #expect(keys.contains(seam16) && keys.contains(seam24))
        #expect(!RouteSolver.physicalBoundaryIsProven(from: seam16, to: seam24,
                graph: linked, rideDate: "1994-08-19"))
    }
}
