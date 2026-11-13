import CryptoKit
import Foundation
import Testing
@testable import RailCore

@Suite("RideRecordFile")
struct RideRecordFileTests {
    typealias File = RideRecordFile
    typealias Stamp = RideRecordFile.LineStamp
    static let timetable = [UInt8](repeating: 0xCD, count: 32)

    /// A region with `count` lines, line `i` stamped (key of id "line-i", hash `seed + i`).
    static func stamps(_ region: String = "jp", count: Int = 12, seed: UInt64 = 1000) -> File.RegionStamps {
        File.RegionStamps(region: region, stamps: (0..<count).map {
            Stamp(lineKey: File.lineKey(region: region, lineID: "line-\($0)"), contentHash: seed + UInt64($0))
        })
    }

    static func ride(_ n: UInt64, outcome: RideRefs.Outcome = .resolved, lines: [UInt16]? = nil, spans: Int = 3,
                     gaps: Int = 0) -> RideRefs {
        let used = lines ?? (0..<spans).map { UInt16($0 + 1) }
        return RideRefs(
            key: .init(high: n &* 0x9E37_79B9_7F4A_7C15, low: ~n),
            outcome: outcome,
            spans: used.enumerated().map { i, line in
                RideRefs.Span(
                    span: RailTopology.Span(line: line, fromNode: UInt16(i), toNode: UInt16(i + 7), wraps: i % 2 == 1),
                    section: UInt16(i / 2), unproven: i % 3 == 2)
            },
            gaps: (0..<gaps).map { RideRefs.Gap(section: UInt16(100 + $0), reason: [.noPath, .withheld]) })
    }

    static func stored(_ rides: [RideRefs], region: String = "jp") -> [File.StoredRide] {
        rides.map { File.StoredRide(region: region, refs: $0) }
    }

    static func encode(_ rides: [RideRefs], stamps: [File.RegionStamps] = [Self.stamps()]) throws -> Data {
        try File.encode(Self.stored(rides), stamps: stamps, timetableRevision: Self.timetable)
    }

    static func decode(_ data: Data, current: [File.RegionStamps] = [Self.stamps()], timetable: [UInt8] = Self.timetable) -> File.ReadResult {
        File.decode(data, current: current, timetableRevision: timetable)
    }

    // MARK: Round trip

