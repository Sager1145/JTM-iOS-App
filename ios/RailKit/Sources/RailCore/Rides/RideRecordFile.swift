import CryptoKit
import Foundation

// MARK: - RideRecordFile: the single ride cache file (U3)
//
// One file holds the resolved `RideRefs` of every cached trip, negative
// results (`unresolved`) included, so a warm launch reads
// one file and resolves nothing. Meant for `Caches/RailMap/rides-v1.bin`;
// this type does no path policy of its own.
//
// Layout, little-endian, no padding:
//
//   header (88 bytes)
//     0   4   magic "JTRR"
//     4   2   formatVersion (1)
//     6   2   semanticsVersion: what a ref means (resolver rules); bumped by
//             hand whenever the resolver's behaviour changes
//     8  32   topologyRevision: SHA-256 over ALL bundled region topology
//             files (not only the enabled regions, so enabling a region never
//             discards the cache) the refs were resolved against (see `revision(ofTopologyFileHashes:)`)
//    40  32   timetableRevision: SHA-256 of the timetable database the
//             timetable-evidence step read; a new timetable is a miss
//    72   4   entryCount
//    76   4   bodyLength (bytes after the header)
//    80   8   bodyChecksum: first 8 bytes of SHA-256 of the body
//   body: entryCount entries sorted ascending by (key.high, key.low)
//     key 16 (high then low) | outcome u8 | reserved u8 (0) |
//     spanCount u16 | gapCount u16 | spans 8 each | gaps 3 each
//     (section u16, reason u8)
//
// `disabledRegion` outcomes are never stored (encode drops them, decode
// rejects them): they cost nothing to recompute and nothing in the key or
// header says which regions were enabled, so a stored one would go stale when
// the user enables the region.
//
// Anything wrong (missing file, truncated, bad magic, bad checksum, bad
// counts, an entry over the per-trip limit, duplicate keys) reads as empty.
// A span with fromNode == toNode, or an empty/unknown gap reason, is corrupt.
// A different topology or timetable revision or semantics version is a miss, also empty:
// line indices, ordinals and metres mean nothing against another file.
public enum RideRecordFile {
    public static let magic: [UInt8] = [0x4A, 0x54, 0x52, 0x52]  // "JTRR"
    public static let formatVersion: UInt16 = 1
    /// Bump when the resolver's rules change in a way that can change refs.
    public static let semanticsVersion: UInt16 = 1
    public static let headerSize = 88
    public static let revisionByteCount = 32
    /// Budget for one trip's entry. An oversize entry is not cached (the trip
    /// is resolved on every load) rather than failing the whole file.
    public static let maxBytesPerTrip = 4096

    private static let entryFixedSize = RideRefs.Key.byteCount + 6
    private static let gapByteCount = 3

    public enum Status: Sendable, Equatable {
        case loaded
        case missing
        case corrupt
        case topologyRevisionMismatch
        case timetableRevisionMismatch
        case semanticsMismatch
    }

    public struct ReadResult: Sendable {
        public var status: Status
        /// Empty unless `status == .loaded`.
        public var entries: [RideRefs.Key: RideRefs]
    }

    public enum WriteError: Error, Equatable { case badRevision }

    /// One revision value for a set of topology files (one per region): the
    /// SHA-256 of their SHA-256s sorted ascending and concatenated, so the
    /// order the regions were loaded in does not matter.
    public static func revision(ofTopologyFileHashes hashes: [[UInt8]]) -> [UInt8] {
        var sha = SHA256()
        for hash in hashes.sorted(by: { $0.lexicographicallyPrecedes($1) }) { sha.update(data: hash) }
        return Array(sha.finalize())
    }

    /// Highest valid `GapReason` bit set.
    private static let knownGapReasons = RideRefs.GapReason([.noPath, .ambiguous, .unknownStop, .withheld])

    /// Bytes one trip occupies in the file.
    public static func entryByteCount(of ride: RideRefs) -> Int {
        entryFixedSize + ride.spans.count * RideRefs.Span.byteCount + ride.gaps.count * gapByteCount
    }

    // MARK: encode

    /// Encodes `rides`. `disabledRegion` entries and entries over
    /// `maxBytesPerTrip` are left out; for a
    /// repeated key the last entry wins. Output is deterministic.
    public static func encode(_ rides: [RideRefs], topologyRevision: [UInt8], timetableRevision: [UInt8]) throws -> Data {
        guard topologyRevision.count == revisionByteCount,
              timetableRevision.count == revisionByteCount else { throw WriteError.badRevision }
        var byKey: [RideRefs.Key: RideRefs] = [:]
        for ride in rides where ride.outcome != .disabledRegion && entryByteCount(of: ride) <= maxBytesPerTrip {
            byKey[ride.key] = ride
        }
        let ordered = byKey.values.sorted { ($0.key.high, $0.key.low) < ($1.key.high, $1.key.low) }
        var body = [UInt8]()
        body.reserveCapacity(ordered.reduce(0) { $0 + entryByteCount(of: $1) })
        for ride in ordered {
            append(ride.key.high, to: &body)
            append(ride.key.low, to: &body)
            body.append(ride.outcome.rawValue)
            body.append(0)
            append(UInt16(ride.spans.count), to: &body)
            append(UInt16(ride.gaps.count), to: &body)
            for span in ride.spans { body.append(contentsOf: span.bytes) }
            for gap in ride.gaps {
                append(gap.section, to: &body)
                body.append(gap.reason.rawValue)
            }
        }
        var out = [UInt8]()
        out.reserveCapacity(headerSize + body.count)
        out.append(contentsOf: magic)
        append(formatVersion, to: &out)
        append(semanticsVersion, to: &out)
        out.append(contentsOf: topologyRevision)
        out.append(contentsOf: timetableRevision)
        append(UInt32(ordered.count), to: &out)
        append(UInt32(body.count), to: &out)
        out.append(contentsOf: checksum(body))
        out.append(contentsOf: body)
        return Data(out)
    }

