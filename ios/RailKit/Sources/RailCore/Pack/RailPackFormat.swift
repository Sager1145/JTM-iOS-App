import Foundation

// MARK: - Format contract: `jtm-rail-pack-v1`
//
// One file per region and datum, `{region}.railpack`. Little-endian, fixed-width,
// no compression, read in place from a memory map. Every section and every row is a
// multiple of 4 bytes, so the file has no padding at all; rows may hold unaligned
// fields (a `UInt32` at offset 6 of a line row) and readers use unaligned loads.
// Nothing here is wired into the app yet.
//
// Layout (offsets in bytes):
//   0   magic "JTRP"            4
//   4   formatVersion u16
//   6   datum u8 (0 WGS84, 1 GCJ-02)
//   7   region code             2 ASCII bytes
//   9   reserved u8
//   10  levelCount u16
//   12  lineCount u16
//   14  groupCount u16
//   16  spanCount u16
//   18  reserved u16
//   20  chainCount u32
//   24  nodeCount u32
//   28  displaySHA256           32
//   60  inputsSHA256            32
//   92  fileLength u64         (detects truncation)
//   100 section table: (offset u64, length u64) for lines, groups, spans, levels,
//       then one per level (the level's arrays, contiguous)
// then the region tables, then each level's arrays in `ArrayKind` order.
//
// Chains row (8 bytes): firstPiece u32, then a u32 whose low 31 bits are the piece count and
// whose top bit (`closedChainFlag`) marks a closed chain (a loop: its last vertex equals its
// first). The flag is repeated identically at every level.
//
// Long pieces (dashed runs, never cut) have no home tile. They are mounted per piece, not per
// tile: a long piece is wanted when its bounding box intersects the request rectangle
// (`RailPackReader.longPieces`), and its mount key is `RailPackMountKey.longPiece`. A normal
// piece is wanted when its home tile lies in the request rectangle grown by half a tile
// (mount key `RailPackMountKey.tile`).
//
// Tile geometry: a tile is 1,024 points square at the level, side in map points
// `1024 * mapPointsPerPoint`. A normal piece is stored relative to the centre of its
// home tile (the tile holding the centre of its bounding box) as Int16 in quanta of
// 1/16 point: `mapX = (tileX + 0.5) * side + x * mapPointsPerPoint / 16`. A long piece
// (dashed run, never cut) is stored as Int32 quanta from the world origin.

public enum RailPackFormat {
    public static let magic: [UInt8] = Array("JTRP".utf8)
    public static let formatVersion: UInt16 = 1

    public static let tilePoints = 1_024.0
    /// Quanta per point (1/16 point).
    public static let quantaPerPoint = 16.0
    /// Largest stored magnitude of a normal vertex: half the Int16 range.
    public static let maxHomeTileQuanta = 16_384

    public static let noSpan: UInt16 = 0xFFFF
    public static let longPieceTile: UInt32 = 0xFFFF_FFFF
    public static let noNode: UInt32 = 0xFFFF_FFFF
    public static let tierNoUpperLimit: Int16 = 0x7FFF
    public static let tierNeverDrawn: Int16 = 0x7FFF
    /// Top bit of a chains row's count word: the chain is closed (a loop).
    public static let closedChainFlag: UInt32 = 0x8000_0000
    public static let chainCountMask: UInt32 = 0x7FFF_FFFF
    /// Accepted `mapPointsPerPoint` range: keeps tile maths inside Int.
    public static let minMapPointsPerPoint = 0.25
    public static let maxMapPointsPerPoint = 1_048_576.0
    /// Adjacent ladder levels must differ by at least this much zoom.
    public static let minZoomGap = 0.01
    /// Tile coordinates are clamped to this magnitude (they are stored as Int32).
    public static let tileCoordinateLimit = 2_147_483_647.0

    public enum Datum: UInt8, Sendable { case wgs84 = 0, gcj02 = 1 }

    public enum StyleClass: UInt8, Sendable { case solid = 0, historicalDashed = 1, withheldDashed = 2 }

    // Header
    public static let headerSize = 100
    public static let sectionEntrySize = 16
    public static let regionSectionCount = 4
    public static let offsetFileLength = 92

    // Region sections, in section-table order.
    public enum Region: Int, CaseIterable, Sendable { case lines = 0, groups, spans, levels }

    // Row sizes.
    public static let lineRow = 12
    public static let groupRow = 16
    public static let spanRow = 8
    public static let levelRow = 120

    /// Per-level arrays, in file order.
    public enum ArrayKind: Int, CaseIterable, Sendable {
        case tileDir = 0, tilePieces, tileNodes, pieces, chains, nodes, vertices, longPieces, longVertices

        public var rowSize: Int {
            switch self {
            case .tileDir: return 20
            case .tilePieces, .tileNodes, .vertices: return 4
            case .pieces: return 16
            case .chains, .nodes, .longVertices: return 8
            case .longPieces: return 20
            }
        }
    }

    // Level row: mapPointsPerPoint f64 @0, laneBucket u8 @8, 3 reserved, then per array (count u32, offset u64) from 12.
    public static let levelArrayEntrySize = 12
    public static let levelArraysOffset = 12

    public static func tileSide(mapPointsPerPoint: Double) -> Double { tilePoints * mapPointsPerPoint }
    public static func quantum(mapPointsPerPoint: Double) -> Double { mapPointsPerPoint / quantaPerPoint }

    /// Map position of a normal vertex; the single decode formula for writer and reader.
    @inline(__always)
    public static func decode(_ q: Int, tile: Int, mapPointsPerPoint: Double) -> Double {
        (Double(tile) + 0.5) * tileSide(mapPointsPerPoint: mapPointsPerPoint) + Double(q) * quantum(mapPointsPerPoint: mapPointsPerPoint)
    }

