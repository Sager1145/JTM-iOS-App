import Foundation

/// Read-only, zero-copy view of a `.railpack` file.
///
/// Opening checks the header, the section table and every per-level array against the
/// file length, so afterwards no accessor can read outside the file. Nothing is decoded
/// into objects: each accessor reads fixed-width rows out of the mapped bytes.
/// ``validateContents()`` additionally checks every cross reference (it touches every
/// page, so it is for tests, bakes and guards, not for app launch).
public struct RailPackReader: Sendable {
    public struct Header: Equatable, Sendable {
        public var formatVersion: UInt16
        public var datum: RailPackFormat.Datum
        public var regionCode: String
        public var levelCount: Int
        public var lineCount: Int
        public var groupCount: Int
        public var spanCount: Int
        public var chainCount: Int
        public var nodeCount: Int
        public var displaySHA256: [UInt8]
        public var inputsSHA256: [UInt8]
        public var fileLength: Int
    }

    public struct LevelInfo: Equatable, Sendable {
        public var mapPointsPerPoint: Double
        public var laneBucket: UInt8
        /// Section of the level's arrays.
        public var sectionOffset: Int
        public var sectionLength: Int
        /// `(count, offset)` per array in `ArrayKind` order.
        var arrays: [(count: Int, offset: Int)]
        public func count(_ kind: RailPackFormat.ArrayKind) -> Int { arrays[kind.rawValue].count }
        public static func == (a: LevelInfo, b: LevelInfo) -> Bool {
            a.mapPointsPerPoint == b.mapPointsPerPoint && a.laneBucket == b.laneBucket
                && a.sectionOffset == b.sectionOffset && a.sectionLength == b.sectionLength
                && a.arrays.elementsEqual(b.arrays) { $0 == $1 }
        }
    }

    public let header: Header
    public let levels: [LevelInfo]
    public let ladder: RailPackLadder
    /// The file's bytes, normally `Data(contentsOf:options: .alwaysMapped)`.
    public let data: Data
    private let regionSections: [(offset: Int, length: Int)]

