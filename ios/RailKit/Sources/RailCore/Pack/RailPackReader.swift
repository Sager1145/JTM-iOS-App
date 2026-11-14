import Foundation

/// Which datum a reader hands its positions out in. The file is always WGS84; `.gcj02` shifts every
/// decoded point (and every query rectangle) the way the China map service draws the same place.
/// The app opens a region with `.gcj02` when `AppleMapDatum.gcj02Countries` contains it.
public enum RailPackDisplayDatum: Sendable { case wgs84, gcj02 }

/// Read-only, zero-copy view of a `.railpack` file (format v2).
///
/// Opening checks the header, the section table and every per-level array against the
/// file length, so afterwards no accessor can read outside the file. Nothing is decoded
/// into objects: each accessor reads fixed-width rows out of the mapped bytes. Level queries
/// go through ``level(_:)``, which builds the level's index (vertex starts, chain starts, tile
/// order) once from its piece rows.
/// ``validateContents()`` additionally checks every cross reference (it touches every
/// page, so it is for tests, bakes and guards, not for app launch).
///
/// The datum shift (`display: .gcj02`) is applied in exactly one place, ``RailPackLevel/appendVertices(piece:first:last:to:)``,
/// and the rectangle queries map their rectangle back, so a caller never sees a WGS84 position
/// from a `.gcj02` reader.
public struct RailPackReader: Sendable {
    public struct Header: Equatable, Sendable {
        public var formatVersion: UInt16
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
    public let display: RailPackDisplayDatum
    /// The file's bytes, normally `Data(contentsOf:options: .alwaysMapped)`.
    public let data: Data
    private let regionSections: [(offset: Int, length: Int)]

