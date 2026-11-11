import Foundation

// MARK: - Format contract: `jtm-display-topology-v1`
//
// One file per region, `rail-display-network/{region}.topology.bin`, written by
// `app/scripts/railway/build-display-network.py` in the same run as
// `{region}.display.bin` and read in place from a memory map. The document
// `docs/reference/rail-topology-format.md` is the prose form of this file; the
// constants below are the single source the test fixture is checked against.
//
// Everything here is a contract for the units that code against it (builder,
// reader and router, ride resolver, statistics index, map). Nothing in this
// file is wired into the app yet.

/// Byte layout, units and id spaces of the topology file.
///
/// ## Encoding
///  - Little-endian, fixed-width records, every table 4-byte aligned, no
///    padding inside a record other than the named `reserved` fields (written
///    as zero, ignored by readers).
///  - Strings live only in the string table: a reference is a `UInt32` byte
///    offset into it, pointing at a `UInt16` byte length followed by that many
///    UTF-8 bytes. Offset 0 is always the empty string. `noString`
///    (`0xFFFF_FFFF`) means "absent" and is distinct from the empty string.
///  - Tables are written in directory order; the file ends with the string
///    table padded with zeros to a multiple of 4 bytes, and
///    `Header.fileLengthOffset` holds the file's byte count.
///  - Writing is deterministic: the same input produces the same bytes.
///
/// ## Units
///  - Lengths and chain positions are unsigned **centimetres** (`UInt32`,
///    0.01 m; a chain can be up to about 42,949 km long). `StrokeRef` and
///    `ChainRef.measures` are in metres, so a position is `Double(cm) / 100`.
///    `unsetMetres` marks "no position on this ruler".
///  - Coordinates are `Float32` degrees, WGS84, for coarse use only (labels,
///    nearest-node lookups). Rides never take geometry from them; geometry
///    comes from the display chunks.
///  - Dates are `UInt32` day numbers: 1 is 1800-01-01 (the data reaches back
///    to 1872), 0 means "no bound". `validFrom` is the first day a row applies
///    and `validTo` the first day it no longer applies: **half-open
///    `[validFrom, validTo)`, exactly the source data's convention**, so the
///    builder copies a source `valid_to`/`validTo` unchanged and never
///    subtracts a day. Both 0 is "always". A dated query (`day` non-nil)
///    matches `validFrom <= day < validTo`, a 0 bound being open. An undated
///    query (a ride with no date) matches exactly the rows with
///    `validTo == 0`, whatever `validFrom` is: the current network, as
///    ADR 0011 does. Source dates before 1800 are a builder error; a source
///    bound of "none" is written as 0. See ``dayNumber(ofISODate:)``.
///
/// ## Id spaces
///  - A **line index** is a position in the lines table (`UInt16` in refs, so
///    a region has at most 65,535 lines). Line ids are strings (for example
///    `jp.jr-east.yamanote`), unique per region.
///  - A **node ordinal** is a position within one line (`UInt16`, so at most
///    65,535 nodes per line). The **global node index** is
///    `line.firstNode + ordinal`; links and stop lists use global indices
///    (`UInt32`). A ``RailTopology/NodeRef`` is (line index, ordinal).
///  - An **edge ordinal** is a position within one line. Edge `k` joins node
///    ordinals `k` and `(k + 1) % nodeCount`; a loop line has `nodeCount`
///    edges (the last closes the loop), any other line `nodeCount - 1`. The
///    global edge index is `line.firstEdge + ordinal`.
///  - A **chain index** (`Node.chain`, `Run.chain`) names a chain of the
///    line's display chunk, which is how `StrokeRef.chainID` is built:
///    `"{region}|{lineID}#{chain}"`. For lines flagged `nonContinuous` the
///    chain index is the **flat part number** (see the part rule below).
///
/// ## Two metre rulers per node
///  A node stores where it sits on its chain twice, because the network layer
///  holds either the full chunk or an overview chunk of a line depending on
///  zoom, and each has its own `measures` ruler:
///   - `fullMetres`: centimetres on the full chunk's ruler;
///   - `overviewMetres`: centimetres on the overview chunk's ruler for the
///     same chain index, or `unsetMetres` when the line has no overview
///     chunk or the node cannot be projected onto it. Unset is legal per
///     node. Overview chunks keep fewer vertices (861 of 8,782 stations on
///     the continuous lines) so the builder projects each node onto the
///     overview chain. A span that needs an unset overview position yields
///     no `StrokeRef`s at `.overview` and the caller draws it at `.full`.
///  Both rulers are `unsetMetres` for the 205 Japanese stations with no chain
///  slot (``NodeFlag/noChainSlot``); a span touching such a node cannot become
///  a `StrokeRef` and the caller treats it as undrawable.
///
///  ## Ruler formula (normative)
///  A ruler is the one the device computes in `joinedChainCoordinates`
///  (`MapLineGeometry.swift`): the chain's intervals are joined in order, each
///  interval after the first dropping its first vertex; coordinates are the
///  display-datum coordinates of the display chunk (not raw WGS84); the value
///  at vertex 0 is 0 and each step adds
///  `hypot((b.lon - a.lon) * 111320 * cos(lat), (b.lat - a.lat) * 111320)`
///  with `lat` the mean of the two latitudes in radians, in `Double`. A
///  node's value is the ruler at its position on the chain; centimetres are
///  that value times 100 rounded to the nearest integer. Parts of
///  non-continuous lines use the same formula over the part's joined vertices.
///  The builder implements this formula; its test compares against
///  Swift-generated measures.
///
/// ## Part-range rule for non-continuous fragments
///  Lines flagged ``LineFlag/nonContinuous`` (11 Japanese lines, and every
///  line of tw, hk, mo and kr) have no single chain. Their display data is a
///  list of lane fragments (`lineKey@lane`), each holding one or more parts
///  (one per interval), and each part has its own ruler starting at 0 m at
///  its first vertex. A part is addressed by one **flat part number**: parts
///  are numbered from 0 across the line's fragments in the order the display
///  chunk lists the fragments, and within a fragment in the order of its
///  `parts`. `Line.chainCount` is the total. The file stores only the flat
///  number; the reader recovers (fragment, part within fragment) by counting,
///  and the drawn id is `"{region}|{lineKey}@{lane}#{part within fragment}"`.
///  No resident chain exists for these parts today (`ChainRef`s are built for
///  continuous lines only), so U10 must build a slicable ruler per part. For
///  these lines:
///   - `Node.chain` is the part the node's station dot sits on, and
///     `Node.fullMetres`/`overviewMetres` are measured on that part;
///   - every edge carries explicit ``Run``s (``EdgeFlag/hasRuns``), because
///     its two end nodes may sit on different parts and the track between
///     them may use several. Runs are pieces of the edge on one part each, in
///     travel order of the edge (first node to second); they, not the end
///     nodes' own positions, are authoritative for the edge's geometry;
///   - overview chunks preserve part indices, so the same `chain` addresses
///     the part at either detail.
///  A full circuit of a loop line from a station back to itself is two
///  spans with the same section index, split at any intermediate node (a span
///  never has `fromNode == toNode`).
///
///  `Edge.cumulativeCm` counts every edge, withheld ones included; the
///  distance of a span is the cumulative difference minus the `lengthCm` of
///  each withheld edge inside it.
///
///  Continuous lines use runs only for the 163 intervals that are split
///  across lane pieces. An edge without `hasRuns` runs directly between its
///  two nodes' positions on their shared chain.
public enum RailTopologyFormat {
    public static let formatName = "jtm-display-topology-v1"
    /// First four bytes of every file: ASCII `JTMT`.
    public static let magic: [UInt8] = [0x4A, 0x54, 0x4D, 0x54]
    public static let formatVersion: UInt16 = 1
    /// Appended to the region code: `{region}.topology.bin`.
    public static let fileSuffix = ".topology.bin"
    public static let noString: UInt32 = 0xFFFF_FFFF
    public static let unsetMetres: UInt32 = 0xFFFF_FFFF
    /// Day-number epoch: day 1 is 1800-01-01; 0 means "no bound".
    public static let noDate: UInt32 = 0
    public static let maxLinesPerRegion = 65_535
    public static let maxNodesPerLine = 65_535

