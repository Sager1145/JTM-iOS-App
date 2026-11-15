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
                func same(_ mine: [StrokePoint], _ theirs: [Coordinate], _ what: String) {
                    #expect(mine.count == theirs.count, "\(what) of \(chain.id) at \(zoom)")
                    for (a, b) in zip(mine, theirs.map(StrokeProjection.point)) {
                        #expect(abs(a.x - b.x) < 1e-6 && abs(a.y - b.y) < 1e-6, "\(what) of \(chain.id) at \(zoom)")
                    }
                }
                var landlord: [(group: String, family: StrokeBake.FamilyRun, index: Int)] = []
                for key in geometry.familyCoordinateChunks.keys.sorted() {
                    let family = geometry.familyCoordinateChunks[key]!
                    landlord += family.coordinateChunks.indices.map { (key, family, $0) }
                }
                #expect(chain.landlord.count == landlord.count, "landlord of \(chain.id)")
                for (mine, theirs) in zip(chain.landlord, landlord) {
                    #expect(mine.groupID == theirs.group)
                    #expect(mine.colorHex == theirs.family.colorHex && mine.colorDarkHex == theirs.family.colorDarkHex)
                    #expect(mine.from == theirs.family.chunkWindows[theirs.index].from)
                    #expect(mine.to == theirs.family.chunkWindows[theirs.index].to)
                    same(mine.vertices, theirs.family.coordinateChunks[theirs.index], "landlord")
                }
                var fallback: [(group: String, family: StrokeBake.FamilyRun, index: Int)] = []
                for item in geometry.familyFallbacks {
                    fallback += item.family.coordinateChunks.indices.map { (item.window.groupID, item.family, $0) }
                }
                #expect(chain.tenantFallback.count == fallback.count, "fallback of \(chain.id)")
                for (mine, theirs) in zip(chain.tenantFallback, fallback) {
                    #expect(mine.groupID == theirs.group)
                    #expect(mine.colorHex == theirs.family.colorHex && mine.colorDarkHex == theirs.family.colorDarkHex)
                    #expect(mine.from == theirs.family.chunkWindows[theirs.index].from)
                    #expect(mine.to == theirs.family.chunkWindows[theirs.index].to)
                    same(mine.vertices, theirs.family.coordinateChunks[theirs.index], "fallback")
                }
                let withheld = prepared.strokes[chain.id]?.withheldRuns ?? []
                #expect(chain.withheld.count == withheld.count, "withheld of \(chain.id)")
                for (mine, theirs) in zip(chain.withheld, withheld) {
                    #expect(mine.groupID == nil)
                    #expect(mine.colorHex == theirs.colorHex && mine.colorDarkHex == theirs.colorDarkHex)
                    #expect(mine.from == theirs.from && mine.to == theirs.to)
                    same(mine.vertices, theirs.coordinates, "withheld")
                }
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

    @Test("pieces that meet on the chain share their boundary vertex exactly, and every piece is a slice of the stroke")
    func boundariesAreShared() throws {
        let network = StrokeBakeFixtures.network(try StrokeBakeFixtures.load())
        let baked = try NetworkStrokeBake.bake(network, level: .init(appZoom: 13))
        var meetings = 0
        var withheldWithRange = 0
        for chain in baked.chains where chain.continuous {
            #expect(chain.strokePoints.count == chain.strokeMeasures.count, "\(chain.id)")
            struct Piece { var from: Double; var to: Double; var vertices: [StrokePoint] }
            let pieces: [Piece] =
                chain.runs.map { Piece(from: $0.from, to: $0.to, vertices: $0.vertices) }
                + chain.withheld.map { Piece(from: $0.from, to: $0.to, vertices: $0.vertices) }
                + chain.landlord.map { Piece(from: $0.from, to: $0.to, vertices: $0.vertices) }
            for piece in pieces {
                #expect(piece.from <= piece.to, "\(chain.id)")
                if let low = chain.strokeMeasures.first, let high = chain.strokeMeasures.last {
                    #expect(piece.from >= low && piece.to <= high, "\(chain.id)")
                }
            }
            withheldWithRange += chain.withheld.filter { $0.to > $0.from }.count
            for a in pieces {
                for b in pieces where abs(a.to - b.from) < 1e-9 && a.to > a.from && b.to > b.from {
                    let end = try #require(a.vertices.last)
                    let start = try #require(b.vertices.first)
                    #expect(end == start, "boundary at \(a.to) m of \(chain.id)")
                    meetings += 1
                }
            }
            for node in chain.nodes {
                if let low = chain.strokeMeasures.first, let high = chain.strokeMeasures.last {
                    #expect(node.measure >= low - 1e-6 && node.measure <= high + 1e-6, "\(chain.id)")
                }
            }
        }
        #expect(meetings > 0, "some pieces meet")
        #expect(withheldWithRange > 0, "withheld runs carry their range")
        let tenant = try #require(baked.chains.first { $0.id.contains("syn-tenant") })
        #expect(tenant.runs.count >= 2 && tenant.runs.allSatisfy { $0.to > $0.from })
    }
}