    // MARK: decode

    public static func decode(_ data: Data, topologyRevision: [UInt8], timetableRevision: [UInt8]) -> ReadResult {
        func fail(_ status: Status) -> ReadResult { ReadResult(status: status, entries: [:]) }
        guard topologyRevision.count == revisionByteCount, timetableRevision.count == revisionByteCount
        else { return fail(.corrupt) }
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> ReadResult in
            guard raw.count >= headerSize, raw[0] == magic[0], raw[1] == magic[1],
                  raw[2] == magic[2], raw[3] == magic[3] else { return fail(.corrupt) }
            func u16(_ o: Int) -> Int { Int(raw.loadUnaligned(fromByteOffset: o, as: UInt16.self).littleEndian) }
            func u32(_ o: Int) -> Int { Int(raw.loadUnaligned(fromByteOffset: o, as: UInt32.self).littleEndian) }
            func u64(_ o: Int) -> UInt64 { raw.loadUnaligned(fromByteOffset: o, as: UInt64.self).littleEndian }
            guard u16(4) == Int(formatVersion) else { return fail(.corrupt) }
            guard u16(6) == Int(semanticsVersion) else { return fail(.semanticsMismatch) }
            guard raw[8..<40].elementsEqual(topologyRevision) else { return fail(.topologyRevisionMismatch) }
            guard raw[40..<72].elementsEqual(timetableRevision) else { return fail(.timetableRevisionMismatch) }
            let count = u32(72), bodyLength = u32(76)
            guard raw.count == headerSize + bodyLength, count <= bodyLength / entryFixedSize
            else { return fail(.corrupt) }
            let digest = SHA256.hash(data: UnsafeRawBufferPointer(rebasing: raw[headerSize...]))
            guard raw[80..<88].elementsEqual(digest.prefix(8)) else { return fail(.corrupt) }

            var entries: [RideRefs.Key: RideRefs] = [:]
            entries.reserveCapacity(count)
            var cursor = headerSize
            for _ in 0..<count {
                guard cursor + entryFixedSize <= raw.count else { return fail(.corrupt) }
                let key = RideRefs.Key(high: u64(cursor), low: u64(cursor + 8))
                guard let outcome = RideRefs.Outcome(rawValue: raw[cursor + 16]),
                      outcome != .disabledRegion, raw[cursor + 17] == 0 else { return fail(.corrupt) }
                let spanCount = u16(cursor + 18), gapCount = u16(cursor + 20)
                let size = entryFixedSize + spanCount * RideRefs.Span.byteCount + gapCount * gapByteCount
                guard size <= maxBytesPerTrip, cursor + size <= raw.count, entries[key] == nil
                else { return fail(.corrupt) }
                var at = cursor + entryFixedSize
                var spans: [RideRefs.Span] = []
                spans.reserveCapacity(spanCount)
                for _ in 0..<spanCount {
                    let tag = UInt16(u16(at + 6))
                    guard u16(at + 2) != u16(at + 4) else { return fail(.corrupt) }
                    spans.append(RideRefs.Span(
                        span: RailTopology.Span(line: UInt16(u16(at)), fromNode: UInt16(u16(at + 2)),
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
                entries[key] = RideRefs(key: key, outcome: outcome, spans: spans, gaps: gaps)
                cursor += size
            }
            guard cursor == raw.count else { return fail(.corrupt) }
            return ReadResult(status: .loaded, entries: entries)
        }
    }

    // MARK: files

    /// Reads and decodes a file. A missing or unreadable file is `.missing`.
    public static func read(from url: URL, topologyRevision: [UInt8], timetableRevision: [UInt8]) -> ReadResult {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return ReadResult(status: .missing, entries: [:])
        }
        return decode(data, topologyRevision: topologyRevision, timetableRevision: timetableRevision)
    }

    /// Encodes and writes atomically (temporary file, then replace).
    public static func write(_ rides: [RideRefs], to url: URL, topologyRevision: [UInt8],
                             timetableRevision: [UInt8]) throws {
        let data = try encode(rides, topologyRevision: topologyRevision, timetableRevision: timetableRevision)
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
