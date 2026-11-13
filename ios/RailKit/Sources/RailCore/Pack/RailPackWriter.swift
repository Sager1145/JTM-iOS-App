import Foundation

// MARK: - Writer input

/// One piece of a chain at one level, in map points (MapKit's `MKMapPoint` space).
public struct RailPackPieceSource: Sendable {
    /// Region-wide chain index. Pieces must be given sorted by chain, in position order inside a chain.
    public var chain: Int
    public var group: UInt16
    public var span: UInt16
    public var flags: UInt16
    /// A dashed run that is never cut: stored as Int32 quanta in `longVertices`.
    public var isLong: Bool
    public var vertices: [RailPackPoint]
    public init(chain: Int, group: UInt16, span: UInt16 = RailPackFormat.noSpan, flags: UInt16 = 0, isLong: Bool = false, vertices: [RailPackPoint]) {
        self.chain = chain; self.group = group; self.span = span
        self.flags = flags; self.isLong = isLong; self.vertices = vertices
    }
}

public struct RailPackLevelSource: Sendable {
    public var mapPointsPerPoint: Double
    public var laneBucket: UInt8
    /// Sorted by chain index; the index in this array is the piece index.
    public var pieces: [RailPackPieceSource]
    /// One entry per global node index (`RailPackNodeSlot.none` when the node has no chain slot).
    public var nodes: [RailPackNodeSlot]
    public init(mapPointsPerPoint: Double, laneBucket: UInt8, pieces: [RailPackPieceSource], nodes: [RailPackNodeSlot]) {
        self.mapPointsPerPoint = mapPointsPerPoint; self.laneBucket = laneBucket
        self.pieces = pieces; self.nodes = nodes
    }
}

public struct RailPackSource: Sendable {
    public var datum: RailPackFormat.Datum
    /// Two ASCII characters, for example "jp".
    public var regionCode: String
    public var displaySHA256: [UInt8]
    public var inputsSHA256: [UInt8]
    public var chainCount: Int
    public var nodeCount: Int
    public var lines: [RailPackLine]
    public var groups: [RailPackGroup]
    public var spans: [RailPackSpan]
    public var levels: [RailPackLevelSource]
    /// Chain indices that are closed loops (flag written to every level's chains rows).
    public var closedChains: Set<Int>
    public init(datum: RailPackFormat.Datum, regionCode: String, displaySHA256: [UInt8], inputsSHA256: [UInt8],
                chainCount: Int, nodeCount: Int, lines: [RailPackLine], groups: [RailPackGroup],
                spans: [RailPackSpan], levels: [RailPackLevelSource], closedChains: Set<Int> = []) {
        self.closedChains = closedChains
        self.datum = datum; self.regionCode = regionCode
        self.displaySHA256 = displaySHA256; self.inputsSHA256 = inputsSHA256
        self.chainCount = chainCount; self.nodeCount = nodeCount
        self.lines = lines; self.groups = groups; self.spans = spans; self.levels = levels
    }
}

// MARK: - Writer

