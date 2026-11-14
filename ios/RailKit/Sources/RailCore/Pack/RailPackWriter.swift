import Foundation

// MARK: - Writer input

/// One piece of a chain at one level, in map points (MapKit's `MKMapPoint` space).
public struct RailPackPieceSource: Sendable {
    /// Region-wide chain index. Pieces must be given sorted by chain, in position order inside a chain.
    public var chain: Int
    public var group: UInt16
    /// A dashed run that is never cut: stored as a first vertex plus Int16 deltas.
    public var isLong: Bool
    public var vertices: [RailPackPoint]
    public init(chain: Int, group: UInt16, isLong: Bool = false, vertices: [RailPackPoint]) {
        self.chain = chain; self.group = group; self.isLong = isLong; self.vertices = vertices
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
    public init(regionCode: String, displaySHA256: [UInt8], inputsSHA256: [UInt8],
                chainCount: Int, nodeCount: Int, lines: [RailPackLine], groups: [RailPackGroup],
                spans: [RailPackSpan], levels: [RailPackLevelSource], closedChains: Set<Int> = []) {
        self.closedChains = closedChains
        self.regionCode = regionCode
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

        // The chain of every node, region-wide; a node's chain must be the same at every level that
        // gives it a slot.
        var nodeChains = [UInt32](repeating: RailPackFormat.noNode, count: source.nodeCount)
        for (index, level) in levels.enumerated() {
            for (node, chain) in level.nodeChains.enumerated() where chain != RailPackFormat.noNode {
                if nodeChains[node] == RailPackFormat.noNode { nodeChains[node] = chain }
                else if nodeChains[node] != chain {
                    throw RailPackError.invalidInput("node \(node): chain differs at level \(index)")
                }
            }
        }

        var lines = ByteSink(), groups = ByteSink(), spans = ByteSink(), nodeChainBytes = ByteSink()
        for line in source.lines {
            lines.u32(line.firstChain); lines.u16(line.chainCount | (line.independentParts ? RailPackFormat.independentPartsFlag : 0)); lines.u32(line.firstNode); lines.u16(line.nodeCount)
        }
        for group in source.groups {
            groups.u32(group.colourLight); groups.u32(group.colourDark)
            groups.i16(group.tierMin); groups.i16(group.tierMax)
            groups.u8(group.styleClass); groups.u8(group.category); groups.u16(group.span)
        }
        for span in source.spans { spans.i32(span.fromDay); spans.i32(span.toDay) }
        for chain in nodeChains { nodeChainBytes.u32(chain) }

        let sectionCount = RailPackFormat.regionSectionCount + levels.count
        let regionStart = RailPackFormat.headerSize + sectionCount * RailPackFormat.sectionEntrySize
        var offset = regionStart
        var sections: [(Int, Int)] = []
        let levelsTableSize = levels.count * RailPackFormat.levelRow
        for length in [lines.bytes.count, groups.bytes.count, spans.bytes.count, nodeChainBytes.bytes.count, levelsTableSize] {
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
        out.u8(0)
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
        out.bytes.append(contentsOf: nodeChainBytes.bytes)
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
        for group in s.groups where group.span != RailPackFormat.noSpan && Int(group.span) >= s.spans.count {
            throw RailPackError.invalidInput("group span out of range")
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
        /// Chain of each node at this level, `noNode` for a node without a slot.
        var nodeChains: [UInt32]
    }

    private static func encodeLevel(_ level: RailPackLevelSource, index: Int, source: RailPackSource) throws -> EncodedLevel {
        let mpp = level.mapPointsPerPoint
        let side = RailPackFormat.tileSide(mapPointsPerPoint: mpp)
        let quantum = RailPackFormat.quantum(mapPointsPerPoint: mpp)
        guard level.nodes.count == source.nodeCount else { throw RailPackError.invalidInput("level \(index): nodes.count != nodeCount") }
        guard level.pieces.count < Int(RailPackFormat.noNode) else { throw RailPackError.valueTooLarge("piece count") }

        var pieces = ByteSink(), vertexBytes = ByteSink(), longVertexBytes = ByteSink(), longRows = ByteSink()
        var vertexTotal = 0, longTotal = 0
        /// The previous piece's home tile and last vertex in world quanta; nil after a long piece or a chain start.
        var previous: (chain: Int, tileX: Int, tileY: Int, lastX: Int, lastY: Int)?

        var lastChain = 0
        for (pieceIndex, piece) in level.pieces.enumerated() {
            guard piece.chain >= 0, piece.chain < source.chainCount else { throw RailPackError.invalidInput("piece \(pieceIndex): chain out of range") }
            guard piece.chain >= lastChain else { throw RailPackError.invalidInput("pieces not sorted by chain") }
            lastChain = piece.chain
            guard Int(piece.group) < source.groups.count else { throw RailPackError.invalidInput("piece \(pieceIndex): group out of range") }
            guard piece.vertices.count >= 2 else { throw RailPackError.valueTooLarge("piece \(pieceIndex) vertex count") }
            guard piece.vertices.count <= RailPackFormat.maxPieceVertices else { throw RailPackError.valueTooLarge("piece \(pieceIndex) vertex count") }
            guard piece.vertices.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { throw RailPackError.invalidInput("piece \(pieceIndex): non-finite vertex") }
            if piece.isLong {
                var minX = Int32.max, minY = Int32.max, maxX = Int32.min, maxY = Int32.min
                var previousQuanta: (Int, Int)?
                var first: (Int32, Int32) = (0, 0)
                for v in piece.vertices {
                    let qx = (v.x / quantum).rounded(), qy = (v.y / quantum).rounded()
                    guard abs(qx) <= Double(Int32.max), abs(qy) <= Double(Int32.max) else { throw RailPackError.valueTooLarge("long vertex") }
                    let q = (Int(qx), Int(qy))
                    if let p = previousQuanta {
                        guard abs(q.0 - p.0) <= Int(Int16.max), abs(q.1 - p.1) <= Int(Int16.max) else {
                            throw RailPackError.valueTooLarge("long piece step in piece \(pieceIndex)")
                        }
                        longVertexBytes.i16(Int16(q.0 - p.0)); longVertexBytes.i16(Int16(q.1 - p.1))
                    } else {
                        first = (Int32(q.0), Int32(q.1))
                    }
                    previousQuanta = q
                    minX = min(minX, Int32(qx)); maxX = max(maxX, Int32(qx))
                    minY = min(minY, Int32(qy)); maxY = max(maxY, Int32(qy))
                }
                longRows.u32(UInt32(pieceIndex)); longRows.i32(minX); longRows.i32(minY); longRows.i32(maxX); longRows.i32(maxY)
                longRows.i32(first.0); longRows.i32(first.1)
                longTotal += piece.vertices.count - 1
                pieces.u16(RailPackFormat.longPieceTile); pieces.u16(RailPackFormat.longPieceTile)
                pieces.u16(UInt16(piece.vertices.count)); pieces.u16(piece.group)
                previous = nil
            } else {
                let xs = piece.vertices.map(\.x), ys = piece.vertices.map(\.y)
                let cx = (xs.min()! + xs.max()!) / 2, cy = (ys.min()! + ys.max()!) / 2
                let homeX = RailPackFormat.tile(containing: cx, mapPointsPerPoint: mpp)
                let homeY = RailPackFormat.tile(containing: cy, mapPointsPerPoint: mpp)
                guard (0...RailPackFormat.maxHomeTile).contains(homeX), (0...RailPackFormat.maxHomeTile).contains(homeY) else {
                    throw RailPackError.valueTooLarge("piece \(pieceIndex) home tile")
                }
                var quanta: [(Int, Int)] = []
                for v in piece.vertices {
                    let qx = ((v.x - (Double(homeX) + 0.5) * side) / quantum).rounded()
                    let qy = ((v.y - (Double(homeY) + 0.5) * side) / quantum).rounded()
                    quanta.append((Int(max(min(qx, 1e9), -1e9)), Int(max(min(qy, 1e9), -1e9))))
                }
                // The first vertex is not stored when it equals the previous piece's last vertex in world quanta.
                var joins = false
                if let p = previous, p.chain == piece.chain,
                   RailPackFormat.worldQuanta(quanta[0].0, tile: homeX) == p.lastX,
                   RailPackFormat.worldQuanta(quanta[0].1, tile: homeY) == p.lastY {
                    joins = true
                }
                for (offset, q) in quanta.enumerated() where !(joins && offset == 0) {
                    guard abs(q.0) <= RailPackFormat.maxHomeTileQuanta, abs(q.1) <= RailPackFormat.maxHomeTileQuanta else {
                        throw RailPackError.pieceOutsideHomeTile(level: index, piece: pieceIndex)
                    }
                    vertexBytes.i16(Int16(q.0)); vertexBytes.i16(Int16(q.1))
                }
                vertexTotal += piece.vertices.count - (joins ? 1 : 0)
                pieces.u16(UInt16(homeX)); pieces.u16(UInt16(homeY))
                pieces.u16(UInt16(piece.vertices.count) | (joins ? RailPackFormat.joinsPreviousFlag : 0)); pieces.u16(piece.group)
                let last = quanta[quanta.count - 1]
                previous = (piece.chain, homeX, homeY,
                            RailPackFormat.worldQuanta(last.0, tile: homeX), RailPackFormat.worldQuanta(last.1, tile: homeY))
            }
        }
        guard vertexTotal < Int(UInt32.max), longTotal < Int(UInt32.max) else { throw RailPackError.valueTooLarge("vertex total") }

        // Chains: piece counts only; the first piece is the running sum.
        var chains = ByteSink()
        var chainFirst = [Int](repeating: 0, count: source.chainCount)
        var cursor = 0
        for chain in 0..<source.chainCount {
            let first = cursor
            chainFirst[chain] = first
            while cursor < level.pieces.count && level.pieces[cursor].chain == chain { cursor += 1 }
            guard cursor - first <= RailPackFormat.maxPiecesPerChain else { throw RailPackError.valueTooLarge("chain piece count") }
            chains.u32(UInt32(cursor - first) | (source.closedChains.contains(chain) ? RailPackFormat.closedChainFlag : 0))
        }

        // Node slots, as the piece's index within its chain.
        var nodes = ByteSink()
        var nodeChains = [UInt32](repeating: RailPackFormat.noNode, count: level.nodes.count)
        for (node, slot) in level.nodes.enumerated() {
            if slot.isNone {
                nodes.u16(RailPackFormat.noNodeSlot); nodes.u16(RailPackFormat.noNodeSlot)
                continue
            }
            guard Int(slot.piece) < level.pieces.count, Int(slot.vertex) < level.pieces[Int(slot.piece)].vertices.count else {
                throw RailPackError.invalidInput("node \(node): slot out of range")
            }
            let chain = level.pieces[Int(slot.piece)].chain
            nodeChains[node] = UInt32(chain)
            nodes.u16(UInt16(Int(slot.piece) - chainFirst[chain])); nodes.u16(slot.vertex)
        }

        return EncodedLevel(mapPointsPerPoint: mpp, laneBucket: level.laneBucket, arrayBytes: [
            pieces.bytes, chains.bytes, nodes.bytes, vertexBytes.bytes, longRows.bytes, longVertexBytes.bytes,
        ], nodeChains: nodeChains)
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