    /// Opens a file from bytes; throws a typed ``RailPackError`` for any structural defect.
    public init(data: Data) throws {
        let size = RailPackFormat.headerSize
        guard data.count >= size else { throw RailPackError.truncated }
        let parsed: (Header, [(Int, Int)], [LevelInfo]) = try data.withUnsafeBytes { raw in
            guard Array(raw[0..<4]) == RailPackFormat.magic else { throw RailPackError.badMagic }
            let version = raw.loadUnaligned(fromByteOffset: 4, as: UInt16.self).littleEndian
            guard version == RailPackFormat.formatVersion else { throw RailPackError.unsupportedVersion(version) }
            guard let datum = RailPackFormat.Datum(rawValue: raw[6]) else { throw RailPackError.corrupt("datum") }
            let region = String(decoding: raw[7..<9], as: UTF8.self)
            func u16(_ o: Int) -> Int { Int(raw.loadUnaligned(fromByteOffset: o, as: UInt16.self).littleEndian) }
            func u32(_ o: Int) -> Int { Int(raw.loadUnaligned(fromByteOffset: o, as: UInt32.self).littleEndian) }
            func u64(_ o: Int) -> UInt64 { raw.loadUnaligned(fromByteOffset: o, as: UInt64.self).littleEndian }
            let declared = u64(RailPackFormat.offsetFileLength)
            guard declared == UInt64(data.count) else {
                if declared > UInt64(data.count) { throw RailPackError.truncated }
                throw RailPackError.lengthMismatch(declared: declared, actual: data.count)
            }
            let header = Header(
                formatVersion: version, datum: datum, regionCode: region,
                levelCount: u16(10), lineCount: u16(12), groupCount: u16(14), spanCount: u16(16),
                chainCount: u32(20), nodeCount: u32(24),
                displaySHA256: Array(raw[28..<60]), inputsSHA256: Array(raw[60..<92]), fileLength: data.count)

            let sectionCount = RailPackFormat.regionSectionCount + header.levelCount
            let tableEnd = size + sectionCount * RailPackFormat.sectionEntrySize
            guard tableEnd <= data.count else { throw RailPackError.truncated }
            var sections: [(Int, Int)] = []
            for index in 0..<sectionCount {
                let base = size + index * RailPackFormat.sectionEntrySize
                let offset = u64(base), length = u64(base + 8)
                let name = index < RailPackFormat.regionSectionCount ? "region \(index)" : "level \(index - RailPackFormat.regionSectionCount)"
                guard offset >= UInt64(tableEnd), offset <= UInt64(data.count), length <= UInt64(data.count) - offset else {
                    throw RailPackError.sectionOutOfBounds(name)
                }
                sections.append((Int(offset), Int(length)))
            }
            let expected = [header.lineCount * RailPackFormat.lineRow, header.groupCount * RailPackFormat.groupRow,
                            header.spanCount * RailPackFormat.spanRow, header.levelCount * RailPackFormat.levelRow]
            for (index, length) in expected.enumerated() where sections[index].1 != length {
                throw RailPackError.sectionOutOfBounds("region \(index) length")
            }

            var levels: [LevelInfo] = []
            let levelTable = sections[RailPackFormat.Region.levels.rawValue].0
            for level in 0..<header.levelCount {
                let row = levelTable + level * RailPackFormat.levelRow
                let mpp = Double(bitPattern: u64(row))
                let previous = levels.last?.mapPointsPerPoint ?? Double.infinity
                guard mpp.isFinite, mpp >= RailPackFormat.minMapPointsPerPoint, mpp <= RailPackFormat.maxMapPointsPerPoint,
                      mpp < previous else {
                    throw RailPackError.badLevel(level)
                }
                let section = sections[RailPackFormat.regionSectionCount + level]
                var arrays: [(count: Int, offset: Int)] = []
                for kind in RailPackFormat.ArrayKind.allCases {
                    let entry = row + RailPackFormat.levelArraysOffset + kind.rawValue * RailPackFormat.levelArrayEntrySize
                    let count = u32(entry), offset = u64(entry + 4)
                    let bytes = UInt64(count) * UInt64(kind.rowSize)
                    guard offset >= UInt64(section.0), offset <= UInt64(section.0 + section.1),
                          bytes <= UInt64(section.0 + section.1) - offset else {
                        throw RailPackError.arrayOutOfBounds(level: level, array: "\(kind)")
                    }
                    arrays.append((count, Int(offset)))
                }
                // The tile directory must be strictly ascending by (tileY, tileX): lookups rely on it.
                let dirCount = arrays[RailPackFormat.ArrayKind.tileDir.rawValue].count
                let dirBase = arrays[RailPackFormat.ArrayKind.tileDir.rawValue].offset
                let dirRow = RailPackFormat.ArrayKind.tileDir.rowSize
                var previousKey: (Int32, Int32)?
                for t in 0..<dirCount {
                    let o = dirBase + t * dirRow
                    let x = Int32(bitPattern: UInt32(truncatingIfNeeded: u32(o))), y = Int32(bitPattern: UInt32(truncatingIfNeeded: u32(o + 4)))
                    if let previousKey, !(previousKey.1 < y || (previousKey.1 == y && previousKey.0 < x)) {
                        throw RailPackError.corrupt("level \(level) tile directory not sorted")
                    }
                    previousKey = (x, y)
                }
                levels.append(LevelInfo(mapPointsPerPoint: mpp, laneBucket: raw[row + 8],
                                        sectionOffset: section.0, sectionLength: section.1, arrays: arrays))
            }
            return (header, Array(sections[0..<RailPackFormat.regionSectionCount]), levels)
        }
        self.header = parsed.0
        self.regionSections = parsed.1.map { (offset: $0.0, length: $0.1) }
        self.levels = parsed.2
        self.ladder = try parsed.2.isEmpty ? RailPackLadder(zooms: [0]) : RailPackLadder(mapPointsPerPoint: parsed.2.map(\.mapPointsPerPoint))
        self.data = data
    }

    /// Opens `url` memory-mapped: no copy, no decode.
    public init(contentsOf url: URL) throws {
        try self.init(data: Data(contentsOf: url, options: .alwaysMapped))
    }

    // MARK: Raw access

    @inline(__always)
    private func read<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R { try data.withUnsafeBytes(body) }

    private func level(_ index: Int) throws -> LevelInfo {
        guard levels.indices.contains(index) else { throw RailPackError.indexOutOfRange("level \(index)") }
        return levels[index]
    }