/// Writes the `.railpack` bytes. Pure and deterministic: the same source gives the same
/// bytes (no clocks, no hash-order iteration, reserved fields zero).
public enum RailPackWriter {
    public static func write(_ source: RailPackSource) throws -> Data {
        try validateRegion(source)
        let levels = try source.levels.enumerated().map { try encodeLevel($0.element, index: $0.offset, source: source) }

        var lines = ByteSink(), groups = ByteSink(), spans = ByteSink()
        for line in source.lines {
            lines.u32(line.firstChain); lines.u16(line.chainCount | (line.independentParts ? RailPackFormat.independentPartsFlag : 0)); lines.u32(line.firstNode); lines.u16(line.nodeCount)
        }
        for group in source.groups {
            groups.u32(group.colourLight); groups.u32(group.colourDark)
            groups.i16(group.tierMin); groups.i16(group.tierMax)
            groups.u8(group.styleClass); groups.u8(group.category); groups.u16(0)
        }
        for span in source.spans { spans.i32(span.fromDay); spans.i32(span.toDay) }

        let sectionCount = RailPackFormat.regionSectionCount + levels.count
        let regionStart = RailPackFormat.headerSize + sectionCount * RailPackFormat.sectionEntrySize
        var offset = regionStart
        var sections: [(Int, Int)] = []
        let levelsTableSize = levels.count * RailPackFormat.levelRow
        for length in [lines.bytes.count, groups.bytes.count, spans.bytes.count, levelsTableSize] {
            sections.append((offset, length)); offset += length
        }
        var levelOffsets: [Int] = []
        for level in levels {
            levelOffsets.append(offset)
            sections.append((offset, level.arrayBytes.reduce(0) { $0 + $1.count }))
            offset += sections[sections.count - 1].1
        }
        let fileLength = offset

        var out = ByteSink()
        out.bytes.reserveCapacity(fileLength)
        out.bytes.append(contentsOf: RailPackFormat.magic)
        out.u16(RailPackFormat.formatVersion)
        out.u8(source.datum.rawValue)
        out.bytes.append(contentsOf: Array(source.regionCode.utf8))
        out.u8(0)
        out.u16(UInt16(levels.count)); out.u16(UInt16(source.lines.count))
        out.u16(UInt16(source.groups.count)); out.u16(UInt16(source.spans.count)); out.u16(0)
        out.u32(UInt32(source.chainCount)); out.u32(UInt32(source.nodeCount))
        out.bytes.append(contentsOf: source.displaySHA256)
        out.bytes.append(contentsOf: source.inputsSHA256)
        out.u64(UInt64(fileLength))
        for (sectionOffset, length) in sections { out.u64(UInt64(sectionOffset)); out.u64(UInt64(length)) }
        out.bytes.append(contentsOf: lines.bytes)
        out.bytes.append(contentsOf: groups.bytes)
        out.bytes.append(contentsOf: spans.bytes)
        for (index, level) in levels.enumerated() {
            out.f64(level.mapPointsPerPoint); out.u8(level.laneBucket); out.u8(0); out.u16(0)
            var arrayOffset = levelOffsets[index]
            for (kind, bytes) in zip(RailPackFormat.ArrayKind.allCases, level.arrayBytes) {
                out.u32(UInt32(bytes.count / kind.rowSize)); out.u64(UInt64(arrayOffset))
                arrayOffset += bytes.count
            }
        }
        for level in levels { for bytes in level.arrayBytes { out.bytes.append(contentsOf: bytes) } }
        assert(out.bytes.count == fileLength)
        return Data(out.bytes)
    }

    // MARK: Validation

    private static func validateRegion(_ s: RailPackSource) throws {
        guard s.regionCode.utf8.count == 2, s.regionCode.utf8.allSatisfy({ $0 < 0x80 }) else {
            throw RailPackError.invalidInput("regionCode must be two ASCII characters")
        }
        guard s.displaySHA256.count == 32, s.inputsSHA256.count == 32 else { throw RailPackError.invalidInput("SHA256 must be 32 bytes") }
        guard s.levels.count <= Int(UInt16.max), s.lines.count <= Int(UInt16.max),
              s.groups.count <= Int(UInt16.max), s.spans.count < Int(RailPackFormat.noSpan) else {
            throw RailPackError.valueTooLarge("level, line, group or span count")
        }
        guard s.chainCount >= 0, s.chainCount <= Int(UInt32.max), s.nodeCount >= 0, s.nodeCount < Int(RailPackFormat.noNode) else {
            throw RailPackError.valueTooLarge("chain or node count")
        }
        for line in s.lines {
            guard line.chainCount <= RailPackFormat.lineChainCountMask else { throw RailPackError.valueTooLarge("line chain count") }
            guard Int(line.firstChain) + Int(line.chainCount) <= s.chainCount,
                  Int(line.firstNode) + Int(line.nodeCount) <= s.nodeCount else {
                throw RailPackError.invalidInput("line refers beyond chain or node count")
            }
        }
        for group in s.groups where group.tierMin > group.tierMax && group.tierMin != RailPackFormat.tierNeverDrawn {
            throw RailPackError.invalidInput("group tierMin above tierMax")
        }
        for span in s.spans where span.fromDay > span.toDay { throw RailPackError.invalidInput("span from after to") }
        guard s.closedChains.allSatisfy({ $0 >= 0 && $0 < s.chainCount }) else { throw RailPackError.invalidInput("closed chain out of range") }
        var previous = Double.infinity
        for level in s.levels {
            guard level.mapPointsPerPoint.isFinite,
                  level.mapPointsPerPoint >= RailPackFormat.minMapPointsPerPoint,
                  level.mapPointsPerPoint <= RailPackFormat.maxMapPointsPerPoint else { throw RailPackError.invalidInput("mapPointsPerPoint") }
            // Levels run from the lowest zoom to the highest: mapPointsPerPoint strictly descending.
            guard level.mapPointsPerPoint < previous else { throw RailPackError.invalidInput("levels not in ascending zoom order") }
            previous = level.mapPointsPerPoint
        }
        do { _ = try RailPackLadder(mapPointsPerPoint: s.levels.map(\.mapPointsPerPoint)) } catch {
            if s.levels.isEmpty { return }
            throw RailPackError.invalidInput("levels closer than \(RailPackFormat.minZoomGap) zoom")
        }
    }

