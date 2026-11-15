import Foundation
import RailCore

/// How many vertices a view mounts: the densest window of tiles a pack can be asked for at a level
/// (limits record docs/maintenance/2026-11-13-rail-pack-limits.md: at most 100,000, target 50,000, for a
/// phone view; design docs/maintenance/2026-11-13-rail-pack-size-design.md, section 4.6). A piece counts
/// its full vertex count, including the first vertex a joined piece shares with the piece before it.
///
/// A 390 x 844 point view plus one ring, grown by half a tile (a piece reaches half a tile outside
/// its home tile), touches at most 4 x 5 or 5 x 4 tiles of 1,024 points; a 1,032 x 1,376 view (pad)
/// at most 6 x 7 or 7 x 6. A window counts every drawable piece homed in its tiles with no tier
/// filter, plus every long piece whose bounding box meets the window, as the loader mounts them.
public enum PackWindows {

    public static let phoneShapes: [(columns: Int, rows: Int)] = [(4, 5), (5, 4)]
    public static let padShapes: [(columns: Int, rows: Int)] = [(6, 7), (7, 6)]

    public struct Maxima: Equatable, Sendable {
        public var phone: Int
        public var pad: Int
    }

    private struct LongPiece {
        var x0: Int, x1: Int, y0: Int, y1: Int
        var vertices: Int
    }

    private struct Anchor: Hashable {
        var x: Int32, y: Int32
    }

    /// The densest phone-sized and pad-sized window at one level, over every window position.
    public static func maxima(level: RailPackLevel) throws -> Maxima {
        let side = RailPackFormat.tileSide(mapPointsPerPoint: level.mapPointsPerPoint)
        let quantum = RailPackFormat.quantum(mapPointsPerPoint: level.mapPointsPerPoint)
        var longs: [LongPiece] = []
        for index in 0..<level.count(.longPieces) {
            let long = try level.longPieceRow(index)
            func tile(_ q: Int32) -> Int { Int((Double(q) * quantum / side).rounded(.down)) }
            longs.append(LongPiece(
                x0: tile(long.minX), x1: tile(long.maxX), y0: tile(long.minY), y1: tile(long.maxY),
                vertices: Int(try level.piece(Int(long.piece)).vertexCount)))
        }
        let tiles = try level.tileSummaries().map { (x: $0.tile.x, y: $0.tile.y, count: $0.vertices) }
        let longTotal = longs.reduce(0) { $0 + $1.vertices }
        func best(_ shapes: [(columns: Int, rows: Int)]) -> Int {
            var maximum = 0
            for shape in shapes {
                var sums: [Anchor: Int] = [:]
                for tile in tiles {
                    for ax in (tile.x - shape.columns + 1)...tile.x {
                        for ay in (tile.y - shape.rows + 1)...tile.y {
                            sums[Anchor(x: Int32(ax), y: Int32(ay)), default: 0] += tile.count
                        }
                    }
                }
                // Long pieces add at most `longTotal` to a window, so only windows that could still
                // beat the best need their long contribution counted.
                maximum = max(maximum, sums.values.max() ?? 0)
                for (anchor, normal) in sums where normal + longTotal > maximum {
                    var total = normal
                    let wx0 = Int(anchor.x), wx1 = wx0 + shape.columns - 1
                    let wy0 = Int(anchor.y), wy1 = wy0 + shape.rows - 1
                    for long in longs where long.x0 <= wx1 && long.x1 >= wx0 && long.y0 <= wy1 && long.y1 >= wy0 {
                        total += long.vertices
                    }
                    maximum = max(maximum, total)
                }
                if sums.isEmpty { maximum = max(maximum, longTotal == 0 ? 0 : longsOnly(longs, shape)) }
            }
            return maximum
        }
        return Maxima(phone: best(phoneShapes), pad: best(padShapes))
    }

    /// With no drawable piece at all: the most long vertices one window can meet, from the first long piece's box.
    private static func longsOnly(_ longs: [LongPiece], _ shape: (columns: Int, rows: Int)) -> Int {
        var best = 0
        for anchor in longs {
            let wx0 = anchor.x0, wx1 = wx0 + shape.columns - 1, wy0 = anchor.y0, wy1 = wy0 + shape.rows - 1
            best = max(best, longs.reduce(0) { total, long in
                total + (long.x0 <= wx1 && long.x1 >= wx0 && long.y0 <= wy1 && long.y1 >= wy0 ? long.vertices : 0)
            })
        }
        return best
    }
}
