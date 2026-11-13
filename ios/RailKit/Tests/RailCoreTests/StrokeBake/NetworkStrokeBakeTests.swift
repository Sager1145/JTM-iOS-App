import Foundation
import Testing
@testable import RailCore

/// The whole-network entry a host tool calls.
@Suite("NetworkStrokeBake")
struct NetworkStrokeBakeTests {

    static let zooms: [Double] = [5, 10.5, 13, 17]

    @Test("the same input twice gives equal output")
    func deterministic() throws {
        let network = StrokeBakeFixtures.network(try StrokeBakeFixtures.load())
        for zoom in Self.zooms {
            let level = NetworkStrokeBake.Level(appZoom: zoom)
            let first = try NetworkStrokeBake.bake(network, level: level)
            let second = try NetworkStrokeBake.bake(network, level: level)
            #expect(first == second, "level \(zoom)")
        }
    }

    @Test("chains keep the input order and ids, one per input line")
    func stableIDs() throws {
        let network = StrokeBakeFixtures.network(try StrokeBakeFixtures.load())
        let baked = try NetworkStrokeBake.bake(network, level: .init(appZoom: 12))
        #expect(baked.chains.map(\.id) == network.lines.map(\.id))
        #expect(Set(baked.chains.map(\.id)).count == baked.chains.count)
    }

    @Test("what the bake writes is what the app's preparation pass draws")
    func bakeEqualsPrepare() throws {
        let network = StrokeBakeFixtures.network(try StrokeBakeFixtures.load())
        let byID = Dictionary(network.lines.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for zoom in Self.zooms {
            let level = NetworkStrokeBake.Level(appZoom: zoom)
            let baked = try NetworkStrokeBake.bake(network, level: level)
            let joined = JoinedChainCache()
            let prepared = try StrokeBake.prepare(
                lines: network.lines, strokes: network.lines.filter(\.continuous), allLines: byID,
                anchors: network.anchors, cachedStrokes: [:], joinedChains: joined,
                chainPixels: ChainPixelCache(joinedChains: joined), frame: level,
                partStyle: { _, _ in .solid })
            for chain in baked.chains {
                let geometry = try #require(prepared.lines[chain.id])
                // Own ink: the bake's runs, chunked the way the app chunks them, are the app's chunks.
                let chunks = chain.runs.flatMap { StrokeBake.chunks($0.vertices) }
                #expect(chunks.count == geometry.coordinateChunks.count, "own ink of \(chain.id) at \(zoom)")
                for (mine, theirs) in zip(chunks, geometry.coordinateChunks) {
                    #expect(mine.count == theirs.count, "\(chain.id) at \(zoom)")
                    for (a, b) in zip(mine, theirs.map(StrokeProjection.point)) {
                        #expect(abs(a.x - b.x) < 1e-6 && abs(a.y - b.y) < 1e-6, "\(chain.id) at \(zoom)")
                    }
                }
                let landlord = geometry.familyCoordinateChunks.keys.sorted().flatMap { key in
                    geometry.familyCoordinateChunks[key]!.coordinateChunks
                }
                #expect(chain.landlord.map(\.vertices.count) == landlord.map(\.count), "landlord of \(chain.id)")
                let fallback = geometry.familyFallbacks.flatMap(\.family.coordinateChunks)
                #expect(chain.tenantFallback.map(\.vertices.count) == fallback.map(\.count), "fallback of \(chain.id)")
                // Station nodes are the stroke's anchors.
                if chain.continuous, let stroke = prepared.strokes[chain.id] {
                    for node in chain.nodes {
                        let anchor = try #require(stroke.anchors[node.anchor])
                        let expected = StrokeProjection.point(anchor)
                        #expect(abs(node.point.x - expected.x) < 1e-6 && abs(node.point.y - expected.y) < 1e-6)
                    }
                }
            }
        }
    }

    @Test("every requested station gets a node on the baked chain")
    func nodes() throws {
        let network = StrokeBakeFixtures.network(try StrokeBakeFixtures.load())
        let baked = try NetworkStrokeBake.bake(network, level: .init(appZoom: 13))
        var checked = 0
        for chain in baked.chains where chain.continuous {
            let requested = Set(network.anchors[chain.id] ?? [])
            guard !requested.isEmpty else { continue }
            #expect(Set(chain.nodes.map(\.anchor)) == requested, "\(chain.id)")
            #expect(chain.nodes.map(\.anchor) == chain.nodes.map(\.anchor).sorted())
            checked += 1
        }
        #expect(checked > 20)
    }

    @Test("withheld, landlord and tenant fallback runs come out of the synthetic chains")
    func tokenRuns() throws {
        let network = StrokeBakeFixtures.network(try StrokeBakeFixtures.load())
        let baked = try NetworkStrokeBake.bake(network, level: .init(appZoom: 13))
        let tenant = try #require(baked.chains.first { $0.id.contains("syn-tenant") })
        let canon = try #require(baked.chains.first { $0.id.contains("syn-canon") })
        #expect(!tenant.withheld.isEmpty)
        #expect(!tenant.tenantFallback.isEmpty)
        #expect(tenant.tenantFallback.allSatisfy { $0.groupID == "syn:family" && $0.colorHex == "#112233" })
        #expect(!canon.landlord.isEmpty)
        #expect(canon.landlord.allSatisfy { $0.colorHex == "#112233" && $0.colorDarkHex == "#445566" })
        #expect(tenant.runs.count >= 2, "the tenant's own ink is the complement of its windows")
    }

    @Test("a lower level has no more baked vertices than a higher one")
    func levelsDiffer() throws {
        let network = StrokeBakeFixtures.network(try StrokeBakeFixtures.load())
        func vertices(_ zoom: Double) throws -> Int {
            try NetworkStrokeBake.bake(network, level: .init(appZoom: zoom)).chains
                .reduce(0) { $0 + $1.runs.reduce(0) { $0 + $1.vertices.count } }
        }
        let low = try vertices(5)
        let high = try vertices(13)
        #expect(low > 0)
        #expect(low <= high)
    }

    @Test("the GCJ-02 variant bakes the shifted network")
    func gcjVariant() throws {
        let fixture = try StrokeBakeFixtures.load()
        let wgs = try NetworkStrokeBake.bake(StrokeBakeFixtures.network(fixture), level: .init(appZoom: 13))
        let gcj = try NetworkStrokeBake.bake(
            StrokeBakeFixtures.network(fixture, shiftToGCJ02: ["hk"]), level: .init(appZoom: 13))
        let a = try #require(wgs.chains.first { $0.region == "hk" })
        let b = try #require(gcj.chains.first { $0.id == a.id })
        let p = try #require(a.runs.first?.vertices.first)
        let q = try #require(b.runs.first?.vertices.first)
        let metres = hypot(p.x - q.x, p.y - q.y) * StrokeProjection.metresPerMapPoint(atLatitude: 22.3)
        #expect(metres > 100 && metres < 1000, "datum shift of \(metres) m")
        let jp = try #require(wgs.chains.first { $0.region == "jp" })
        #expect(jp == gcj.chains.first { $0.id == jp.id })
    }
}