    private func rowOffset(_ info: LevelInfo, _ kind: RailPackFormat.ArrayKind, _ row: Int) throws -> Int {
        guard row >= 0, row < info.arrays[kind.rawValue].count else { throw RailPackError.indexOutOfRange("\(kind) \(row)") }
        return info.arrays[kind.rawValue].offset + row * kind.rowSize
    }

    private func u16(_ raw: UnsafeRawBufferPointer, _ o: Int) -> UInt16 { raw.loadUnaligned(fromByteOffset: o, as: UInt16.self).littleEndian }
    private func i16(_ raw: UnsafeRawBufferPointer, _ o: Int) -> Int16 { Int16(bitPattern: u16(raw, o)) }
    private func u32(_ raw: UnsafeRawBufferPointer, _ o: Int) -> UInt32 { raw.loadUnaligned(fromByteOffset: o, as: UInt32.self).littleEndian }
    private func i32(_ raw: UnsafeRawBufferPointer, _ o: Int) -> Int32 { Int32(bitPattern: u32(raw, o)) }

    // MARK: Region tables

    public func line(_ index: Int) throws -> RailPackLine {
        guard index >= 0, index < header.lineCount else { throw RailPackError.indexOutOfRange("line \(index)") }
        let o = regionSections[RailPackFormat.Region.lines.rawValue].offset + index * RailPackFormat.lineRow
        return read { RailPackLine(firstChain: u32($0, o), chainCount: u16($0, o + 4), firstNode: u32($0, o + 6), nodeCount: u16($0, o + 10)) }
    }

    public func group(_ index: Int) throws -> RailPackGroup {
        guard index >= 0, index < header.groupCount else { throw RailPackError.indexOutOfRange("group \(index)") }
        let o = regionSections[RailPackFormat.Region.groups.rawValue].offset + index * RailPackFormat.groupRow
        return read {
            RailPackGroup(colourLight: u32($0, o), colourDark: u32($0, o + 4), tierMin: i16($0, o + 8), tierMax: i16($0, o + 10),
                          styleClass: $0[o + 12], category: $0[o + 13])
        }
    }

    /// The span at `index`; nil for `RailPackFormat.noSpan` (undated).
    public func span(_ index: UInt16) throws -> RailPackSpan? {
        if index == RailPackFormat.noSpan { return nil }
        guard Int(index) < header.spanCount else { throw RailPackError.indexOutOfRange("span \(index)") }
        let o = regionSections[RailPackFormat.Region.spans.rawValue].offset + Int(index) * RailPackFormat.spanRow
        return read { RailPackSpan(fromDay: i32($0, o), toDay: i32($0, o + 4)) }
    }

    // MARK: Level queries

    public func count(level: Int, _ kind: RailPackFormat.ArrayKind) throws -> Int { try self.level(level).count(kind) }

    /// Tile directory rows (indices) whose tile lies in the map-point rectangle, ascending by (tileY, tileX).
    /// Pieces are listed under their home tile and reach up to half a tile outside it, so a caller
    /// that must not miss a piece grows the rectangle by half a tile (``RailPackFormat/tileSide(mapPointsPerPoint:)`` / 2).
    public func tiles(level: Int, minX: Double, minY: Double, maxX: Double, maxY: Double) throws -> [Int] {
        let info = try self.level(level)
        let mpp = info.mapPointsPerPoint
        let count = info.count(.tileDir)
        // NaN bounds compare false and give nothing; infinite or huge bounds clamp to the Int32 tile range.
        guard minX <= maxX, minY <= maxY, count > 0 else { return [] }
        let x0 = RailPackFormat.tile(containing: minX, mapPointsPerPoint: mpp), x1 = RailPackFormat.tile(containing: maxX, mapPointsPerPoint: mpp)
        let y0 = RailPackFormat.tile(containing: minY, mapPointsPerPoint: mpp), y1 = RailPackFormat.tile(containing: maxY, mapPointsPerPoint: mpp)
        let base = info.arrays[RailPackFormat.ArrayKind.tileDir.rawValue].offset
        let size = RailPackFormat.ArrayKind.tileDir.rowSize
        return read { raw in
            func key(_ row: Int) -> (Int, Int) { (Int(i32(raw, base + row * size + 4)), Int(i32(raw, base + row * size))) }
            func lowerBound(_ y: Int, _ x: Int) -> Int {
                var lo = 0, hi = count
                while lo < hi {
                    let mid = (lo + hi) / 2
                    let k = key(mid)
                    if k.0 < y || (k.0 == y && k.1 < x) { lo = mid + 1 } else { hi = mid }
                }
                return lo
            }
            var result: [Int] = []
            var row = lowerBound(y0, x0)
            // Walk the sorted directory, jumping to the next row band when a band's x range is exhausted.
            while row < count {
                let (ty, tx) = key(row)
                if ty > y1 { break }
                // `max(row + 1, ...)` guarantees progress even on an unsorted directory.
                if tx < x0 { row = max(row + 1, lowerBound(ty, x0)); continue }
                if tx > x1 { row = max(row + 1, lowerBound(ty + 1, x0)); continue }
                result.append(row)
                row += 1
            }
            return result
        }
    }

