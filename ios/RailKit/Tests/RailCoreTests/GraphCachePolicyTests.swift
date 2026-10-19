import Foundation
import Testing
@testable import RailCore

struct GraphCachePolicyTests {
    private let points = [Coordinate(lon: 139, lat: 35), Coordinate(lon: 139.001, lat: 35),
                          Coordinate(lon: 140, lat: 36), Coordinate(lon: 140.001, lat: 36)]
    private var sections: [RouteGraph.SectionFeature] {
        [Array(points.prefix(2)), Array(points.suffix(2))].map {
            .init(properties: .init(lineName: "Rail", operator: "Operator", institutionTypeCode: "1"), lines: [$0])
        }
    }
    private var box: RouteGraph.BBox {
        .init(minX: 138.99, minY: 34.99, maxX: 139.01, maxY: 35.01)
    }

    @Test("Bounded caches release the full graph before building a regional one")
    func releasesFullGraphBeforeRegional() {
        let store = RouteGraph.RouteGraphStore(sections: sections, cachePolicy: .bounded(maximumNodes: 4))
        weak let previous = store.fullGraph()
        #expect(previous != nil)
        #expect(store.retainedGraphNodeCount == 4)
        var releasedBeforeAugmentation = false
        store.augment = { _, _ in releasedBeforeAugmentation = previous == nil }
        let regional = store.regionalGraph(for: box)
        #expect(releasedBeforeAugmentation)
        #expect(previous == nil)
        #expect(regional === store.regionalGraph(for: box))
        #expect(store.retainedGraphNodeCount == 2)
        // An active caller's graph survives eviction intact.
        #expect(regional.nodeCount == 2)
        store.invalidate()
        #expect(store.retainedGraphNodeCount == 0)
    }

    /// A route solve alternates a section's regional graph with corridor
    /// proofs of the path it found. A single shared slot made every proof
    /// evict the regional graph, so each following section rebuilt it.
    @Test("Corridor proofs keep the regional graph within the node budget")
    func corridorProofsKeepRegionalGraph() {
        let store = RouteGraph.RouteGraphStore(sections: sections, cachePolicy: .bounded(maximumNodes: 4))
        let regional = store.regionalGraph(for: box)
        let corridor = store.corridorGraph(for: Array(points.suffix(2)), meters: 10)
        #expect(store.regionCacheKeys.count == 1)
        #expect(regional === store.regionalGraph(for: box))
        #expect(corridor === store.corridorGraph(for: Array(points.suffix(2)), meters: 10))
        #expect(store.retainedGraphNodeCount == 4)
        // A third graph evicts the least recently used one, never the new one.
        let other = RouteGraph.BBox(minX: 139.99, minY: 35.99, maxX: 140.01, maxY: 36.01)
        let second = store.regionalGraph(for: other)
        #expect(store.retainedGraphNodeCount <= 4)
        #expect(second === store.regionalGraph(for: other))
        #expect(regional === store.regionalGraph(for: box))
        #expect(store.retainedGraphNodeCount <= 4)
    }

    @Test("Oversized graphs stay complete but are not cached")
    func oversizedGraphsAreTransient() {
        let store = RouteGraph.RouteGraphStore(sections: sections, cachePolicy: .bounded(maximumNodes: 1))
        var compilerReleasedBeforeAugmentation = false
        store.augment = { _, _ in
            compilerReleasedBeforeAugmentation = store.retainedCompiledNodeCount == 0
        }
        let full = store.fullGraph()
        #expect(compilerReleasedBeforeAugmentation)
        #expect(store.retainedCompiledNodeCount == 0)
        #expect(full.nodeCount == 4)
        #expect(store.retainedGraphNodeCount == 0)
        #expect(full !== store.fullGraph())
        #expect(store.regionalGraph(for: box).nodeCount == 2)
        #expect(store.retainedGraphNodeCount == 0)
        #expect(store.corridorGraph(for: points, meters: 10).nodeCount == 4)
        #expect(store.retainedGraphNodeCount == 0)
    }

    @Test("Exact corridor reuse respects radius, invalidation and node budget")
    func corridorRequestsRemainScoped() {
        let local = Array(points.prefix(2))
        let store = RouteGraph.RouteGraphStore(sections: sections, cachePolicy: .bounded(maximumNodes: 4))
        let narrow = store.corridorGraph(for: local, meters: 10)
        #expect(narrow.nodeCount == 2)
        #expect(store.corridorGraph(for: local, meters: 10) === narrow)
        let wide = store.corridorGraph(for: local, meters: 200_000)
        #expect(wide.nodeCount == 4)
        #expect(store.retainedGraphNodeCount <= 4)
        // The wider replacement evicted the old corridor. A repeated request
        // must rebuild its own topology, rather than keep an unbudgeted alias.
        let rebuilt = store.corridorGraph(for: local, meters: 10)
        #expect(rebuilt.nodeCount == 2)
        #expect(rebuilt !== narrow)
        store.invalidate()
        #expect(store.corridorGraph(for: local, meters: 10) !== rebuilt)
    }

    @Test("Shared proof provenance belongs to an immutable feature snapshot")
    func proofProvenanceInvalidatesOnMutation() {
        let snapshot = UUID()
        let first = RouteGraph.RouteGraphStore(sections: sections, sourceSnapshotID: snapshot)
        let second = RouteGraph.RouteGraphStore(sections: sections, sourceSnapshotID: snapshot)
        let local = Array(points.prefix(2))
        let graph = first.corridorGraph(for: local, meters: 10)
        #expect(graph.sourceProofProvenance != nil)
        #expect(graph.sourceProofProvenance == second.corridorGraph(for: local, meters: 10).sourceProofProvenance)
        #expect(graph.sourceProofProvenance != RouteGraph.RouteGraphStore(
            sections: sections, sourceSnapshotID: UUID()).corridorGraph(for: local, meters: 10).sourceProofProvenance)
        let nodes = graph.nodes
        graph.nodes = nodes
        #expect(graph.sourceProofProvenance == nil)
        let augmented = RouteGraph.RouteGraphStore(sections: sections, sourceSnapshotID: snapshot)
        augmented.augment = { _, _ in }
        #expect(augmented.corridorGraph(for: local, meters: 10).sourceProofProvenance == nil)
    }

    @Test("Eviction and rebuilding preserve physical topology and adjacency order")
    func rebuildingPreservesGraph() {
        let standard = RouteGraph.RouteGraphStore(sections: sections)
        let bounded = RouteGraph.RouteGraphStore(sections: sections, cachePolicy: .bounded(maximumNodes: 4))
        let expected = standard.fullGraph()
        _ = bounded.regionalGraph(for: box)
        let rebuilt = bounded.fullGraph()
        #expect(rebuilt.nodes == expected.nodes)
        #expect(rebuilt.adjacency == expected.adjacency)
        _ = bounded.corridorGraph(for: Array(points.suffix(2)), meters: 10)
        #expect(bounded.fullGraph().adjacency == expected.adjacency)
        #expect(standard.retainedCompiledNodeCount == 4)
        #expect(standard.fullGraph() === expected)
    }
}
