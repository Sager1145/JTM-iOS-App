import Foundation

// MARK: - Format contract: `jtm-rail-pack-v2`
//
// One WGS84 file per region, `{region}.railpack` (the GCJ-02 shift of the China-service regions is
// applied by the reader when a level is mounted, `RailPackReader(data:display:)`). Little-endian,
// fixed-width, no compression, no varint, read in place from a memory map. Every section and every
// row is a multiple of 4 bytes, so the file has no padding at all; rows may hold unaligned fields
// (a `UInt32` at offset 6 of a line row) and readers use unaligned loads. Version 1 (a tile
// directory per level, a datum byte, absolute long vertices) is not read: no pack shipped in it.
//
// Layout (offsets in bytes):
//   0   magic "JTRP"            4
//   4   formatVersion u16
//   6   reserved u8 (0)
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
//   100 section table: (offset u64, length u64) for lines, groups, spans, nodeChains, levels,
//       then one per level (the level's arrays, contiguous)
// then the region tables, then each level's arrays in `ArrayKind` order.
//
// Region tables: lines (12 B), groups (16 B: two colours, tier window, style, category and the
// group's date span index `span u16`, `noSpan` meaning undated), spans (8 B), nodeChains (4 B per
// node: the region-wide chain index of the node, `noNode` for a node with no chain slot at any level).
//
// Level arrays (`ArrayKind` order):
//   pieces       8 B   tileX u16, tileY u16, vertexCount u16, group u16
//   chains       4 B   piece count in the low 31 bits, `closedChainFlag` in the top bit
//   nodes        4 B   pieceInChain u16, vertex u16 ((0xFFFF, 0xFFFF) means no slot at this level)
//   vertices     4 B   x Int16, y Int16 in quanta of 1/16 point from the home tile's centre
//   longPieces  28 B   piece u32, box 4 x i32, firstX i32, firstY i32 (world quanta)
//   longVertices 4 B   dx Int16, dy Int16 from the previous vertex; n vertices store n-1 rows
//
// A piece's `vertexCount` word: the low 15 bits are its vertex count (2 to 32,767) and the top bit
// (`joinsPreviousFlag`) says its first vertex is the previous piece's last vertex and is not stored
// (the writer sets it only for two normal pieces of one chain whose shared vertex is equal in world
// quanta). A long piece (a dashed run, never cut) has `tileX == tileY == longPieceTile`.
//
// Chains rows carry no first piece: the first piece of a chain is the running sum of the counts, which
// a reader builds once per opened level with the per-piece vertex starts and a tile order
// (`RailPackLevel`); the file holds no tile directory. The closed flag is repeated identically at every
// level (a closed chain is a loop: its last vertex equals its first).
//
// Long pieces are mounted per piece, not per tile: a long piece is wanted when its bounding box
// intersects the request rectangle (`RailPackLevel.longPieces`), and its mount key is
// `RailPackMountKey.longPiece`. A normal piece is wanted when its home tile lies in the request
// rectangle grown by half a tile (mount key `RailPackMountKey.tile`).
//
// Tile geometry: a tile is 1,024 points square at the level, side in map points
// `1024 * mapPointsPerPoint`. A normal piece is stored relative to the centre of its home tile (the
// tile holding the centre of its bounding box) as Int16 in quanta of 1/16 point:
// `mapX = (tileX + 0.5) * side + x * mapPointsPerPoint / 16`. Tile coordinates are 16 bits, so the
// top level is z17 by format. A long piece's first vertex is stored in world quanta (Int32) in its
// longPieces row and the rest as Int16 deltas.

public enum RailPackFormat {
    public static let magic: [UInt8] = Array("JTRP".utf8)
    public static let formatVersion: UInt16 = 2

    public static let tilePoints = 1_024.0
    /// Quanta per point (1/16 point).
    public static let quantaPerPoint = 16.0
    /// Quanta across a tile: 16,384, so a tile centre sits at `tile * 16384 + 8192` world quanta.
    public static let tileQuanta = 16_384
    /// Largest stored magnitude of a normal vertex: half the Int16 range.
    public static let maxHomeTileQuanta = 16_384