    // MARK: Header (160 bytes)

    /// Header layout. Offsets are from the start of the file.
    public enum Header {
        public static let size = 160
        public static let magicOffset = 0            // 4 bytes
        public static let versionOffset = 4          // UInt16
        public static let headerSizeOffset = 6       // UInt16, always `size`
        public static let regionOffset = 8           // 4 ASCII bytes, NUL padded (`jp`, `tw`, ...)
        public static let flagsOffset = 12           // UInt32, 0 in v1
        public static let packageSHA256Offset = 16   // 32 bytes: SHA-256 of the compact package the builder read
        public static let displaySHA256Offset = 48   // 32 bytes: SHA-256 of `{region}.display.bin`
        public static let fileLengthOffset = 80      // UInt32: total bytes
        public static let reservedOffset = 84        // UInt32
        public static let directoryOffset = 88       // 9 x (offset UInt32, count UInt32)
        public static let directoryEntrySize = 8
    }

    /// The nine tables, in directory and file order. The directory's `count`
    /// is the number of records, except for `strings` where it is the byte
    /// length of the table (before padding).
    public enum Table: Int, CaseIterable, Sendable {
        case lines, nodes, edges, runs, links, identities, stops, stopNodes, strings

        /// Record size in bytes (`stopNodes` entries are one `UInt32`; `strings` is bytes).
        public var recordSize: Int {
            switch self {
            case .lines: Line.size
            case .nodes: Node.size
            case .edges: Edge.size
            case .runs: Run.size
            case .links: Link.size
            case .identities: Identity.size
            case .stops: Stop.size
            case .stopNodes: 4
            case .strings: 1
            }
        }
    }

