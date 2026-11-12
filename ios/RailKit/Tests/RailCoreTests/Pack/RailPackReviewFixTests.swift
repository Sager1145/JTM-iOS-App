import CryptoKit
import Foundation
import Testing
@testable import RailCore

/// Guards for the P2 format review: closed chains, chain gaps, hostile files, scales, the ladder rule,
/// long-piece mounting, and the frozen byte layout.
@Suite("RailPackReviewFixes")
struct RailPackReviewFixTests {
    typealias T = RailPackTestPack
    typealias L = RailPackLoopTestPack

    private func loop() throws -> RailPackReader { try RailPackReader(data: L.bytes()) }

    private func points(_ r: RailPackReader, level: Int, _ ranges: [RailPackVertexRange]) throws -> [RailPackPoint] {
        var out: [RailPackPoint] = []
        for range in ranges { try r.appendVertices(level: level, piece: Int(range.piece), first: range.first, last: range.last, to: &out) }
        return out
    }

    private func hex(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    // MARK: Closed chains and wrap spans

    @Test func closedFlagIsStoredPerChainAtEveryLevel() throws {
        let r = try loop()
        try r.validateContents()
        for level in 0..<2 {
            #expect(try r.isClosed(level: level, chain: 0))
            for chain in 1..<5 { #expect(try !r.isClosed(level: level, chain: chain)) }
            #expect(try r.pieceRange(level: level, chain: 0) == 0..<3)  // the flag does not leak into the count
            #expect(try r.chain(level: level, ofPiece: 2) == 0)
        }
        #expect(throws: RailPackError.self) { try r.isClosed(level: 0, chain: 5) }
        #expect(throws: RailPackError.invalidInput("closed chain out of range")) {
            var s = L.source(); s.closedChains = [9]; return try RailPackWriter.write(s)
        }
    }

    @Test func forwardTripAcrossTheSeamWrapsInsteadOfReversingTheLoop() throws {
        let r = try loop()
        // Node 1 (loop vertex 7) forward to node 0 (loop vertex 1): across the seam.
        let wrap = try r.vertexRanges(level: 1, fromNode: 1, toNode: 0, wraps: true)
        #expect(!wrap.reversed)
        #expect(wrap.ranges == [RailPackVertexRange(chain: 0, piece: 2, first: 1, last: 2),
                                RailPackVertexRange(chain: 0, piece: 0, first: 0, last: 1)])
        let mpp = RailPackLadder.mapPointsPerPoint(forZoom: 12.5)
        let decoded = try points(r, level: 1, wrap.ranges)
        let expected = [L.ring[7], L.ring[8], L.ring[0], L.ring[1]].map { L.pt(mpp, $0.0, $0.1) }
        #expect(decoded.count == 4)
        for (d, e) in zip(decoded, expected) { #expect(abs(d.x - e.x) <= mpp / 16 && abs(d.y - e.y) <= mpp / 16) }
        // Without wraps the same pair is the near-full loop, run backwards: what wraps must avoid.
        let plain = try r.vertexRanges(level: 1, fromNode: 1, toNode: 0)
        #expect(plain.reversed && plain.ranges.count == 3)
        // The opposite direction across the seam is the same ranges, reversed.
        let back = try r.vertexRanges(level: 1, fromNode: 0, toNode: 1, wraps: true)
        #expect(back.reversed && back.ranges == wrap.ranges)
        // wraps needs a closed chain and one chain.
        #expect(throws: RailPackError.chainNotClosed) { try r.vertexRanges(level: 1, fromNode: 4, toNode: 4, wraps: true) }
        #expect(throws: RailPackError.nodesNotOnOneChain) { try r.vertexRanges(level: 1, fromNode: 4, toNode: 5, wraps: true) }
    }

    // MARK: Gaps in non-continuous lines