    public func tile(level: Int, index: Int) throws -> RailPackTileRow {
        try tileRow(try self.level(level), index)
    }

    private func tileRow(_ info: LevelInfo, _ index: Int) throws -> RailPackTileRow {
        let o = try rowOffset(info, .tileDir, index)
        return read {
            RailPackTileRow(tileX: i32($0, o), tileY: i32($0, o + 4), firstTilePiece: u32($0, o + 8),
                            pieceCount: u16($0, o + 12), nodeCount: u16($0, o + 14), firstTileNode: u32($0, o + 16))
        }
    }

    /// Piece indices homed in a tile, sorted by group then piece.
    public func pieceIndices(level: Int, tile index: Int) throws -> [UInt32] {
        let info = try self.level(level)
        let row = try tile(level: level, index: index)
        return try indices(info, .tilePieces, first: Int(row.firstTilePiece), count: Int(row.pieceCount))
    }

    /// Global node indices whose stored vertex lies in a tile.
    public func nodeIndices(level: Int, tile index: Int) throws -> [UInt32] {
        let info = try self.level(level)
        let row = try tile(level: level, index: index)
        return try indices(info, .tileNodes, first: Int(row.firstTileNode), count: Int(row.nodeCount))
    }

    private func indices(_ info: LevelInfo, _ kind: RailPackFormat.ArrayKind, first: Int, count: Int) throws -> [UInt32] {
        guard count > 0 else { return [] }
        let start = try rowOffset(info, kind, first)
        _ = try rowOffset(info, kind, first + count - 1)
        return read { raw in (0..<count).map { u32(raw, start + $0 * 4) } }
    }

    public func piece(level: Int, index: Int) throws -> RailPackPieceRow {
        try pieceRow(try self.level(level), index)
    }

    private func pieceRow(_ info: LevelInfo, _ index: Int) throws -> RailPackPieceRow {
        let o = try rowOffset(info, .pieces, index)
        return read {
            RailPackPieceRow(tile: u32($0, o), vertexStart: u32($0, o + 4), vertexCount: u16($0, o + 8),
                             group: u16($0, o + 10), span: u16($0, o + 12), flags: u16($0, o + 14))
        }
    }

    /// Appends the map-point positions of vertices `first...last` of a piece (the whole piece by default)
    /// to `points`: one widening loop, no intermediate objects.
    public func appendVertices(level: Int, piece index: Int, first: Int = 0, last: Int? = nil, to points: inout [RailPackPoint]) throws {
        let info = try self.level(level)  // one copy of the level info for the whole call
        let row = try pieceRow(info, index)
        let lastVertex = last ?? Int(row.vertexCount) - 1
        guard first >= 0, first <= lastVertex, lastVertex < Int(row.vertexCount) else { throw RailPackError.indexOutOfRange("vertex range") }
        let mpp = info.mapPointsPerPoint
        let n = lastVertex - first + 1
        points.reserveCapacity(points.count + n)
        if row.isLong {
            let start = try rowOffset(info, .longVertices, Int(row.vertexStart) + first)
            _ = try rowOffset(info, .longVertices, Int(row.vertexStart) + lastVertex)
            read { raw in
                for i in 0..<n {
                    points.append(RailPackPoint(x: RailPackFormat.decodeLong(Int(i32(raw, start + i * 8)), mapPointsPerPoint: mpp),
                                                y: RailPackFormat.decodeLong(Int(i32(raw, start + i * 8 + 4)), mapPointsPerPoint: mpp)))
                }
            }
        } else {
            let tile = try tileRow(info, Int(row.tile))
            let start = try rowOffset(info, .vertices, Int(row.vertexStart) + first)
            _ = try rowOffset(info, .vertices, Int(row.vertexStart) + lastVertex)
            read { raw in
                for i in 0..<n {
                    points.append(RailPackPoint(x: RailPackFormat.decode(Int(i16(raw, start + i * 4)), tile: Int(tile.tileX), mapPointsPerPoint: mpp),
                                                y: RailPackFormat.decode(Int(i16(raw, start + i * 4 + 2)), tile: Int(tile.tileY), mapPointsPerPoint: mpp)))
                }
            }
        }
    }

