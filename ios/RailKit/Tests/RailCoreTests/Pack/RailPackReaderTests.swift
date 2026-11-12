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
        #expect(r.header.datum == .gcj02)
        #expect(r.header.regionCode == "jp")
        #expect(r.header.levelCount == 3 && r.header.chainCount == 3 && r.header.nodeCount == 4)
        #expect(r.header.displaySHA256 == source.displaySHA256 && r.header.inputsSHA256 == source.inputsSHA256)
        #expect(try r.line(0) == source.lines[0] && r.line(1) == source.lines[1])
        #expect(try r.group(1) == source.groups[1])
        #expect(try r.span(0) == source.spans[0])
        #expect(try r.span(RailPackFormat.noSpan) == nil)
        #expect(throws: RailPackError.self) { try r.line(2) }
        #expect(throws: RailPackError.self) { try r.span(5) }

        for (levelIndex, level) in source.levels.enumerated() {
            let bound = level.mapPointsPerPoint / 32 + 1e-3
            #expect(r.levels[levelIndex].laneBucket == level.laneBucket)
            for (pieceIndex, piece) in level.pieces.enumerated() {
                let row = try r.piece(level: levelIndex, index: pieceIndex)
                #expect(row.isLong == piece.isLong)
                #expect(Int(row.vertexCount) == piece.vertices.count)
                #expect(row.group == piece.group && row.span == piece.span && row.flags == piece.flags)
                var decoded: [RailPackPoint] = []
                try r.appendVertices(level: levelIndex, piece: pieceIndex, to: &decoded)
                #expect(decoded.count == piece.vertices.count)
                for (d, v) in zip(decoded, piece.vertices) {
                    #expect(abs(d.x - v.x) <= bound && abs(d.y - v.y) <= bound)
                }
            }
            // Chains and node slots.
            #expect(try r.pieceRange(level: levelIndex, chain: 0) == 0..<4)
            #expect(try r.pieceRange(level: levelIndex, chain: 1) == 4..<5)
            #expect(try r.pieceRange(level: levelIndex, chain: 2) == 5..<7)
            #expect(try r.chain(level: levelIndex, ofPiece: 3) == 0 && r.chain(level: levelIndex, ofPiece: 4) == 1 && r.chain(level: levelIndex, ofPiece: 6) == 2)
            for node in 0..<4 { #expect(try r.nodeSlot(level: levelIndex, node: node) == level.nodes[node]) }
        }
    }

    @Test func longPieceIsStoredWithItsBoxAndSurvivesTileBorders() throws {
        let r = try reader()
        let source = T.source()
        let mpp = source.levels[2].mapPointsPerPoint
        let long = source.levels[2].pieces[4].vertices
        let row = try r.longPieceRow(level: 2, index: 0)
        #expect(row.piece == 4)
        let quantum = mpp / 16
        #expect(abs(Double(row.minX) * quantum - long.map(\.x).min()!) <= quantum)
        #expect(abs(Double(row.maxY) * quantum - long.map(\.y).max()!) <= quantum)
        let hit = try r.longPieces(level: 2, minX: long[0].x, minY: long[0].y, maxX: long[0].x + quantum, maxY: long[0].y + quantum)
        #expect(hit == [4])
        #expect(try r.longPieces(level: 2, minX: 0, minY: 0, maxX: 10, maxY: 10).isEmpty)
    }

    @Test func tileLookupMatchesBruteForceAtEveryLevel() throws {
        let r = try reader()
        let source = T.source()
        for level in 0..<3 {
            let mpp = source.levels[level].mapPointsPerPoint
            let side = RailPackFormat.tileSide(mapPointsPerPoint: mpp)
            let total = try r.count(level: level, .tileDir)
            let all = try (0..<total).map { try r.tile(level: level, index: $0) }
            // Sorted by (tileY, tileX), unique.
            for pair in zip(all, all.dropFirst()) {
                #expect(pair.0.tileY < pair.1.tileY || (pair.0.tileY == pair.1.tileY && pair.0.tileX < pair.1.tileX))
            }
            // The chain-0 line crosses the tile border between x tiles 99 and 100 (and 101).
            let rects: [(Double, Double, Double, Double)] = [
                (99.5 * side, 49 * side, 100.2 * side, 53 * side),
                (0, 0, 200 * side, 200 * side),
                (99.9 * side, 49.9 * side, 100.0 * side, 50.0 * side),
                (5 * side, 5 * side, 6 * side, 6 * side),
            ]
            for rect in rects {
                let found = try r.tiles(level: level, minX: rect.0, minY: rect.1, maxX: rect.2, maxY: rect.3)
                let x0 = Int((rect.0 / side).rounded(.down)), x1 = Int((rect.2 / side).rounded(.down))
                let y0 = Int((rect.1 / side).rounded(.down)), y1 = Int((rect.3 / side).rounded(.down))
                let expected = all.indices.filter { i in
                    Int(all[i].tileX) >= x0 && Int(all[i].tileX) <= x1 && Int(all[i].tileY) >= y0 && Int(all[i].tileY) <= y1
                }
                #expect(found == expected)
            }
            #expect(try r.tiles(level: level, minX: 0, minY: 0, maxX: 200 * side, maxY: 200 * side).count == total)
            // Every non-long piece is listed under exactly its home tile; every node under its vertex's tile.
            var seen = Set<UInt32>()
            for tile in 0..<total {
                for piece in try r.pieceIndices(level: level, tile: tile) {
                    #expect(try r.piece(level: level, index: Int(piece)).tile == UInt32(tile))
                    seen.insert(piece)
                }
            }
            #expect(seen == [0, 1, 2, 3, 5, 6])
            var nodes = Set<UInt32>()
            for tile in 0..<total { try nodes.formUnion(r.nodeIndices(level: level, tile: tile)) }
            #expect(nodes == [0, 1, 2])
        }
        // Chain 0 spans at least three tile columns at the finest level (3,000 points).
        let columns = try (0..<r.count(level: 2, .tileDir)).map { try r.tile(level: 2, index: $0).tileX }
        #expect(Set(columns).count >= 3)
    }

    @Test func nodesGiveVertexRangesAndDirection() throws {
        let r = try reader()
        // Node 0 (piece 0 vertex 0) to node 1 (piece 2 vertex 1): pieces 0, 1 whole, piece 2 up to vertex 1.
        let forward = try r.vertexRanges(level: 1, fromNode: 0, toNode: 1)
        #expect(!forward.reversed)
        #expect(forward.ranges == [RailPackVertexRange(piece: 0, first: 0, last: 3),
                                   RailPackVertexRange(piece: 1, first: 0, last: 3),
                                   RailPackVertexRange(piece: 2, first: 0, last: 1)])
        let back = try r.vertexRanges(level: 1, fromNode: 1, toNode: 0)
        #expect(back.reversed && back.ranges == forward.ranges)
        #expect(throws: RailPackError.nodesNotOnOneChain) { try r.vertexRanges(level: 1, fromNode: 0, toNode: 2) }
        #expect(throws: RailPackError.self) { try r.vertexRanges(level: 1, fromNode: 0, toNode: 3) }  // node 3 has no slot
        // Ranges decode to the stored vertices.
        var points: [RailPackPoint] = []
        for range in forward.ranges { try r.appendVertices(level: 1, piece: Int(range.piece), first: range.first, last: range.last, to: &points) }
        #expect(points.count == 4 + 4 + 2)
    }

    // MARK: Rejection

    @Test func rejectsBadMagicVersionAndTruncation() throws {
        let data = try T.bytes()
        #expect(throws: RailPackError.truncated) { try RailPackReader(data: Data()) }
        #expect(throws: RailPackError.truncated) { try RailPackReader(data: data.prefix(50)) }
        #expect(throws: RailPackError.badMagic) { try RailPackReader(data: T.patched(data, at: 0, 0x4142_4344, width: 4)) }
        #expect(throws: RailPackError.unsupportedVersion(2)) { try RailPackReader(data: T.patched(data, at: 4, 2, width: 2)) }
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
            try RailPackReader(data: T.patched(data, at: T.sectionEntry(4) + 8, UInt64(data.count), width: 8))
        }
        // A region table whose length no longer matches its count.
        #expect(throws: RailPackError.sectionOutOfBounds("region 0 length")) {
            try RailPackReader(data: T.patched(data, at: T.sectionEntry(0) + 8, 0, width: 8))
        }
        // The pieces array of level 1 claims a billion rows.
        let levelTable = T.u64(data, T.sectionEntry(3))
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
        let levelTable = T.u64(data, T.sectionEntry(3))
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
        expectCorrupt(T.patched(data, at: pieces0 + 4, 4_000_000, width: 4))      // vertexStart beyond vertices
        expectCorrupt(T.patched(data, at: pieces0 + 10, 77, width: 2))            // group out of range
        expectCorrupt(T.patched(data, at: pieces0 + 12, 9, width: 2))             // span out of range
        expectCorrupt(T.patched(data, at: pieces0, 999, width: 4))                // tile index beyond directory
        expectCorrupt(T.patched(data, at: arrayOffset(1, .nodes), 500, width: 4)) // node piece out of range
        expectCorrupt(T.patched(data, at: arrayOffset(2, .chains), 3, width: 4))  // chain no longer starts where the last ended
        expectCorrupt(T.patched(data, at: arrayOffset(0, .tileDir) + 4, 0x7FFF_0000, width: 4))  // tile directory unsorted (first row's tileY)
        // Accessors reject out-of-range indices with typed errors rather than trapping.
        let r = try RailPackReader(data: data)
        #expect(throws: RailPackError.self) { try r.piece(level: 0, index: 7) }
        #expect(throws: RailPackError.self) { try r.piece(level: 3, index: 0) }
        #expect(throws: RailPackError.self) { try r.tile(level: 0, index: -1) }
        var sink: [RailPackPoint] = []
        #expect(throws: RailPackError.self) { try r.appendVertices(level: 0, piece: 0, first: 2, last: 9, to: &sink) }
        let wrecked = try RailPackReader(data: T.patched(data, at: pieces0 + 4, 4_000_000, width: 4))
        #expect(throws: RailPackError.self) { try wrecked.appendVertices(level: 0, piece: 0, to: &sink) }
    }

    @Test func readsFromAMappedFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pack-\(UUID().uuidString).railpack")
        defer { try? FileManager.default.removeItem(at: url) }
        try T.bytes().write(to: url)
        let r = try RailPackReader(contentsOf: url)
        #expect(r.header.fileLength == (try Data(contentsOf: url)).count)
        try r.validateContents()
    }
}