    public static let noSpan: UInt16 = 0xFFFF
    /// `tileX` and `tileY` of a long piece.
    public static let longPieceTile: UInt16 = 0xFFFF
    /// Largest home tile coordinate of a normal piece (0xFFFF is the long sentinel).
    public static let maxHomeTile = 65_534
    public static let noNode: UInt32 = 0xFFFF_FFFF
    /// `pieceInChain` and `vertex` of a nodes row without a slot.
    public static let noNodeSlot: UInt16 = 0xFFFF
    public static let tierNoUpperLimit: Int16 = 0x7FFF
    public static let tierNeverDrawn: Int16 = 0x7FFF
    /// Top bit of a chains row's count word: the chain is closed (a loop).
    public static let closedChainFlag: UInt32 = 0x8000_0000
    public static let chainCountMask: UInt32 = 0x7FFF_FFFF
    /// Most pieces one chain may hold (a nodes row stores the piece's index in its chain as u16).
    public static let maxPiecesPerChain = 65_535
    /// Top bit of a pieces row's count word: the first vertex is the previous piece's last vertex.
    public static let joinsPreviousFlag: UInt16 = 0x8000
    public static let pieceVertexCountMask: UInt16 = 0x7FFF
    public static let maxPieceVertices = 32_767
    /// Top bit of a lines row's chain-count word: the line's chains are independent parts (branches or
    /// lane fragments), not one sequence, so a trip never spans two of them (`vertexRanges` throws).
    public static let independentPartsFlag: UInt16 = 0x8000
    public static let lineChainCountMask: UInt16 = 0x7FFF
    /// Accepted `mapPointsPerPoint` range: keeps tile maths inside Int.
    public static let minMapPointsPerPoint = 0.25
    public static let maxMapPointsPerPoint = 1_048_576.0
    /// Adjacent ladder levels must differ by at least this much zoom.
    public static let minZoomGap = 0.01
    /// Query rectangles are clamped to this tile magnitude before they are clamped to the stored range.
    public static let tileCoordinateLimit = 2_147_483_647.0

    public enum StyleClass: UInt8, Sendable { case solid = 0, historicalDashed = 1, withheldDashed = 2 }

    // Header
    public static let headerSize = 100
    public static let sectionEntrySize = 16
    public static let regionSectionCount = 5
    public static let offsetFileLength = 92

    // Region sections, in section-table order.
    public enum Region: Int, CaseIterable, Sendable { case lines = 0, groups, spans, nodeChains, levels }

    // Row sizes.
    public static let lineRow = 12
    public static let groupRow = 16
    public static let spanRow = 8
    public static let nodeChainRow = 4
    public static let levelRow = 84

    /// Per-level arrays, in file order.
    public enum ArrayKind: Int, CaseIterable, Sendable {
        case pieces = 0, chains, nodes, vertices, longPieces, longVertices

        public var rowSize: Int {
            switch self {
            case .pieces: return 8
            case .chains, .nodes, .vertices, .longVertices: return 4
            case .longPieces: return 28
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

    /// World quanta of a normal vertex stored as `q` relative to `tile`'s centre.
    @inline(__always)
    public static func worldQuanta(_ q: Int, tile: Int) -> Int { tile * tileQuanta + tileQuanta / 2 + q }

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
    /// The chains are the parts of a non-continuous line: each is its own piece of track and the
    /// file order of the chains says nothing about which are neighbours. Stored in the top bit of the
    /// row's chain count (so a line holds at most 32,767 chains).
    public var independentParts: Bool
    public init(firstChain: UInt32, chainCount: UInt16, firstNode: UInt32, nodeCount: UInt16, independentParts: Bool = false) {
        self.firstChain = firstChain; self.chainCount = chainCount
        self.firstNode = firstNode; self.nodeCount = nodeCount
        self.independentParts = independentParts
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
    /// Index into spans; `noSpan` for undated. Every piece of a group shares it.
    public var span: UInt16
    public init(colourLight: UInt32, colourDark: UInt32, tierMin: Int16, tierMax: Int16, styleClass: UInt8, category: UInt8,
                span: UInt16 = RailPackFormat.noSpan) {
        self.colourLight = colourLight; self.colourDark = colourDark
        self.tierMin = tierMin; self.tierMax = tierMax
        self.styleClass = styleClass; self.category = category; self.span = span
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
    /// Home tile; both `longPieceTile` for a long piece.
    public var tileX: UInt16
    public var tileY: UInt16
    /// Vertex count of the piece (the flag bit removed).
    public var vertexCount: UInt16
    /// The first vertex is the previous piece's last vertex and takes that piece's tile.
    public var joinsPrevious: Bool
    public var group: UInt16
    public var isLong: Bool { tileX == RailPackFormat.longPieceTile && tileY == RailPackFormat.longPieceTile }
}

/// A home tile of a level.
public struct RailPackTile: Hashable, Comparable, Sendable {
    public var x: Int
    public var y: Int
    public init(x: Int, y: Int) { self.x = x; self.y = y }
    public static func < (a: RailPackTile, b: RailPackTile) -> Bool { a.y != b.y ? a.y < b.y : a.x < b.x }
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
    /// The piece's first vertex in level quanta from the world origin.
    public var firstX: Int32, firstY: Int32
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
