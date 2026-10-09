import Foundation
import Testing
@testable import RailCore

struct CompiledRouteGraphEquivalenceTests {
    private struct Fixture {
        let sections: [RouteGraph.SectionFeature]
        let junctions: [RouteGraph.PhysicalJunction]
    }

    private static let slice = RouteGraph.BBox(
        minX: 134.62, minY: 34.76, maxX: 134.78, maxY: 34.88)

    private static func loadFixture() throws -> Fixture {
        let data = try PortFixtures.repositoryRoot().appending(path: "app/data")
        func containsSliceCoordinate(_ value: Any) -> Bool {
            guard let array = value as? [Any] else { return false }
            if array.count >= 2, let lon = array[0] as? NSNumber,
               let lat = array[1] as? NSNumber {
                return lon.doubleValue >= slice.minX && lon.doubleValue <= slice.maxX
                    && lat.doubleValue >= slice.minY && lat.doubleValue <= slice.maxY
            }
            return array.contains(where: containsSliceCoordinate)
        }
        let rawData = try Data(contentsOf: data.appending(path: "rail-sections.json"))
        guard let document = try JSONSerialization.jsonObject(with: rawData) as? [String: Any],
              let rawFeatures = document["features"] as? [[String: Any]] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let selected = rawFeatures.filter { feature in
            guard let properties = feature["properties"] as? [String: Any],
                  properties["N02_004"] as? String == "西日本旅客鉄道",
                  let lineName = properties["N02_003"] as? String,
                  ["山陽線", "播但線"].contains(lineName),
                  let geometry = feature["geometry"] as? [String: Any],
                  let coordinates = geometry["coordinates"] else { return false }
            return containsSliceCoordinate(coordinates)
        }
        let selectedData = try JSONSerialization.data(withJSONObject: ["features": selected])
        let sections = try JSONDecoder().decode(
            RouteGraph.SectionFeatureCollection.self, from: selectedData).features
        let junctions = try PhysicalRailJunctionRegistry(data: Data(contentsOf:
            data.appending(path: "physical-rail-junctions.json"))).junctions(for: "jp").filter {
                ([$0.from.coordinate, $0.to.coordinate] + ($0.path ?? [])).contains { point in
                    point.lon >= slice.minX && point.lon <= slice.maxX
                        && point.lat >= slice.minY && point.lat <= slice.maxY
                }
            }
        return Fixture(sections: sections, junctions: junctions)
    }

    private static func expectEquivalent(
        _ actual: RouteGraph.Graph, _ expected: RouteGraph.Graph, _ label: String
    ) {
        let nodeKeys = actual.nodes.keys.sorted()
        #expect(nodeKeys == expected.nodes.keys.sorted(), "\(label) node keys")
        for key in nodeKeys {
            #expect(actual.nodes[key] == expected.nodes[key], "\(label) node \(key)")
        }

        let adjacencyKeys = actual.adjacency.keys.sorted()
        #expect(adjacencyKeys == expected.adjacency.keys.sorted(), "\(label) adjacency keys")
        for key in adjacencyKeys {
            #expect(actual.adjacency[key] == expected.adjacency[key],
                    "\(label) ordered adjacency \(key)")
        }

