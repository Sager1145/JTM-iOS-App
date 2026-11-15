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
        let l = try r.level(level)
        for range in ranges { try l.appendVertices(piece: Int(range.piece), first: range.first, last: range.last, to: &out) }
        return out
    }

    private func hex(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    // MARK: Closed chains and wrap spans

    @Test func closedFlagIsStoredPerChainAtEveryLevel() throws {
        let r = try loop()
        try r.validateContents()
        for level in 0..<2 {
            let l = try r.level(level)
            #expect(try l.isClosed(chain: 0))
            for chain in 1..<5 { #expect(try !l.isClosed(chain: chain)) }
            #expect(try l.pieceRange(chain: 0) == 0..<3)  // the flag does not leak into the count
            #expect(try l.chain(ofPiece: 2) == 0)
        }
        #expect(throws: RailPackError.self) { try r.level(0).isClosed(chain: 5) }
        #expect(throws: RailPackError.invalidInput("closed chain out of range")) {
            var s = L.source(); s.closedChains = [9]; return try RailPackWriter.write(s)
        }
    }

    @Test func forwardTripAcrossTheSeamWrapsInsteadOfReversingTheLoop() throws {
        let r = try loop()
        // Node 1 (loop vertex 7) forward to node 0 (loop vertex 1): across the seam.
        let wrap = try r.level(1).vertexRanges(fromNode: 1, toNode: 0, wraps: true)
        #expect(!wrap.reversed)
        #expect(wrap.ranges == [RailPackVertexRange(chain: 0, piece: 2, first: 1, last: 2),
                                RailPackVertexRange(chain: 0, piece: 0, first: 0, last: 1)])
        let mpp = RailPackLadder.mapPointsPerPoint(forZoom: 12.5)
        let decoded = try points(r, level: 1, wrap.ranges)
        let expected = [L.ring[7], L.ring[8], L.ring[0], L.ring[1]].map { L.pt(mpp, $0.0, $0.1) }
        #expect(decoded.count == 4)
        for (d, e) in zip(decoded, expected) { #expect(abs(d.x - e.x) <= mpp / 16 && abs(d.y - e.y) <= mpp / 16) }
        // Without wraps the same pair is the near-full loop, run backwards: what wraps must avoid.
        let plain = try r.level(1).vertexRanges(fromNode: 1, toNode: 0)
        #expect(plain.reversed && plain.ranges.count == 3)
        // The opposite direction across the seam is the same ranges, reversed.
        let back = try r.level(1).vertexRanges(fromNode: 0, toNode: 1, wraps: true)
        #expect(back.reversed && back.ranges == wrap.ranges)
        // wraps needs a closed chain and one chain.
        #expect(throws: RailPackError.chainNotClosed) { try r.level(1).vertexRanges(fromNode: 4, toNode: 4, wraps: true) }
        #expect(throws: RailPackError.nodesNotOnOneChain) { try r.level(1).vertexRanges(fromNode: 4, toNode: 5, wraps: true) }
    }

    // MARK: Gaps in non-continuous lines

    @Test func spanAcrossAChainGapWalksTheChainsAndOnlyTheGapDrawsNothing() throws {
        let r = try loop()
        let across = try r.level(0).vertexRanges(fromNode: 4, toNode: 5)
        #expect(!across.reversed)
        #expect(across.ranges == [RailPackVertexRange(chain: 1, piece: 3, first: 1, last: 2),
                                  RailPackVertexRange(chain: 2, piece: 4, first: 0, last: 2),
                                  RailPackVertexRange(chain: 3, piece: 5, first: 0, last: 1)])
        let back = try r.level(0).vertexRanges(fromNode: 5, toNode: 4)
        #expect(back.reversed && back.ranges == across.ranges)
        let adjacent = try r.level(0).vertexRanges(fromNode: 4, toNode: 6)
        #expect(adjacent.ranges.map(\.chain) == [1, 2] && adjacent.ranges.last == RailPackVertexRange(chain: 2, piece: 4, first: 0, last: 1))
        // Nodes of different lines stay an error.
        #expect(throws: RailPackError.nodesNotOnOneChain) { try r.level(0).vertexRanges(fromNode: 0, toNode: 7) }
        #expect(throws: RailPackError.nodesNotOnOneChain) { try r.level(0).vertexRanges(fromNode: 4, toNode: 7) }
    }

    @Test func independentPartsLineRefusesATripAcrossParts() throws {
        var source = L.source()
        source.lines[1].independentParts = true
        let r = try RailPackReader(data: RailPackWriter.write(source))
        try r.validateContents()
        // The flag round trips and does not leak into the chain count.
        #expect(try r.line(0).independentParts == false && r.line(1).independentParts && !r.line(2).independentParts)
        #expect(try r.line(1).chainCount == 3 && r.line(1).firstChain == 1)
        // Inside one part the trip is unchanged; across parts it is refused both ways, adjacent or not.
        #expect(try r.level(0).vertexRanges(fromNode: 4, toNode: 4).ranges.count == 1)
        for (from, to) in [(4, 5), (5, 4), (4, 6), (6, 5)] {
            #expect(throws: RailPackError.nodesNotOnOneChain) { try r.level(0).vertexRanges(fromNode: from, toNode: to) }
        }
        // Negative control: the same pack without the flag walks the gap.
        #expect(try loop().level(0).vertexRanges(fromNode: 4, toNode: 5).ranges.count == 3)
        // A line holds at most 32,767 chains.
        #expect(throws: RailPackError.valueTooLarge("line chain count")) {
            var s = L.source(); s.lines[1].chainCount = 0x8000; return try RailPackWriter.write(s)
        }
    }

    // MARK: Shared boundary vertex

    @Test func nodesOnASharedBoundaryVertexDropDegenerateRanges() throws {
        let r = try loop()
        // Nodes 2 and 3 are the same loop vertex: start of piece 1 and end of piece 0. Piece 1 joins piece 0, so the
        // vertex is stored once and both slots decode to it bit for bit.
        var a: [RailPackPoint] = [], b: [RailPackPoint] = []
        let l = try r.level(0)
        try l.appendVertices(piece: 1, first: 0, last: 0, to: &a)
        try l.appendVertices(piece: 0, first: 3, last: 3, to: &b)
        #expect(a == b)
        #expect(try l.piece(1).joinsPrevious)
        #expect(try l.nodeSlot(node: 2) == RailPackNodeSlot(piece: 1, vertex: 0) && l.nodeSlot(node: 3) == RailPackNodeSlot(piece: 0, vertex: 3))
        // Node 0 to node 2: the one-vertex tail on piece 1 is dropped.
        #expect(try r.level(0).vertexRanges(fromNode: 0, toNode: 2).ranges == [RailPackVertexRange(chain: 0, piece: 0, first: 1, last: 3)])
        #expect(try r.level(0).vertexRanges(fromNode: 0, toNode: 3).ranges == [RailPackVertexRange(chain: 0, piece: 0, first: 1, last: 3)])
        // Node 3 to node 1: the one-vertex head on piece 0 is dropped.
        #expect(try r.level(0).vertexRanges(fromNode: 3, toNode: 1).ranges == [RailPackVertexRange(chain: 0, piece: 1, first: 0, last: 3),
                                                                               RailPackVertexRange(chain: 0, piece: 2, first: 0, last: 1)])
        // Only degenerate ranges: the first stays, so there is still a point to draw.
        let both = try r.level(0).vertexRanges(fromNode: 3, toNode: 2)
        #expect(both.ranges == [RailPackVertexRange(chain: 0, piece: 0, first: 3, last: 3)] && !both.reversed)
        #expect(try r.level(0).vertexRanges(fromNode: 2, toNode: 2).ranges.count == 1)
    }

    // MARK: Hostile files

    @Test func badLevelScalesAreRejectedAtOpenAndNeverTrap() throws {
        let data = try T.bytes()
        let levelTable = T.u64(data, T.sectionEntry(4))
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
        let l = try r.level(0)
        let total = try l.tiles(minX: -1e12, minY: -1e12, maxX: 1e12, maxY: 1e12).count
        #expect(total == 6, "the test pack's home tiles at level 0")
        let inf = Double.infinity
        #expect(try l.tiles(minX: -inf, minY: -inf, maxX: inf, maxY: inf).count == total)
        #expect(try l.tiles(minX: -1e300, minY: -1e300, maxX: 1e300, maxY: 1e300).count == total)
        #expect(try l.tiles(minX: .nan, minY: 0, maxX: 1, maxY: 1).isEmpty)
        #expect(try l.tiles(minX: 0, minY: 0, maxX: .nan, maxY: 1).isEmpty)
        #expect(try l.longPieces(minX: .nan, minY: 0, maxX: 1, maxY: 1).isEmpty)
        #expect(try l.mountKeys(minX: .nan, minY: 0, maxX: 1, maxY: 1).isEmpty)
        // The same on a GCJ-02 reader: no trap and no change of meaning for infinite or NaN rectangles.
        let g = try RailPackReader(data: T.bytes(), display: .gcj02).level(0)
        #expect(try g.tiles(minX: -inf, minY: -inf, maxX: inf, maxY: inf).count == total)
        #expect(try g.tiles(minX: .nan, minY: 0, maxX: 1, maxY: 1).isEmpty)
        #expect(try g.mountKeys(minX: -1e300, minY: -1e300, maxX: 1e300, maxY: 1e300).count == total + 1)
        #expect(RailPackFormat.tile(containing: 1e300, mapPointsPerPoint: 0.25) == 2_147_483_647)
        #expect(RailPackFormat.tile(containing: -inf, mapPointsPerPoint: 0.25) == -2_147_483_647)
        #expect(RailPackFormat.tile(containing: .nan, mapPointsPerPoint: 0.25) == 0)
    }

    // MARK: Ladder rule

    @Test func switchDistanceFollowsTheLocalSpacing() throws {
        // Camera zooms are the app's (ladder zoom + 1). Gaps: 4 to 5 is 1.0, 5 to 6 is 1.0, 6 to 6.5 is 0.5, 6.5 to 7 is 0.5.
        let ladder = try RailPackLadder(zooms: [4, 5, 6, 6.5, 7])
        #expect(abs(ladder.switchDistance(from: 1, towards: 6) - 0.7) < 1e-12)
        #expect(abs(ladder.switchDistance(from: 2, towards: 6.4) - 0.45) < 1e-12)  // towards the 0.5 gap
        #expect(abs(ladder.switchDistance(from: 2, towards: 5.4) - 0.7) < 1e-12)   // towards the 1.0 gap
        // Installed z5: with 1.0 spacing the camera may pass the midpoint (5.5) and still hold.
        #expect(ladder.chooseLevel(cameraZoom: 6.65, installed: 1) == 1)
        #expect(ladder.chooseLevel(cameraZoom: 6.75, installed: 1) == 2)
        #expect(ladder.chooseLevel(cameraZoom: 5.35, installed: 1) == 1)
        #expect(ladder.chooseLevel(cameraZoom: 5.25, installed: 1) == 0)
        // Installed z6: 0.45 upward, 0.7 downward.
        #expect(ladder.chooseLevel(cameraZoom: 7.44, installed: 2) == 2)
        #expect(ladder.chooseLevel(cameraZoom: 7.46, installed: 2) == 3)
        #expect(ladder.chooseLevel(cameraZoom: 6.35, installed: 2) == 2)
        #expect(ladder.chooseLevel(cameraZoom: 6.25, installed: 2) == 1)
    }

    // MARK: Geometry limits

    @Test func pieceExactlyOneTileWideCentredOnATileEdgeRoundTrips() throws {
        let mpp = RailPackLadder.mapPointsPerPoint(forZoom: 10)
        let side = RailPackFormat.tileSide(mapPointsPerPoint: mpp)
        let edgeX = 100 * side, edgeY = 51 * side, half = 512 * mpp
        func source(widening quanta: Double) -> RailPackSource {
            let q = mpp / 16 * quanta
            let vertices = [RailPackPoint(x: edgeX - half - q, y: edgeY - half - q), RailPackPoint(x: edgeX + half + q, y: edgeY + half + q)]
            return RailPackFormatTests.onePiece(mpp: mpp, pieces: [RailPackPieceSource(chain: 0, group: 0, vertices: vertices)])
        }
        let r = try RailPackReader(data: RailPackWriter.write(source(widening: 0)))
        try r.validateContents()
        let l = try r.level(0)
        let row = try l.piece(0)
        #expect(row.tileX == 100 && row.tileY == 51)
        var decoded: [RailPackPoint] = []
        try l.appendVertices(piece: 0, to: &decoded)
        #expect(decoded == [RailPackPoint(x: edgeX - half, y: edgeY - half), RailPackPoint(x: edgeX + half, y: edgeY + half)])
        // One quantum wider on each side no longer fits half the Int16 range.
        #expect(throws: RailPackError.pieceOutsideHomeTile(level: 0, piece: 0)) { try RailPackWriter.write(source(widening: 1)) }
    }

    // MARK: Long-piece mounting

    @Test func longPiecesMountByBoundingBoxNotByTile() throws {
        let r = try RailPackReader(data: T.bytes())
        let l = try r.level(2)
        let long = T.source().levels[2].pieces[4].vertices
        let mpp = T.source().levels[2].mapPointsPerPoint
        let mid = long[3]
        let near = try l.mountKeys(minX: mid.x - mpp, minY: mid.y - mpp, maxX: mid.x + mpp, maxY: mid.y + mpp)
        #expect(near.contains(.longPiece(level: 2, piece: 4)))
        let far = try l.mountKeys(minX: 0, minY: 0, maxX: 10 * mpp, maxY: 10 * mpp)
        #expect(far.isEmpty)
        // A rectangle beside the box (outside it by a hair) does not mount it.
        let row = try l.longPieceRow(0)
        let q = mpp / 16
        let outside = try l.mountKeys(minX: Double(row.maxX) * q + mpp, minY: Double(row.minY) * q, maxX: Double(row.maxX) * q + 2 * mpp, maxY: Double(row.maxY) * q)
        #expect(!outside.contains(.longPiece(level: 2, piece: 4)))
        // No tile lists a long piece.
        for tile in try l.tiles(minX: -1e12, minY: -1e12, maxX: 1e12, maxY: 1e12) {
            #expect(try !l.pieceIndices(tileX: tile.x, tileY: tile.y).contains(4))
        }
        // Tile keys carry the tile coordinates.
        let all = try l.mountKeys(minX: -1e12, minY: -1e12, maxX: 1e12, maxY: 1e12)
        let tiles = try l.tiles(minX: -1e12, minY: -1e12, maxX: 1e12, maxY: 1e12)
        #expect(all.filter { if case .tile = $0 { return true } else { return false } }.count == tiles.count)
        #expect(all.contains(.tile(level: 2, x: tiles[0].x, y: tiles[0].y)))
    }

    // MARK: Frozen layout

    @Test func goldenFixturesPinTheByteLayout() throws {
        // If these change the format changed: bump the format version (no migration before first ship), do not just re-pin.
        // Re-pinned for format v2 (2026-11-13): piece rows carry their tile, shared boundary vertices are stored once,
        // long pieces are deltas, the date span moved to the group, the tile directory left the file.
        let synth = hex(try T.bytes()), loop = hex(try L.bytes())
        #expect(synth == "acc12463c34f7f11a1807be3ff17fe7adc290b98fdfafcc90e00415601990d5e", "synth \(synth)")
        #expect(loop == "74a17ab913e79626c0c0c177b2c510a5ad724806cbdb811b3378b76d9357bc13", "loop \(loop)")
    }

    // MARK: Corruption fuzz

    private func exercise(_ data: Data) {
        for display in [RailPackDisplayDatum.wgs84, .gcj02] {
            guard let r = try? RailPackReader(data: data, display: display) else { return }
            if display == .wgs84 { _ = try? r.validateContents() }
            _ = r.sizeAccounting()
            for i in -1...(min(r.header.lineCount, 40)) { _ = try? r.line(i) }
            for i in -1...(min(r.header.groupCount, 40)) { _ = try? r.group(i) }
            for i in 0...(min(r.header.spanCount, 40)) { _ = try? r.span(UInt16(i)) }
            for i in -1...(min(r.header.nodeCount, 40)) { _ = try? r.nodeChain(i) }
            let big = 1e18
            let rects: [(Double, Double, Double, Double)] = [(-big, -big, big, big), (0, 0, 1e7, 1e7), (5e7, 5e7, 6e7, 6e7), (.nan, 0, 1, 1)]
            let nodes = min(r.header.nodeCount, 8)
            for level in -1...r.levels.count {
                for kind in RailPackFormat.ArrayKind.allCases { _ = try? r.count(level: level, kind) }
                guard let l = try? r.level(level) else { continue }
                for rect in rects {
                    _ = try? l.tiles(minX: rect.0, minY: rect.1, maxX: rect.2, maxY: rect.3)
                    _ = try? l.longPieces(minX: rect.0, minY: rect.1, maxX: rect.2, maxY: rect.3)
                    _ = try? l.mountKeys(minX: rect.0, minY: rect.1, maxX: rect.2, maxY: rect.3)
                }
                _ = try? l.tileSummaries()
                for t in [-1, 0, 1, 99, 100, 65_535, 70_000] { _ = try? l.pieceIndices(tileX: t, tileY: t) }
                for p in -1...min(l.pieceCount, 64) {
                    _ = try? l.piece(p)
                    _ = try? l.chain(ofPiece: p)
                    var sink: [RailPackPoint] = []
                    _ = try? l.appendVertices(piece: p, to: &sink)
                    _ = try? l.appendVertices(piece: p, first: 1, last: 2, to: &sink)
                    _ = try? l.appendVertices(piece: p, first: 1, to: &sink)
                }
                for i in -1...min(l.count(.longPieces), 16) { _ = try? l.longPieceRow(i) }
                for c in -1...min(l.count(.chains), 16) {
                    _ = try? l.pieceRange(chain: c)
                    _ = try? l.isClosed(chain: c)
                }
                for n in -1...nodes { _ = try? l.nodeSlot(node: n) }
                for from in 0..<nodes {
                    for to in 0..<nodes {
                        _ = try? l.vertexRanges(fromNode: from, toNode: to)
                        _ = try? l.vertexRanges(fromNode: from, toNode: to, wraps: true)
                    }
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
