import CryptoKit
import Foundation

// MARK: - RideRecordFile: the single ride cache file (v2, keyed per line)
//
// One file holds the resolved `RideRefs` of every cached trip, negative
// results (`unresolved`) included, so a warm launch reads one file and
// resolves nothing. Meant for `Caches/RailMap/rides-v2.bin`; this type does no
// path policy of its own.
//
// A trip's stored result stays valid until one of the lines it uses changes or
// its own route fields change (the key, `RideKey`). The file does not carry a
// whole-topology revision: it carries its own line table, one row per line any
// stored span uses, `(lineKey, contentHash)`:
//  - `lineKey` is the first 8 bytes of SHA-256 over region, NUL and line id: the
//    line's identity, stable across data builds;
//  - `contentHash` is the topology file's own per-line hash
//    (`RailTopologyFormat.Line.contentHash`): everything a trip over the line
//    depends on.
// A span's `line` field in the file indexes this table, not a topology. On read each
// row is matched to the current topology by `lineKey`. Equal hash: the span is
// remapped to the current line index and the trip is kept untouched. Different or
// missing row: only the trips that use that line are listed in `stale`, to be
// re-solved, and are not returned as entries. A data rebuild therefore lists exactly
// the trips to re-solve and nothing else.
//
// Failures are results too: an `unresolved` trip, and the gaps of a `partial` one,
// stay as stored. They are returned in `failed` and retried only when the user
// asks to repair, never at launch, never because a line changed (a trip with no
// span uses no line). A `partial` trip is still re-solved as a whole when a line
// its spans use changed.
//
// Layout, little-endian, no padding:
//
//   header (64 bytes)
//     0   4   magic "JTRR"
//     4   2   formatVersion (2)
//     6   2   semanticsVersion: what a ref means (resolver rules); bumped by
//             hand whenever the resolver's behaviour changes
//     8  32   timetableRevision: SHA-256 of the timetable database the
//             timetable-evidence step read; a new timetable is a miss
//    40   2   reserved (0)
//    42   2   lineCount
//    44   4   entryCount
//    48   4   bodyLength (bytes after the header)
//    52   4   reserved (0)
//    56   8   bodyChecksum: first 8 bytes of SHA-256 of the body
//   body: lineCount line rows sorted ascending by lineKey (lineKey u64 |
//     contentHash u64), then entryCount entries sorted ascending by
//     (key.high, key.low): key 16 (high then low) | outcome u8 | reserved u8 (0) |
//     spanCount u16 | gapCount u16 | spans 8 each | gaps 3 each
//     (section u16, reason u8)
//
// `disabledRegion` outcomes are never stored (encode drops them, decode
// rejects them): they cost nothing to recompute and nothing in the key says
// which regions were enabled, so a stored one would go stale when the user
// enables the region.
//
// Anything wrong (missing file, truncated, bad magic, bad checksum, bad
// counts, a span naming a line row that is not there, an entry over the
// per-trip limit, duplicate keys or lines) reads as empty. A different timetable
// revision or semantics version is a miss, also empty.
public enum RideRecordFile {
    public static let magic: [UInt8] = [0x4A, 0x54, 0x52, 0x52]  // "JTRR"
    public static let formatVersion: UInt16 = 2
    /// Bump when the resolver's rules change in a way that can change refs.
    public static let semanticsVersion: UInt16 = 1
    public static let headerSize = 64
    public static let revisionByteCount = 32
    /// Budget for one trip's entry. An oversize entry is not cached (the trip
    /// is resolved on every load) rather than failing the whole file.
    public static let maxBytesPerTrip = 4096

    private static let entryFixedSize = RideRefs.Key.byteCount + 6
    private static let gapByteCount = 3
    private static let lineRowSize = 16

    public enum Status: Sendable, Equatable {
        case loaded
        case missing
        case corrupt
        case timetableRevisionMismatch
        case semanticsMismatch
    }

    /// A line's identity and content in one topology: a row of the file's line table.
    public struct LineStamp: Sendable, Hashable {
        public var lineKey: UInt64
        public var contentHash: UInt64
        public init(lineKey: UInt64, contentHash: UInt64) { self.lineKey = lineKey; self.contentHash = contentHash }
    }