    /// Long pieces whose bounding box meets the map-point rectangle; piece indices in file order.
    public func longPieces(level: Int, minX: Double, minY: Double, maxX: Double, maxY: Double) throws -> [UInt32] {
        let info = try self.level(level)
        let quantum = RailPackFormat.quantum(mapPointsPerPoint: info.mapPointsPerPoint)
        let base = info.arrays[RailPackFormat.ArrayKind.longPieces.rawValue].offset
        return read { raw in
            (0..<info.count(.longPieces)).compactMap { row in
                let o = base + row * RailPackFormat.ArrayKind.longPieces.rowSize
                let bx0 = Double(i32(raw, o + 4)) * quantum, by0 = Double(i32(raw, o + 8)) * quantum
                let bx1 = Double(i32(raw, o + 12)) * quantum, by1 = Double(i32(raw, o + 16)) * quantum
                return bx0 <= maxX && bx1 >= minX && by0 <= maxY && by1 >= minY ? u32(raw, o) : nil
            }
        }
    }

    /// Everything a loader must mount for a request rectangle: the home tiles in the rectangle grown by
    /// half a tile (a piece reaches half a tile outside its home tile), then every long piece whose
    /// bounding box meets the rectangle itself. Long pieces have no home tile and are never listed
    /// under one, so they mount and unmount per piece.
    public func mountKeys(level: Int, minX: Double, minY: Double, maxX: Double, maxY: Double) throws -> [RailPackMountKey] {
        let info = try self.level(level)
        let half = RailPackFormat.tileSide(mapPointsPerPoint: info.mapPointsPerPoint) / 2
        var keys: [RailPackMountKey] = []
        for row in try tiles(level: level, minX: minX - half, minY: minY - half, maxX: maxX + half, maxY: maxY + half) {
            let t = try tileRow(info, row)
            keys.append(.tile(level: level, x: Int(t.tileX), y: Int(t.tileY)))
        }
        for piece in try longPieces(level: level, minX: minX, minY: minY, maxX: maxX, maxY: maxY) {
            keys.append(.longPiece(level: level, piece: Int(piece)))
        }
        return keys
    }

    public func longPieceRow(level: Int, index: Int) throws -> RailPackLongPieceRow {
        let info = try self.level(level)
        let o = try rowOffset(info, .longPieces, index)
        return read {
            RailPackLongPieceRow(piece: u32($0, o), minX: i32($0, o + 4), minY: i32($0, o + 8), maxX: i32($0, o + 12), maxY: i32($0, o + 16))
        }
    }

    public func nodeSlot(level: Int, node: Int) throws -> RailPackNodeSlot {
        let info = try self.level(level)
        let o = try rowOffset(info, .nodes, node)
        return read { RailPackNodeSlot(piece: u32($0, o), vertex: u16($0, o + 4)) }
    }

    /// Piece indices of a chain: contiguous rows, in position order.
    public func pieceRange(level: Int, chain: Int) throws -> Range<Int> {
        let info = try self.level(level)
        let o = try rowOffset(info, .chains, chain)
        return read { Int(u32($0, o))..<(Int(u32($0, o)) + Int(u32($0, o + 4) & RailPackFormat.chainCountMask)) }
    }

    /// Whether a chain is a closed loop (the flag in the top bit of its chains row's count word).
    public func isClosed(level: Int, chain: Int) throws -> Bool {
        let info = try self.level(level)
        let o = try rowOffset(info, .chains, chain)
        return read { u32($0, o + 4) & RailPackFormat.closedChainFlag != 0 }
    }

