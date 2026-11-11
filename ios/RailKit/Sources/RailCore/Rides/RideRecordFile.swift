import CryptoKit
import Foundation

// MARK: - RideRecordFile: the single ride cache file (U3)
//
// One file holds the resolved `RideRefs` of every cached trip, negative
// results (`unresolved`, `disabledRegion`) included, so a warm launch reads
// one file and resolves nothing. Meant for `Caches/RailMap/rides-v1.bin`;
// this type does no path policy of its own.
//
// Layout, little-endian, no padding:
//
//   header (56 bytes)
//     0   4   magic "JTRR"
//     4   2   formatVersion (1)
//     6   2   semanticsVersion: what a ref means (resolver rules); bumped by
//             hand whenever the resolver's behaviour changes
//     8  32   topologyRevision: SHA-256 over the topology files the refs
//             were resolved against (see `revision(ofTopologyFileHashes:)`)
//     40  4   entryCount
//     44  4   bodyLength (bytes after the header)
//     48  8   bodyChecksum: first 8 bytes of SHA-256 of the body
//   body: entryCount entries sorted ascending by (key.high, key.low)
//     key 16 (high then low) | outcome u8 | reserved u8 (0) |
//     spanCount u16 | gapCount u16 | spans 8 each | gaps 3 each
//     (section u16, reason u8)
//
// Anything wrong (missing file, truncated, bad magic, bad checksum, bad
// counts, an entry over the per-trip limit, duplicate keys) reads as empty.
// A different topology revision or semantics version is a miss, also empty:
// line indices, ordinals and metres mean nothing against another file.
public enum RideRecordFile {
    public static let magic: [UInt8] = [0x4A, 0x54, 0x52, 0x52]  // "JTRR"
    public static let formatVersion: UInt16 = 1
    /// Bump when the resolver's rules change in a way that can change refs.
    public static let semanticsVersion: UInt16 = 1
    public static let headerSize = 56
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

    /// Bytes one trip occupies in the file.
    public static func entryByteCount(of ride: RideRefs) -> Int {
        entryFixedSize + ride.spans.count * RideRefs.Span.byteCount + ride.gaps.count * gapByteCount
    }

    // MARK: encode

    /// Encodes `rides`. Entries over `maxBytesPerTrip` are left out; for a
    /// repeated key the last entry wins. Output is deterministic.
    public static func encode(_ rides: [RideRefs], topologyRevision: [UInt8]) throws -> Data {
        guard topologyRevision.count == revisionByteCount else { throw WriteError.badRevision }
        var byKey: [RideRefs.Key: RideRefs] = [:]
        for ride in rides where entryByteCount(of: ride) <= maxBytesPerTrip {
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
        append(UInt32(ordered.count), to: &out)
        append(UInt32(body.count), to: &out)
        out.append(contentsOf: checksum(body))
        out.append(contentsOf: body)
        return Data(out)
    }

    // MARK: decode

    public static func decode(_ data: Data, topologyRevision: [UInt8]) -> ReadResult {
        func fail(_ status: Status) -> ReadResult { ReadResult(status: status, entries: [:]) }
        let bytes = [UInt8](data)
        guard bytes.count >= headerSize, Array(bytes[0..<4]) == magic,
              topologyRevision.count == revisionByteCount else { return fail(.corrupt) }
        guard word16(bytes, 4) == formatVersion else { return fail(.corrupt) }
        guard word16(bytes, 6) == semanticsVersion else { return fail(.semanticsMismatch) }
        guard Array(bytes[8..<40]) == topologyRevision else { return fail(.topologyRevisionMismatch) }
        let count = Int(word32(bytes, 40)), bodyLength = Int(word32(bytes, 44))
        guard bytes.count == headerSize + bodyLength,
              count <= bodyLength / entryFixedSize else { return fail(.corrupt) }
        let body = Array(bytes[headerSize...])
        guard Array(bytes[48..<56]) == checksum(body) else { return fail(.corrupt) }

        var entries: [RideRefs.Key: RideRefs] = [:]
        entries.reserveCapacity(count)
        var cursor = 0
        for _ in 0..<count {
            guard cursor + entryFixedSize <= body.count else { return fail(.corrupt) }
            let key = RideRefs.Key(high: word64(body, cursor), low: word64(body, cursor + 8))
            guard let outcome = RideRefs.Outcome(rawValue: body[cursor + 16]), body[cursor + 17] == 0
            else { return fail(.corrupt) }
            let spanCount = Int(word16(body, cursor + 18)), gapCount = Int(word16(body, cursor + 20))
            let size = entryFixedSize + spanCount * RideRefs.Span.byteCount + gapCount * gapByteCount
            guard size <= maxBytesPerTrip, cursor + size <= body.count, entries[key] == nil
            else { return fail(.corrupt) }
            var at = cursor + entryFixedSize
            var spans: [RideRefs.Span] = []
            spans.reserveCapacity(spanCount)
            for _ in 0..<spanCount {
                guard let span = RideRefs.Span(bytes: Array(body[at..<(at + RideRefs.Span.byteCount)]))
                else { return fail(.corrupt) }
                spans.append(span)
                at += RideRefs.Span.byteCount
            }
            var gaps: [RideRefs.Gap] = []
            gaps.reserveCapacity(gapCount)
            for _ in 0..<gapCount {
                gaps.append(RideRefs.Gap(section: word16(body, at),
                                         reason: RideRefs.GapReason(rawValue: body[at + 2])))
                at += gapByteCount
            }
            entries[key] = RideRefs(key: key, outcome: outcome, spans: spans, gaps: gaps)
            cursor += size
        }
        guard cursor == body.count else { return fail(.corrupt) }
        return ReadResult(status: .loaded, entries: entries)
    }

    // MARK: files

    /// Reads and decodes a file. A missing or unreadable file is `.missing`.
    public static func read(from url: URL, topologyRevision: [UInt8]) -> ReadResult {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return ReadResult(status: .missing, entries: [:])
        }
        return decode(data, topologyRevision: topologyRevision)
    }

    /// Encodes and writes atomically (temporary file, then replace).
    public static func write(_ rides: [RideRefs], to url: URL, topologyRevision: [UInt8]) throws {
        let data = try encode(rides, topologyRevision: topologyRevision)
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

    private static func word16(_ b: [UInt8], _ o: Int) -> UInt16 { UInt16(b[o]) | UInt16(b[o + 1]) << 8 }
    private static func word32(_ b: [UInt8], _ o: Int) -> UInt32 {
        UInt32(word16(b, o)) | UInt32(word16(b, o + 2)) << 16
    }
    private static func word64(_ b: [UInt8], _ o: Int) -> UInt64 {
        UInt64(word32(b, o)) | UInt64(word32(b, o + 4)) << 32
    }
}
