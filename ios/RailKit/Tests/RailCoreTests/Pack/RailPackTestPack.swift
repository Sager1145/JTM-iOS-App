import Foundation
@testable import RailCore

/// A small synthetic region: three levels, three chains, lines crossing tile borders, a dashed
/// long run and four nodes. Chain 0's neighbouring pieces share their boundary vertex, so the writer
/// stores that vertex once (pieces 1, 2, 3 and 6 join the piece before them). Geometry is built in points at each level so it spans several tiles.
enum RailPackTestPack {
    static let zooms: [Double] = [10, 10.5, 11]
    static let chainCount = 3
    static let nodeCount = 4

    /// A map point `px, py` points from the world origin at a level.
    static func map(_ mpp: Double, _ px: Double, _ py: Double) -> RailPackPoint {
        RailPackPoint(x: px * mpp, y: py * mpp)
    }

    static func level(zoom: Double) -> RailPackLevelSource {
        let mpp = RailPackLadder.mapPointsPerPoint(forZoom: zoom)
        let originX = 100.0 * 1024 - 1500  // chain 0 crosses the border between tiles 99 and 100
        let originY = 50.0 * 1024 + 100.25
        var pieces: [RailPackPieceSource] = []

        // Chain 0 (line 0): 11 vertices every 300 points, fractional so quantisation matters; cut in runs of
        // three segments (900 points) that share their boundary vertex.
        let chain0 = (0...10).map { map(mpp, originX + Double($0) * 300 + 0.37, originY + sin(Double($0)) * 40) }
        for (n, range) in [0...3, 3...6, 6...9, 9...10].enumerated() {
            pieces.append(RailPackPieceSource(chain: 0, group: n == 3 ? 1 : (n == 2 ? 3 : 0), vertices: Array(chain0[range])))
        }
        // Chain 1 (line 0, second part): one dashed run, 2,500 points across tiles, never cut.
        let chain1 = (0..<8).map { map(mpp, originX + Double($0) * 357.5 + 0.11, originY + 2_000 + Double($0) * 120) }
        pieces.append(RailPackPieceSource(chain: 1, group: 2, isLong: true, vertices: chain1))
        // Chain 2 (line 1): a vertical line, two pieces.
        let chain2 = (0...4).map { map(mpp, originX + 4_000.5, originY + Double($0) * 400 - 600) }
        pieces.append(RailPackPieceSource(chain: 2, group: 0, vertices: Array(chain2[0...2])))
        pieces.append(RailPackPieceSource(chain: 2, group: 0, vertices: Array(chain2[2...4])))

        let nodes: [RailPackNodeSlot] = [
            RailPackNodeSlot(piece: 0, vertex: 0),   // node 0: start of chain 0
            RailPackNodeSlot(piece: 2, vertex: 1),   // node 1: inside chain 0's third piece
            RailPackNodeSlot(piece: 4, vertex: 3),   // node 2: on the long piece
            .none,                                   // node 3: no chain slot
        ]
        return RailPackLevelSource(mapPointsPerPoint: mpp, laneBucket: zoom >= 11 ? 2 : (zoom >= 9 ? 1 : 0), pieces: pieces, nodes: nodes)
    }

    static func source(zooms: [Double] = RailPackTestPack.zooms) -> RailPackSource {
        RailPackSource(
            regionCode: "jp",
            displaySHA256: (0..<32).map { UInt8($0) }, inputsSHA256: (0..<32).map { UInt8(255 - $0) },
            chainCount: chainCount, nodeCount: nodeCount,
            lines: [RailPackLine(firstChain: 0, chainCount: 2, firstNode: 0, nodeCount: 3),
                    RailPackLine(firstChain: 2, chainCount: 1, firstNode: 3, nodeCount: 1)],
            groups: [
                RailPackGroup(colourLight: 0xFF0000FF, colourDark: 0x00FF00FF, tierMin: 36, tierMax: RailPackFormat.tierNoUpperLimit, styleClass: 0, category: 1),
                RailPackGroup(colourLight: 0x0000FFFF, colourDark: 0xFFFF00FF, tierMin: 40, tierMax: 48, styleClass: 0, category: 2),
                RailPackGroup(colourLight: 0x808080FF, colourDark: 0x404040FF, tierMin: 0, tierMax: RailPackFormat.tierNoUpperLimit, styleClass: 1, category: 3),
                RailPackGroup(colourLight: 0xFF0000FF, colourDark: 0x00FF00FF, tierMin: 36, tierMax: RailPackFormat.tierNoUpperLimit, styleClass: 1, category: 1, span: 0),
            ],
            spans: [RailPackSpan(fromDay: 100, toDay: 200)],
            levels: zooms.map(level(zoom:)))
    }

    static func bytes() throws -> Data { try RailPackWriter.write(source()) }

    /// Returns a copy of `data` with `value` written little-endian at `offset`.
    static func patched(_ data: Data, at offset: Int, _ value: UInt64, width: Int) -> Data {
        var copy = data
        for i in 0..<width { copy[offset + i] = UInt8((value >> (8 * UInt64(i))) & 0xFF) }
        return copy
    }

    static func u64(_ data: Data, _ offset: Int) -> Int {
        (0..<8).reduce(0) { $0 | Int(data[offset + $1]) << (8 * $1) }
    }

    /// File offset of section-table entry `index` (0 lines, 1 groups, 2 spans, 3 nodeChains, 4 levels, 5+ level arrays).
    static func sectionEntry(_ index: Int) -> Int { RailPackFormat.headerSize + index * RailPackFormat.sectionEntrySize }
}