    /// Opens a file from bytes; throws a typed ``RailPackError`` for any structural defect.
    public init(data: Data, display: RailPackDisplayDatum = .wgs84) throws {
        let size = RailPackFormat.headerSize
        guard data.count >= size else { throw RailPackError.truncated }
        let parsed: (Header, [(Int, Int)], [LevelInfo]) = try data.withUnsafeBytes { raw in
            guard Array(raw[0..<4]) == RailPackFormat.magic else { throw RailPackError.badMagic }
            let version = raw.loadUnaligned(fromByteOffset: 4, as: UInt16.self).littleEndian
            guard version == RailPackFormat.formatVersion else { throw RailPackError.unsupportedVersion(version) }
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
                formatVersion: version, regionCode: region,
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
                            header.spanCount * RailPackFormat.spanRow, header.nodeCount * RailPackFormat.nodeChainRow,
                            header.levelCount * RailPackFormat.levelRow]
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
                levels.append(LevelInfo(mapPointsPerPoint: mpp, laneBucket: raw[row + 8],
                                        sectionOffset: section.0, sectionLength: section.1, arrays: arrays))
            }
            return (header, Array(sections[0..<RailPackFormat.regionSectionCount]), levels)
        }
        self.header = parsed.0
        self.regionSections = parsed.1.map { (offset: $0.0, length: $0.1) }
        self.levels = parsed.2
        self.ladder = try parsed.2.isEmpty ? RailPackLadder(zooms: [0]) : RailPackLadder(mapPointsPerPoint: parsed.2.map(\.mapPointsPerPoint))
        self.display = display
        self.data = data
    }

    /// Opens `url` memory-mapped: no copy, no decode.
    public init(contentsOf url: URL, display: RailPackDisplayDatum = .wgs84) throws {
        try self.init(data: Data(contentsOf: url, options: .alwaysMapped), display: display)
    }

    // MARK: Raw access

    @inline(__always)
    fileprivate func read<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R { try data.withUnsafeBytes(body) }

    fileprivate func rowOffset(_ info: LevelInfo, _ kind: RailPackFormat.ArrayKind, _ row: Int) throws -> Int {
        guard row >= 0, row < info.arrays[kind.rawValue].count else { throw RailPackError.indexOutOfRange("\(kind) \(row)") }
        return info.arrays[kind.rawValue].offset + row * kind.rowSize
    }

    fileprivate func levelInfo(_ index: Int) throws -> LevelInfo {
        guard levels.indices.contains(index) else { throw RailPackError.indexOutOfRange("level \(index)") }
        return levels[index]
    }

    fileprivate func u16(_ raw: UnsafeRawBufferPointer, _ o: Int) -> UInt16 { raw.loadUnaligned(fromByteOffset: o, as: UInt16.self).littleEndian }
    fileprivate func i16(_ raw: UnsafeRawBufferPointer, _ o: Int) -> Int16 { Int16(bitPattern: u16(raw, o)) }
    fileprivate func u32(_ raw: UnsafeRawBufferPointer, _ o: Int) -> UInt32 { raw.loadUnaligned(fromByteOffset: o, as: UInt32.self).littleEndian }
    fileprivate func i32(_ raw: UnsafeRawBufferPointer, _ o: Int) -> Int32 { Int32(bitPattern: u32(raw, o)) }

    // MARK: Region tables

    public func line(_ index: Int) throws -> RailPackLine {
        guard index >= 0, index < header.lineCount else { throw RailPackError.indexOutOfRange("line \(index)") }
        let o = regionSections[RailPackFormat.Region.lines.rawValue].offset + index * RailPackFormat.lineRow
        return read {
            let word = u16($0, o + 4)
            return RailPackLine(firstChain: u32($0, o), chainCount: word & RailPackFormat.lineChainCountMask,
                                firstNode: u32($0, o + 6), nodeCount: u16($0, o + 10),
                                independentParts: word & RailPackFormat.independentPartsFlag != 0)
        }
    }

    public func group(_ index: Int) throws -> RailPackGroup {
        guard index >= 0, index < header.groupCount else { throw RailPackError.indexOutOfRange("group \(index)") }
        let o = regionSections[RailPackFormat.Region.groups.rawValue].offset + index * RailPackFormat.groupRow
        return read {
            RailPackGroup(colourLight: u32($0, o), colourDark: u32($0, o + 4), tierMin: i16($0, o + 8), tierMax: i16($0, o + 10),
                          styleClass: $0[o + 12], category: $0[o + 13], span: u16($0, o + 14))
        }
    }

    /// The span at `index`; nil for `RailPackFormat.noSpan` (undated).
    public func span(_ index: UInt16) throws -> RailPackSpan? {
        if index == RailPackFormat.noSpan { return nil }
        guard Int(index) < header.spanCount else { throw RailPackError.indexOutOfRange("span \(index)") }
        let o = regionSections[RailPackFormat.Region.spans.rawValue].offset + Int(index) * RailPackFormat.spanRow
        return read { RailPackSpan(fromDay: i32($0, o), toDay: i32($0, o + 4)) }
    }

    /// The region-wide chain index of a node, `RailPackFormat.noNode` for a node with no chain slot.
    public func nodeChain(_ node: Int) throws -> UInt32 {
        guard node >= 0, node < header.nodeCount else { throw RailPackError.indexOutOfRange("node \(node)") }
        let o = regionSections[RailPackFormat.Region.nodeChains.rawValue].offset + node * RailPackFormat.nodeChainRow
        return read { u32($0, o) }
    }

    // MARK: Level queries

    public func count(level: Int, _ kind: RailPackFormat.ArrayKind) throws -> Int { try levelInfo(level).count(kind) }

    /// The level at `index` with its index built: one pass over its piece rows and chain rows. The value
    /// holds about 12 bytes per normal piece (0.6 MB for Japan z17) for as long as the caller keeps it.
    public func level(_ index: Int) throws -> RailPackLevel {
        try RailPackLevel(reader: self, index: index)
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
        /// Stored vertex rows (a vertex shared by two pieces is stored once; a long piece stores one row fewer than its vertices).
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
        for index in 0..<header.groupCount {
            let g = try group(index)
            guard g.span == RailPackFormat.noSpan || Int(g.span) < header.spanCount else { throw RailPackError.corrupt("group \(index) span") }
        }
        for node in 0..<header.nodeCount {
            let chain = try nodeChain(node)
            guard chain == RailPackFormat.noNode || Int(chain) < header.chainCount else { throw RailPackError.corrupt("node \(node) chain") }
        }
        for level in 0..<levels.count { try validateLevel(level) }
    }

    private func validateLevel(_ levelIndex: Int) throws {
        let info = levels[levelIndex]
        guard info.count(.nodes) == header.nodeCount, info.count(.chains) == header.chainCount else {
            throw RailPackError.corrupt("level \(levelIndex) node or chain table size")
        }
        let level = try self.level(levelIndex)
        let first = levelIndex > 0 ? try self.level(0) : level
        let pieceCount = info.count(.pieces)
        var normalRows = 0, longRowsTotal = 0, longSeen = 0, cursor = 0
        for c in 0..<header.chainCount {
            let range = try level.pieceRange(chain: c)
            guard range.lowerBound == cursor, range.upperBound <= pieceCount else { throw RailPackError.corrupt("level \(levelIndex) chain \(c)") }
            cursor = range.upperBound
            if try level.isClosed(chain: c) != first.isClosed(chain: c) {
                throw RailPackError.corrupt("level \(levelIndex) chain \(c) closed flag differs from level 0")
            }
            var previous: RailPackPieceRow?
            for p in range {
                let row = try level.piece(p)
                guard Int(row.group) < header.groupCount else { throw RailPackError.corrupt("level \(levelIndex) piece \(p) group") }
                if row.isLong {
                    longSeen += 1
                    longRowsTotal += Int(row.vertexCount) - 1
                } else {
                    guard row.tileX != RailPackFormat.longPieceTile, row.tileY != RailPackFormat.longPieceTile else {
                        throw RailPackError.corrupt("level \(levelIndex) piece \(p) tile")
                    }
                    normalRows += Int(row.vertexCount) - (row.joinsPrevious ? 1 : 0)
                }
                if row.joinsPrevious {
                    guard let previous, !previous.isLong, !row.isLong else { throw RailPackError.corrupt("level \(levelIndex) piece \(p) joins nothing") }
                }
                previous = row
            }
        }
        guard cursor == pieceCount else { throw RailPackError.corrupt("level \(levelIndex) chains do not cover the pieces") }
        guard normalRows == info.count(.vertices), longRowsTotal == info.count(.longVertices) else {
            throw RailPackError.corrupt("level \(levelIndex) vertex row totals")
        }
        guard longSeen == info.count(.longPieces) else { throw RailPackError.corrupt("level \(levelIndex) long piece count") }
        var lastLong = -1
        for l in 0..<info.count(.longPieces) {
            let row = try level.longPieceRow(l)
            guard Int(row.piece) > lastLong, Int(row.piece) < pieceCount, try level.piece(Int(row.piece)).isLong else {
                throw RailPackError.corrupt("level \(levelIndex) longPieces")
            }
            lastLong = Int(row.piece)
        }
        for n in 0..<header.nodeCount {
            let slot = try level.nodeSlot(node: n)
            if slot.isNone { continue }
            guard Int(slot.piece) < pieceCount, slot.vertex < (try level.piece(Int(slot.piece))).vertexCount else {
                throw RailPackError.corrupt("level \(levelIndex) node \(n)")
            }
        }
    }
}