    // MARK: Records

    /// `lines[]`, 56 bytes, in manifest blob order, including retired lines.
    public enum Line {
        public static let size = 56
        public static let id = 0                 // UInt32 string: line id
        public static let family = 4             // UInt32 string: operator plus normalised name
        public static let name = 8               // UInt32 string: current display name
        public static let aliases = 12           // UInt32 string: alias names joined by U+001F, or empty
        public static let institution = 16       // UInt16: institution type code
        public static let categoryMask = 18      // UInt16: statistics category bits
        public static let flags = 20             // UInt16: ``LineFlag``
        public static let chainCount = 22        // UInt16: chains (or parts) in the display chunk
        public static let validFrom = 24         // UInt32 day number
        public static let validTo = 28           // UInt32 day number, exclusive
        public static let firstNode = 32         // UInt32 global node index
        public static let nodeCount = 36         // UInt32, at most `maxNodesPerLine`
        public static let firstEdge = 40         // UInt32 global edge index
        public static let edgeCount = 44         // UInt32
        public static let firstIdentity = 48     // UInt32 index into `identities`
        public static let identityCount = 52     // UInt16
        public static let reserved = 54          // UInt16
    }

    /// `nodes[]`, 28 bytes, grouped per line in station order.
    public enum Node {
        public static let size = 28
        public static let stationCode = 0        // UInt32 string; `noString` for a junction point
        public static let fullMetres = 4         // UInt32 cm on the full ruler, or `unsetMetres`
        public static let overviewMetres = 8     // UInt32 cm on the overview ruler, or `unsetMetres`
        public static let longitude = 12         // Float32
        public static let latitude = 16          // Float32
        public static let line = 20              // UInt16 line index (matches the line's node range)
        public static let chain = 22             // UInt16 chain or part index
        public static let flags = 24             // UInt16: ``NodeFlag``
        public static let reserved = 26          // UInt16
    }

    /// `edges[]`, 24 bytes, grouped per line in node order.
    public enum Edge {
        public static let size = 24
        public static let lengthCm = 0           // UInt32 surveyed length; always above zero
        public static let cumulativeCm = 4       // UInt32 length (withheld edges included) from the line's first node to this edge's first node
        public static let validFrom = 8          // UInt32 day number
        public static let validTo = 12           // UInt32 day number, exclusive
        public static let flags = 16             // UInt16: ``EdgeFlag``
        public static let runCount = 18          // UInt16
        public static let firstRun = 20          // UInt32 index into `runs`
    }

    /// `runs[]`, 20 bytes: one piece of an edge on one chain or part.
    public enum Run {
        public static let size = 20
        public static let chain = 0              // UInt16 chain or part index
        public static let reserved = 2           // UInt16
        public static let fullFromCm = 4         // UInt32 on the full ruler, in the edge's travel order
        public static let fullToCm = 8           // UInt32
        public static let overviewFromCm = 12    // UInt32 or `unsetMetres`
        public static let overviewToCm = 16      // UInt32 or `unsetMetres`
    }

    /// `links[]`, 24 bytes: the only way to change rows.
    ///
    /// A link joins two nodes of different lines. It exists only for a
    /// reviewed physical junction (`physical-rail-junctions.json`) or a dated
    /// through service (`japan-through-services.json`). Equal station codes,
    /// equal names, shared stations, station complexes and operator families
    /// never create a link. Nodes of the same line need no link.
    public enum Link {
        public static let size = 24
        public static let nodeA = 0              // UInt32 global node index
        public static let nodeB = 4              // UInt32 global node index
        public static let kind = 8               // UInt8: ``LinkKind``
        public static let flags = 9              // UInt8: bit 0 set means directed, A to B only
        public static let reserved = 10          // UInt16
        public static let validFrom = 12         // UInt32 day number
        public static let validTo = 16           // UInt32 day number, exclusive
        public static let registryID = 20        // UInt32 string: junction or through-service row id (never empty)
    }