        let metaKeys = actual.nodeMeta.keys.sorted()
        #expect(metaKeys == expected.nodeMeta.keys.sorted(), "\(label) node metadata keys")
        for key in metaKeys {
            #expect(actual.nodeMeta[key] == expected.nodeMeta[key],
                    "\(label) node metadata \(key)")
        }

        let gridKeys = actual.grid.keys.sorted()
        #expect(gridKeys == expected.grid.keys.sorted(), "\(label) grid keys")
        for key in gridKeys {
            #expect(actual.grid[key] == expected.grid[key], "\(label) ordered grid \(key)")
        }

        #expect(actual.rejectedPhysicalJunctionIDs == expected.rejectedPhysicalJunctionIDs,
                "\(label) rejected junction IDs")
        #expect(actual.rejectedPhysicalJunctionReasons == expected.rejectedPhysicalJunctionReasons,
                "\(label) rejected junction reasons")
    }

    private static func corridorFeatureIndices(
        store: RouteGraph.RouteGraphStore, coordinates: [Coordinate], meters: Double
    ) -> [Int] {
        func cell(_ coordinate: Coordinate) -> String {
            JSNumber.string((coordinate.lon / RouteGraph.railIndexCellDeg).rounded(.down)) + ","
                + JSNumber.string((coordinate.lat / RouteGraph.railIndexCellDeg).rounded(.down))
        }

        var points = coordinates
        var cells = Set(coordinates.map(cell))
        var pending = store.junctions.map { junction in
            let junctionPoints = [junction.from.coordinate, junction.to.coordinate]
                + (junction.path ?? [])
            return (points: junctionPoints, cells: Set(junctionPoints.map(cell)))
        }
        var grew = true
        while grew {
            grew = false
            pending.removeAll { junction in
                guard !junction.cells.isDisjoint(with: cells) else { return false }
                points += junction.points
                cells.formUnion(junction.cells)
                grew = true
                return true
            }
        }

        var indices = store.featureIndicesNear(points, meters: meters)
        guard let first = coordinates.first else { return indices }
        var box = RouteGraph.BBox(
            minX: first.lon, minY: first.lat, maxX: first.lon, maxY: first.lat)
        for coordinate in coordinates {
            box.minX = min(box.minX, coordinate.lon)
            box.minY = min(box.minY, coordinate.lat)
            box.maxX = max(box.maxX, coordinate.lon)
            box.maxY = max(box.maxY, coordinate.lat)
        }
        let query = RouteGraph.quantizeBBoxOutward(
            RouteGraph.padBBoxMeters(box, meters: meters))
        let x0 = (query.minX / RouteGraph.railIndexCellDeg).rounded(.down)
        let y0 = (query.minY / RouteGraph.railIndexCellDeg).rounded(.down)
        func scanOrder(_ index: Int) -> (Double, Double, Int) {
            guard let bbox = RouteGraph.featureBBox(store.sections[index]) else {
                return (x0, y0, index)
            }
            return (max((bbox.minX / RouteGraph.railIndexCellDeg).rounded(.down), x0),
                    max((bbox.minY / RouteGraph.railIndexCellDeg).rounded(.down), y0), index)
        }
        indices.sort { scanOrder($0) < scanOrder($1) }
        return indices
    }

    @Test("Compiled store graphs equal public builds for the same ordered features")
    func compiledStoreGraphsEqualPublicBuilds() throws {
        let fixture = try Self.loadFixture()
        #expect(!fixture.sections.isEmpty)
        let himeji = try #require(fixture.junctions.first {
            $0.id == "west-himeji-sanyo-bantan"
        })
        let store = RouteGraph.RouteGraphStore(
            sections: fixture.sections, policy: .physicalRailway, junctions: fixture.junctions)

        Self.expectEquivalent(
            store.fullGraph(),
            RouteGraph.build(from: fixture.sections, policy: .physicalRailway,
                             junctions: fixture.junctions),
            "full")

        let requestedRegion = RouteGraph.BBox(
            minX: 134.66, minY: 34.80, maxX: 134.73, maxY: 34.85)
        let region = RouteGraph.quantizeBBoxOutward(requestedRegion)
        let regionalIndices = store.featureIndicesInBBox(region)
        Self.expectEquivalent(
            store.regionalGraph(for: requestedRegion, routeSolveInProgress: true),
            RouteGraph.build(from: regionalIndices.map { fixture.sections[$0] },
                             policy: .physicalRailway, junctions: fixture.junctions),
            "regional")

        let corridorCoordinates = [himeji.from.coordinate, himeji.to.coordinate]
            + (himeji.path ?? [])
        let corridorMeters = 2_000.0
        let corridorIndices = Self.corridorFeatureIndices(
            store: store, coordinates: corridorCoordinates, meters: corridorMeters)
        Self.expectEquivalent(
            store.corridorGraph(for: corridorCoordinates, meters: corridorMeters),
            RouteGraph.build(from: corridorIndices.map { fixture.sections[$0] },
                             policy: .physicalRailway, junctions: fixture.junctions),
            "corridor")

        let parityStore = RouteGraph.RouteGraphStore(
            sections: fixture.sections, policy: .coordinateParity, junctions: fixture.junctions)
        Self.expectEquivalent(
            parityStore.fullGraph(),
            RouteGraph.build(from: fixture.sections, policy: .coordinateParity,
                             junctions: fixture.junctions),
            "coordinate parity")
    }
    @Test("Bounded compiler eviction preserves surveyed fixture graph and metadata")
    func boundedCompilerEvictionPreservesFixture() throws {
        let fixture = try Self.loadFixture()
        let expected = RouteGraph.build(
            from: fixture.sections, policy: .physicalRailway, junctions: fixture.junctions)
        let store = RouteGraph.RouteGraphStore(
            sections: fixture.sections, policy: .physicalRailway,
            junctions: fixture.junctions, cachePolicy: .bounded(maximumNodes: 1))
        var releasedBeforeAugmentation = false
        store.augment = { _, _ in
            releasedBeforeAugmentation = store.retainedCompiledNodeCount == 0
        }
        Self.expectEquivalent(store.fullGraph(), expected, "bounded first build")
        #expect(releasedBeforeAugmentation)
        #expect(store.retainedGraphNodeCount == 0)
        #expect(store.retainedCompiledNodeCount == 0)
        Self.expectEquivalent(store.fullGraph(), expected, "bounded recompiled build")
        #expect(releasedBeforeAugmentation)
        #expect(store.retainedCompiledNodeCount == 0)
    }

}