    @Test func spanAcrossAChainGapWalksTheChainsAndOnlyTheGapDrawsNothing() throws {
        let r = try loop()
        let across = try r.vertexRanges(level: 0, fromNode: 4, toNode: 5)
        #expect(!across.reversed)
        #expect(across.ranges == [RailPackVertexRange(chain: 1, piece: 3, first: 1, last: 2),
                                  RailPackVertexRange(chain: 2, piece: 4, first: 0, last: 2),
                                  RailPackVertexRange(chain: 3, piece: 5, first: 0, last: 1)])
        let back = try r.vertexRanges(level: 0, fromNode: 5, toNode: 4)
        #expect(back.reversed && back.ranges == across.ranges)
        let adjacent = try r.vertexRanges(level: 0, fromNode: 4, toNode: 6)
        #expect(adjacent.ranges.map(\.chain) == [1, 2] && adjacent.ranges.last == RailPackVertexRange(chain: 2, piece: 4, first: 0, last: 1))
        // Nodes of different lines stay an error.
        #expect(throws: RailPackError.nodesNotOnOneChain) { try r.vertexRanges(level: 0, fromNode: 0, toNode: 7) }
        #expect(throws: RailPackError.nodesNotOnOneChain) { try r.vertexRanges(level: 0, fromNode: 4, toNode: 7) }
    }

    // MARK: Shared boundary vertex

    @Test func nodesOnASharedBoundaryVertexDropDegenerateRanges() throws {
        let r = try loop()
        // Nodes 2 and 3 are the same loop vertex: start of piece 1 and end of piece 0.
        var a: [RailPackPoint] = [], b: [RailPackPoint] = []
        try r.appendVertices(level: 0, piece: 1, first: 0, last: 0, to: &a)
        try r.appendVertices(level: 0, piece: 0, first: 3, last: 3, to: &b)
        #expect(a == b)
        #expect(try r.nodeIndices(level: 0, tile: 0) == [0, 1, 2, 3, 4, 5, 6, 7])
        // Node 0 to node 2: the one-vertex tail on piece 1 is dropped.
        #expect(try r.vertexRanges(level: 0, fromNode: 0, toNode: 2).ranges == [RailPackVertexRange(chain: 0, piece: 0, first: 1, last: 3)])
        #expect(try r.vertexRanges(level: 0, fromNode: 0, toNode: 3).ranges == [RailPackVertexRange(chain: 0, piece: 0, first: 1, last: 3)])
        // Node 3 to node 1: the one-vertex head on piece 0 is dropped.
        #expect(try r.vertexRanges(level: 0, fromNode: 3, toNode: 1).ranges == [RailPackVertexRange(chain: 0, piece: 1, first: 0, last: 3),
                                                                               RailPackVertexRange(chain: 0, piece: 2, first: 0, last: 1)])
        // Only degenerate ranges: the first stays, so there is still a point to draw.
        let both = try r.vertexRanges(level: 0, fromNode: 3, toNode: 2)
        #expect(both.ranges == [RailPackVertexRange(chain: 0, piece: 0, first: 3, last: 3)] && !both.reversed)
        #expect(try r.vertexRanges(level: 0, fromNode: 2, toNode: 2).ranges.count == 1)
    }

    // MARK: Hostile files

    @Test func unsortedTileDirectoryIsRejectedAtOpen() throws {
        let data = try T.bytes()
        let levelTable = T.u64(data, T.sectionEntry(3))
        let dir = T.u64(data, levelTable + RailPackFormat.levelArraysOffset + RailPackFormat.ArrayKind.tileDir.rawValue * RailPackFormat.levelArrayEntrySize + 4)
        var edited = data
        for (row, key) in [(0, 0), (9, 0), (0, 0)].enumerated() {
            edited = T.patched(edited, at: dir + row * 20, UInt64(key.0), width: 4)
            edited = T.patched(edited, at: dir + row * 20 + 4, UInt64(key.1), width: 4)
        }
        #expect(throws: RailPackError.corrupt("level 0 tile directory not sorted")) { try RailPackReader(data: edited) }
    }

    @Test func badLevelScalesAreRejectedAtOpenAndNeverTrap() throws {
        let data = try T.bytes()
        let levelTable = T.u64(data, T.sectionEntry(3))
        func patchedScale(level: Int, _ value: Double) -> Data {
            T.patched(data, at: levelTable + level * RailPackFormat.levelRow, UInt64(value.bitPattern), width: 8)
        }
        for bad in [1e-300, 0.1, 0.125, 2_097_152.0, 1e300, .nan, .infinity, -4] {
            #expect(throws: RailPackError.badLevel(0)) { try RailPackReader(data: patchedScale(level: 0, bad)) }
        }
        // Two scales whose zooms differ by under 0.01 (0.005 here) hit the ladder check, not a precondition.
        #expect(throws: RailPackError.badLevel(1)) { try RailPackReader(data: patchedScale(level: 1, 512 * 0.9965)) }
        // The ladder initialiser throws for every bad shape.
        for zooms: [Double] in [[], [1, 1], [1, 1.005], [.nan], [3, 2]] {
            #expect(throws: RailPackError.self) { try RailPackLadder(zooms: zooms) }
        }
        _ = try RailPackLadder(zooms: [1, 1.01])
        // The writer refuses the same scales.
        for bad in [0.1, 2_097_152.0] {
            var s = T.source(); s.levels[0].mapPointsPerPoint = bad
            #expect(throws: RailPackError.self) { try RailPackWriter.write(s) }
        }
        var close = T.source(); close.levels[1].mapPointsPerPoint = close.levels[0].mapPointsPerPoint * 0.9965
        #expect(throws: RailPackError.self) { try RailPackWriter.write(close) }
    }

    @Test func extremeRectanglesClampInsteadOfTrapping() throws {
        let r = try RailPackReader(data: T.bytes())
        let total = try r.count(level: 0, .tileDir)
        let inf = Double.infinity
        #expect(try r.tiles(level: 0, minX: -inf, minY: -inf, maxX: inf, maxY: inf).count == total)
        #expect(try r.tiles(level: 0, minX: -1e300, minY: -1e300, maxX: 1e300, maxY: 1e300).count == total)
        #expect(try r.tiles(level: 0, minX: .nan, minY: 0, maxX: 1, maxY: 1).isEmpty)
        #expect(try r.tiles(level: 0, minX: 0, minY: 0, maxX: .nan, maxY: 1).isEmpty)
        #expect(try r.longPieces(level: 0, minX: .nan, minY: 0, maxX: 1, maxY: 1).isEmpty)
        #expect(try r.mountKeys(level: 0, minX: .nan, minY: 0, maxX: 1, maxY: 1).isEmpty)
        #expect(RailPackFormat.tile(containing: 1e300, mapPointsPerPoint: 0.25) == 2_147_483_647)
        #expect(RailPackFormat.tile(containing: -inf, mapPointsPerPoint: 0.25) == -2_147_483_647)
        #expect(RailPackFormat.tile(containing: .nan, mapPointsPerPoint: 0.25) == 0)
    }

    // MARK: Ladder rule

    @Test func switchDistanceFollowsTheLocalSpacing() throws {
        // Gaps: 4 to 5 is 1.0, 5 to 6 is 1.0, 6 to 6.5 is 0.5, 6.5 to 7 is 0.5.
        let ladder = try RailPackLadder(zooms: [4, 5, 6, 6.5, 7])
        #expect(abs(ladder.switchDistance(from: 1, towards: 6) - 0.7) < 1e-12)
        #expect(abs(ladder.switchDistance(from: 2, towards: 6.4) - 0.45) < 1e-12)  // towards the 0.5 gap
        #expect(abs(ladder.switchDistance(from: 2, towards: 5.4) - 0.7) < 1e-12)   // towards the 1.0 gap
        // Installed z5: with 1.0 spacing the camera may pass the midpoint (5.5) and still hold.
        #expect(ladder.chooseLevel(cameraZoom: 5.65, installed: 1) == 1)
        #expect(ladder.chooseLevel(cameraZoom: 5.75, installed: 1) == 2)
        #expect(ladder.chooseLevel(cameraZoom: 4.35, installed: 1) == 1)
        #expect(ladder.chooseLevel(cameraZoom: 4.25, installed: 1) == 0)
        // Installed z6: 0.45 upward, 0.7 downward.
        #expect(ladder.chooseLevel(cameraZoom: 6.44, installed: 2) == 2)
        #expect(ladder.chooseLevel(cameraZoom: 6.46, installed: 2) == 3)
        #expect(ladder.chooseLevel(cameraZoom: 5.35, installed: 2) == 2)
        #expect(ladder.chooseLevel(cameraZoom: 5.25, installed: 2) == 1)
    }

    // MARK: Geometry limits

    @Test func pieceExactlyOneTileWideCentredOnATileEdgeRoundTrips() throws {
        let mpp = RailPackLadder.mapPointsPerPoint(forZoom: 10)
        let side = RailPackFormat.tileSide(mapPointsPerPoint: mpp)
        let edgeX = 100 * side, edgeY = 51 * side, half = 512 * mpp
        func source(widening quanta: Double) -> RailPackSource {
            let q = mpp / 16 * quanta
            let vertices = [RailPackPoint(x: edgeX - half - q, y: edgeY - half - q), RailPackPoint(x: edgeX + half + q, y: edgeY + half + q)]
            return RailPackSource(
                datum: .wgs84, regionCode: "xx", displaySHA256: [UInt8](repeating: 1, count: 32), inputsSHA256: [UInt8](repeating: 2, count: 32),
                chainCount: 1, nodeCount: 0, lines: [], groups: [RailPackGroup(colourLight: 0, colourDark: 0, tierMin: 0, tierMax: 0x7FFF, styleClass: 0, category: 0)],
                spans: [], levels: [RailPackLevelSource(mapPointsPerPoint: mpp, laneBucket: 0,
                                                         pieces: [RailPackPieceSource(chain: 0, group: 0, vertices: vertices)], nodes: [])])
        }
        let r = try RailPackReader(data: RailPackWriter.write(source(widening: 0)))
        try r.validateContents()
        let tile = try r.tile(level: 0, index: Int(r.piece(level: 0, index: 0).tile))
        #expect(tile.tileX == 100 && tile.tileY == 51)
        var decoded: [RailPackPoint] = []
        try r.appendVertices(level: 0, piece: 0, to: &decoded)
        #expect(decoded == [RailPackPoint(x: edgeX - half, y: edgeY - half), RailPackPoint(x: edgeX + half, y: edgeY + half)])
        // One quantum wider on each side no longer fits half the Int16 range.
        #expect(throws: RailPackError.pieceOutsideHomeTile(level: 0, piece: 0)) { try RailPackWriter.write(source(widening: 1)) }
    }

    // MARK: Long-piece mounting

    @Test func longPiecesMountByBoundingBoxNotByTile() throws {
        let r = try RailPackReader(data: T.bytes())
        let long = T.source().levels[2].pieces[4].vertices
        let mpp = T.source().levels[2].mapPointsPerPoint
        let mid = long[3]
        let near = try r.mountKeys(level: 2, minX: mid.x - mpp, minY: mid.y - mpp, maxX: mid.x + mpp, maxY: mid.y + mpp)
        #expect(near.contains(.longPiece(level: 2, piece: 4)))
        let far = try r.mountKeys(level: 2, minX: 0, minY: 0, maxX: 10 * mpp, maxY: 10 * mpp)
        #expect(far.isEmpty)
        // A rectangle beside the box (outside it by a hair) does not mount it.
        let row = try r.longPieceRow(level: 2, index: 0)
        let q = mpp / 16
        let outside = try r.mountKeys(level: 2, minX: Double(row.maxX) * q + mpp, minY: Double(row.minY) * q, maxX: Double(row.maxX) * q + 2 * mpp, maxY: Double(row.maxY) * q)
        #expect(!outside.contains(.longPiece(level: 2, piece: 4)))
        // No tile lists a long piece.
        for tile in 0..<(try r.count(level: 2, .tileDir)) { #expect(try !r.pieceIndices(level: 2, tile: tile).contains(4)) }
        // Tile keys carry the tile coordinates.
        let all = try r.mountKeys(level: 2, minX: -1e12, minY: -1e12, maxX: 1e12, maxY: 1e12)
        #expect(all.filter { if case .tile = $0 { return true } else { return false } }.count == (try r.count(level: 2, .tileDir)))
    }

    // MARK: Frozen layout

    @Test func goldenFixturesPinTheByteLayout() throws {
        // If these change the format changed: bump the format version and migrate, do not just re-pin.
        let synth = hex(try T.bytes()), loop = hex(try L.bytes())
        #expect(synth == "a00e63025fa8e74017fb34c7f85f06f5861001d97b68ccbdb7b6e00689285d01", "synth \(synth)")
        #expect(loop == "452de7d10f5f79edb896ab1c2a405d90318c4ad4031cebfa811447667072bbb0", "loop \(loop)")
    }

    // MARK: Corruption fuzz

    private func exercise(_ data: Data) {
        guard let r = try? RailPackReader(data: data) else { return }
        _ = try? r.validateContents()
        _ = r.sizeAccounting()
        for i in -1...(min(r.header.lineCount, 40)) { _ = try? r.line(i) }
        for i in -1...(min(r.header.groupCount, 40)) { _ = try? r.group(i) }
        for i in 0...(min(r.header.spanCount, 40)) { _ = try? r.span(UInt16(i)) }
        let big = 1e18
        let rects: [(Double, Double, Double, Double)] = [(-big, -big, big, big), (0, 0, 1e7, 1e7), (5e7, 5e7, 6e7, 6e7), (.nan, 0, 1, 1)]
        let nodes = min(r.header.nodeCount, 8)
        for level in -1...r.levels.count {
            for kind in RailPackFormat.ArrayKind.allCases { _ = try? r.count(level: level, kind) }
            for rect in rects {
                _ = try? r.tiles(level: level, minX: rect.0, minY: rect.1, maxX: rect.2, maxY: rect.3)
                _ = try? r.longPieces(level: level, minX: rect.0, minY: rect.1, maxX: rect.2, maxY: rect.3)
                _ = try? r.mountKeys(level: level, minX: rect.0, minY: rect.1, maxX: rect.2, maxY: rect.3)
            }
            guard level >= 0, level < r.levels.count else { continue }
            let info = r.levels[level]
            for t in -1...min(info.count(.tileDir), 64) {
                _ = try? r.tile(level: level, index: t)
                _ = try? r.pieceIndices(level: level, tile: t)
                _ = try? r.nodeIndices(level: level, tile: t)
            }
            for p in -1...min(info.count(.pieces), 64) {
                _ = try? r.piece(level: level, index: p)
                _ = try? r.chain(level: level, ofPiece: p)
                var sink: [RailPackPoint] = []
                _ = try? r.appendVertices(level: level, piece: p, to: &sink)
                _ = try? r.appendVertices(level: level, piece: p, first: 1, last: 2, to: &sink)
            }
            for l in -1...min(info.count(.longPieces), 16) { _ = try? r.longPieceRow(level: level, index: l) }
            for c in -1...min(info.count(.chains), 16) {
                _ = try? r.pieceRange(level: level, chain: c)
                _ = try? r.isClosed(level: level, chain: c)
            }
            for n in -1...nodes { _ = try? r.nodeSlot(level: level, node: n) }
            for from in 0..<nodes {
                for to in 0..<nodes {
                    _ = try? r.vertexRanges(level: level, fromNode: from, toNode: to)
                    _ = try? r.vertexRanges(level: level, fromNode: from, toNode: to, wraps: true)
                }
            }
        }
    }

    @Test func randomByteCorruptionNeverTrapsOrHangs() throws {
        var state: UInt64 = 0xC0FF_EE12_3456_789A
        func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state >> 24
        }
        for base in [try T.bytes(), try L.bytes()] {
            exercise(base)
            for iteration in 0..<1_500 {
                var data = base
                for _ in 0..<(1 + Int(next() % 3)) {
                    // Half the edits land in the header, section table and level rows, where structure lives.
                    let limit = iteration % 2 == 0 ? min(data.count, 760) : data.count
                    data[Int(next() % UInt64(limit))] = UInt8(truncatingIfNeeded: next())
                }
                exercise(data)
            }
        }
    }
}