    /// `identities[]`, 20 bytes: dated former names of a renamed or
    /// transferred line, listed under the line (`Line.firstIdentity`).
    public enum Identity {
        public static let size = 20
        public static let line = 0               // UInt32 line index
        public static let name = 4               // UInt32 string
        public static let family = 8             // UInt32 string
        public static let validFrom = 12         // UInt32 day number
        public static let validTo = 16           // UInt32 day number, exclusive
    }

    /// `stops[]`, 16 bytes, sorted ascending by (key UTF-8 bytes, kind) so a
    /// reader binary-searches without decoding anything.
    public enum Stop {
        public static let size = 16
        public static let key = 0                // UInt32 string
        public static let keyLength = 4          // UInt16: byte length of the key
        public static let kind = 6               // UInt8: ``StopKind``
        public static let reserved = 7           // UInt8
        public static let firstNode = 8          // UInt32 index into `stopNodes`
        public static let nodeCount = 12         // UInt32
    }

    // MARK: Flags and kinds

    public struct LineFlag: OptionSet, Sendable {
        public let rawValue: UInt16
        public init(rawValue: UInt16) { self.rawValue = rawValue }
        public static let loop = LineFlag(rawValue: 1 << 0)
        public static let highSpeed = LineFlag(rawValue: 1 << 1)
        public static let pairedUpDown = LineFlag(rawValue: 1 << 2)
        /// Closed or renamed away; `validTo` says when. Still routable for dated trips.
        public static let retired = LineFlag(rawValue: 1 << 3)
        /// Display data is separate parts, not one chain: see the part-range rule.
        public static let nonContinuous = LineFlag(rawValue: 1 << 4)
    }

    public struct NodeFlag: OptionSet, Sendable {
        public let rawValue: UInt16
        public init(rawValue: UInt16) { self.rawValue = rawValue }
        /// A junction point between stations: no station code, so no stop lookup reaches it.
        public static let junctionPoint = NodeFlag(rawValue: 1 << 0)
        /// Both rulers are `unsetMetres`: the station has no slot on any chain.
        public static let noChainSlot = NodeFlag(rawValue: 1 << 1)
    }

    public struct EdgeFlag: OptionSet, Sendable {
        public let rawValue: UInt16
        public init(rawValue: UInt16) { self.rawValue = rawValue }
        /// Travel from the edge's first node to its second is allowed.
        public static let forward = EdgeFlag(rawValue: 1 << 0)
        /// Travel from the second node to the first is allowed.
        public static let reverse = EdgeFlag(rawValue: 1 << 1)
        /// Drawn dashed: the interval is withheld (not proven track). Distance excludes it (its `lengthCm` is subtracted from a span's cumulative difference).
        public static let withheld = EdgeFlag(rawValue: 1 << 2)
        /// The edge's geometry is `runCount` runs, not the straight node-to-node range.
        public static let hasRuns = EdgeFlag(rawValue: 1 << 3)
    }

    public enum LinkKind: UInt8, Sendable {
        case physicalJunction = 1
        case throughService = 2
    }

    public enum StopKind: UInt8, Sendable {
        /// A platform or station code as found on an interval code (`stA`).
        case platformCode = 1
        /// A registry station id (`st:*`).
        case registryStationID = 2
        /// A station group code.
        case groupCode = 3
    }

    // MARK: Dates

