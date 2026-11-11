import CryptoKit
import Foundation

// MARK: - RideKey: the 16-byte route-input key (U3)
//
// The key answers one question for the ride cache: "is this trip's route
// input the one the cached refs were resolved from?" It is a SHA-256 over a
// framed byte stream of the route fields, truncated to 16 bytes. No JSON is
// built, so computing it for 500 trips allocates nothing beyond the hasher.
//
// Included (anything that can change which track the trip resolves to):
// region, date, number, train type, company, operator ids, origin and
// destination, confirmation state, every stop's name, codes, platform, stop
// type and ride-segment flag, every field of every route section, and every
// field of the route policy.
//
// Excluded on purpose: id, notes, visibility, style, list and group
// membership, rolling stock, ticket, trip notes, vehicle type, direction text,
// stop clocks (scheduled and actual) and the editor's visit ids. None of them
// changes the route input. The app's build identity is also excluded, so an
// app update never invalidates the cache; only `RideKey.version` (the hashing
// layout) and the file's semantics version (`RideRecordFile`) do.
public enum RideKey {
    /// Bump when the set of hashed fields or their framing changes. It is
    /// hashed into every key, so old keys simply stop matching.
    public static let version: UInt8 = 1

    public static func make(for train: Train) -> RideRefs.Key {
        var h = FramedHasher()
        h.byte(version)
        h.string(train.region)
        h.string(train.date)
        h.string(train.number)
        h.string(train.trainType)
        h.string(train.company)
        h.string(train.operatorID)
        h.strings(train.operatorIDs)
        h.string(train.origin)
        h.string(train.destination)
        h.string(train.routeConfirmation?.rawValue)
        h.count(train.stops.count)
        for stop in train.stops {
            h.string(stop.name)
            h.string(stop.n02StationCode)
            h.string(stop.stationID)
            h.int(stop.platformNumber)
            h.string(stop.stopType)
            h.bool(stop.rideSegment)
        }
        if let sections = train.routeSections {
            h.byte(1)
            h.count(sections.count)
            for section in sections { hash(section, into: &h) }
        } else {
            h.byte(0)
        }
        if let policy = train.routePolicy {
            h.byte(1)
            hash(policy, into: &h)
        } else {
            h.byte(0)
        }
        return h.finish()
    }

    private static func hash(_ s: RouteSection, into h: inout FramedHasher) {
        h.string(s.from)
        h.string(s.to)
        h.string(s.fromN02StationCode)
        h.string(s.toN02StationCode)
        h.string(s.fromStationID)
        h.string(s.toStationID)
        h.strings(s.lineNames)
        h.strings(s.operatorNames)
        h.strings(s.lineIDs)
        h.strings(s.sectionCodes)
        h.string(s.sectionCodesOrigin?.rawValue)
        h.string(s.number)
        h.string(s.name)
        h.string(s.trackPreference?.rawValue)
    }

    private static func hash(_ p: RoutePolicy, into h: inout FramedHasher) {
        h.string(p.mode)
        h.bool(p.jrOnly)
        h.bool(p.allowAlternatives)
        h.bool(p.allowBrowserStraightLineFallback)
        h.strings(p.allowedInstitutionTypeCodes)
        h.strings(p.preferredLineNames)
        h.strings(p.preferredOperatorNames)
        h.string(p.institutionFilterMode)
    }
}

/// Length-prefixed, presence-marked framing so that no two different field
/// sequences produce the same byte stream ("ab","c" never equals "a","bc";
/// nil never equals "").
private struct FramedHasher {
    private var sha = SHA256()

    mutating func byte(_ value: UInt8) { sha.update(data: [value]) }
    mutating func count(_ value: Int) { word(UInt32(truncatingIfNeeded: value)) }

    mutating func word(_ value: UInt32) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { sha.update(bufferPointer: $0) }
    }

    mutating func string(_ value: String?) {
        guard let value else { byte(0); return }
        byte(1)
        var copy = value
        copy.withUTF8 { buffer in
            word(UInt32(truncatingIfNeeded: buffer.count))
            sha.update(bufferPointer: UnsafeRawBufferPointer(buffer))
        }
    }

    mutating func strings(_ values: [String]?) {
        guard let values else { byte(0); return }
        byte(1)
        count(values.count)
        for value in values { string(value) }
    }

    mutating func bool(_ value: Bool?) {
        guard let value else { byte(0); return }
        byte(value ? 2 : 1)
    }

    mutating func int(_ value: Int?) {
        guard let value else { byte(0); return }
        byte(1)
        var le = Int64(value).littleEndian
        withUnsafeBytes(of: &le) { sha.update(bufferPointer: $0) }
    }

    func finish() -> RideRefs.Key {
        let digest = Array(sha.finalize())
        func word(_ offset: Int) -> UInt64 {
            (0..<8).reduce(UInt64(0)) { $0 | UInt64(digest[offset + $1]) << (8 * UInt64($1)) }
        }
        return RideRefs.Key(high: word(0), low: word(8))
    }
}
