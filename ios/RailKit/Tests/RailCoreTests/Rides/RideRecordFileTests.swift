import CryptoKit
import Foundation
import Testing
@testable import RailCore

@Suite("RideRecordFile")
struct RideRecordFileTests {
    typealias File = RideRecordFile
    static let revision = [UInt8](repeating: 0xAB, count: 32)
    static let timetable = [UInt8](repeating: 0xCD, count: 32)

    static func ride(_ n: UInt64, outcome: RideRefs.Outcome = .resolved, spans: Int = 3, gaps: Int = 0) -> RideRefs {
        RideRefs(
            key: .init(high: n &* 0x9E37_79B9_7F4A_7C15, low: ~n),
            outcome: outcome,
            spans: (0..<spans).map {
                RideRefs.Span(
                    span: RailTopology.Span(line: UInt16($0 + 1), fromNode: UInt16($0), toNode: UInt16($0 + 7),
                                            wraps: $0 % 2 == 1),
                    section: UInt16($0 / 2), unproven: $0 % 3 == 2)
            },
            gaps: (0..<gaps).map { RideRefs.Gap(section: UInt16(100 + $0), reason: [.noPath, .withheld]) })
    }

    @Test("round trip keeps every field, unresolved entries included")
    func roundTrip() throws {
        let rides = [
            Self.ride(1), Self.ride(2, outcome: .partial, spans: 2, gaps: 2),
            Self.ride(3, outcome: .unresolved, spans: 0, gaps: 1),
        ]
        let data = try File.encode(rides, topologyRevision: Self.revision, timetableRevision: Self.timetable)
        let read = File.decode(data, topologyRevision: Self.revision, timetableRevision: Self.timetable)
        #expect(read.status == .loaded)
        #expect(read.entries.count == 3)
        for ride in rides { #expect(read.entries[ride.key] == ride) }
    }

    @Test("an empty file is a loaded, empty cache")
    func emptyRoundTrip() throws {
        let data = try File.encode([], topologyRevision: Self.revision, timetableRevision: Self.timetable)
        #expect(data.count == File.headerSize)
        let read = File.decode(data, topologyRevision: Self.revision, timetableRevision: Self.timetable)
        #expect(read.status == .loaded && read.entries.isEmpty)
    }

    @Test("output is deterministic and independent of input order")
    func deterministic() throws {
        let rides = (1...20).map { Self.ride(UInt64($0)) }
        let a = try File.encode(rides, topologyRevision: Self.revision, timetableRevision: Self.timetable)
        let b = try File.encode(rides.reversed(), topologyRevision: Self.revision, timetableRevision: Self.timetable)
        #expect(a == b)
    }

    @Test("a wrong topology revision is a miss")
    func revisionMiss() throws {
        let data = try File.encode([Self.ride(1)], topologyRevision: Self.revision, timetableRevision: Self.timetable)
        var other = Self.revision
        other[31] ^= 1
        let read = File.decode(data, topologyRevision: other, timetableRevision: Self.timetable)
        #expect(read.status == .topologyRevisionMismatch && read.entries.isEmpty)
    }

    @Test("a wrong timetable revision is a miss")
    func timetableMiss() throws {
        let data = try File.encode([Self.ride(1)], topologyRevision: Self.revision, timetableRevision: Self.timetable)
        var other = Self.timetable
        other[0] ^= 1
        let read = File.decode(data, topologyRevision: Self.revision, timetableRevision: other)
        #expect(read.status == .timetableRevisionMismatch && read.entries.isEmpty)
    }

    @Test("disabledRegion results are never stored")
    func disabledRegionDropped() throws {
        let data = try File.encode([Self.ride(1), Self.ride(2, outcome: .disabledRegion, spans: 0)],
                                   topologyRevision: Self.revision, timetableRevision: Self.timetable)
        let read = File.decode(data, topologyRevision: Self.revision, timetableRevision: Self.timetable)
        #expect(read.entries.count == 1 && read.entries[Self.ride(1).key] != nil)
    }

    @Test("a wrong semantics version is a miss")
    func semanticsMiss() throws {
        var bytes = [UInt8](try File.encode([Self.ride(1)], topologyRevision: Self.revision, timetableRevision: Self.timetable))
        bytes[6] = UInt8(truncatingIfNeeded: File.semanticsVersion &+ 1)
        let read = File.decode(Data(bytes), topologyRevision: Self.revision, timetableRevision: Self.timetable)
        #expect(read.status == .semanticsMismatch && read.entries.isEmpty)
    }

    @Test("corrupt files read as empty", arguments: ["truncated", "magic", "body", "checksum", "extra", "tiny", "empty", "gapReasonZero", "gapReasonUndefined", "gapSection", "disabledRegion"])
    func corrupt(_ kind: String) throws {
        let gapped = kind.hasPrefix("gap")
        let rides = gapped ? [Self.ride(1, spans: 1, gaps: 1)] : (1...5).map { Self.ride(UInt64($0)) }
        var bytes = [UInt8](try File.encode(rides, topologyRevision: Self.revision, timetableRevision: Self.timetable))
        // The only entry's gap record is the last 3 bytes of the file.
        func reseal() {
            let digest = Array(SHA256.hash(data: bytes[File.headerSize...]).prefix(8))
            bytes.replaceSubrange(80..<88, with: digest)
        }
        switch kind {
        case "gapReasonZero": bytes[bytes.count - 1] = 0; reseal()
        case "gapReasonUndefined": bytes[bytes.count - 1] = 0x40; reseal()
        case "gapSection": bytes[bytes.count - 2] = 0xFF; bytes[bytes.count - 3] = 0xFF; reseal()
        case "disabledRegion": bytes[File.headerSize + 16] = RideRefs.Outcome.disabledRegion.rawValue; reseal()
        case "truncated": bytes.removeLast(5)
        case "magic": bytes[0] = 0
        case "body": bytes[File.headerSize + 20] ^= 0xFF
        case "checksum": bytes[82] ^= 0xFF
        case "extra": bytes.append(0)
        case "tiny": bytes = Array(bytes.prefix(10))
        default: bytes = []
        }
        let read = File.decode(Data(bytes), topologyRevision: Self.revision, timetableRevision: Self.timetable)
        #expect(read.status == .corrupt && read.entries.isEmpty, "\(kind): \(read.status)")
    }

    @Test("every single-byte flip of a small file never yields a wrong hit")
    func byteFlips() throws {
        let rides = [Self.ride(1), Self.ride(2, outcome: .unresolved, spans: 0, gaps: 1)]
        let good = [UInt8](try File.encode(rides, topologyRevision: Self.revision, timetableRevision: Self.timetable))
        for i in 0..<good.count {
            var bytes = good
            bytes[i] ^= 0x01
            let read = File.decode(Data(bytes), topologyRevision: Self.revision, timetableRevision: Self.timetable)
            if read.status == .loaded { #expect(Array(read.entries.values).sorted { $0.key.low < $1.key.low } == rides.sorted { $0.key.low < $1.key.low }, "flip at \(i)") }
            else { #expect(read.entries.isEmpty) }
        }
    }

    @Test("a missing file is empty, and files round trip atomically")
    func files() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "ride-record-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "Caches/rides-v1.bin")
        let missing = File.read(from: url, topologyRevision: Self.revision, timetableRevision: Self.timetable)
        #expect(missing.status == .missing && missing.entries.isEmpty)
        try File.write([Self.ride(1), Self.ride(2)], to: url, topologyRevision: Self.revision, timetableRevision: Self.timetable)
        let read = File.read(from: url, topologyRevision: Self.revision, timetableRevision: Self.timetable)
        #expect(read.status == .loaded && read.entries.count == 2)
        try File.write([Self.ride(3)], to: url, topologyRevision: Self.revision, timetableRevision: Self.timetable)
        #expect(File.read(from: url, topologyRevision: Self.revision, timetableRevision: Self.timetable).entries.count == 1)
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
        let data = try File.encode([typical, atLimit, oversize], topologyRevision: Self.revision, timetableRevision: Self.timetable)
        let read = File.decode(data, topologyRevision: Self.revision, timetableRevision: Self.timetable)
        #expect(read.status == .loaded)
        #expect(read.entries[typical.key] == typical)
        #expect(read.entries[atLimit.key] == atLimit)
        #expect(read.entries[oversize.key] == nil)
    }

    @Test("500 typical trips stay far under the 150 KB cache budget")
    func fiveHundredTrips() throws {
        let rides = (1...500).map { Self.ride(UInt64($0), spans: 6, gaps: $0 % 10 == 0 ? 1 : 0) }
        let data = try File.encode(rides, topologyRevision: Self.revision, timetableRevision: Self.timetable)
        #expect(data.count < 150_000)
    }

    @Test("a revision must be 32 bytes, and combined revisions ignore order")
    func revisions() throws {
        #expect(throws: File.WriteError.badRevision) { try File.encode([], topologyRevision: [1, 2, 3], timetableRevision: Self.timetable) }
        let a = [UInt8](repeating: 1, count: 32), b = [UInt8](repeating: 2, count: 32)
        #expect(File.revision(ofTopologyFileHashes: [a, b]) == File.revision(ofTopologyFileHashes: [b, a]))
        #expect(File.revision(ofTopologyFileHashes: [a, b]) != File.revision(ofTopologyFileHashes: [a]))
        #expect(File.revision(ofTopologyFileHashes: [a]).count == 32)
    }
}