    /// The day number of an ISO `YYYY-MM-DD` date: 1 for 1800-01-01. Nil when
    /// malformed or before 1800-01-01. A source `valid_to` converts with this
    /// function unchanged (the file is half-open like the sources).
    public static func dayNumber(ofISODate iso: String) -> UInt32? {
        let parts = iso.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), d >= 1, d <= daysInMonth(year: y, month: m) else { return nil }
        let n = daysFromCivil(year: y, month: m, day: d) - daysFromCivil(year: 1799, month: 12, day: 31)
        return n >= 1 ? UInt32(n) : nil
    }

    /// Whether a row with `validFrom`/`validTo` (half-open, 0 is open) applies
    /// on `day`. An undated query (`nil`) matches exactly the rows without a
    /// `validTo`, whatever `validFrom` is (ADR 0011: the current network).
    public static func isValid(on day: UInt32?, from validFrom: UInt32, to validTo: UInt32) -> Bool {
        guard let day else { return validTo == noDate }
        if validFrom != noDate, day < validFrom { return false }
        if validTo != noDate, day >= validTo { return false }
        return true
    }

    private static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2: (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    /// Days since 1970-01-01 (proleptic Gregorian).
    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    // MARK: Header parsing

    public enum FormatError: Error, Equatable, Sendable {
        case truncated
        case badMagic
        case unsupportedVersion(UInt16)
        case badHeaderSize(UInt16)
        case lengthMismatch(declared: UInt32, actual: Int)
        /// A table starts outside the file, is misaligned, or runs past its end.
        case badTable(Table)
        /// The file's recorded display SHA-256 is not the blob's (raised by the reader).
        case displayBlobMismatch
    }

    /// The decoded header and table directory.
    public struct ParsedHeader: Sendable {
        public var version: UInt16
        public var region: String
        public var flags: UInt32
        public var packageSHA256: [UInt8]
        public var displaySHA256: [UInt8]
        public var fileLength: UInt32
        /// Byte offset and record count of each table, indexed by `Table.rawValue`.
        public var offsets: [Int]
        public var counts: [Int]

        public func offset(_ table: Table) -> Int { offsets[table.rawValue] }
        public func count(_ table: Table) -> Int { counts[table.rawValue] }
    }

    /// Validates the header and directory against the file's length. Reads no
    /// record: that is the reader's job.
    public static func parseHeader(_ data: Data) throws -> ParsedHeader {
        guard data.count >= Header.size else { throw FormatError.truncated }
        guard data.rawBytes(0, 4) == magic else { throw FormatError.badMagic }
        let version = data.u16(Header.versionOffset)
        guard version == formatVersion else { throw FormatError.unsupportedVersion(version) }
        let headerSize = data.u16(Header.headerSizeOffset)
        guard Int(headerSize) == Header.size else { throw FormatError.badHeaderSize(headerSize) }
        let length = data.u32(Header.fileLengthOffset)
        guard Int(length) == data.count else {
            throw FormatError.lengthMismatch(declared: length, actual: data.count)
        }
        var offsets: [Int] = [], counts: [Int] = []
        for table in Table.allCases {
            let entry = Header.directoryOffset + table.rawValue * Header.directoryEntrySize
            let offset = Int(data.u32(entry)), count = Int(data.u32(entry + 4))
            let (bytes, overflow) = count.multipliedReportingOverflow(by: table.recordSize)
            guard !overflow, offset % 4 == 0, offset >= Header.size,
                  offset + bytes <= data.count else { throw FormatError.badTable(table) }
            offsets.append(offset); counts.append(count)
        }
        let region = data.rawBytes(Header.regionOffset, 4).prefix { $0 != 0 }
        return ParsedHeader(
            version: version, region: String(decoding: region, as: UTF8.self),
            flags: data.u32(Header.flagsOffset),
            packageSHA256: data.rawBytes(Header.packageSHA256Offset, 32),
            displaySHA256: data.rawBytes(Header.displaySHA256Offset, 32),
            fileLength: length, offsets: offsets, counts: counts)
    }
}

// MARK: - Little-endian access (shared by the reader and the tests)

extension Data {
    /// Little-endian reads at an offset from the first byte. Callers
    /// bounds-check through the table directory first; these trap on overrun.
    /// Internal to RailCore so they do not leak onto `Data` elsewhere.
    func u8(_ offset: Int) -> UInt8 { load(offset, as: UInt8.self) }
    func u16(_ offset: Int) -> UInt16 { UInt16(littleEndian: load(offset, as: UInt16.self)) }
    func u32(_ offset: Int) -> UInt32 { UInt32(littleEndian: load(offset, as: UInt32.self)) }
    func f32(_ offset: Int) -> Float { Float(bitPattern: u32(offset)) }
    /// Allocates: header and test use only, never in a hot loop.
    func rawBytes(_ offset: Int, _ count: Int) -> [UInt8] {
        Array(self[(startIndex + offset)..<(startIndex + offset + count)])
    }

    private func load<T>(_ offset: Int, as type: T.Type) -> T {
        precondition(offset >= 0 && offset + MemoryLayout<T>.size <= count, "topology read out of range")
        return withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: T.self) }
    }
}

// MARK: - RailTopology: public signatures (STUBS)

