import Foundation
import Testing
@testable import RailCore

@Suite("RailPackFormat")
struct RailPackFormatTests {
    @Test func sameInputGivesIdenticalBytes() throws {
        let a = try RailPackWriter.write(RailPackTestPack.source())
        let b = try RailPackWriter.write(RailPackTestPack.source())
        #expect(a == b)
        #expect(a.starts(with: Array("JTRP".utf8)))
        #expect(a[6] == 0, "header byte 6 is reserved")
    }

    @Test func changingOneVertexChangesTheBytes() throws {
        var source = RailPackTestPack.source()
        source.levels[1].pieces[0].vertices[0].x += 3 * source.levels[1].mapPointsPerPoint
        #expect(try RailPackWriter.write(source) != RailPackTestPack.bytes())
    }

    static func onePiece(mpp: Double, chains: Int = 1, pieces: [RailPackPieceSource]) -> RailPackSource {
        RailPackSource(
            regionCode: "xx", displaySHA256: [UInt8](repeating: 1, count: 32), inputsSHA256: [UInt8](repeating: 2, count: 32),
            chainCount: chains, nodeCount: 0, lines: [], groups: [RailPackGroup(colourLight: 0, colourDark: 0, tierMin: 0, tierMax: 0x7FFF, styleClass: 0, category: 0)],
            spans: [], levels: [RailPackLevelSource(mapPointsPerPoint: mpp, laneBucket: 0, pieces: pieces, nodes: [])])
    }

