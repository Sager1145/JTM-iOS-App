import Foundation
import RailCore

/// The size report of a pack (`RailBake --report`): bytes, pieces, vertices and tiles per level.
public struct PackReport: Sendable, Equatable {

    public struct Level: Sendable, Equatable {
        public var zoom: Double
        public var bytes: Int
        public var pieces: Int
        public var longPieces: Int
        /// Normal plus long vertices.
        public var vertices: Int
        public var tiles: Int
        public var nodes: Int
        /// Most pieces in any one tile.
        public var largestTilePieces: Int
        /// Most vertices a phone-sized view plus one ring mounts at this level (`PackWindows`).
        public var phoneWindowVertices: Int
        /// The same for a pad-sized view.
        public var padWindowVertices: Int
    }

    public var fileBytes: Int
    /// Header, section table and region tables: bytes outside any level.
    public var sharedBytes: Int
    public var chains: Int
    public var groups: Int
    public var spans: Int
    public var levels: [Level]

    public var totalPieces: Int { levels.reduce(0) { $0 + $1.pieces } }
    public var totalVertices: Int { levels.reduce(0) { $0 + $1.vertices } }

    public init(reader: RailPackReader) throws {
        let size = reader.sizeAccounting()
        fileBytes = size.fileBytes
        sharedBytes = size.headerBytes + size.regionTableBytes
        chains = reader.header.chainCount
        groups = reader.header.groupCount
        spans = reader.header.spanCount
        var levels: [Level] = []
        for (index, level) in size.levels.enumerated() {
            func rows(_ kind: RailPackFormat.ArrayKind) -> Int { level.rows[kind.rawValue] }
            var largest = 0
            for tile in 0..<rows(.tileDir) { largest = max(largest, Int(try reader.tile(level: index, index: tile).pieceCount)) }
            let windows = try PackWindows.maxima(reader: reader, level: index)
            levels.append(Level(
                zoom: level.zoom, bytes: level.totalBytes, pieces: rows(.pieces), longPieces: rows(.longPieces),
                vertices: rows(.vertices) + rows(.longVertices), tiles: rows(.tileDir),
                nodes: rows(.nodes), largestTilePieces: largest,
                phoneWindowVertices: windows.phone, padWindowVertices: windows.pad))
        }
        self.levels = levels
    }

    /// One line per level and a total line, for the terminal.
    public func text() -> String {
        var lines = ["level zoom      bytes     pieces   long   vertices    tiles  maxTilePieces   phoneWin    padWin"]
        for (index, level) in levels.enumerated() {
            lines.append(String(
                format: "%5d %4.1f %10d %10d %6d %10d %8d %14d %10d %9d", index, level.zoom, level.bytes, level.pieces,
                level.longPieces, level.vertices, level.tiles, level.largestTilePieces,
                level.phoneWindowVertices, level.padWindowVertices))
        }
        lines.append("total: \(fileBytes) bytes (\(sharedBytes) shared), \(totalPieces) pieces, "
            + "\(totalVertices) vertices, \(chains) chains, \(groups) groups, \(spans) spans")
        return lines.joined(separator: "\n")
    }
}

/// `RailBake --compare a b`: two packs of one input agree when their structure is equal and every
/// vertex is within one quantum.
public enum PackCompare {

    /// Differences found, at most `limit` of them; empty when the packs agree.
    public static func differences(_ a: RailPackReader, _ b: RailPackReader, limit: Int = 20) throws -> [String] {
        var found: [String] = []
        func note(_ text: String) -> Bool {
            found.append(text)
            return found.count >= limit
        }
        let ha = a.header, hb = b.header
        if ha.levelCount != hb.levelCount { _ = note("level count \(ha.levelCount) vs \(hb.levelCount)"); return found }
        if ha.datum != hb.datum || ha.regionCode != hb.regionCode { if note("datum or region differ") { return found } }
        if ha.chainCount != hb.chainCount || ha.nodeCount != hb.nodeCount || ha.lineCount != hb.lineCount {
            _ = note("chain, node or line count differs"); return found
        }
        if ha.displaySHA256 != hb.displaySHA256 { if note("displaySHA256 differs") { return found } }
        for level in 0..<ha.levelCount {
            let mpp = a.levels[level].mapPointsPerPoint
            if mpp != b.levels[level].mapPointsPerPoint { if note("level \(level): scale differs") { return found } }
            let quantum = RailPackFormat.quantum(mapPointsPerPoint: mpp)
            let pieces = try a.count(level: level, .pieces)
            if pieces != (try b.count(level: level, .pieces)) {
                if note("level \(level): \(pieces) vs \(try b.count(level: level, .pieces)) pieces") { return found }
                continue
            }
            var pa: [RailPackPoint] = [], pb: [RailPackPoint] = []
            for piece in 0..<pieces {
                let ra = try a.piece(level: level, index: piece), rb = try b.piece(level: level, index: piece)
                if ra.group != rb.group || ra.span != rb.span || ra.vertexCount != rb.vertexCount || ra.isLong != rb.isLong {
                    if note("level \(level) piece \(piece): row differs") { return found }
                    continue
                }
                pa.removeAll(keepingCapacity: true)
                pb.removeAll(keepingCapacity: true)
                try a.appendVertices(level: level, piece: piece, to: &pa)
                try b.appendVertices(level: level, piece: piece, to: &pb)
                for (p, q) in zip(pa, pb) where abs(p.x - q.x) > quantum || abs(p.y - q.y) > quantum {
                    if note("level \(level) piece \(piece): vertex differs by more than a quantum") { return found }
                    break
                }
            }
        }
        return found
    }
}