    /// The stamps of one region's topology, indexed by line index.
    public struct RegionStamps: Sendable {
        public var region: String
        public var stamps: [LineStamp]
        public init(region: String, stamps: [LineStamp]) { self.region = region; self.stamps = stamps }
    }

    /// A ride and the region whose topology its line indices belong to.
    public struct StoredRide: Sendable {
        public var region: String
        public var refs: RideRefs
        public init(region: String, refs: RideRefs) { self.region = region; self.refs = refs }
    }

    public struct ReadResult: Sendable {
        public var status: Status
        /// Valid trips, spans remapped to the current topology's line indices.
        /// Empty unless `status == .loaded`.
        public var entries: [RideRefs.Key: RideRefs]
        /// Trips that use a line which changed or is gone: re-solve these, exactly these.
        public var stale: [RideRefs.Key]
        /// Valid trips that are stored failures (unresolved, or with gaps): retried only on repair.
        public var failed: [RideRefs.Key]
    }

    public enum WriteError: Error, Equatable {
        case badRevision
        /// A ride's span names a line the region's stamps do not have, or a region that was not given.
        case unknownLine
        case tooManyLines
    }

    /// The line's identity: the first 8 bytes (little-endian) of SHA-256 over region, NUL, line id.
    public static func lineKey(region: String, lineID: String) -> UInt64 {
        var sha = SHA256()
        sha.update(data: Data(region.utf8)); sha.update(data: [0]); sha.update(data: Data(lineID.utf8))
        return Array(sha.finalize().prefix(8)).enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << (8 * UInt64($1.offset)) }
    }

    /// Highest valid `GapReason` bit set.
    private static let knownGapReasons = RideRefs.GapReason([.noPath, .ambiguous, .unknownStop, .withheld])

    /// Bytes one trip occupies in the file.
    public static func entryByteCount(of ride: RideRefs) -> Int {
        entryFixedSize + ride.spans.count * RideRefs.Span.byteCount + ride.gaps.count * gapByteCount
    }

    /// Whether a stored result is a failure: nothing resolved, or some section a gap.
    public static func isFailure(_ ride: RideRefs) -> Bool {
        ride.outcome == .unresolved || ride.outcome == .partial || !ride.gaps.isEmpty
    }

    // MARK: encode

    /// Encodes `rides`. `disabledRegion` entries and entries over `maxBytesPerTrip` are left
    /// out; for a repeated key the last entry wins. The line table holds only the lines the
    /// kept rides use. Output is deterministic and independent of input order.
    public static func encode(_ rides: [StoredRide], stamps: [RegionStamps], timetableRevision: [UInt8]) throws -> Data {
        guard timetableRevision.count == revisionByteCount else { throw WriteError.badRevision }
        let stampsByRegion = Dictionary(stamps.map { ($0.region, $0.stamps) }, uniquingKeysWith: { _, last in last })
        var byKey: [RideRefs.Key: StoredRide] = [:]
        for ride in rides where ride.refs.outcome != .disabledRegion && entryByteCount(of: ride.refs) <= maxBytesPerTrip {
            byKey[ride.refs.key] = ride
        }
        let ordered = byKey.values.sorted { ($0.refs.key.high, $0.refs.key.low) < ($1.refs.key.high, $1.refs.key.low) }
        var used: [UInt64: UInt64] = [:]
        for ride in ordered {
            guard let regionStamps = stampsByRegion[ride.region] else {
                if ride.refs.spans.isEmpty { continue }
                throw WriteError.unknownLine
            }
            for span in ride.refs.spans {
                guard Int(span.span.line) < regionStamps.count else { throw WriteError.unknownLine }
                let stamp = regionStamps[Int(span.span.line)]
                used[stamp.lineKey] = stamp.contentHash
            }
        }
        guard used.count <= Int(UInt16.max) else { throw WriteError.tooManyLines }
        let table = used.sorted { $0.key < $1.key }
        let rowOf = Dictionary(uniqueKeysWithValues: table.enumerated().map { ($1.key, UInt16($0)) })

        var body = [UInt8]()
        body.reserveCapacity(table.count * lineRowSize + ordered.reduce(0) { $0 + entryByteCount(of: $1.refs) })
        for row in table { append(row.key, to: &body); append(row.value, to: &body) }
        for ride in ordered {
            let refs = ride.refs
            append(refs.key.high, to: &body)
            append(refs.key.low, to: &body)
            body.append(refs.outcome.rawValue)
            body.append(0)
            append(UInt16(refs.spans.count), to: &body)
            append(UInt16(refs.gaps.count), to: &body)
            for span in refs.spans {
                var stored = span
                stored.span.line = rowOf[stampsByRegion[ride.region]![Int(span.span.line)].lineKey]!
                body.append(contentsOf: stored.bytes)
            }
            for gap in refs.gaps {
                append(gap.section, to: &body)
                body.append(gap.reason.rawValue)
            }
        }
        var out = [UInt8]()
        out.reserveCapacity(headerSize + body.count)
        out.append(contentsOf: magic)
        append(formatVersion, to: &out)
        append(semanticsVersion, to: &out)
        out.append(contentsOf: timetableRevision)
        append(UInt16(0), to: &out)
        append(UInt16(table.count), to: &out)
        append(UInt32(ordered.count), to: &out)
        append(UInt32(body.count), to: &out)
        append(UInt32(0), to: &out)
        out.append(contentsOf: checksum(body))
        out.append(contentsOf: body)
        return Data(out)
    }

    // MARK: decode

    /// Decodes a file against the current topologies' stamps (one entry per loaded region).
    public static func decode(_ data: Data, current: [RegionStamps], timetableRevision: [UInt8]) -> ReadResult {
        func fail(_ status: Status) -> ReadResult { ReadResult(status: status, entries: [:], stale: [], failed: []) }
        guard timetableRevision.count == revisionByteCount else { return fail(.corrupt) }
        var now: [UInt64: (index: UInt16, hash: UInt64)] = [:]
        for region in current {
            for (index, stamp) in region.stamps.enumerated() where index <= Int(UInt16.max) {
                now[stamp.lineKey] = (UInt16(index), stamp.contentHash)
            }
        }
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> ReadResult in
            guard raw.count >= headerSize, raw[0] == magic[0], raw[1] == magic[1],
                  raw[2] == magic[2], raw[3] == magic[3] else { return fail(.corrupt) }
            func u16(_ o: Int) -> Int { Int(raw.loadUnaligned(fromByteOffset: o, as: UInt16.self).littleEndian) }
            func u32(_ o: Int) -> Int { Int(raw.loadUnaligned(fromByteOffset: o, as: UInt32.self).littleEndian) }
            func u64(_ o: Int) -> UInt64 { raw.loadUnaligned(fromByteOffset: o, as: UInt64.self).littleEndian }
            guard u16(4) == Int(formatVersion) else { return fail(.corrupt) }
            guard u16(6) == Int(semanticsVersion) else { return fail(.semanticsMismatch) }
            guard raw[8..<40].elementsEqual(timetableRevision) else { return fail(.timetableRevisionMismatch) }
            guard u16(40) == 0, u32(52) == 0 else { return fail(.corrupt) }
            let lineCount = u16(42), count = u32(44), bodyLength = u32(48)
            let tableBytes = lineCount * lineRowSize
            guard raw.count == headerSize + bodyLength, tableBytes <= bodyLength,
                  count <= (bodyLength - tableBytes) / entryFixedSize
            else { return fail(.corrupt) }
            let digest = SHA256.hash(data: UnsafeRawBufferPointer(rebasing: raw[headerSize...]))
            guard raw[56..<64].elementsEqual(digest.prefix(8)) else { return fail(.corrupt) }

            // The file's line table against the current topologies: the new index, or nil when the line
            // changed or is gone.
            var remap = [UInt16?](repeating: nil, count: lineCount)
            var previousKey: UInt64?
            for row in 0..<lineCount {
                let key = u64(headerSize + row * lineRowSize), hash = u64(headerSize + row * lineRowSize + 8)
                if let previousKey, key <= previousKey { return fail(.corrupt) }
                previousKey = key
                if let found = now[key], found.hash == hash { remap[row] = found.index }
            }

            var entries: [RideRefs.Key: RideRefs] = [:]
            var seen = Set<RideRefs.Key>()
            var stale: [RideRefs.Key] = [], failed: [RideRefs.Key] = []
            entries.reserveCapacity(count)
            var cursor = headerSize + tableBytes
            for _ in 0..<count {
                guard cursor + entryFixedSize <= raw.count else { return fail(.corrupt) }
                let key = RideRefs.Key(high: u64(cursor), low: u64(cursor + 8))
                guard let outcome = RideRefs.Outcome(rawValue: raw[cursor + 16]),
                      outcome != .disabledRegion, raw[cursor + 17] == 0 else { return fail(.corrupt) }
                let spanCount = u16(cursor + 18), gapCount = u16(cursor + 20)
                let size = entryFixedSize + spanCount * RideRefs.Span.byteCount + gapCount * gapByteCount
                guard size <= maxBytesPerTrip, cursor + size <= raw.count, seen.insert(key).inserted
                else { return fail(.corrupt) }
                var at = cursor + entryFixedSize
                var spans: [RideRefs.Span] = []
                spans.reserveCapacity(spanCount)
                var usesChangedLine = false
                for _ in 0..<spanCount {
                    let tag = UInt16(u16(at + 6))
                    let row = u16(at)
                    guard row < lineCount, u16(at + 2) != u16(at + 4) else { return fail(.corrupt) }
                    let line = remap[row]
                    if line == nil { usesChangedLine = true }
                    spans.append(RideRefs.Span(
                        span: RailTopology.Span(line: line ?? UInt16(row), fromNode: UInt16(u16(at + 2)),
                                                toNode: UInt16(u16(at + 4)), wraps: tag & (1 << 15) != 0),
                        section: tag & RideRefs.Span.maxSection, unproven: tag & (1 << 14) != 0))
                    at += RideRefs.Span.byteCount
                }
                var gaps: [RideRefs.Gap] = []
                gaps.reserveCapacity(gapCount)
                for _ in 0..<gapCount {
                    let section = UInt16(u16(at))
                    let reason = RideRefs.GapReason(rawValue: raw[at + 2])
                    guard section <= RideRefs.Span.maxSection, !reason.isEmpty,
                          knownGapReasons.isSuperset(of: reason) else { return fail(.corrupt) }
                    gaps.append(RideRefs.Gap(section: section, reason: reason))
                    at += gapByteCount
                }
                let ride = RideRefs(key: key, outcome: outcome, spans: spans, gaps: gaps)
                if usesChangedLine { stale.append(key) }
                else {
                    entries[key] = ride
                    if isFailure(ride) { failed.append(key) }
                }
                cursor += size
            }
            guard cursor == raw.count else { return fail(.corrupt) }
            return ReadResult(status: .loaded, entries: entries, stale: stale, failed: failed)
        }
    }

    // MARK: files

    /// Reads and decodes a file. A missing or unreadable file is `.missing`.
    public static func read(from url: URL, current: [RegionStamps], timetableRevision: [UInt8]) -> ReadResult {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return ReadResult(status: .missing, entries: [:], stale: [], failed: [])
        }
        return decode(data, current: current, timetableRevision: timetableRevision)
    }

    /// Encodes and writes atomically (temporary file, then replace).
    public static func write(_ rides: [StoredRide], stamps: [RegionStamps], to url: URL,
                             timetableRevision: [UInt8]) throws {
        let data = try encode(rides, stamps: stamps, timetableRevision: timetableRevision)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    // MARK: byte helpers

    private static func checksum(_ body: [UInt8]) -> [UInt8] {
        Array(SHA256.hash(data: body).prefix(8))
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to bytes: inout [UInt8]) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { bytes.append(contentsOf: $0) }
    }
}

extension RailTopology {
    /// The ride cache's view of this topology: one stamp per line, indexed by line index
    /// (see ``RideRecordFile``).
    public var rideStamps: RideRecordFile.RegionStamps {
        RideRecordFile.RegionStamps(
            region: header.region,
            stamps: (0..<lineCount).map { line in
                RideRecordFile.LineStamp(
                    lineKey: RideRecordFile.lineKey(region: header.region, lineID: lineID(UInt16(line)) ?? ""),
                    contentHash: contentHash(ofLine: UInt16(line)) ?? 0)
            })
    }
}