    /// The chain index owning a piece (binary search over the chain table).
    public func chain(level: Int, ofPiece piece: Int) throws -> Int {
        let info = try self.level(level)
        let count = info.count(.chains)
        guard piece >= 0, piece < info.count(.pieces) else { throw RailPackError.indexOutOfRange("piece \(piece)") }
        let base = info.arrays[RailPackFormat.ArrayKind.chains.rawValue].offset
        return try read { raw in
            func first(_ c: Int) -> Int { Int(u32(raw, base + c * 8)) }
            // Last chain whose firstPiece <= piece, then walk back over empty chains.
            var lo = 0, hi = count
            while lo < hi { let mid = (lo + hi) / 2; if first(mid) <= piece { lo = mid + 1 } else { hi = mid } }
            var c = lo - 1
            while c >= 0 {
                let n = Int(u32(raw, base + c * 8 + 4) & RailPackFormat.chainCountMask)
                if n > 0 { if piece < first(c) + n { return c } else { break } }
                c -= 1
            }
            throw RailPackError.corrupt("piece \(piece) belongs to no chain")
        }
    }

    /// The vertex ranges a trip span draws, from node `fromNode` to node `toNode`.
    ///
    /// Ranges come in forward (file) order; `reversed` is true when the trip runs against it, so a
    /// caller walks the ranges (and each range's vertices) backwards. Boundary vertices shared by
    /// neighbouring pieces appear in both ranges, except that a range of a single vertex
    /// (`first == last`) is dropped unless it is all there is.
    ///
    /// - Same chain, `wraps` false: the pieces between the two nodes.
    /// - Same closed chain, `wraps` true: the span crosses the chain's seam. Forward order is
    ///   `[later node ... chain end] + [chain start ... earlier node]` (the seam vertex appears at the end
    ///   of the first part and the start of the second); `reversed` is true when `fromNode` sits earlier in
    ///   the file than `toNode`. `wraps` on an open chain throws ``RailPackError/chainNotClosed``, and on
    ///   nodes of different chains ``RailPackError/nodesNotOnOneChain``.
    /// - Different chains of one line (a non-continuous line): the tail of the first chain from its node,
    ///   every chain between, and the head of the last chain up to its node. Each range carries its
    ///   `chain`, and the stroke breaks where `chain` changes: the gap itself draws nothing. Nodes on
    ///   different lines throw ``RailPackError/nodesNotOnOneChain``. This looks the line up by linear scan.
    public func vertexRanges(level: Int, fromNode: Int, toNode: Int, wraps: Bool = false) throws -> (ranges: [RailPackVertexRange], reversed: Bool) {
        let a = try nodeSlot(level: level, node: fromNode), b = try nodeSlot(level: level, node: toNode)
        guard !a.isNone, !b.isNone else { throw RailPackError.indexOutOfRange("node without chain slot") }
        let ca = try chain(level: level, ofPiece: Int(a.piece)), cb = try chain(level: level, ofPiece: Int(b.piece))
        let aFirst = (a.piece, a.vertex) <= (b.piece, b.vertex)
        let early = aFirst ? a : b, late = aFirst ? b : a
        var ranges: [RailPackVertexRange] = []
        let reversed: Bool

        if wraps {
            guard ca == cb else { throw RailPackError.nodesNotOnOneChain }
            guard try isClosed(level: level, chain: ca) else { throw RailPackError.chainNotClosed }
            try appendRanges(level: level, chain: ca, from: late, to: nil, into: &ranges)
            try appendRanges(level: level, chain: ca, from: nil, to: early, into: &ranges)
            reversed = (a.piece, a.vertex) < (b.piece, b.vertex)
        } else if ca == cb {
            try appendRanges(level: level, chain: ca, from: early, to: late, into: &ranges)
            reversed = (a.piece, a.vertex) > (b.piece, b.vertex)
        } else {
            guard let owner = try lineOwning(nodes: fromNode, toNode) else { throw RailPackError.nodesNotOnOneChain }
            let chains = Int(owner.firstChain)..<(Int(owner.firstChain) + Int(owner.chainCount))
            guard chains.contains(ca), chains.contains(cb) else { throw RailPackError.nodesNotOnOneChain }
            let lowFirst = ca < cb
            let (lowChain, low, highChain, high) = lowFirst ? (ca, a, cb, b) : (cb, b, ca, a)
            try appendRanges(level: level, chain: lowChain, from: low, to: nil, into: &ranges)
            for middle in (lowChain + 1)..<highChain { try appendRanges(level: level, chain: middle, from: nil, to: nil, into: &ranges) }
            try appendRanges(level: level, chain: highChain, from: nil, to: high, into: &ranges)
            reversed = !lowFirst
        }
        let drawn = ranges.filter { $0.first != $0.last }
        return (drawn.isEmpty ? Array(ranges.prefix(1)) : drawn, reversed)
    }