    @Test("round trip keeps every field, unresolved entries included")
    func roundTrip() throws {
        let rides = [
            Self.ride(1), Self.ride(2, outcome: .partial, spans: 2, gaps: 2),
            Self.ride(3, outcome: .unresolved, spans: 0, gaps: 1),
        ]
        let read = Self.decode(try Self.encode(rides))
        #expect(read.status == .loaded && read.stale.isEmpty)
        #expect(read.entries.count == 3)
        for ride in rides { #expect(read.entries[ride.key] == ride) }
    }

    @Test("an empty file is a loaded, empty cache with no line table")
    func emptyRoundTrip() throws {
        let data = try Self.encode([])
        #expect(data.count == File.headerSize)
        let read = Self.decode(data)
        #expect(read.status == .loaded && read.entries.isEmpty && read.stale.isEmpty && read.failed.isEmpty)
    }

    @Test("output is deterministic and independent of input order")
    func deterministic() throws {
        let rides = (1...20).map { Self.ride(UInt64($0), lines: [UInt16($0 % 5), UInt16($0 % 7 + 5)]) }
        #expect(try Self.encode(rides) == Self.encode(rides.reversed()))
    }

    @Test("the line table holds only the lines the stored trips use, and a span names a table row, not a topology line")
    func lineTableIsCompact() throws {
        // Lines 3 and 9 of the topology only.
        let data = try Self.encode([Self.ride(1, lines: [9, 3]), Self.ride(2, lines: [3])])
        let rows = Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 42, as: UInt16.self) })
        #expect(rows == 2)
        // The same file reads against a topology whose lines moved: stamps found by key, spans remapped.
        let moved = File.RegionStamps(region: "jp", stamps: Self.stamps().stamps.reversed())
        let read = Self.decode(data, current: [moved])
        #expect(read.stale.isEmpty)
        #expect(read.entries[Self.ride(1).key]?.spans.map(\.span.line) == [2, 8])   // 12 lines, reversed: 11 - 9, 11 - 3
        #expect(read.entries[Self.ride(2).key]?.spans.map(\.span.line) == [8])
    }

    // MARK: Per-line validity

    @Test("an unchanged line keeps its trips valid, remapped to the current line index")
    func unchangedLineStillValid() throws {
        let data = try Self.encode([Self.ride(1, lines: [2, 5]), Self.ride(2, lines: [7])])
        // The data was rebuilt with two new lines in front: every index moved by 2, no content changed.
        let shifted = File.RegionStamps(region: "jp", stamps: [
            Stamp(lineKey: File.lineKey(region: "jp", lineID: "new-a"), contentHash: 1),
            Stamp(lineKey: File.lineKey(region: "jp", lineID: "new-b"), contentHash: 2),
        ] + Self.stamps().stamps)
        let read = Self.decode(data, current: [shifted])
        #expect(read.status == .loaded && read.stale.isEmpty)
        #expect(read.entries[Self.ride(1).key]?.spans.map(\.span.line) == [4, 7])
        #expect(read.entries[Self.ride(2).key]?.spans.map(\.span.line) == [9])
        // Everything else about the trip is untouched.
        var expected = Self.ride(1, lines: [4, 7]); expected.key = Self.ride(1).key
        #expect(read.entries[Self.ride(1).key] == expected)
    }

    @Test("a changed line invalidates only the trips that use it")
    func changedLineInvalidatesOnlyItsTrips() throws {
        let rides = [Self.ride(1, lines: [2, 5]), Self.ride(2, lines: [5, 6]), Self.ride(3, lines: [7]), Self.ride(4, lines: [2])]
        let data = try Self.encode(rides)
        var changed = Self.stamps()
        changed.stamps[5].contentHash &+= 1
        let read = Self.decode(data, current: [changed])
        #expect(read.status == .loaded)
        #expect(Set(read.stale) == [rides[0].key, rides[1].key])
        #expect(Set(read.entries.keys) == [rides[2].key, rides[3].key])
        #expect(read.entries[rides[2].key] == rides[2] && read.entries[rides[3].key] == rides[3])
    }

    @Test("a line that left the data, or moved to another region, invalidates its trips; a line added changes nothing")
    func removedLine() throws {
        let rides = [Self.ride(1, lines: [2]), Self.ride(2, lines: [3])]
        let data = try Self.encode(rides)
        var without = Self.stamps()
        without.stamps.remove(at: 3)
        let read = Self.decode(data, current: [without])
        #expect(read.stale == [rides[1].key] && read.entries[rides[0].key] != nil)
        // The same ids under another region are other lines (the key includes the region).
        let other = Self.decode(data, current: [Self.stamps("tw")])
        #expect(Set(other.stale) == [rides[0].key, rides[1].key] && other.entries.isEmpty)
        // A region with no topology at all: the same.
        #expect(Set(Self.decode(data, current: []).stale) == [rides[0].key, rides[1].key])
        // More lines than before, none of the used ones changed.
        let more = Self.stamps(count: 40)
        #expect(Self.decode(data, current: [more]).stale.isEmpty)
    }

    @Test("a data rebuild lists exactly the trips to re-solve")
    func rebuildListsExactlyTheTrips() throws {
        // 30 trips over 12 lines; the rebuild changes lines 4 and 9.
        let rides = (1...30).map { Self.ride(UInt64($0), lines: [UInt16($0 % 12), UInt16(($0 * 5) % 12)]) }
        let data = try Self.encode(rides)
        var rebuilt = Self.stamps()
        for line in [4, 9] { rebuilt.stamps[line].contentHash ^= 0xFF }
        let read = Self.decode(data, current: [rebuilt])
        let expected = Set(rides.filter { ride in ride.spans.contains { [4, 9].contains(Int($0.span.line)) } }.map(\.key))
        #expect(!expected.isEmpty && expected.count < rides.count)
        #expect(Set(read.stale) == expected)
        #expect(Set(read.entries.keys) == Set(rides.map(\.key)).subtracting(expected))
        #expect(read.stale.count == expected.count)   // no repeats
    }

    @Test("a trip's own route fields are its key: a different key is a different trip, never a stale one")
    func routeFieldsAreTheKey() throws {
        let data = try Self.encode([Self.ride(1, lines: [2])])
        let read = Self.decode(data)
        #expect(read.entries[Self.ride(1).key] != nil)
        #expect(read.entries[Self.ride(99).key] == nil && !read.stale.contains(Self.ride(99).key))
    }

    @Test("a failure is stored as it is and not retried unless asked, while the network is unchanged")
    func failuresStayUntilRepair() throws {
        let failed = Self.ride(1, outcome: .unresolved, spans: 0, gaps: 2)
        let partial = Self.ride(2, outcome: .partial, lines: [5], gaps: 1)
        let good = Self.ride(3, lines: [5])
        let data = try Self.encode([failed, partial, good])
        let same = Self.decode(data)
        #expect(same.stale.isEmpty)
        #expect(Set(same.failed) == [failed.key, partial.key])
        #expect(same.entries[failed.key] == failed && same.entries[partial.key] == partial)
        #expect(!same.failed.contains(good.key))
        // Lines moving about without a content change is no change of the network.
        let reordered = File.RegionStamps(region: "jp", stamps: Self.stamps().stamps.reversed())
        #expect(Self.decode(data, current: [reordered]).stale.isEmpty)
    }

    @Test("a change anywhere in the region's network turns a stored failure stale, once")
    func failureGoesStaleWhenTheNetworkChanges() throws {
        // An unresolved trip has no span: no line says it depends on anything. A link added between two
        // lines the trip never used changes the hashes of exactly those two lines.
        let failed = Self.ride(1, outcome: .unresolved, spans: 0, gaps: 2)
        let partial = Self.ride(2, outcome: .partial, lines: [5], gaps: 1)   // its gap is on other lines
        let good = Self.ride(3, lines: [5])
        let data = try Self.encode([failed, partial, good])
        var linked = Self.stamps()
        linked.stamps[8].contentHash &+= 1
        linked.stamps[9].contentHash &+= 1
        let read = Self.decode(data, current: [linked])
        #expect(Set(read.stale) == [failed.key, partial.key])
        #expect(read.entries[good.key] == good && read.failed.isEmpty)
        // A line added, or removed, counts the same.
        #expect(Set(Self.decode(data, current: [Self.stamps(count: 13)]).stale) == [failed.key, partial.key])
        #expect(Set(Self.decode(data, current: [Self.stamps(count: 11)]).stale) == [failed.key, partial.key])
        // A resolved trip that did not use a changed line is not listed (documented limit).
        #expect(read.stale.contains(good.key) == false)
        // After the re-solve the file is written against the new network and the failure is current again.
        let rewritten = try Self.encode([failed], stamps: [linked])
        #expect(Self.decode(rewritten, current: [linked]).failed == [failed.key])
    }

    @Test("a failure goes stale only with its own region's network")
    func failureStaleIsPerRegion() throws {
        let jp = Self.stamps("jp"), tw = Self.stamps("tw", seed: 5000)
        let a = Self.ride(1, outcome: .unresolved, spans: 0, gaps: 1)
        let b = Self.ride(2, outcome: .unresolved, spans: 0, gaps: 1)
        let data = try File.encode(Self.stored([a], region: "jp") + Self.stored([b], region: "tw"),
                                   stamps: [jp, tw], timetableRevision: Self.timetable)
        var changedTW = tw
        changedTW.stamps[0].contentHash += 1
        let read = Self.decode(data, current: [jp, changedTW])
        #expect(read.stale == [b.key] && read.entries[a.key] == a && read.failed == [a.key])
        // A region whose topology is not loaded cannot vouch for its failures.
        #expect(Self.decode(data, current: [jp]).stale == [b.key])
    }

    // MARK: Misses and corruption

    @Test("a wrong timetable revision is a miss")
    func timetableMiss() throws {
        let data = try Self.encode([Self.ride(1)])
        var other = Self.timetable
        other[0] ^= 1
        let read = Self.decode(data, timetable: other)
        #expect(read.status == .timetableRevisionMismatch && read.entries.isEmpty && read.stale.isEmpty)
    }

    @Test("disabledRegion results are never stored")
    func disabledRegionDropped() throws {
        let data = try Self.encode([Self.ride(1), Self.ride(2, outcome: .disabledRegion, spans: 0)])
        let read = Self.decode(data)
        #expect(read.entries.count == 1 && read.entries[Self.ride(1).key] != nil)
    }

    @Test("a wrong semantics version is a miss")
    func semanticsMiss() throws {
        var bytes = [UInt8](try Self.encode([Self.ride(1)]))
        bytes[6] = UInt8(truncatingIfNeeded: File.semanticsVersion &+ 1)
        let read = Self.decode(Data(bytes))
        #expect(read.status == .semanticsMismatch && read.entries.isEmpty)
    }

    @Test("a version 1 file is corrupt, not a hit")
    func oldFormatRefused() throws {
        var bytes = [UInt8](try Self.encode([Self.ride(1)]))
        bytes[4] = 1
        #expect(Self.decode(Data(bytes)).status == .corrupt)
    }

    @Test("corrupt files read as empty", arguments: ["truncated", "magic", "body", "checksum", "extra", "tiny", "empty", "gapReasonZero", "gapReasonUndefined", "gapSection", "disabledRegion", "spanSameNode", "spanLineRow", "tableOrder"])
    func corrupt(_ kind: String) throws {
        let gapped = kind.hasPrefix("gap")
        let rides = gapped ? [Self.ride(1, lines: [1], gaps: 1)] : (1...5).map { Self.ride(UInt64($0), lines: [UInt16($0), 7]) }
        var bytes = [UInt8](try Self.encode(rides))
        let tableBytes = Int(bytes[42]) * 16 + Int(bytes[40]) * 16
        func reseal() {
            let digest = Array(SHA256.hash(data: bytes[File.headerSize...]).prefix(8))
            bytes.replaceSubrange(56..<64, with: digest)
        }
        let firstEntry = File.headerSize + tableBytes
        switch kind {
        case "gapReasonZero": bytes[bytes.count - 1] = 0; reseal()
        case "gapReasonUndefined": bytes[bytes.count - 1] = 0x40; reseal()
        case "gapSection": bytes[bytes.count - 2] = 0xFF; bytes[bytes.count - 3] = 0xFF; reseal()
        case "disabledRegion": bytes[firstEntry + 16] = RideRefs.Outcome.disabledRegion.rawValue; reseal()
        case "spanSameNode":
            let span = firstEntry + 22
            bytes[span + 4] = bytes[span + 2]; bytes[span + 5] = bytes[span + 3]; reseal()
        case "spanLineRow": bytes[firstEntry + 22] = 0xFF; bytes[firstEntry + 23] = 0xFF; reseal()
        case "tableOrder":
            // Two rows out of order.
            let a = Array(bytes[File.headerSize..<(File.headerSize + 16)]), b = Array(bytes[(File.headerSize + 16)..<(File.headerSize + 32)])
            bytes.replaceSubrange(File.headerSize..<(File.headerSize + 16), with: b)
            bytes.replaceSubrange((File.headerSize + 16)..<(File.headerSize + 32), with: a)
            reseal()
        case "truncated": bytes.removeLast(5)
        case "magic": bytes[0] = 0
        case "body": bytes[firstEntry + 20] ^= 0xFF
        case "checksum": bytes[58] ^= 0xFF
        case "extra": bytes.append(0)
        case "tiny": bytes = Array(bytes.prefix(10))
        default: bytes = []
        }
        let read = Self.decode(Data(bytes))
        #expect(read.status == .corrupt && read.entries.isEmpty && read.stale.isEmpty, "\(kind): \(read.status)")
    }

    @Test("every single-byte flip of a small file never yields a wrong hit")
    func byteFlips() throws {
        let rides = [Self.ride(1, lines: [2, 3]), Self.ride(2, outcome: .unresolved, spans: 0, gaps: 1)]
        let good = [UInt8](try Self.encode(rides))
        for i in 0..<good.count {
            var bytes = good
            bytes[i] ^= 0x01
            let read = Self.decode(Data(bytes))
            if read.status == .loaded {
                // A flip may drop a trip (a region row that no longer matches makes a failure stale), never alter one.
                for (key, ride) in read.entries { #expect(rides.first { $0.key == key } == ride, "flip at \(i)") }
            } else { #expect(read.entries.isEmpty && read.stale.isEmpty) }
        }
    }

    @Test("a missing file is empty, and files round trip atomically")
    func files() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "ride-record-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "Caches/rides-v2.bin")
        let current = [Self.stamps()]
        let missing = File.read(from: url, current: current, timetableRevision: Self.timetable)
        #expect(missing.status == .missing && missing.entries.isEmpty)
        try File.write(Self.stored([Self.ride(1), Self.ride(2)]), stamps: current, to: url, timetableRevision: Self.timetable)
        let read = File.read(from: url, current: current, timetableRevision: Self.timetable)
        #expect(read.status == .loaded && read.entries.count == 2)
        try File.write(Self.stored([Self.ride(3)]), stamps: current, to: url, timetableRevision: Self.timetable)
        #expect(File.read(from: url, current: current, timetableRevision: Self.timetable).entries.count == 1)
    }

    @Test("a span on a line the stamps do not have is a write error, not a silent drop")
    func unknownLineIsRefused() {
        #expect(throws: File.WriteError.unknownLine) { try Self.encode([Self.ride(1, lines: [99])]) }
        #expect(throws: File.WriteError.unknownLine) {
            try File.encode(Self.stored([Self.ride(1, lines: [1])], region: "tw"), stamps: [Self.stamps()], timetableRevision: Self.timetable)
        }
        // A trip with no spans needs no line table and is stored whatever region it names.
        #expect(throws: Never.self) {
            try File.encode(Self.stored([Self.ride(2, outcome: .unresolved, spans: 0, gaps: 1)], region: "tw"),
                            stamps: [], timetableRevision: Self.timetable)
        }
    }

    @Test("two regions share one file: each trip is remapped by its own region's lines")
    func twoRegions() throws {
        let jp = Self.stamps("jp"), tw = Self.stamps("tw", seed: 5000)
        let a = Self.ride(1, lines: [3]), b = Self.ride(2, lines: [3])
        let data = try File.encode(Self.stored([a], region: "jp") + Self.stored([b], region: "tw"),
                                   stamps: [jp, tw], timetableRevision: Self.timetable)
        // Only tw's line 3 changes.
        var changedTW = tw
        changedTW.stamps[3].contentHash += 1
        let read = Self.decode(data, current: [jp, changedTW])
        #expect(read.stale == [b.key] && read.entries[a.key] == a)
    }

    @Test("a trip costs at most 4 KB; an oversize trip is left out, not the file")
    func perTripLimit() throws {
        let typical = Self.ride(1, spans: 40, gaps: 5)
        #expect(File.entryByteCount(of: typical) == 22 + 40 * 8 + 5 * 3)
        #expect(File.entryByteCount(of: typical) <= File.maxBytesPerTrip)
        let atLimit = Self.ride(2, spans: (File.maxBytesPerTrip - 22) / 8)
        #expect(File.entryByteCount(of: atLimit) <= File.maxBytesPerTrip)
        let oversize = Self.ride(3, spans: (File.maxBytesPerTrip - 22) / 8 + 1)
        #expect(File.entryByteCount(of: oversize) > File.maxBytesPerTrip)
        let read = Self.decode(try Self.encode([typical, atLimit, oversize], stamps: [Self.stamps(count: 600)]), current: [Self.stamps(count: 600)])
        #expect(read.status == .loaded)
        #expect(read.entries[typical.key] == typical)
        #expect(read.entries[atLimit.key] == atLimit)
        #expect(read.entries[oversize.key] == nil)
    }

    @Test("500 typical trips over a real-sized line table stay far under the 150 KB cache budget")
    func fiveHundredTrips() throws {
        let rides = (1...500).map { n in
            Self.ride(UInt64(n), lines: (0..<6).map { UInt16((Int(n) * 7 + $0 * 13) % 658) }, gaps: n % 10 == 0 ? 1 : 0)
        }
        let big = Self.stamps(count: 658)
        let data = try Self.encode(rides, stamps: [big])
        #expect(data.count < 150_000)
    }

    @Test("a timetable revision must be 32 bytes")
    func revisionLength() {
        #expect(throws: File.WriteError.badRevision) { try File.encode([], stamps: [], timetableRevision: [1, 2, 3]) }
        #expect(Self.decode(Data(), timetable: [1, 2, 3]).status == .corrupt)
    }

    @Test("the line key depends on region and id, and is stable")
    func lineKeys() {
        #expect(File.lineKey(region: "jp", lineID: "a") == File.lineKey(region: "jp", lineID: "a"))
        #expect(File.lineKey(region: "jp", lineID: "a") != File.lineKey(region: "tw", lineID: "a"))
        #expect(File.lineKey(region: "jp", lineID: "a") != File.lineKey(region: "jp", lineID: "b"))
        // A region/id split cannot be forged by moving the boundary.
        #expect(File.lineKey(region: "jp", lineID: "xa") != File.lineKey(region: "jpx", lineID: "a"))
    }

    @Test("a topology's stamps are keyed by region and id and carry its content hashes")
    func topologyStamps() throws {
        var net = TestNetwork()
        net.lines = [.chain("a", ["A0", "A1"], lengths: [100]), .chain("b", ["B0", "B1"], lengths: [200])]
        let before = try net.topology().rideStamps
        #expect(before.region == "jp" && before.stamps.count == 2)
        #expect(before.stamps[0].lineKey == File.lineKey(region: "jp", lineID: "a"))
        net.lines[1].edges[0].length = 201
        let after = try net.topology().rideStamps
        #expect(after.stamps[0] == before.stamps[0])
        #expect(after.stamps[1].lineKey == before.stamps[1].lineKey && after.stamps[1].contentHash != before.stamps[1].contentHash)
    }
}