    /// Map position of a long-piece vertex.
    @inline(__always)
    public static func decodeLong(_ q: Int, mapPointsPerPoint: Double) -> Double {
        Double(q) * quantum(mapPointsPerPoint: mapPointsPerPoint)
    }

    /// Tile coordinate holding a map coordinate, clamped to the Int32 range (NaN gives 0); never traps.
    @inline(__always)
    public static func tile(containing map: Double, mapPointsPerPoint: Double) -> Int {
        let t = (map / tileSide(mapPointsPerPoint: mapPointsPerPoint)).rounded(.down)
        if t.isNaN { return 0 }
        return Int(min(max(t, -tileCoordinateLimit), tileCoordinateLimit))
    }
}

/// Typed failures of the writer and the reader.
public enum RailPackError: Error, Equatable, Sendable {
    // Reader: file level.
    case truncated
    case badMagic
    case unsupportedVersion(UInt16)
    case lengthMismatch(declared: UInt64, actual: Int)
    case sectionOutOfBounds(String)
    case arrayOutOfBounds(level: Int, array: String)
    case badLevel(Int)
    case corrupt(String)
    case indexOutOfRange(String)
    case nodesNotOnOneChain
    case chainNotClosed
    // Writer: input level.
    case invalidInput(String)
    case pieceOutsideHomeTile(level: Int, piece: Int)
    case valueTooLarge(String)
}

// MARK: - Row value types

public struct RailPackPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct RailPackLine: Equatable, Sendable {
    public var firstChain: UInt32
    public var chainCount: UInt16
    /// Global node index of the line's node ordinal 0.
    public var firstNode: UInt32
    public var nodeCount: UInt16
    public init(firstChain: UInt32, chainCount: UInt16, firstNode: UInt32, nodeCount: UInt16) {
        self.firstChain = firstChain; self.chainCount = chainCount
        self.firstNode = firstNode; self.nodeCount = nodeCount
    }
}

/// Drawing attributes shared by many pieces.
public struct RailPackGroup: Equatable, Sendable {
    public var colourLight: UInt32
    public var colourDark: UInt32
    /// `lodMinZoom` x 4. `RailPackFormat.tierNeverDrawn` means trip geometry only.
    public var tierMin: Int16
    /// `lodMinZoom` x 4, exclusive; `RailPackFormat.tierNoUpperLimit` means none.
    public var tierMax: Int16
    public var styleClass: UInt8
    public var category: UInt8
    public init(colourLight: UInt32, colourDark: UInt32, tierMin: Int16, tierMax: Int16, styleClass: UInt8, category: UInt8) {
        self.colourLight = colourLight; self.colourDark = colourDark
        self.tierMin = tierMin; self.tierMax = tierMax
        self.styleClass = styleClass; self.category = category
    }

    public func colour(dark: Bool) -> UInt32 { dark ? colourDark : colourLight }

    /// Tier filter: drawn when `tierMin <= visibilityZoom x 4 < tierMax`.
    public func isDrawn(visibilityZoom: Double) -> Bool {
        guard tierMin != RailPackFormat.tierNeverDrawn else { return false }
        let scaled = visibilityZoom * 4
        return Double(tierMin) <= scaled && (tierMax == RailPackFormat.tierNoUpperLimit || scaled < Double(tierMax))
    }
}

/// Half-open day range `[fromDay, toDay)`.
public struct RailPackSpan: Equatable, Sendable {
    public var fromDay: Int32
    public var toDay: Int32
    public init(fromDay: Int32, toDay: Int32) { self.fromDay = fromDay; self.toDay = toDay }
    public func contains(day: Int32) -> Bool { fromDay <= day && day < toDay }
}

public struct RailPackPieceRow: Equatable, Sendable {
    /// Index into the level's tile directory; `longPieceTile` for a long piece.
    public var tile: UInt32
    /// Index into `vertices`, or into `longVertices` for a long piece.
    public var vertexStart: UInt32
    public var vertexCount: UInt16
    public var group: UInt16
    /// Index into spans; `noSpan` for undated.
    public var span: UInt16
    public var flags: UInt16
    public var isLong: Bool { tile == RailPackFormat.longPieceTile }
}

public struct RailPackTileRow: Equatable, Sendable {
    public var tileX: Int32
    public var tileY: Int32
    public var firstTilePiece: UInt32
    public var pieceCount: UInt16
    public var nodeCount: UInt16
    public var firstTileNode: UInt32
}

/// Where a topology node sits on the level's stroke.
public struct RailPackNodeSlot: Equatable, Sendable {
    public var piece: UInt32
    public var vertex: UInt16
    public static let none = RailPackNodeSlot(piece: RailPackFormat.noNode, vertex: 0)
    public init(piece: UInt32, vertex: UInt16) { self.piece = piece; self.vertex = vertex }
    public var isNone: Bool { piece == RailPackFormat.noNode }
}

public struct RailPackLongPieceRow: Equatable, Sendable {
    public var piece: UInt32
    /// Bounding box in level quanta from the world origin.
    public var minX: Int32, minY: Int32, maxX: Int32, maxY: Int32
}

/// What a loader mounts: one key per tile, or one per long piece (which has no home tile).
public enum RailPackMountKey: Hashable, Sendable {
    case tile(level: Int, x: Int, y: Int)
    case longPiece(level: Int, piece: Int)
}

/// A run of vertices of one piece, `first...last` inclusive, ascending in the file.
/// `chain` lets a caller break the stroke where a trip crosses from one chain to the next
/// (the gap between them draws nothing).
public struct RailPackVertexRange: Equatable, Sendable {
    public var chain: Int
    public var piece: UInt32
    public var first: Int
    public var last: Int
}