// MARK: - A level with its index

/// One level of a pack, opened: the level's piece rows are read once into a vertex-start table, a
/// chain-start table and a tile order, and every per-level query runs on them. Nothing else is held
/// in memory; vertices are read from the map on demand.
public struct RailPackLevel: Sendable {
    public let index: Int
    public let mapPointsPerPoint: Double
    /// Vertices a loader mounts for the whole level: the sum of every piece's vertex count (a joined
    /// piece counts its shared first vertex, which is stored once).
    public let vertexCount: Int
    let reader: RailPackReader
    let info: RailPackReader.LevelInfo
    /// Per piece: the first row of its own vertices (`vertices` for a normal piece, `longVertices` for a long one).
    private let vertexStart: [UInt32]
    /// Per chain, the first piece; one entry more than there are chains, holding the piece total.
    private let chainFirstPiece: [UInt32]
    /// The normal pieces sorted by `tileY << 48 | tileX << 32 | piece`.
    private let tileOrder: [UInt64]

    public var pieceCount: Int { info.count(.pieces) }
    public func count(_ kind: RailPackFormat.ArrayKind) -> Int { info.count(kind) }

    init(reader: RailPackReader, index: Int) throws {
        let info = try reader.levelInfo(index)
        let pieceCount = info.count(.pieces), chainCount = info.count(.chains)
        let verticesAvailable = info.count(.vertices), longAvailable = info.count(.longVertices)
        var starts = [UInt32](), order = [UInt64]()
        starts.reserveCapacity(pieceCount)
        var normalRows = 0, longRows = 0, mounted = 0
        try reader.read { raw in
            let base = info.arrays[RailPackFormat.ArrayKind.pieces.rawValue].offset
            for p in 0..<pieceCount {
                let o = base + p * RailPackFormat.ArrayKind.pieces.rowSize
                let tileX = reader.u16(raw, o), tileY = reader.u16(raw, o + 2), word = reader.u16(raw, o + 4)
                let count = Int(word & RailPackFormat.pieceVertexCountMask)
                guard count >= 2 else { throw RailPackError.corrupt("level \(index) piece \(p) vertices") }
                if tileX == RailPackFormat.longPieceTile && tileY == RailPackFormat.longPieceTile {
                    starts.append(UInt32(longRows))
                    longRows += count - 1
                } else {
                    starts.append(UInt32(normalRows))
                    normalRows += count - (word & RailPackFormat.joinsPreviousFlag != 0 ? 1 : 0)
                    order.append(UInt64(tileY) << 48 | UInt64(tileX) << 32 | UInt64(p))
                }
                guard normalRows <= verticesAvailable, longRows <= longAvailable else {
                    throw RailPackError.corrupt("level \(index) piece rows exceed the vertex arrays")
                }
                mounted += count
            }
        }
        var chainFirst = [UInt32]()
        chainFirst.reserveCapacity(chainCount + 1)
        var cursor = 0
        try reader.read { raw in
            let base = info.arrays[RailPackFormat.ArrayKind.chains.rawValue].offset
            for c in 0..<chainCount {
                chainFirst.append(UInt32(cursor))
                cursor += Int(reader.u32(raw, base + c * RailPackFormat.ArrayKind.chains.rowSize) & RailPackFormat.chainCountMask)
                guard cursor <= pieceCount else { throw RailPackError.corrupt("level \(index) chain counts exceed the pieces") }
            }
        }
        chainFirst.append(UInt32(cursor))
        order.sort()
        self.reader = reader
        self.index = index
        self.info = info
        self.mapPointsPerPoint = info.mapPointsPerPoint
        self.vertexCount = mounted
        self.vertexStart = starts
        self.chainFirstPiece = chainFirst
        self.tileOrder = order
    }