/// An immutable, `Sendable` view over a mapped topology file. Opening it
/// validates the header only; every query reads records in place.
///
/// STUB (U0b): the bodies below only fix the signatures. U2 deletes this
/// declaration and moves the type to `RailTopology.swift` with real reads and
/// `RailTopologyRouter.swift`; no other unit should edit it.
public struct RailTopology: Sendable {
    /// A node: line index plus node ordinal within that line (see "Id spaces").
    public struct NodeRef: Sendable, Hashable {
        public var line: UInt16
        public var node: UInt16
        public init(line: UInt16, node: UInt16) { self.line = line; self.node = node }
    }

    /// A ride's run along one line: from one node to another, addressed by
    /// ordinals of that line. Direction is the order of the two nodes (see
    /// ``RideRefs/Span`` for loop lines).
    public struct Span: Sendable, Hashable {
        public var line: UInt16
        public var fromNode: UInt16
        public var toNode: UInt16
        /// Wraps across a loop line's closing edge; false on non-loop lines.
        public var wraps: Bool
        public init(line: UInt16, fromNode: UInt16, toNode: UInt16, wraps: Bool = false) {
            self.line = line; self.fromNode = fromNode; self.toNode = toNode; self.wraps = wraps
        }
    }

    /// Which chunk's ruler a `StrokeRef` is measured on.
    public enum Detail: Sendable { case full, overview }

    /// One section's routing question.
    public struct SectionQuery: Sendable {
        /// Candidate start and end nodes (a station may have several, one per line).
        public var from: [NodeRef]
        public var to: [NodeRef]
        /// Day number of the ride (see ``RailTopologyFormat/dayNumber(ofISODate:)``);
        /// nil: undated, only rows without a `validTo` count.
        public var day: UInt32?
        /// Hard filters: when non-empty only these line ids / institution codes may be used.
        public var lineIDs: Set<String>
        public var institutions: Set<UInt16>
        /// Soft preference: these lines cost less.
        public var preferredLineIDs: Set<String>
        public init(from: [NodeRef], to: [NodeRef], day: UInt32? = nil,
                    lineIDs: Set<String> = [], institutions: Set<UInt16> = [],
                    preferredLineIDs: Set<String> = []) {
            self.from = from; self.to = to; self.day = day
            self.lineIDs = lineIDs; self.institutions = institutions
            self.preferredLineIDs = preferredLineIDs
        }
    }

    /// The router's answer: spans in travel order and their length.
    public struct SectionPath: Sendable {
        public var spans: [Span]
        public var lengthCm: UInt64
        /// True when found only after dropping the line filter: drawn dotted, excluded from distance.
        public var unproven: Bool
        public init(spans: [Span], lengthCm: UInt64, unproven: Bool = false) {
            self.spans = spans; self.lengthCm = lengthCm; self.unproven = unproven
        }
    }

    public let header: RailTopologyFormat.ParsedHeader
    /// The file's bytes, normally `Data(contentsOf:options: .alwaysMapped)`.
    public let data: Data

    /// Opens a file. Throws a ``RailTopologyFormat/FormatError`` for a
    /// truncated, corrupt or wrong-version file; no decode step. U2 adds the
    /// display-blob SHA-256 check.
    public init(data: Data) throws {
        self.header = try RailTopologyFormat.parseHeader(data)
        self.data = data
    }

    /// Nodes for a platform code, registry station id or group code, in
    /// ascending global node index. Empty when unknown. STUB.
    public func nodes(forStop key: String) -> [NodeRef] { [] }

    /// Spans for authored interval codes (`lineID@stA:stB~n`, in travel
    /// order); nil when any code does not resolve. STUB.
    public func spans(forIntervalCodes codes: [String]) -> [Span]? { nil }

    /// Deterministic shortest-length path with hard filters and dated links;
    /// nil when none exists. STUB.
    public func route(_ query: SectionQuery) -> SectionPath? { nil }

    /// Surveyed length of a span in centimetres: a cumulative-length
    /// subtraction (plus the closing edge for a wrapping span). STUB.
    public func lengthCm(of span: Span) -> UInt64 { 0 }

    /// The span as `StrokeRef`s on the given detail's ruler: one per
    /// contiguous piece (a new piece starts wherever the chain or part
    /// changes), in travel order, `from > to` when against the chain's own
    /// direction. Empty when a node has no chain slot or a ruler is unset.
    /// STUB.
    public func strokeRefs(of span: Span, detail: Detail) -> [StrokeRef] { [] }
}
