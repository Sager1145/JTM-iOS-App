import Foundation
@testable import RailCore

/// A second synthetic region for topology cases: a closed loop (chain 0, three pieces, the seam vertex
/// repeated), a non-continuous line of three chains with gaps (chains 1 to 3) and a one-chain line.
/// Everything lies in tile (10, 10) of its level so the geometry is the same at every level.
enum RailPackLoopTestPack {
    static let chainCount = 5
    static let nodeCount = 8

    /// A map point `dx, dy` points from the centre of tile (10, 10) at a level.
    static func pt(_ mpp: Double, _ dx: Double, _ dy: Double) -> RailPackPoint {
        RailPackPoint(x: (10 * 1024 + 512 + dx) * mpp, y: (10 * 1024 + 512 + dy) * mpp)
    }

    /// The loop's nine vertices (the last repeats the first) in points from the tile centre.
    static let ring: [(Double, Double)] = (0...8).map { k in
        let angle = Double(k % 8) * Double.pi / 4
        return (200 * cos(angle), 200 * sin(angle))
    }

    static func level(zoom: Double) -> RailPackLevelSource {
        let mpp = RailPackLadder.mapPointsPerPoint(forZoom: zoom)
        let loop = ring.map { pt(mpp, $0.0, $0.1) }
        func run(_ x: Double, _ y: Double) -> [RailPackPoint] { (0..<3).map { pt(mpp, x + Double($0) * 50, y) } }
        let pieces = [
            RailPackPieceSource(chain: 0, group: 0, vertices: Array(loop[0...3])),
            RailPackPieceSource(chain: 0, group: 0, vertices: Array(loop[3...6])),
            RailPackPieceSource(chain: 0, group: 0, vertices: Array(loop[6...8])),
            RailPackPieceSource(chain: 1, group: 0, vertices: run(-400, 300)),
            RailPackPieceSource(chain: 2, group: 0, vertices: run(-250, 300)),
            RailPackPieceSource(chain: 3, group: 0, vertices: run(0, 350)),
            RailPackPieceSource(chain: 4, group: 0, vertices: run(200, -350)),
        ]
        let nodes = [
            RailPackNodeSlot(piece: 0, vertex: 1),  // 0: loop vertex 1
            RailPackNodeSlot(piece: 2, vertex: 1),  // 1: loop vertex 7
            RailPackNodeSlot(piece: 1, vertex: 0),  // 2: loop vertex 3, start of piece 1
            RailPackNodeSlot(piece: 0, vertex: 3),  // 3: loop vertex 3, end of piece 0 (shared boundary vertex)
            RailPackNodeSlot(piece: 3, vertex: 1),  // 4: chain 1
            RailPackNodeSlot(piece: 5, vertex: 1),  // 5: chain 3
            RailPackNodeSlot(piece: 4, vertex: 1),  // 6: chain 2
            RailPackNodeSlot(piece: 6, vertex: 0),  // 7: chain 4 (another line)
        ]
        return RailPackLevelSource(mapPointsPerPoint: mpp, laneBucket: 0, pieces: pieces, nodes: nodes)
    }

    static func source(zooms: [Double] = [12, 12.5]) -> RailPackSource {
        RailPackSource(
            regionCode: "lp",
            displaySHA256: [UInt8](repeating: 7, count: 32), inputsSHA256: [UInt8](repeating: 9, count: 32),
            chainCount: chainCount, nodeCount: nodeCount,
            lines: [RailPackLine(firstChain: 0, chainCount: 1, firstNode: 0, nodeCount: 4),
                    RailPackLine(firstChain: 1, chainCount: 3, firstNode: 4, nodeCount: 3),
                    RailPackLine(firstChain: 4, chainCount: 1, firstNode: 7, nodeCount: 1)],
            groups: [RailPackGroup(colourLight: 1, colourDark: 2, tierMin: 0, tierMax: RailPackFormat.tierNoUpperLimit, styleClass: 0, category: 0)],
            spans: [], levels: zooms.map(level(zoom:)), closedChains: [0])
    }

    static func bytes() throws -> Data { try RailPackWriter.write(source()) }
}