    // MARK: Display datum

    private struct Rect { var minX, minY, maxX, maxY: Double }

    private var shifted: Bool { reader.display == .gcj02 }

    @inline(__always)
    private func displayPoint(_ x: Double, _ y: Double) -> RailPackPoint {
        guard shifted else { return RailPackPoint(x: x, y: y) }
        let p = StrokeProjection.point(GCJ02.fromWGS84(StrokeProjection.coordinate(StrokePoint(x: x, y: y))))
        return RailPackPoint(x: p.x, y: p.y)
    }

    /// The rectangle of the file's own (WGS84) space a display-space rectangle shows: translated by the
    /// inverse shift of its centre, then grown on each side by 2% of its diagonal. The shift changes by
    /// under 1% across any distance, so no vertex whose shifted position is inside the rectangle is missed.
    /// A WGS84 reader returns the rectangle unchanged.
    private func sourceRect(_ minX: Double, _ minY: Double, _ maxX: Double, _ maxY: Double) -> Rect {
        let plain = Rect(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
        guard shifted, minX <= maxX, minY <= maxY else { return plain }
        let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
        let diagonal = hypot(maxX - minX, maxY - minY)
        guard cx.isFinite, cy.isFinite, diagonal.isFinite else { return plain }
        let source = StrokeProjection.point(GCJ02.toWGS84(StrokeProjection.coordinate(StrokePoint(x: cx, y: cy))))
        let dx = source.x - cx, dy = source.y - cy
        let grow = 0.02 * diagonal
        guard dx.isFinite, dy.isFinite else { return Rect(minX: minX - grow, minY: minY - grow, maxX: maxX + grow, maxY: maxY + grow) }
        return Rect(minX: minX + dx - grow, minY: minY + dy - grow, maxX: maxX + dx + grow, maxY: maxY + dy + grow)
    }

    // MARK: Tiles

    private func firstRow(atOrAfter key: UInt64) -> Int {
        var lo = 0, hi = tileOrder.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if tileOrder[mid] < key { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    private func tiles(inSource r: Rect) -> [RailPackTile] {
        // NaN bounds compare false and give nothing; infinite or huge bounds clamp to the stored tile range.
        guard r.minX <= r.maxX, r.minY <= r.maxY, !tileOrder.isEmpty else { return [] }
        let mpp = mapPointsPerPoint
        let top = Int(UInt16.max)
        let x0 = max(RailPackFormat.tile(containing: r.minX, mapPointsPerPoint: mpp), 0)
        let x1 = min(RailPackFormat.tile(containing: r.maxX, mapPointsPerPoint: mpp), top)
        let y0 = max(RailPackFormat.tile(containing: r.minY, mapPointsPerPoint: mpp), 0)
        let y1 = min(RailPackFormat.tile(containing: r.maxY, mapPointsPerPoint: mpp), top)
        guard x0 <= x1, y0 <= y1 else { return [] }
        var result: [RailPackTile] = []
        var row = firstRow(atOrAfter: UInt64(y0) << 48 | UInt64(x0) << 32)
        // Walk the sorted order, jumping to the next row band when a band's x range is exhausted.
        while row < tileOrder.count {
            let key = tileOrder[row]
            let ty = Int(key >> 48), tx = Int((key >> 32) & 0xFFFF)
            if ty > y1 { break }
            if tx < x0 { row = max(row + 1, firstRow(atOrAfter: UInt64(ty) << 48 | UInt64(x0) << 32)); continue }
            if tx > x1 {
                if ty >= top { break }
                row = max(row + 1, firstRow(atOrAfter: UInt64(ty + 1) << 48 | UInt64(x0) << 32))
                continue
            }
            result.append(RailPackTile(x: tx, y: ty))
            if key >> 32 == 0xFFFF_FFFF { break }
            // Every piece of this tile is next to this one: skip to the next tile.
            row = max(row + 1, firstRow(atOrAfter: ((key >> 32) + 1) << 32))
        }
        return result
    }

    /// Tiles holding at least one normal piece whose coordinates lie in the display-space map-point
    /// rectangle, ascending by (y, x). Pieces are listed under their home tile and reach up to half a
    /// tile outside it, so a caller that must not miss a piece grows the rectangle by half a tile
    /// (``mountKeys(minX:minY:maxX:maxY:)`` does).
    public func tiles(minX: Double, minY: Double, maxX: Double, maxY: Double) throws -> [RailPackTile] {
        tiles(inSource: sourceRect(minX, minY, maxX, maxY))
    }

    /// Piece indices homed in a tile, ascending.
    public func pieceIndices(tileX: Int, tileY: Int) throws -> [UInt32] {
        guard (0...Int(UInt16.max)).contains(tileX), (0...Int(UInt16.max)).contains(tileY) else { return [] }
        let tileKey = UInt64(tileY) << 48 | UInt64(tileX) << 32
        var row = firstRow(atOrAfter: tileKey)
        var result: [UInt32] = []
        while row < tileOrder.count, tileOrder[row] & ~0xFFFF_FFFF == tileKey {
            result.append(UInt32(truncatingIfNeeded: tileOrder[row]))
            row += 1
        }
        return result
    }

    /// Pieces and mounted vertices of each tile that holds a normal piece, ascending by (y, x).
    public struct TileSummary: Equatable, Sendable {
        public var tile: RailPackTile
        public var pieces: Int
        public var vertices: Int
    }

    public func tileSummaries() throws -> [TileSummary] {
        var result: [TileSummary] = []
        var current: UInt64?
        for key in tileOrder {
            let tileKey = key >> 32
            let count = Int(try piece(Int(key & 0xFFFF_FFFF)).vertexCount)
            if tileKey == current {
                result[result.count - 1].pieces += 1
                result[result.count - 1].vertices += count
            } else {
                current = tileKey
                result.append(TileSummary(tile: RailPackTile(x: Int(tileKey & 0xFFFF), y: Int(tileKey >> 16)), pieces: 1, vertices: count))
            }
        }
        return result
    }

    // MARK: Pieces

    public func piece(_ pieceIndex: Int) throws -> RailPackPieceRow {
        let o = try reader.rowOffset(info, .pieces, pieceIndex)
        return reader.read {
            let word = reader.u16($0, o + 4)
            return RailPackPieceRow(
                tileX: reader.u16($0, o), tileY: reader.u16($0, o + 2),
                vertexCount: word & RailPackFormat.pieceVertexCountMask,
                joinsPrevious: word & RailPackFormat.joinsPreviousFlag != 0, group: reader.u16($0, o + 6))
        }
    }

    /// Appends the display-space map-point positions of vertices `first...last` of a piece (the whole
    /// piece by default) to `points`: one widening loop, no intermediate objects. This is the only place
    /// the datum shift is applied.
    public func appendVertices(piece pieceIndex: Int, first: Int = 0, last: Int? = nil, to points: inout [RailPackPoint]) throws {
        let row = try piece(pieceIndex)
        let lastVertex = last ?? Int(row.vertexCount) - 1
        guard first >= 0, first <= lastVertex, lastVertex < Int(row.vertexCount) else { throw RailPackError.indexOutOfRange("vertex range") }
        let mpp = mapPointsPerPoint
        let n = lastVertex - first + 1
        points.reserveCapacity(points.count + n)
        if row.isLong {
            let long = try longRow(ofPiece: pieceIndex)
            let start = Int(vertexStart[pieceIndex])
            if lastVertex >= 1 {
                _ = try reader.rowOffset(info, .longVertices, start)
                _ = try reader.rowOffset(info, .longVertices, start + lastVertex - 1)
            }
            let deltas = lastVertex >= 1 ? info.arrays[RailPackFormat.ArrayKind.longVertices.rawValue].offset + start * 4 : 0
            reader.read { raw in
                var qx = Int(long.firstX), qy = Int(long.firstY)
                if first == 0 {
                    points.append(displayPoint(RailPackFormat.decodeLong(qx, mapPointsPerPoint: mpp), RailPackFormat.decodeLong(qy, mapPointsPerPoint: mpp)))
                }
                if lastVertex >= 1 {
                    for v in 1...lastVertex {
                        qx += Int(reader.i16(raw, deltas + (v - 1) * 4)); qy += Int(reader.i16(raw, deltas + (v - 1) * 4 + 2))
                        if v >= first {
                            points.append(displayPoint(RailPackFormat.decodeLong(qx, mapPointsPerPoint: mpp), RailPackFormat.decodeLong(qy, mapPointsPerPoint: mpp)))
                        }
                    }
                }
            }
        } else {
            // A joined piece's first vertex is stored as the previous piece's last row, in that piece's tile.
            let base = Int(vertexStart[pieceIndex]) - (row.joinsPrevious ? 1 : 0)
            var previousTile: (x: Int, y: Int)?
            if row.joinsPrevious, first == 0 {
                guard pieceIndex > 0 else { throw RailPackError.corrupt("piece 0 joins nothing") }
                let previous = try piece(pieceIndex - 1)
                guard !previous.isLong else { throw RailPackError.corrupt("piece \(pieceIndex) joins a long piece") }
                previousTile = (Int(previous.tileX), Int(previous.tileY))
            }
            let start = try reader.rowOffset(info, .vertices, base + first)
            _ = try reader.rowOffset(info, .vertices, base + lastVertex)
            reader.read { raw in
                for i in 0..<n {
                    let tile = i == 0 ? (previousTile ?? (Int(row.tileX), Int(row.tileY))) : (Int(row.tileX), Int(row.tileY))
                    let x = RailPackFormat.decode(Int(reader.i16(raw, start + i * 4)), tile: tile.0, mapPointsPerPoint: mpp)
                    let y = RailPackFormat.decode(Int(reader.i16(raw, start + i * 4 + 2)), tile: tile.1, mapPointsPerPoint: mpp)
                    points.append(displayPoint(x, y))
                }
            }
        }
    }

    // MARK: Long pieces

    public func longPieceRow(_ row: Int) throws -> RailPackLongPieceRow {
        let o = try reader.rowOffset(info, .longPieces, row)
        return reader.read {
            RailPackLongPieceRow(piece: reader.u32($0, o), minX: reader.i32($0, o + 4), minY: reader.i32($0, o + 8),
                                 maxX: reader.i32($0, o + 12), maxY: reader.i32($0, o + 16),
                                 firstX: reader.i32($0, o + 20), firstY: reader.i32($0, o + 24))
        }
    }

    /// The long-piece row of a piece, by binary search (the rows ascend by piece).
    private func longRow(ofPiece piece: Int) throws -> RailPackLongPieceRow {
        var lo = 0, hi = info.count(.longPieces)
        while lo < hi {
            let mid = (lo + hi) / 2
            let row = try longPieceRow(mid)
            if Int(row.piece) == piece { return row }
            if Int(row.piece) < piece { lo = mid + 1 } else { hi = mid }
        }
        throw RailPackError.corrupt("long piece \(piece) has no longPieces row")
    }

    private func longPieces(inSource r: Rect) -> [UInt32] {
        let quantum = RailPackFormat.quantum(mapPointsPerPoint: mapPointsPerPoint)
        let base = info.arrays[RailPackFormat.ArrayKind.longPieces.rawValue].offset
        return reader.read { raw in
            (0..<info.count(.longPieces)).compactMap { row in
                let o = base + row * RailPackFormat.ArrayKind.longPieces.rowSize
                let bx0 = Double(reader.i32(raw, o + 4)) * quantum, by0 = Double(reader.i32(raw, o + 8)) * quantum
                let bx1 = Double(reader.i32(raw, o + 12)) * quantum, by1 = Double(reader.i32(raw, o + 16)) * quantum
                return bx0 <= r.maxX && bx1 >= r.minX && by0 <= r.maxY && by1 >= r.minY ? reader.u32(raw, o) : nil
            }
        }
    }

    /// Long pieces whose bounding box meets the display-space map-point rectangle; piece indices in file order.
    public func longPieces(minX: Double, minY: Double, maxX: Double, maxY: Double) throws -> [UInt32] {
        longPieces(inSource: sourceRect(minX, minY, maxX, maxY))
    }

    /// Everything a loader must mount for a display-space request rectangle: the home tiles in the
    /// rectangle grown by half a tile (a piece reaches half a tile outside its home tile), then every
    /// long piece whose bounding box meets the rectangle itself. Long pieces have no home tile and are
    /// never listed under one, so they mount and unmount per piece.
    public func mountKeys(minX: Double, minY: Double, maxX: Double, maxY: Double) throws -> [RailPackMountKey] {
        let r = sourceRect(minX, minY, maxX, maxY)
        let half = RailPackFormat.tileSide(mapPointsPerPoint: mapPointsPerPoint) / 2
        var keys: [RailPackMountKey] = []
        for tile in tiles(inSource: Rect(minX: r.minX - half, minY: r.minY - half, maxX: r.maxX + half, maxY: r.maxY + half)) {
            keys.append(.tile(level: index, x: tile.x, y: tile.y))
        }
        for piece in longPieces(inSource: r) { keys.append(.longPiece(level: index, piece: Int(piece))) }
        return keys
    }

    // MARK: Chains and nodes

    /// Where a topology node sits on this level's stroke; `.none` for a node without a slot. The piece is
    /// the absolute piece index.
    public func nodeSlot(node: Int) throws -> RailPackNodeSlot {
        let chain = try reader.nodeChain(node)
        let o = try reader.rowOffset(info, .nodes, node)
        let (inChain, vertex) = reader.read { (reader.u16($0, o), reader.u16($0, o + 2)) }
        let empty = inChain == RailPackFormat.noNodeSlot && vertex == RailPackFormat.noNodeSlot
        if chain == RailPackFormat.noNode {
            guard empty else { throw RailPackError.corrupt("level \(index) node \(node) has a slot but no chain") }
            return .none
        }
        if empty { return .none }
        guard Int(chain) < chainFirstPiece.count - 1 else { throw RailPackError.corrupt("level \(index) node \(node) chain") }
        let piece = Int(chainFirstPiece[Int(chain)]) + Int(inChain)
        guard piece < Int(chainFirstPiece[Int(chain) + 1]) else { throw RailPackError.corrupt("level \(index) node \(node) piece") }
        return RailPackNodeSlot(piece: UInt32(piece), vertex: vertex)
    }

    /// Piece indices of a chain: contiguous rows, in position order.
    public func pieceRange(chain: Int) throws -> Range<Int> {
        guard chain >= 0, chain < chainFirstPiece.count - 1 else { throw RailPackError.indexOutOfRange("\(RailPackFormat.ArrayKind.chains) \(chain)") }
        return Int(chainFirstPiece[chain])..<Int(chainFirstPiece[chain + 1])
    }

    /// Whether a chain is a closed loop (the flag in the top bit of its chains row).
    public func isClosed(chain: Int) throws -> Bool {
        let o = try reader.rowOffset(info, .chains, chain)
        return reader.read { reader.u32($0, o) & RailPackFormat.closedChainFlag != 0 }
    }

    /// The chain index owning a piece (binary search over the chain starts).
    public func chain(ofPiece piece: Int) throws -> Int {
        guard piece >= 0, piece < pieceCount, piece < Int(chainFirstPiece[chainFirstPiece.count - 1]) else {
            throw RailPackError.indexOutOfRange("piece \(piece)")
        }
        // The last chain whose first piece is at or before `piece`; empty chains share their successor's first piece.
        var lo = 0, hi = chainFirstPiece.count - 1
        while lo < hi { let mid = (lo + hi) / 2; if Int(chainFirstPiece[mid]) <= piece { lo = mid + 1 } else { hi = mid } }
        return lo - 1
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
    /// - Different chains of one line whose chains are a sequence (a line with gaps): the tail of the first chain from its node,
    ///   every chain between, and the head of the last chain up to its node. Each range carries its
    ///   `chain`, and the stroke breaks where `chain` changes: the gap itself draws nothing. Nodes on
    ///   different lines throw ``RailPackError/nodesNotOnOneChain``. This looks the line up by linear scan.
    ///   A line flagged `independentParts` (a non-continuous line: its chains are branches or lane
    ///   fragments whose file order is not track order) also throws, because the chains between two parts
    ///   in file order are not the track the trip rides; such a trip needs the topology's own runs.
    public func vertexRanges(fromNode: Int, toNode: Int, wraps: Bool = false) throws -> (ranges: [RailPackVertexRange], reversed: Bool) {
        let a = try nodeSlot(node: fromNode), b = try nodeSlot(node: toNode)
        guard !a.isNone, !b.isNone else { throw RailPackError.indexOutOfRange("node without chain slot") }
        let ca = try chain(ofPiece: Int(a.piece)), cb = try chain(ofPiece: Int(b.piece))
        let aFirst = (a.piece, a.vertex) <= (b.piece, b.vertex)
        let early = aFirst ? a : b, late = aFirst ? b : a
        var ranges: [RailPackVertexRange] = []
        let reversed: Bool

        if wraps {
            guard ca == cb else { throw RailPackError.nodesNotOnOneChain }
            guard try isClosed(chain: ca) else { throw RailPackError.chainNotClosed }
            try appendRanges(chain: ca, from: late, to: nil, into: &ranges)
            try appendRanges(chain: ca, from: nil, to: early, into: &ranges)
            reversed = (a.piece, a.vertex) < (b.piece, b.vertex)
        } else if ca == cb {
            try appendRanges(chain: ca, from: early, to: late, into: &ranges)
            reversed = (a.piece, a.vertex) > (b.piece, b.vertex)
        } else {
            guard let owner = try lineOwning(nodes: fromNode, toNode) else { throw RailPackError.nodesNotOnOneChain }
            guard !owner.independentParts else { throw RailPackError.nodesNotOnOneChain }
            let chains = Int(owner.firstChain)..<(Int(owner.firstChain) + Int(owner.chainCount))
            guard chains.contains(ca), chains.contains(cb) else { throw RailPackError.nodesNotOnOneChain }
            let lowFirst = ca < cb
            let (lowChain, low, highChain, high) = lowFirst ? (ca, a, cb, b) : (cb, b, ca, a)
            try appendRanges(chain: lowChain, from: low, to: nil, into: &ranges)
            for middle in (lowChain + 1)..<highChain { try appendRanges(chain: middle, from: nil, to: nil, into: &ranges) }
            try appendRanges(chain: highChain, from: nil, to: high, into: &ranges)
            reversed = !lowFirst
        }
        let drawn = ranges.filter { $0.first != $0.last }
        return (drawn.isEmpty ? Array(ranges.prefix(1)) : drawn, reversed)
    }

    /// Appends the pieces of `chain` from slot `from` (or the chain start) to slot `to` (or the chain end).
    private func appendRanges(chain: Int, from: RailPackNodeSlot?, to: RailPackNodeSlot?, into ranges: inout [RailPackVertexRange]) throws {
        let pieces = try pieceRange(chain: chain)
        guard !pieces.isEmpty else { return }
        let first = from.map { Int($0.piece) } ?? pieces.lowerBound
        let last = to.map { Int($0.piece) } ?? pieces.upperBound - 1
        guard pieces.contains(first), pieces.contains(last), first <= last else { throw RailPackError.corrupt("span outside chain \(chain)") }
        for p in first...last {
            let count = Int(try piece(p).vertexCount)
            let firstVertex = (p == first ? from.map { Int($0.vertex) } : nil) ?? 0
            let lastVertex = (p == last ? to.map { Int($0.vertex) } : nil) ?? count - 1
            guard firstVertex <= lastVertex, lastVertex < count else { throw RailPackError.indexOutOfRange("vertex range") }
            ranges.append(RailPackVertexRange(chain: chain, piece: UInt32(p), first: firstVertex, last: lastVertex))
        }
    }

    /// The line whose node range holds both nodes.
    private func lineOwning(nodes a: Int, _ b: Int) throws -> RailPackLine? {
        for lineIndex in 0..<reader.header.lineCount {
            let l = try reader.line(lineIndex)
            let nodes = Int(l.firstNode)..<(Int(l.firstNode) + Int(l.nodeCount))
            if nodes.contains(a), nodes.contains(b) { return l }
        }
        return nil
    }
}