    /// Appends the pieces of `chain` from slot `from` (or the chain start) to slot `to` (or the chain end).
    private func appendRanges(level: Int, chain: Int, from: RailPackNodeSlot?, to: RailPackNodeSlot?, into ranges: inout [RailPackVertexRange]) throws {
        let info = try self.level(level)
        let pieces = try pieceRange(level: level, chain: chain)
        guard !pieces.isEmpty else { return }
        let first = from.map { Int($0.piece) } ?? pieces.lowerBound
        let last = to.map { Int($0.piece) } ?? pieces.upperBound - 1
        guard pieces.contains(first), pieces.contains(last), first <= last else { throw RailPackError.corrupt("span outside chain \(chain)") }
        for p in first...last {
            let count = Int(try pieceRow(info, p).vertexCount)
            let firstVertex = (p == first ? from.map { Int($0.vertex) } : nil) ?? 0
            let lastVertex = (p == last ? to.map { Int($0.vertex) } : nil) ?? count - 1
            guard firstVertex <= lastVertex, lastVertex < count else { throw RailPackError.indexOutOfRange("vertex range") }
            ranges.append(RailPackVertexRange(chain: chain, piece: UInt32(p), first: firstVertex, last: lastVertex))
        }
    }

    /// The line whose node range holds both nodes.
    private func lineOwning(nodes a: Int, _ b: Int) throws -> RailPackLine? {
        for index in 0..<header.lineCount {
            let l = try line(index)
            let nodes = Int(l.firstNode)..<(Int(l.firstNode) + Int(l.nodeCount))
            if nodes.contains(a), nodes.contains(b) { return l }
        }
        return nil
    }

    // MARK: Size accounting

    public struct SizeAccounting: Equatable, Sendable {
        public struct Level: Equatable, Sendable {
            public var zoom: Double
            /// Bytes per array in `ArrayKind` order.
            public var arrayBytes: [Int]
            public var rows: [Int]
            public var totalBytes: Int { arrayBytes.reduce(0, +) }
        }
        public var headerBytes: Int
        public var regionTableBytes: Int
        public var levels: [Level]
        public var fileBytes: Int
        /// Every byte of the file belongs to exactly one of the parts above.
        public var accountedBytes: Int { headerBytes + regionTableBytes + levels.reduce(0) { $0 + $1.totalBytes } }
        public var vertexCount: Int { levels.reduce(0) { $0 + $1.rows[RailPackFormat.ArrayKind.vertices.rawValue] + $1.rows[RailPackFormat.ArrayKind.longVertices.rawValue] } }
    }

    /// Bytes and row counts per part, from the headers only (no page of the geometry is touched).
    public func sizeAccounting() -> SizeAccounting {
        let tableBytes = (RailPackFormat.regionSectionCount + header.levelCount) * RailPackFormat.sectionEntrySize
        let regionBytes = regionSections.reduce(0) { $0 + $1.length }
        let levelsAccounted = levels.enumerated().map { index, info in
            SizeAccounting.Level(
                zoom: ladder.zooms[index],
                arrayBytes: RailPackFormat.ArrayKind.allCases.map { info.count($0) * $0.rowSize },
                rows: RailPackFormat.ArrayKind.allCases.map { info.count($0) })
        }
        return SizeAccounting(headerBytes: RailPackFormat.headerSize + tableBytes, regionTableBytes: regionBytes,
                              levels: levelsAccounted, fileBytes: data.count)
    }

    // MARK: Deep validation

    /// Checks every cross reference in the file; throws ``RailPackError/corrupt(_:)`` or
    /// ``RailPackError/indexOutOfRange(_:)`` on the first defect. Touches every page.
    public func validateContents() throws {
        for index in 0..<header.lineCount {
            let l = try line(index)
            guard Int(l.firstChain) + Int(l.chainCount) <= header.chainCount, Int(l.firstNode) + Int(l.nodeCount) <= header.nodeCount else {
                throw RailPackError.corrupt("line \(index) range")
            }
        }
        for index in 0..<header.groupCount { _ = try group(index) }
        for level in 0..<levels.count { try validateLevel(level) }
    }