    @Test func quantisationErrorStaysWithinHalfAQuantum() throws {
        // Pseudo-random vertices (fixed LCG) inside one piece at several levels.
        var state: UInt64 = 0x1234_5678_9ABC_DEF0
        func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(1 << 53)
        }
        for zoom in [4.0, 7.5, 10.0, 13.5, 17.0] {
            let mpp = RailPackLadder.mapPointsPerPoint(forZoom: zoom)
            let quantum = mpp / 16
            let base = RailPackPoint(x: 77.3 * 1024 * mpp, y: 31.9 * 1024 * mpp)
            let vertices = (0..<500).map { _ in RailPackPoint(x: base.x + next() * 900 * mpp, y: base.y + next() * 900 * mpp) }
            let source = Self.onePiece(mpp: mpp, pieces: [RailPackPieceSource(chain: 0, group: 0, vertices: vertices)])
            let reader = try RailPackReader(data: RailPackWriter.write(source))
            var decoded: [RailPackPoint] = []
            try reader.level(0).appendVertices(piece: 0, to: &decoded)
            #expect(decoded.count == vertices.count)
            // Half a quantum per axis, plus a little for the double arithmetic at large coordinates.
            let bound = quantum / 2 + mpp * 1e-9 + 1e-3
            for (d, v) in zip(decoded, vertices) {
                #expect(abs(d.x - v.x) <= bound)
                #expect(abs(d.y - v.y) <= bound)
            }
        }
    }

    @Test func writerRejectsPieceOutsideItsHomeTile() {
        var source = RailPackTestPack.source()
        let mpp = source.levels[0].mapPointsPerPoint
        // A piece 3,000 points wide cannot fit within half a tile of its home tile's centre.
        source.levels[0].pieces[0].vertices = [RailPackPoint(x: 100 * 1024 * mpp, y: 51_300 * mpp),
                                               RailPackPoint(x: 103 * 1024 * mpp, y: 51_300 * mpp)]
        #expect(throws: RailPackError.pieceOutsideHomeTile(level: 0, piece: 0)) { try RailPackWriter.write(source) }
    }

    @Test func writerRejectsInvalidInput() {
        func expectInvalid(_ edit: (inout RailPackSource) -> Void) {
            var source = RailPackTestPack.source()
            edit(&source)
            #expect(throws: RailPackError.self) { try RailPackWriter.write(source) }
        }
        expectInvalid { $0.regionCode = "jpn" }
        expectInvalid { $0.displaySHA256 = [1, 2, 3] }
        expectInvalid { $0.levels[0].pieces[0].group = 99 }
        expectInvalid { $0.groups[3].span = 7 }
        expectInvalid { $0.levels[0].pieces[0].vertices = [$0.levels[0].pieces[0].vertices[0]] }
        expectInvalid { $0.levels[0].pieces.swapAt(0, 5) }  // not sorted by chain
        expectInvalid { $0.levels[0].nodes[0] = RailPackNodeSlot(piece: 0, vertex: 99) }
        expectInvalid { $0.levels[0].nodes.removeLast() }
        expectInvalid { $0.levels.reverse() }  // zoom order must ascend
        expectInvalid { $0.lines[0].nodeCount = 99 }
        // A node whose chain differs between levels has no single region-wide chain.
        expectInvalid { $0.levels[1].nodes[0] = RailPackNodeSlot(piece: 5, vertex: 0) }
    }

    // MARK: Format limits (each enforced by the writer)

    @Test func writerRefusesEachFormatLimit() throws {
        let group = RailPackFormat.maxPieceVertices
        let mpp = RailPackLadder.mapPointsPerPoint(forZoom: 10)
        func piece(_ vertices: Int, x: Double = 100 * 1024, long: Bool = false) -> RailPackPieceSource {
            RailPackPieceSource(chain: 0, group: 0, isLong: long, vertices: (0..<vertices).map {
                RailPackPoint(x: (x + Double($0 % 2)) * mpp, y: 51 * 1024 * mpp)
            })
        }
        // 32,767 vertices is the most a piece may hold; one more is refused.
        _ = try RailPackWriter.write(Self.onePiece(mpp: mpp, pieces: [piece(group)]))
        #expect(throws: RailPackError.valueTooLarge("piece 0 vertex count")) {
            try RailPackWriter.write(Self.onePiece(mpp: mpp, pieces: [piece(group + 1)]))
        }
        #expect(throws: RailPackError.valueTooLarge("piece 0 vertex count")) {
            try RailPackWriter.write(Self.onePiece(mpp: mpp, pieces: [piece(group + 1, long: true)]))
        }
        // A home tile above 65,534: the top level is z17 by format. At mapPointsPerPoint 4 the world has 65,536 tiles.
        let fine = RailPackLadder.mapPointsPerPoint(forZoom: 17)
        let side = RailPackFormat.tileSide(mapPointsPerPoint: fine)
        func atTile(_ tile: Double) -> RailPackSource {
            Self.onePiece(mpp: fine, pieces: [RailPackPieceSource(chain: 0, group: 0, vertices: [
                RailPackPoint(x: (tile + 0.5) * side, y: 100 * side), RailPackPoint(x: (tile + 0.5) * side + 4, y: 100 * side)])])
        }
        _ = try RailPackWriter.write(atTile(65_534))
        #expect(throws: RailPackError.valueTooLarge("piece 0 home tile")) { try RailPackWriter.write(atTile(65_535)) }
        #expect(throws: RailPackError.valueTooLarge("piece 0 home tile")) { try RailPackWriter.write(atTile(-1)) }
        // More than 65,535 pieces in one chain: a nodes row holds the piece's index in its chain as u16.
        func manyPieces(_ count: Int) -> RailPackSource {
            Self.onePiece(mpp: mpp, pieces: (0..<count).map {
                RailPackPieceSource(chain: 0, group: 0, vertices: [
                    RailPackPoint(x: (100 * 1024 + Double($0 % 500)) * mpp, y: (51 * 1024 + Double($0 / 500)) * mpp),
                    RailPackPoint(x: (100 * 1024 + Double($0 % 500) + 0.5) * mpp, y: (51 * 1024 + Double($0 / 500)) * mpp)])
            })
        }
        _ = try RailPackWriter.write(manyPieces(RailPackFormat.maxPiecesPerChain))
        #expect(throws: RailPackError.valueTooLarge("chain piece count")) {
            try RailPackWriter.write(manyPieces(RailPackFormat.maxPiecesPerChain + 1))
        }
        // A long-piece step must fit Int16 quanta: 2,047 points do, 2,048 do not.
        func longStep(_ points: Double) -> RailPackSource {
            Self.onePiece(mpp: mpp, pieces: [RailPackPieceSource(chain: 0, group: 0, isLong: true, vertices: [
                RailPackPoint(x: 100 * 1024 * mpp, y: 51 * 1024 * mpp), RailPackPoint(x: (100 * 1024 + points) * mpp, y: 51 * 1024 * mpp)])])
        }
        _ = try RailPackWriter.write(longStep(2_047))
        #expect(throws: RailPackError.valueTooLarge("long piece step in piece 0")) { try RailPackWriter.write(longStep(2_048)) }
    }

    @Test func ladderIsDataAndChoosesLevelsWithHysteresis() throws {
        let ladder = RailPackLadder.default
        #expect(abs(ladder.switchDistance(from: 12, towards: 11) - 0.45) < 1e-12 && abs(ladder.switchDistance(from: 12, towards: 13) - 0.45) < 1e-12)
        #expect(ladder.levelCount == 27)
        #expect(ladder.zooms.first == 4 && ladder.zooms.last == 17)
        #expect(ladder.mapPointsPerPoint(level: 0) == 32_768)        // 2^15 at z4
        #expect(ladder.mapPointsPerPoint(level: 26) == 4)            // 2^2 at z17
        #expect(ladder.nearestLevel(cameraZoom: 11.26) == 13)        // ladder z10.5 = app zoom 11.5
        #expect(ladder.nearestLevel(cameraZoom: 3) == 0)
        #expect(ladder.nearestLevel(cameraZoom: 21) == 26)
        // Installed level z10.0 (index 12, app zoom 11.0) holds until the camera is more than 0.45 away.
        #expect(ladder.chooseLevel(cameraZoom: 11.44, installed: 12) == 12)
        #expect(ladder.chooseLevel(cameraZoom: 11.46, installed: 12) == 13)
        #expect(ladder.chooseLevel(cameraZoom: 10.56, installed: 12) == 12)
        #expect(ladder.chooseLevel(cameraZoom: 10.4, installed: 12) == 11)
        #expect(ladder.chooseLevel(cameraZoom: 11.3, installed: nil) == 13)
        // The ends absorb anything beyond them.
        #expect(ladder.chooseLevel(cameraZoom: 2, installed: 0) == 0)
        #expect(ladder.chooseLevel(cameraZoom: 26, installed: 26) == 26)
        // A file's ladder is rebuilt from its stored values.
        let reader = try RailPackReader(data: RailPackTestPack.bytes())
        #expect(reader.ladder.zooms == RailPackTestPack.zooms)
    }

    @Test func groupAndSpanFiltersFollowTheSpec() {
        let group = RailPackGroup(colourLight: 1, colourDark: 2, tierMin: 40, tierMax: 48, styleClass: 0, category: 0)
        #expect(!group.isDrawn(visibilityZoom: 9.9))
        #expect(group.isDrawn(visibilityZoom: 10))
        #expect(group.isDrawn(visibilityZoom: 11.99))
        #expect(!group.isDrawn(visibilityZoom: 12))
        #expect(group.colour(dark: true) == 2 && group.colour(dark: false) == 1)
        let open = RailPackGroup(colourLight: 0, colourDark: 0, tierMin: 8, tierMax: RailPackFormat.tierNoUpperLimit, styleClass: 0, category: 0)
        #expect(open.isDrawn(visibilityZoom: 17))
        let never = RailPackGroup(colourLight: 0, colourDark: 0, tierMin: RailPackFormat.tierNeverDrawn, tierMax: RailPackFormat.tierNoUpperLimit, styleClass: 0, category: 0)
        #expect(!never.isDrawn(visibilityZoom: 17))
        let span = RailPackSpan(fromDay: 100, toDay: 200)
        #expect(!span.contains(day: 99) && span.contains(day: 100) && span.contains(day: 199) && !span.contains(day: 200))
    }

    @Test func sizeAccountingCoversEveryByte() throws {
        let data = try RailPackTestPack.bytes()
        let reader = try RailPackReader(data: data)
        let report = reader.sizeAccounting()
        #expect(report.fileBytes == data.count)
        #expect(report.accountedBytes == data.count)
        #expect(report.levels.count == 3)
        // Per level: 7 pieces, 1 of them long with 8 vertices (7 delta rows); 20 normal vertices, 4 of them
        // the shared first vertex of a joined piece and so not stored: 16 rows.
        for level in report.levels {
            #expect(level.rows[RailPackFormat.ArrayKind.pieces.rawValue] == 7)
            #expect(level.rows[RailPackFormat.ArrayKind.vertices.rawValue] == 16)
            #expect(level.rows[RailPackFormat.ArrayKind.longVertices.rawValue] == 7)
            #expect(level.arrayBytes[RailPackFormat.ArrayKind.vertices.rawValue] == 64)
            #expect(level.arrayBytes[RailPackFormat.ArrayKind.pieces.rawValue] == 7 * 8)
            #expect(level.arrayBytes[RailPackFormat.ArrayKind.longPieces.rawValue] == 28)
            #expect(level.totalBytes == level.arrayBytes.reduce(0, +))
        }
        #expect(report.vertexCount == 3 * (16 + 7))
        #expect(report.regionTableBytes == 2 * 12 + 4 * 16 + 1 * 8 + 4 * 4 + 3 * 84)
    }
}
