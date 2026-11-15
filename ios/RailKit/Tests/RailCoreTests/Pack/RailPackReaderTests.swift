import Foundation
import Testing
@testable import RailCore

@Suite("RailPackReader")
struct RailPackReaderTests {
    typealias T = RailPackTestPack

    private func reader() throws -> RailPackReader { try RailPackReader(data: T.bytes()) }

    @Test func roundTripsHeaderTablesAndGeometry() throws {
        let source = T.source()
        let r = try RailPackReader(data: RailPackWriter.write(source))
        try r.validateContents()
        #expect(r.header.formatVersion == 2)
        #expect(r.header.regionCode == "jp")
        #expect(r.header.levelCount == 3 && r.header.chainCount == 3 && r.header.nodeCount == 4)
        #expect(r.header.displaySHA256 == source.displaySHA256 && r.header.inputsSHA256 == source.inputsSHA256)
        #expect(try r.line(0) == source.lines[0] && r.line(1) == source.lines[1])
        #expect(try r.group(1) == source.groups[1])
        #expect(try r.group(3) == source.groups[3] && r.group(3).span == 0 && r.group(0).span == RailPackFormat.noSpan)
        #expect(try r.span(0) == source.spans[0])
        #expect(try r.span(RailPackFormat.noSpan) == nil)
        #expect(throws: RailPackError.self) { try r.line(2) }
        #expect(throws: RailPackError.self) { try r.span(5) }
        // The region-wide chain of each node: nodes 0 and 1 on chain 0, node 2 on the long piece's chain 1, node 3 none.
        #expect(try (0..<4).map { try r.nodeChain($0) } == [0, 0, 1, RailPackFormat.noNode])

        for (levelIndex, level) in source.levels.enumerated() {
            let bound = level.mapPointsPerPoint / 32 + 1e-3
            let l = try r.level(levelIndex)
            #expect(r.levels[levelIndex].laneBucket == level.laneBucket)
            #expect(l.vertexCount == level.pieces.reduce(0) { $0 + $1.vertices.count })
            for (pieceIndex, piece) in level.pieces.enumerated() {
                let row = try l.piece(pieceIndex)
                #expect(row.isLong == piece.isLong)
                #expect(Int(row.vertexCount) == piece.vertices.count)
                #expect(row.group == piece.group)
                var decoded: [RailPackPoint] = []
                try l.appendVertices(piece: pieceIndex, to: &decoded)
                #expect(decoded.count == piece.vertices.count)
                for (d, v) in zip(decoded, piece.vertices) {
                    #expect(abs(d.x - v.x) <= bound && abs(d.y - v.y) <= bound)
                }
                // A sub-range decodes to the same points as the whole piece.
                var sub: [RailPackPoint] = []
                try l.appendVertices(piece: pieceIndex, first: 1, last: piece.vertices.count - 1, to: &sub)
                #expect(sub == Array(decoded[1...]))
            }
            // Chains and node slots.
            #expect(try l.pieceRange(chain: 0) == 0..<4)
            #expect(try l.pieceRange(chain: 1) == 4..<5)
            #expect(try l.pieceRange(chain: 2) == 5..<7)
            #expect(try l.chain(ofPiece: 3) == 0 && l.chain(ofPiece: 4) == 1 && l.chain(ofPiece: 6) == 2)
            for node in 0..<4 { #expect(try l.nodeSlot(node: node) == level.nodes[node]) }
        }
    }

    // MARK: Joined pieces

    @Test func aJoinedPieceDecodesBitEqualToItsNeighboursLastVertex() throws {
        let r = try reader()
        let source = T.source()
        for levelIndex in 0..<3 {
            let l = try r.level(levelIndex)
            let rows = try (0..<7).map { try l.piece($0) }
            // Chain 0 pieces 1, 2, 3 and chain 2's second piece (6) join the piece before them; the others do not.
            #expect(rows.map(\.joinsPrevious) == [false, true, true, true, false, false, true])
            for p in [1, 2, 3, 6] {
                var previous: [RailPackPoint] = [], this: [RailPackPoint] = []
                try l.appendVertices(piece: p - 1, to: &previous)
                try l.appendVertices(piece: p, to: &this)
                #expect(this[0] == previous[previous.count - 1], "level \(levelIndex) piece \(p)")
                // Decoding from vertex 1 on (no join involved) agrees with decoding the whole piece.
                var tail: [RailPackPoint] = []
                try l.appendVertices(piece: p, first: 1, to: &tail)
                #expect(tail == Array(this[1...]))
                // Within a quantum of the source, as for any vertex.
                let bound = source.levels[levelIndex].mapPointsPerPoint / 32 + 1e-3
                #expect(abs(this[0].x - source.levels[levelIndex].pieces[p].vertices[0].x) <= bound)
            }
        }
    }

    @Test func aPieceAfterALongPieceIsNotJoined() throws {
        let mpp = RailPackLadder.mapPointsPerPoint(forZoom: 10)
        func pt(_ x: Double, _ y: Double) -> RailPackPoint { RailPackPoint(x: (100 * 1024 + x) * mpp, y: (51 * 1024 + y) * mpp) }
        // normal, long, normal, normal in one chain; every neighbour pair shares its boundary vertex exactly.
        let pieces = [
            RailPackPieceSource(chain: 0, group: 0, vertices: [pt(0, 0), pt(50, 0)]),
            RailPackPieceSource(chain: 0, group: 0, isLong: true, vertices: [pt(50, 0), pt(100, 10), pt(150, 0)]),
            RailPackPieceSource(chain: 0, group: 0, vertices: [pt(150, 0), pt(200, 0)]),
            RailPackPieceSource(chain: 0, group: 0, vertices: [pt(200, 0), pt(250, 0)]),
        ]
        let r = try RailPackReader(data: RailPackWriter.write(RailPackFormatTests.onePiece(mpp: mpp, pieces: pieces)))
        try r.validateContents()
        let l = try r.level(0)
        #expect(try (0..<4).map { try l.piece($0).joinsPrevious } == [false, false, false, true])
        // A long piece never joins a normal piece before it either; the first piece of a second chain starts fresh.
        #expect(try l.piece(1).isLong && !l.piece(1).joinsPrevious)
        let across = [
            RailPackPieceSource(chain: 0, group: 0, vertices: [pt(0, 0), pt(50, 0)]),
            RailPackPieceSource(chain: 1, group: 0, vertices: [pt(50, 0), pt(100, 0)]),
        ]
        let two = try RailPackReader(data: RailPackWriter.write(RailPackFormatTests.onePiece(mpp: mpp, chains: 2, pieces: across)))
        #expect(try !two.level(0).piece(1).joinsPrevious, "a chain's first piece joins nothing")
    }

    // MARK: Long pieces

    @Test func longPieceIsStoredWithItsBoxAndSurvivesTileBorders() throws {
        let r = try reader()
        let source = T.source()
        let l = try r.level(2)
        let mpp = source.levels[2].mapPointsPerPoint
        let long = source.levels[2].pieces[4].vertices
        let row = try l.longPieceRow(0)
        #expect(row.piece == 4)
        let quantum = mpp / 16
        #expect(abs(Double(row.minX) * quantum - long.map(\.x).min()!) <= quantum)
        #expect(abs(Double(row.maxY) * quantum - long.map(\.y).max()!) <= quantum)
        #expect(abs(Double(row.firstX) * quantum - long[0].x) <= quantum && abs(Double(row.firstY) * quantum - long[0].y) <= quantum)
        let hit = try l.longPieces(minX: long[0].x, minY: long[0].y, maxX: long[0].x + quantum, maxY: long[0].y + quantum)
        #expect(hit == [4])
        #expect(try l.longPieces(minX: 0, minY: 0, maxX: 10, maxY: 10).isEmpty)
    }

    @Test func longPieceRoundTripsThroughDeltasIncludingTheLargestStep() throws {
        let mpp = RailPackLadder.mapPointsPerPoint(forZoom: 9)
        let quantum = mpp / 16
        // A step of 2,047 points (32,752 quanta) and one back, then small and negative steps.
        let steps: [(Double, Double)] = [(2_047, 0), (-2_047, 3), (0.3, -2_047), (-5.1, 7.7), (1_000, -1_000)]
        var vertices = [RailPackPoint(x: 100 * 1024 * mpp + 0.3, y: 51 * 1024 * mpp)]
        for s in steps { vertices.append(RailPackPoint(x: vertices.last!.x + s.0 * mpp, y: vertices.last!.y + s.1 * mpp)) }
        let source = RailPackFormatTests.onePiece(mpp: mpp, pieces: [RailPackPieceSource(chain: 0, group: 0, isLong: true, vertices: vertices)])
        let r = try RailPackReader(data: RailPackWriter.write(source))
        try r.validateContents()
        let l = try r.level(0)
        var decoded: [RailPackPoint] = []
        try l.appendVertices(piece: 0, to: &decoded)
        #expect(decoded.count == vertices.count)
        for (d, v) in zip(decoded, vertices) { #expect(abs(d.x - v.x) <= quantum / 2 + 1e-6 && abs(d.y - v.y) <= quantum / 2 + 1e-6) }
        // Any sub-range starts from the right place: it equals the same slice of the whole.
        for first in 0..<vertices.count {
            var sub: [RailPackPoint] = []
            try l.appendVertices(piece: 0, first: first, last: vertices.count - 1, to: &sub)
            #expect(sub == Array(decoded[first...]))
        }
        var one: [RailPackPoint] = []
        try l.appendVertices(piece: 0, first: 3, last: 3, to: &one)
        #expect(one == [decoded[3]])
    }

    // MARK: Tiles

    @Test func tileLookupMatchesBruteForceAtEveryLevel() throws {
        let r = try reader()
        let source = T.source()
        for levelIndex in 0..<3 {
            let l = try r.level(levelIndex)
            let mpp = source.levels[levelIndex].mapPointsPerPoint
            let side = RailPackFormat.tileSide(mapPointsPerPoint: mpp)
            // Brute force: every normal piece's home tile, from the piece rows alone.
            var homes: [RailPackTile: [UInt32]] = [:]
            for p in 0..<l.pieceCount {
                let row = try l.piece(p)
                if !row.isLong { homes[RailPackTile(x: Int(row.tileX), y: Int(row.tileY)), default: []].append(UInt32(p)) }
            }
            let all = homes.keys.sorted()
            // The chain-0 line crosses the tile border between x tiles 99 and 100 (and 101).
            let rects: [(Double, Double, Double, Double)] = [
                (99.5 * side, 49 * side, 100.2 * side, 53 * side),
                (0, 0, 200 * side, 200 * side),
                (99.9 * side, 49.9 * side, 100.0 * side, 50.0 * side),
                (5 * side, 5 * side, 6 * side, 6 * side),
                (-5 * side, -5 * side, 300 * side, 300 * side),
            ]
            for rect in rects {
                let found = try l.tiles(minX: rect.0, minY: rect.1, maxX: rect.2, maxY: rect.3)
                let x0 = Int((rect.0 / side).rounded(.down)), x1 = Int((rect.2 / side).rounded(.down))
                let y0 = Int((rect.1 / side).rounded(.down)), y1 = Int((rect.3 / side).rounded(.down))
                #expect(found == all.filter { $0.x >= x0 && $0.x <= x1 && $0.y >= y0 && $0.y <= y1 })
            }
            #expect(try l.tiles(minX: 0, minY: 0, maxX: 200 * side, maxY: 200 * side) == all)
            // Every non-long piece is listed under exactly its home tile.
            for (tile, pieces) in homes { #expect(try l.pieceIndices(tileX: tile.x, tileY: tile.y) == pieces) }
            #expect(try l.pieceIndices(tileX: 5, tileY: 5).isEmpty)
            #expect(try l.pieceIndices(tileX: -1, tileY: 70_000).isEmpty)
            #expect(Set(homes.values.flatMap { $0 }) == [0, 1, 2, 3, 5, 6])
            // Summaries add up to the mounted vertices of the normal pieces.
            let summaries = try l.tileSummaries()
            #expect(summaries.map(\.tile) == all)
            #expect(summaries.reduce(0) { $0 + $1.pieces } == 6)
            #expect(summaries.reduce(0) { $0 + $1.vertices } == 4 + 4 + 4 + 2 + 3 + 3)
        }
        // Chain 0 spans at least three tile columns at the finest level (3,000 points).
        #expect(Set(try r.level(2).tiles(minX: -1e12, minY: -1e12, maxX: 1e12, maxY: 1e12).map(\.x)).count >= 3)
    }

    @Test func nodesGiveVertexRangesAndDirection() throws {
        let l = try reader().level(1)
        // Node 0 (piece 0 vertex 0) to node 1 (piece 2 vertex 1): pieces 0, 1 whole, piece 2 up to vertex 1.
        let forward = try l.vertexRanges(fromNode: 0, toNode: 1)
        #expect(!forward.reversed)
        #expect(forward.ranges == [RailPackVertexRange(chain: 0, piece: 0, first: 0, last: 3),
                                   RailPackVertexRange(chain: 0, piece: 1, first: 0, last: 3),
                                   RailPackVertexRange(chain: 0, piece: 2, first: 0, last: 1)])
        let back = try l.vertexRanges(fromNode: 1, toNode: 0)
        #expect(back.reversed && back.ranges == forward.ranges)
        // Node 2 is on chain 1 of the same line (a non-continuous line): chain 0 from node 0, then chain 1's head.
        let gap = try l.vertexRanges(fromNode: 0, toNode: 2)
        #expect(gap.ranges.map(\.chain) == [0, 0, 0, 0, 1] && gap.ranges.last == RailPackVertexRange(chain: 1, piece: 4, first: 0, last: 3))
        #expect(throws: RailPackError.self) { try l.vertexRanges(fromNode: 0, toNode: 3) }  // node 3 has no slot
        // Ranges decode to the stored vertices (a joined piece still has all its vertices).
        var points: [RailPackPoint] = []
        for range in forward.ranges { try l.appendVertices(piece: Int(range.piece), first: range.first, last: range.last, to: &points) }
        #expect(points.count == 4 + 4 + 2)
    }

    @Test func nodeSlotsRoundTripThroughThePieceInChain() throws {
        // Every node of the loop pack, at both levels, comes back as the piece index the writer was given:
        // the file stores only its index within the chain, and the reader adds the chain's first piece.
        let source = RailPackLoopTestPack.source()
        let r = try RailPackReader(data: RailPackWriter.write(source))
        try r.validateContents()
        for levelIndex in 0..<2 {
            let l = try r.level(levelIndex)
            for (node, slot) in source.levels[levelIndex].nodes.enumerated() { #expect(try l.nodeSlot(node: node) == slot) }
        }
        // The test pack: node 1 sits on piece 2 (index 2 in chain 0), node 2 on piece 4 (index 0 in chain 1).
        let t = try reader().level(0)
        #expect(try t.nodeSlot(node: 1) == RailPackNodeSlot(piece: 2, vertex: 1) && t.nodeSlot(node: 2) == RailPackNodeSlot(piece: 4, vertex: 3))
        // A node on the second piece of chain 2 (piece 6, index 1 in its chain).
        var edited = T.source()
        edited.levels = edited.levels.map { var l = $0; l.nodes[3] = RailPackNodeSlot(piece: 6, vertex: 2); return l }
        let e = try RailPackReader(data: RailPackWriter.write(edited))
        try e.validateContents()
        #expect(try e.level(1).nodeSlot(node: 3) == RailPackNodeSlot(piece: 6, vertex: 2))
        #expect(try e.nodeChain(3) == 2)
    }

    // MARK: Rejection

    @Test func rejectsBadMagicVersionAndTruncation() throws {
        let data = try T.bytes()
        #expect(throws: RailPackError.truncated) { try RailPackReader(data: Data()) }
        #expect(throws: RailPackError.truncated) { try RailPackReader(data: data.prefix(50)) }
        #expect(throws: RailPackError.badMagic) { try RailPackReader(data: T.patched(data, at: 0, 0x4142_4344, width: 4)) }
        // Version 1 files (a tile directory per level, a datum byte) are not read: no pack shipped in it.
        #expect(throws: RailPackError.unsupportedVersion(1)) { try RailPackReader(data: T.patched(data, at: 4, 1, width: 2)) }
        #expect(throws: RailPackError.unsupportedVersion(3)) { try RailPackReader(data: T.patched(data, at: 4, 3, width: 2)) }
        // The reserved header byte (formerly the datum) must be 0.
        #expect(throws: RailPackError.corrupt("reserved header byte 6 is 1")) { try RailPackReader(data: T.patched(data, at: 6, 1, width: 1)) }
        #expect(throws: RailPackError.truncated) { try RailPackReader(data: data.prefix(data.count - 1)) }
        #expect(throws: RailPackError.truncated) { try RailPackReader(data: data.prefix(data.count / 2)) }
        #expect(throws: RailPackError.truncated) { try RailPackReader(data: data.prefix(RailPackFormat.headerSize + 8)) }
        var longer = data
        longer.append(0)
        #expect(throws: RailPackError.lengthMismatch(declared: UInt64(data.count), actual: data.count + 1)) { try RailPackReader(data: longer) }
    }

    @Test func rejectsOutOfRangeSectionsArraysAndLevels() throws {
        let data = try T.bytes()
        // A region section pointing past the end of the file.
        #expect(throws: RailPackError.sectionOutOfBounds("region 1")) {
            try RailPackReader(data: T.patched(data, at: T.sectionEntry(1), UInt64(data.count + 100), width: 8))
        }
        // A level section longer than the file.
        #expect(throws: RailPackError.sectionOutOfBounds("level 0")) {
            try RailPackReader(data: T.patched(data, at: T.sectionEntry(5) + 8, UInt64(data.count), width: 8))
        }
        // A region table whose length no longer matches its count (the lines, then the node chains).
        #expect(throws: RailPackError.sectionOutOfBounds("region 0 length")) {
            try RailPackReader(data: T.patched(data, at: T.sectionEntry(0) + 8, 0, width: 8))
        }
        #expect(throws: RailPackError.sectionOutOfBounds("region 3 length")) {
            try RailPackReader(data: T.patched(data, at: T.sectionEntry(3) + 8, 0, width: 8))
        }
        // The pieces array of level 1 claims a billion rows.
        let levelTable = T.u64(data, T.sectionEntry(4))
        let piecesEntry = levelTable + RailPackFormat.levelRow + RailPackFormat.levelArraysOffset + RailPackFormat.ArrayKind.pieces.rawValue * RailPackFormat.levelArrayEntrySize
        #expect(throws: RailPackError.arrayOutOfBounds(level: 1, array: "pieces")) {
            try RailPackReader(data: T.patched(data, at: piecesEntry, 1_000_000_000, width: 4))
        }
        // A level with a zero or non-descending mapPointsPerPoint.
        #expect(throws: RailPackError.badLevel(0)) { try RailPackReader(data: T.patched(data, at: levelTable, 0, width: 8)) }
        let first = T.u64(data, levelTable)
        #expect(throws: RailPackError.badLevel(1)) { try RailPackReader(data: T.patched(data, at: levelTable + RailPackFormat.levelRow, UInt64(first), width: 8)) }
    }

    @Test func deepValidationRejectsBrokenReferences() throws {
        let data = try T.bytes()
        let levelTable = T.u64(data, T.sectionEntry(4))
        func arrayOffset(_ level: Int, _ kind: RailPackFormat.ArrayKind) -> Int {
            T.u64(data, levelTable + level * RailPackFormat.levelRow + RailPackFormat.levelArraysOffset + kind.rawValue * RailPackFormat.levelArrayEntrySize + 4)
        }
        func expectCorrupt(_ broken: Data, sourceLocation: SourceLocation = #_sourceLocation) {
            // Structure still opens; contents do not validate; accessors never trap.
            do {
                let r = try RailPackReader(data: broken)
                #expect(throws: RailPackError.self, sourceLocation: sourceLocation) { try r.validateContents() }
            } catch {
                Issue.record("structure should still open: \(error)", sourceLocation: sourceLocation)
            }
        }
        let pieces0 = arrayOffset(0, .pieces)
        expectCorrupt(T.patched(data, at: pieces0 + 4, 4_000_000 & 0x7FFF, width: 2))  // vertex count no longer matches the vertex rows
        expectCorrupt(T.patched(data, at: pieces0 + 6, 77, width: 2))             // group out of range
        expectCorrupt(T.patched(data, at: pieces0 + 4, 0x8004, width: 2))         // first piece "joins" nothing
        expectCorrupt(T.patched(data, at: pieces0 + 8 * 4 + 4, 0x8003, width: 2)) // the long piece's count word edited
        expectCorrupt(T.patched(data, at: pieces0, 0xFFFF, width: 2))             // tileX is the long sentinel but tileY is not
        expectCorrupt(T.patched(data, at: arrayOffset(1, .nodes), 500, width: 2)) // node piece-in-chain out of range
        expectCorrupt(T.patched(data, at: arrayOffset(1, .nodes) + 2, 900, width: 2)) // node vertex out of range
        expectCorrupt(T.patched(data, at: arrayOffset(2, .chains), 7, width: 4))  // chain counts no longer cover the pieces
        expectCorrupt(T.patched(data, at: arrayOffset(1, .longPieces), 3, width: 4)) // a longPieces row naming a normal piece
        expectCorrupt(T.patched(data, at: T.u64(data, T.sectionEntry(3)), 9, width: 4)) // node chain beyond the chain count
        expectCorrupt(T.patched(data, at: T.u64(data, T.sectionEntry(1)) + 14, 9, width: 2)) // group span beyond the span count
        // Accessors reject out-of-range indices with typed errors rather than trapping.
        let r = try RailPackReader(data: data)
        let l = try r.level(0)
        #expect(throws: RailPackError.self) { try l.piece(7) }
        #expect(throws: RailPackError.self) { try r.level(3) }
        #expect(throws: RailPackError.self) { try l.pieceRange(chain: -1) }
        var sink: [RailPackPoint] = []
        #expect(throws: RailPackError.self) { try l.appendVertices(piece: 0, first: 2, last: 9, to: &sink) }
        // A level whose piece rows claim more vertices than the file holds does not even build its index.
        let wrecked = try RailPackReader(data: T.patched(data, at: pieces0 + 4, 0x7FFF, width: 2))
        #expect(throws: RailPackError.corrupt("level 0 piece rows exceed the vertex arrays")) { try wrecked.level(0) }
    }

    @Test func readsFromAMappedFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pack-\(UUID().uuidString).railpack")
        defer { try? FileManager.default.removeItem(at: url) }
        try T.bytes().write(to: url)
        let r = try RailPackReader(contentsOf: url)
        #expect(r.header.fileLength == (try Data(contentsOf: url)).count)
        try r.validateContents()
        #expect(try RailPackReader(contentsOf: url, display: .gcj02).display == .gcj02)
    }

    // MARK: GCJ-02 at mount

    /// Pieces scattered around Hong Kong at ladder z14, each its own chain: random walks of up to ten vertices.
    static func hongKongSource(pieces count: Int, seed: UInt64) -> RailPackSource {
        var state = seed
        func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(1 << 53)
        }
        let mpp = RailPackLadder.mapPointsPerPoint(forZoom: 14)
        var pieces: [RailPackPieceSource] = []
        for chain in 0..<count {
            let start = StrokeProjection.point(Coordinate(lon: 113.7 + next() * 0.9, lat: 22.15 + next() * 0.45))
            var vertices = [RailPackPoint(x: start.x, y: start.y)]
            for _ in 0..<Int(2 + next() * 8) {
                vertices.append(RailPackPoint(x: vertices.last!.x + (next() - 0.5) * 120 * mpp, y: vertices.last!.y + (next() - 0.5) * 120 * mpp))
            }
            pieces.append(RailPackPieceSource(chain: chain, group: 0, vertices: vertices))
        }
        pieces.append(RailPackPieceSource(chain: count, group: 0, isLong: true, vertices: [
            RailPackPoint(x: pieces[0].vertices[0].x, y: pieces[0].vertices[0].y),
            RailPackPoint(x: pieces[0].vertices[0].x + 900 * mpp, y: pieces[0].vertices[0].y + 300 * mpp)]))
        return RailPackFormatTests.onePiece(mpp: mpp, chains: count + 1, pieces: pieces)
    }

    @Test func aGCJReaderReturnsExactlyTheShiftOfTheWGS84ReadersPoints() throws {
        let data = try RailPackWriter.write(Self.hongKongSource(pieces: 40, seed: 0xABCD_1234))
        let plain = try RailPackReader(data: data).level(0)
        let shifted = try RailPackReader(data: data, display: .gcj02).level(0)
        var moved = 0.0
        for p in 0..<plain.pieceCount {
            var a: [RailPackPoint] = [], b: [RailPackPoint] = []
            try plain.appendVertices(piece: p, to: &a)
            try shifted.appendVertices(piece: p, to: &b)
            #expect(a.count == b.count)
            for (wgs, gcj) in zip(a, b) {
                let expected = StrokeProjection.point(GCJ02.fromWGS84(StrokeProjection.coordinate(StrokePoint(x: wgs.x, y: wgs.y))))
                #expect(gcj == RailPackPoint(x: expected.x, y: expected.y))
                moved = max(moved, hypot(gcj.x - wgs.x, gcj.y - wgs.y))
            }
            // A sub-range shifts the same way.
            var tail: [RailPackPoint] = []
            try shifted.appendVertices(piece: p, first: 1, to: &tail)
            #expect(tail == Array(b[1...]))
        }
        // The shift is real: hundreds of map points at z14 (about 500 m).
        #expect(moved > 100)
    }

    @Test func everyVertexShiftedIntoARectangleLiesInATileMountKeysReturns() throws {
        let data = try RailPackWriter.write(Self.hongKongSource(pieces: 400, seed: 0x5EED_0001))
        let level = try RailPackReader(data: data, display: .gcj02).level(0)
        let side = RailPackFormat.tileSide(mapPointsPerPoint: level.mapPointsPerPoint)
        // Display positions of every vertex, with the piece's home tile.
        var vertices: [(point: RailPackPoint, tile: RailPackTile?, piece: Int)] = []
        for p in 0..<level.pieceCount {
            let row = try level.piece(p)
            var points: [RailPackPoint] = []
            try level.appendVertices(piece: p, to: &points)
            let tile = row.isLong ? nil : RailPackTile(x: Int(row.tileX), y: Int(row.tileY))
            vertices.append(contentsOf: points.map { ($0, tile, p) })
        }
        var state: UInt64 = 0x0123_4567_89AB_CDEF
        func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(1 << 53)
        }
        // About 7.2 map points per metre at this latitude; rectangles from 100 m to 1,000 km on a side.
        let perMetre = 7.2
        var inside = 0, rectangles = 0
        for _ in 0..<1_500 {
            let centre = StrokeProjection.point(Coordinate(lon: 113.6 + next() * 1.1, lat: 22.1 + next() * 0.55))
            let width = 100 * pow(10, next() * 4) * perMetre, height = 100 * pow(10, next() * 4) * perMetre
            let rect = (minX: centre.x - width / 2, minY: centre.y - height / 2, maxX: centre.x + width / 2, maxY: centre.y + height / 2)
            let keys = Set(try level.mountKeys(minX: rect.minX, minY: rect.minY, maxX: rect.maxX, maxY: rect.maxY))
            rectangles += 1
            for v in vertices where v.point.x >= rect.minX && v.point.x <= rect.maxX && v.point.y >= rect.minY && v.point.y <= rect.maxY {
                inside += 1
                if let tile = v.tile {
                    #expect(keys.contains(.tile(level: 0, x: tile.x, y: tile.y)), "piece \(v.piece) of side \(side)")
                } else {
                    #expect(keys.contains(.longPiece(level: 0, piece: v.piece)), "long piece \(v.piece)")
                }
            }
        }
        #expect(rectangles == 1_500 && inside > 5_000, "the rectangles must actually hold vertices: \(inside)")
    }

    /// `tiles` and `longPieces` called directly on a GCJ-02 reader (no half-tile margin, unlike `mountKeys`):
    /// a vertex whose shifted position is inside the rectangle has its unshifted position in a tile
    /// `tiles` returns (when that tile holds pieces) and, for a long piece, the piece is in `longPieces`.
    @Test func tilesAndLongPiecesUnderGCJCoverEveryShiftedVertexInTheRectangle() throws {
        let data = try RailPackWriter.write(Self.hongKongSource(pieces: 400, seed: 0x5EED_0002))
        let plain = try RailPackReader(data: data).level(0)
        let level = try RailPackReader(data: data, display: .gcj02).level(0)
        let mpp = level.mapPointsPerPoint
        let existing = Set(try level.tileSummaries().map { "\($0.tile.x),\($0.tile.y)" })
        var vertices: [(shifted: RailPackPoint, source: RailPackPoint, piece: Int)] = []
        for p in 0..<level.pieceCount {
            var a: [RailPackPoint] = [], b: [RailPackPoint] = []
            try plain.appendVertices(piece: p, to: &a)
            try level.appendVertices(piece: p, to: &b)
            vertices.append(contentsOf: zip(b, a).map { ($0, $1, p) })
        }
        var state: UInt64 = 0xFEDC_BA98_7654_3210
        func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(1 << 53)
        }
        let perMetre = 7.2
        var inside = 0
        for _ in 0..<1_500 {
            let centre = StrokeProjection.point(Coordinate(lon: 113.6 + next() * 1.1, lat: 22.1 + next() * 0.55))
            let width = 50 * pow(10, next() * 3) * perMetre, height = 50 * pow(10, next() * 3) * perMetre
            let rect = (minX: centre.x - width / 2, minY: centre.y - height / 2, maxX: centre.x + width / 2, maxY: centre.y + height / 2)
            let tiles = Set(try level.tiles(minX: rect.minX, minY: rect.minY, maxX: rect.maxX, maxY: rect.maxY).map { "\($0.x),\($0.y)" })
            let longs = Set(try level.longPieces(minX: rect.minX, minY: rect.minY, maxX: rect.maxX, maxY: rect.maxY).map(Int.init))
            for v in vertices where v.shifted.x >= rect.minX && v.shifted.x <= rect.maxX && v.shifted.y >= rect.minY && v.shifted.y <= rect.maxY {
                inside += 1
                let key = "\(RailPackFormat.tile(containing: v.source.x, mapPointsPerPoint: mpp)),\(RailPackFormat.tile(containing: v.source.y, mapPointsPerPoint: mpp))"
                if existing.contains(key) { #expect(tiles.contains(key), "vertex of piece \(v.piece) in tile \(key)") }
                if try level.piece(v.piece).isLong { #expect(longs.contains(v.piece), "long piece \(v.piece)") }
            }
        }
        #expect(inside > 2_000, "the rectangles must actually hold vertices: \(inside)")
    }
}