    // MARK: Level encoding

    private struct EncodedLevel {
        var mapPointsPerPoint: Double
        var laneBucket: UInt8
        /// Bytes of each array in `ArrayKind` order.
        var arrayBytes: [[UInt8]]
    }

    private struct TileKey: Hashable, Comparable {
        var x: Int, y: Int
        static func < (a: TileKey, b: TileKey) -> Bool { a.y != b.y ? a.y < b.y : a.x < b.x }
    }

    private static func encodeLevel(_ level: RailPackLevelSource, index: Int, source: RailPackSource) throws -> EncodedLevel {
        let mpp = level.mapPointsPerPoint
        let side = RailPackFormat.tileSide(mapPointsPerPoint: mpp)
        let quantum = RailPackFormat.quantum(mapPointsPerPoint: mpp)
        guard level.nodes.count == source.nodeCount else { throw RailPackError.invalidInput("level \(index): nodes.count != nodeCount") }
        guard level.pieces.count < Int(RailPackFormat.noNode) else { throw RailPackError.valueTooLarge("piece count") }

        // Per piece: home tile, quantised vertices.
        var homes = [TileKey?](repeating: nil, count: level.pieces.count)
        var vertexBytes = ByteSink(), longVertexBytes = ByteSink()
        var vertexTotal = 0, longTotal = 0
        var starts = [UInt32](repeating: 0, count: level.pieces.count)
        var longRows = ByteSink()
        /// Stored quanta per piece, so node tiles use exactly what a reader decodes.
        var storedQuanta: [[(Int, Int)]] = Array(repeating: [], count: level.pieces.count)

        var lastChain = 0
        for (pieceIndex, piece) in level.pieces.enumerated() {
            guard piece.chain >= 0, piece.chain < source.chainCount else { throw RailPackError.invalidInput("piece \(pieceIndex): chain out of range") }
            guard piece.chain >= lastChain else { throw RailPackError.invalidInput("pieces not sorted by chain") }
            lastChain = piece.chain
            guard Int(piece.group) < source.groups.count else { throw RailPackError.invalidInput("piece \(pieceIndex): group out of range") }
            guard piece.span == RailPackFormat.noSpan || Int(piece.span) < source.spans.count else { throw RailPackError.invalidInput("piece \(pieceIndex): span out of range") }
            guard piece.vertices.count >= 2, piece.vertices.count <= Int(UInt16.max) else { throw RailPackError.valueTooLarge("piece \(pieceIndex) vertex count") }
            guard piece.vertices.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { throw RailPackError.invalidInput("piece \(pieceIndex): non-finite vertex") }
            if piece.isLong {
                var minX = Int32.max, minY = Int32.max, maxX = Int32.min, maxY = Int32.min
                starts[pieceIndex] = UInt32(longTotal)
                var quanta: [(Int, Int)] = []
                for v in piece.vertices {
                    let qx = (v.x / quantum).rounded(), qy = (v.y / quantum).rounded()
                    guard abs(qx) <= Double(Int32.max), abs(qy) <= Double(Int32.max) else { throw RailPackError.valueTooLarge("long vertex") }
                    longVertexBytes.i32(Int32(qx)); longVertexBytes.i32(Int32(qy))
                    minX = min(minX, Int32(qx)); maxX = max(maxX, Int32(qx))
                    minY = min(minY, Int32(qy)); maxY = max(maxY, Int32(qy))
                    quanta.append((Int(qx), Int(qy)))
                }
                storedQuanta[pieceIndex] = quanta
                longRows.u32(UInt32(pieceIndex)); longRows.i32(minX); longRows.i32(minY); longRows.i32(maxX); longRows.i32(maxY)
                longTotal += piece.vertices.count
            } else {
                let xs = piece.vertices.map(\.x), ys = piece.vertices.map(\.y)
                let cx = (xs.min()! + xs.max()!) / 2, cy = (ys.min()! + ys.max()!) / 2
                let home = TileKey(x: RailPackFormat.tile(containing: cx, mapPointsPerPoint: mpp),
                                   y: RailPackFormat.tile(containing: cy, mapPointsPerPoint: mpp))
                homes[pieceIndex] = home
                starts[pieceIndex] = UInt32(vertexTotal)
                var quanta: [(Int, Int)] = []
                for v in piece.vertices {
                    let qx = ((v.x - (Double(home.x) + 0.5) * side) / quantum).rounded()
                    let qy = ((v.y - (Double(home.y) + 0.5) * side) / quantum).rounded()
                    guard abs(qx) <= Double(RailPackFormat.maxHomeTileQuanta), abs(qy) <= Double(RailPackFormat.maxHomeTileQuanta) else {
                        throw RailPackError.pieceOutsideHomeTile(level: index, piece: pieceIndex)
                    }
                    vertexBytes.i16(Int16(qx)); vertexBytes.i16(Int16(qy))
                    quanta.append((Int(qx), Int(qy)))
                }
                storedQuanta[pieceIndex] = quanta
                vertexTotal += piece.vertices.count
            }
        }
        guard vertexTotal < Int(UInt32.max), longTotal < Int(UInt32.max) else { throw RailPackError.valueTooLarge("vertex total") }

        // Node slots and the tile each node's stored vertex lies in.
        var nodeTiles = [TileKey?](repeating: nil, count: level.nodes.count)
        for (node, slot) in level.nodes.enumerated() where !slot.isNone {
            guard Int(slot.piece) < level.pieces.count, Int(slot.vertex) < level.pieces[Int(slot.piece)].vertices.count else {
                throw RailPackError.invalidInput("node \(node): slot out of range")
            }
            let p = Int(slot.piece)
            let (qx, qy) = storedQuanta[p][Int(slot.vertex)]
            let mapX: Double, mapY: Double
            if let home = homes[p] {
                mapX = RailPackFormat.decode(qx, tile: home.x, mapPointsPerPoint: mpp)
                mapY = RailPackFormat.decode(qy, tile: home.y, mapPointsPerPoint: mpp)
            } else {
                mapX = RailPackFormat.decodeLong(qx, mapPointsPerPoint: mpp)
                mapY = RailPackFormat.decodeLong(qy, mapPointsPerPoint: mpp)
            }
            nodeTiles[node] = TileKey(x: RailPackFormat.tile(containing: mapX, mapPointsPerPoint: mpp),
                                      y: RailPackFormat.tile(containing: mapY, mapPointsPerPoint: mpp))
        }

        // Tile directory: every home tile and every node tile, sorted by (y, x).
        var keySet = Set<TileKey>()
        for case let home? in homes { keySet.insert(home) }
        for case let tile? in nodeTiles { keySet.insert(tile) }
        let keys = keySet.sorted()
        var tileIndex: [TileKey: Int] = [:]
        for (i, key) in keys.enumerated() { tileIndex[key] = i }
        var piecesByTile = [[Int]](repeating: [], count: keys.count)
        var nodesByTile = [[Int]](repeating: [], count: keys.count)
        for (pieceIndex, home) in homes.enumerated() {
            if let home { piecesByTile[tileIndex[home]!].append(pieceIndex) }
        }
        for (node, tile) in nodeTiles.enumerated() {
            if let tile { nodesByTile[tileIndex[tile]!].append(node) }  // ascending by construction
        }
        for i in piecesByTile.indices {
            piecesByTile[i].sort { a, b in
                let ga = level.pieces[a].group, gb = level.pieces[b].group
                return ga != gb ? ga < gb : a < b
            }
        }
        var tileDir = ByteSink(), tilePieces = ByteSink(), tileNodes = ByteSink()
        var pieceCursor = 0, nodeCursor = 0
        for (i, key) in keys.enumerated() {
            guard piecesByTile[i].count <= Int(UInt16.max), nodesByTile[i].count <= Int(UInt16.max) else {
                throw RailPackError.valueTooLarge("tile \(key.x),\(key.y) piece or node count")
            }
            guard abs(key.x) < Int(Int32.max), abs(key.y) < Int(Int32.max) else { throw RailPackError.valueTooLarge("tile coordinate") }
            tileDir.i32(Int32(key.x)); tileDir.i32(Int32(key.y))
            tileDir.u32(UInt32(pieceCursor)); tileDir.u16(UInt16(piecesByTile[i].count))
            tileDir.u16(UInt16(nodesByTile[i].count)); tileDir.u32(UInt32(nodeCursor))
            for piece in piecesByTile[i] { tilePieces.u32(UInt32(piece)) }
            for node in nodesByTile[i] { tileNodes.u32(UInt32(node)) }
            pieceCursor += piecesByTile[i].count; nodeCursor += nodesByTile[i].count
        }

        // Pieces and chains.
        var pieces = ByteSink()
        for (pieceIndex, piece) in level.pieces.enumerated() {
            pieces.u32(homes[pieceIndex].map { UInt32(tileIndex[$0]!) } ?? RailPackFormat.longPieceTile)
            pieces.u32(starts[pieceIndex]); pieces.u16(UInt16(piece.vertices.count))
            pieces.u16(piece.group); pieces.u16(piece.span); pieces.u16(piece.flags)
        }
        var chains = ByteSink()
        var cursor = 0
        for chain in 0..<source.chainCount {
            let first = cursor
            while cursor < level.pieces.count && level.pieces[cursor].chain == chain { cursor += 1 }
            guard cursor - first <= Int(RailPackFormat.chainCountMask) else { throw RailPackError.valueTooLarge("chain piece count") }
            chains.u32(UInt32(first))
            chains.u32(UInt32(cursor - first) | (source.closedChains.contains(chain) ? RailPackFormat.closedChainFlag : 0))
        }
        var nodes = ByteSink()
        for slot in level.nodes { nodes.u32(slot.piece); nodes.u16(slot.vertex); nodes.u16(0) }

        return EncodedLevel(mapPointsPerPoint: mpp, laneBucket: level.laneBucket, arrayBytes: [
            tileDir.bytes, tilePieces.bytes, tileNodes.bytes, pieces.bytes, chains.bytes,
            nodes.bytes, vertexBytes.bytes, longRows.bytes, longVertexBytes.bytes,
        ])
    }
}

// MARK: - Little-endian byte sink

struct ByteSink {
    var bytes: [UInt8] = []
    mutating func u8(_ v: UInt8) { bytes.append(v) }
    mutating func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { bytes.append(contentsOf: $0) } }
    mutating func i16(_ v: Int16) { u16(UInt16(bitPattern: v)) }
    mutating func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { bytes.append(contentsOf: $0) } }
    mutating func i32(_ v: Int32) { u32(UInt32(bitPattern: v)) }
    mutating func u64(_ v: UInt64) { withUnsafeBytes(of: v.littleEndian) { bytes.append(contentsOf: $0) } }
    mutating func f64(_ v: Double) { u64(v.bitPattern) }
}