    private func validateLevel(_ levelIndex: Int) throws {
        let info = levels[levelIndex]
        guard info.count(.nodes) == header.nodeCount, info.count(.chains) == header.chainCount else {
            throw RailPackError.corrupt("level \(levelIndex) node or chain table size")
        }
        let tileCount = info.count(.tileDir), pieceCount = info.count(.pieces)
        var previous: (Int32, Int32)?
        var pieceCursor = 0, nodeCursor = 0
        for t in 0..<tileCount {
            let row = try tile(level: levelIndex, index: t)
            if let previous, !(previous.1 < row.tileY || (previous.1 == row.tileY && previous.0 < row.tileX)) {
                throw RailPackError.corrupt("level \(levelIndex) tile directory not sorted")
            }
            previous = (row.tileX, row.tileY)
            guard Int(row.firstTilePiece) == pieceCursor, Int(row.firstTileNode) == nodeCursor else { throw RailPackError.corrupt("level \(levelIndex) tile \(t) offsets") }
            pieceCursor += Int(row.pieceCount); nodeCursor += Int(row.nodeCount)
            for p in try pieceIndices(level: levelIndex, tile: t) {
                guard Int(p) < pieceCount, try piece(level: levelIndex, index: Int(p)).tile == UInt32(t) else { throw RailPackError.corrupt("level \(levelIndex) tilePieces") }
            }
            for n in try nodeIndices(level: levelIndex, tile: t) where Int(n) >= header.nodeCount { throw RailPackError.corrupt("level \(levelIndex) tileNodes") }
        }
        guard pieceCursor == info.count(.tilePieces), nodeCursor == info.count(.tileNodes) else { throw RailPackError.corrupt("level \(levelIndex) tile totals") }
        var longSeen = 0
        for p in 0..<pieceCount {
            let row = try piece(level: levelIndex, index: p)
            guard Int(row.group) < header.groupCount, row.span == RailPackFormat.noSpan || Int(row.span) < header.spanCount else {
                throw RailPackError.corrupt("level \(levelIndex) piece \(p) group or span")
            }
            let kind: RailPackFormat.ArrayKind = row.isLong ? .longVertices : .vertices
            guard row.vertexCount >= 2, Int(row.vertexStart) + Int(row.vertexCount) <= info.count(kind) else {
                throw RailPackError.corrupt("level \(levelIndex) piece \(p) vertices")
            }
            if row.isLong { longSeen += 1 } else if Int(row.tile) >= tileCount { throw RailPackError.corrupt("level \(levelIndex) piece \(p) tile") }
        }
        guard longSeen == info.count(.longPieces) else { throw RailPackError.corrupt("level \(levelIndex) long piece count") }
        for l in 0..<info.count(.longPieces) {
            let row = try longPieceRow(level: levelIndex, index: l)
            guard Int(row.piece) < pieceCount, try piece(level: levelIndex, index: Int(row.piece)).isLong else { throw RailPackError.corrupt("level \(levelIndex) longPieces") }
        }
        var cursor = 0, lastChainEnd = 0
        for c in 0..<header.chainCount {
            let range = try pieceRange(level: levelIndex, chain: c)
            guard range.lowerBound == cursor, range.upperBound <= pieceCount else { throw RailPackError.corrupt("level \(levelIndex) chain \(c)") }
            cursor = range.upperBound; lastChainEnd = cursor
            if levelIndex > 0, try isClosed(level: levelIndex, chain: c) != isClosed(level: 0, chain: c) {
                throw RailPackError.corrupt("level \(levelIndex) chain \(c) closed flag differs from level 0")
            }
        }
        guard lastChainEnd == pieceCount else { throw RailPackError.corrupt("level \(levelIndex) chains do not cover the pieces") }
        for n in 0..<header.nodeCount {
            let slot = try nodeSlot(level: levelIndex, node: n)
            if slot.isNone { continue }
            guard Int(slot.piece) < pieceCount, slot.vertex < (try piece(level: levelIndex, index: Int(slot.piece))).vertexCount else {
                throw RailPackError.corrupt("level \(levelIndex) node \(n)")
            }
        }
    }
}
