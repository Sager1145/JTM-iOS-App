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
    }

    @Test func changingOneVertexChangesTheBytes() throws {
        var source = RailPackTestPack.source()
        source.levels[1].pieces[0].vertices[0].x += 3 * source.levels[1].mapPointsPerPoint
        #expect(try RailPackWriter.write(source) != RailPackTestPack.bytes())
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
            let source = RailPackSource(
                datum: .wgs84, regionCode: "xx", displaySHA256: [UInt8](repeating: 1, count: 32), inputsSHA256: [UInt8](repeating: 2, count: 32),
                chainCount: 1, nodeCount: 0, lines: [], groups: [RailPackGroup(colourLight: 0, colourDark: 0, tierMin: 0, tierMax: 0x7FFF, styleClass: 0, category: 0)],
                spans: [], levels: [RailPackLevelSource(mapPointsPerPoint: mpp, laneBucket: 0,
                                                         pieces: [RailPackPieceSource(chain: 0, group: 0, vertices: vertices)], nodes: [])])
            let reader = try RailPackReader(data: RailPackWriter.write(source))
            var decoded: [RailPackPoint] = []
            try reader.appendVertices(level: 0, piece: 0, to: &decoded)
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
        expectInvalid { $0.levels[0].pieces[0].span = 7 }
        expectInvalid { $0.levels[0].pieces[0].vertices = [$0.levels[0].pieces[0].vertices[0]] }
        expectInvalid { $0.levels[0].pieces.swapAt(0, 5) }  // not sorted by chain
        expectInvalid { $0.levels[0].nodes[0] = RailPackNodeSlot(piece: 0, vertex: 99) }
        expectInvalid { $0.levels[0].nodes.removeLast() }
        expectInvalid { $0.levels.reverse() }  // zoom order must ascend
        expectInvalid { $0.lines[0].nodeCount = 99 }
    }

    @Test func ladderIsDataAndChoosesLevelsWithHysteresis() throws {
        let ladder = RailPackLadder.default
        #expect(abs(ladder.switchDistance(from: 12, towards: 11) - 0.45) < 1e-12 && abs(ladder.switchDistance(from: 12, towards: 13) - 0.45) < 1e-12)
        #expect(ladder.levelCount == 27)
        #expect(ladder.zooms.first == 4 && ladder.zooms.last == 17)
        #expect(ladder.mapPointsPerPoint(level: 0) == 32_768)        // 2^15 at z4
        #expect(ladder.mapPointsPerPoint(level: 26) == 4)            // 2^2 at z17
        #expect(ladder.nearestLevel(cameraZoom: 10.26) == 13)        // z10.5
        #expect(ladder.nearestLevel(cameraZoom: 2) == 0)
        #expect(ladder.nearestLevel(cameraZoom: 20) == 26)
        // Installed level z10.0 (index 12) holds until the camera is more than 0.45 away.
        #expect(ladder.chooseLevel(cameraZoom: 10.44, installed: 12) == 12)
        #expect(ladder.chooseLevel(cameraZoom: 10.46, installed: 12) == 13)
        #expect(ladder.chooseLevel(cameraZoom: 9.56, installed: 12) == 12)
        #expect(ladder.chooseLevel(cameraZoom: 9.4, installed: 12) == 11)
        #expect(ladder.chooseLevel(cameraZoom: 10.3, installed: nil) == 13)
        // The ends absorb anything beyond them.
        #expect(ladder.chooseLevel(cameraZoom: 1, installed: 0) == 0)
        #expect(ladder.chooseLevel(cameraZoom: 25, installed: 26) == 26)
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
        // Per level: 7 normal pieces, 1 long piece with 8 vertices, 4 + 4 + 4 + 2 + 3 + 3 = 20 normal vertices.
        for level in report.levels {
            #expect(level.rows[RailPackFormat.ArrayKind.pieces.rawValue] == 7)
            #expect(level.rows[RailPackFormat.ArrayKind.vertices.rawValue] == 20)
            #expect(level.rows[RailPackFormat.ArrayKind.longVertices.rawValue] == 8)
            #expect(level.arrayBytes[RailPackFormat.ArrayKind.vertices.rawValue] == 80)
            #expect(level.arrayBytes[RailPackFormat.ArrayKind.pieces.rawValue] == 7 * 16)
            #expect(level.totalBytes == level.arrayBytes.reduce(0, +))
        }
        #expect(report.vertexCount == 3 * 28)
        #expect(report.regionTableBytes == 2 * 12 + 3 * 16 + 1 * 8 + 3 * 120)
    }
}
