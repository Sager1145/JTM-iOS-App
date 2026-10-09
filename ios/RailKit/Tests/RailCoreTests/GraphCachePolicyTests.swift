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

    @Test("Bounded caches release ownership across all graph categories")
    func replacesAcrossCategories() {
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
        let corridor = store.corridorGraph(for: Array(points.suffix(2)), meters: 10)
        #expect(store.regionCacheKeys.isEmpty)
        #expect(store.retainedGraphNodeCount == 2)
        #expect(corridor === store.corridorGraph(for: Array(points.suffix(2)), meters: 10))
        // An active caller's graph survives eviction intact.
        #expect(regional.nodeCount == 2)
        store.invalidate()
        #expect(store.retainedGraphNodeCount == 0)
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
