import Foundation
import Testing
@testable import RailCore

/// The checked-in `topology-mini.bin` was built by hand with literal offsets
/// (not from these constants); these tests hold the constants, the document
/// `docs/reference/rail-topology-format.md` and the fixture to one layout.
@Suite("RailTopologyFormat")
struct RailTopologyFormatTests {
    typealias F = RailTopologyFormat

    static var fixtureURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appending(path: "Fixtures/topology-mini.bin")
    }

    static func fixture() throws -> Data { try Data(contentsOf: fixtureURL) }

    /// String at a string-table reference.
    static func string(_ data: Data, _ header: F.ParsedHeader, _ ref: UInt32) -> String? {
        if ref == F.noString { return nil }
        let base = header.offset(.strings) + Int(ref)
        let length = Int(data.u16(base))
        return String(decoding: data.rawBytes(base + 2, length), as: UTF8.self)
    }

    @Test("record sizes and field offsets are tight and in range")
    func recordLayoutsAreTight() {
        func check(_ size: Int, _ fields: [(Int, Int)], _ name: String) {
            // Fields are laid end to end with no gaps or overlaps.
            var cursor = 0
            for (offset, width) in fields.sorted(by: { $0.0 < $1.0 }) {
                #expect(offset == cursor, "\(name): field at \(offset) expected at \(cursor)")
                cursor = offset + width
            }
            #expect(cursor == size, "\(name): fields cover \(cursor) of \(size) bytes")
        }
        check(F.Line.size, [(F.Line.id, 4), (F.Line.family, 4), (F.Line.name, 4), (F.Line.aliases, 4),
            (F.Line.institution, 2), (F.Line.categoryMask, 2), (F.Line.flags, 2), (F.Line.chainCount, 2),
            (F.Line.validFrom, 4), (F.Line.validTo, 4), (F.Line.firstNode, 4), (F.Line.nodeCount, 4),
            (F.Line.firstEdge, 4), (F.Line.edgeCount, 4), (F.Line.firstIdentity, 4),
            (F.Line.identityCount, 2), (F.Line.reserved, 2), (F.Line.operatorName, 4), (F.Line.solverName, 4), (F.Line.contentHash, 8)], "line")
        check(F.Node.size, [(F.Node.stationCode, 4), (F.Node.fullMetres, 4), (F.Node.overviewMetres, 4),
            (F.Node.longitude, 4), (F.Node.latitude, 4), (F.Node.line, 2), (F.Node.chain, 2),
            (F.Node.flags, 2), (F.Node.reserved, 2)], "node")
        check(F.Edge.size, [(F.Edge.lengthCm, 4), (F.Edge.cumulativeCm, 4), (F.Edge.validFrom, 4),
            (F.Edge.validTo, 4), (F.Edge.flags, 2), (F.Edge.runCount, 2), (F.Edge.firstRun, 4),
            (F.Edge.fineEdges, 4)], "edge")
        check(F.Run.size, [(F.Run.chain, 2), (F.Run.reserved, 2), (F.Run.fullFromCm, 4),
            (F.Run.fullToCm, 4), (F.Run.overviewFromCm, 4), (F.Run.overviewToCm, 4)], "run")
        check(F.Link.size, [(F.Link.nodeA, 4), (F.Link.nodeB, 4), (F.Link.kind, 1), (F.Link.flags, 1),
            (F.Link.reserved, 2), (F.Link.validFrom, 4), (F.Link.validTo, 4), (F.Link.registryID, 4)], "link")
        check(F.Identity.size, [(F.Identity.line, 4), (F.Identity.name, 4), (F.Identity.family, 4),
            (F.Identity.validFrom, 4), (F.Identity.validTo, 4)], "identity")
        check(F.Stop.size, [(F.Stop.key, 4), (F.Stop.keyLength, 2), (F.Stop.kind, 1), (F.Stop.reserved, 1),
            (F.Stop.firstNode, 4), (F.Stop.nodeCount, 4)], "stop")
        check(F.Header.size, [(F.Header.magicOffset, 4), (F.Header.versionOffset, 2),
            (F.Header.headerSizeOffset, 2), (F.Header.regionOffset, 4), (F.Header.flagsOffset, 4),
            (F.Header.packageSHA256Offset, 32), (F.Header.displaySHA256Offset, 32),
            (F.Header.fileLengthOffset, 4), (F.Header.reservedOffset, 4),
            (F.Header.directoryOffset, F.Table.allCases.count * F.Header.directoryEntrySize)], "header")
    }

    @Test("fixture header and directory equal the constants")
    func fixtureHeader() throws {
        let data = try Self.fixture()
        let header = try F.parseHeader(data)
        #expect(header.region == "jp")
        #expect(header.version == 2 && header.flags == 0)
        #expect(header.packageSHA256 == Array(repeating: 0x11, count: 32))
        #expect(header.displaySHA256 == Array(repeating: 0x22, count: 32))
        #expect(Int(header.fileLength) == data.count && data.count == 1064)
        #expect(F.Table.allCases.map { header.count($0) } == [2, 6, 5, 4, 2, 1, 3, 4, 239])
        // Tables are contiguous, 4-aligned, in directory order, and the file ends with the padded strings.
        var cursor = F.Header.size
        for table in F.Table.allCases {
            #expect(header.offset(table) == cursor, "\(table) offset")
            cursor += header.count(table) * table.recordSize
        }
        #expect(cursor + (4 - cursor % 4) % 4 == data.count)
    }

    @Test("fixture records decode to the documented mini network")
    func fixtureRecords() throws {
        let data = try Self.fixture()
        let h = try F.parseHeader(data)
        func rec(_ t: F.Table, _ i: Int) -> Int { h.offset(t) + i * t.recordSize }
        func str(_ ref: UInt32) -> String? { Self.string(data, h, ref) }

        // Offset 0 is the empty string.
        #expect(str(0) == "")

        let a = rec(.lines, 0), b = rec(.lines, 1)
        #expect(str(data.u32(a + F.Line.id)) == "jp.test-a")
        #expect(str(data.u32(a + F.Line.aliases)) == "A線\u{1F}Test A")
        #expect(data.u16(a + F.Line.flags) == 0)
        #expect(data.u32(a + F.Line.firstNode) == 0 && data.u32(a + F.Line.nodeCount) == 3)
        #expect(data.u32(a + F.Line.edgeCount) == 2)
        // v2: the operator name and the 8-byte content hash the builder wrote (Python `line_content_hashes`).
        #expect(str(data.u32(a + F.Line.operatorName)) == "test-op")
        #expect(str(data.u32(b + F.Line.operatorName)) == "test-op-2")
        #expect(str(data.u32(a + F.Line.solverName)) == "solver-a" && str(data.u32(b + F.Line.solverName)) == "solver-b")
        #expect(data.rawBytes(a + F.Line.contentHash, 8) == MiniTopologyEncoder.hashA)
        #expect(data.rawBytes(b + F.Line.contentHash, 8) == MiniTopologyEncoder.hashB)
        #expect(str(data.u32(b + F.Line.id)) == "jp.test-b")
        let bFlags = F.LineFlag(rawValue: data.u16(b + F.Line.flags))
        #expect(bFlags == [.loop, .retired, .nonContinuous])
        #expect(data.u32(b + F.Line.validFrom) == F.dayNumber(ofISODate: "2010-01-01"))
        #expect(data.u32(b + F.Line.validTo) == F.dayNumber(ofISODate: "2020-01-01"))
        #expect(data.u32(b + F.Line.firstNode) == 3 && data.u32(b + F.Line.nodeCount) == 3)
        // A loop line has as many edges as nodes.
        #expect(data.u32(b + F.Line.edgeCount) == 3 && data.u32(b + F.Line.firstEdge) == 2)

        // Nodes: station, junction point, no overview ruler.
        let n2 = rec(.nodes, 2), n4 = rec(.nodes, 4), n5 = rec(.nodes, 5)
        #expect(str(data.u32(n2 + F.Node.stationCode)) == "A03")
        #expect(data.u32(n2 + F.Node.fullMetres) == 400_050)
        // Unset is legal per node (this one cannot be projected onto the overview chain).
        #expect(data.u32(n2 + F.Node.overviewMetres) == F.unsetMetres)
        #expect(data.f32(n2 + F.Node.longitude) == 139.03)
        #expect(data.u32(n4 + F.Node.stationCode) == F.noString)
        #expect(F.NodeFlag(rawValue: data.u16(n4 + F.Node.flags)) == .junctionPoint)
        #expect(data.u16(n5 + F.Node.chain) == 1 && data.u16(n5 + F.Node.line) == 1)

        // Edges: cumulative length, one-way withheld edge, runs.
        let e0 = rec(.edges, 0), e1 = rec(.edges, 1), e3 = rec(.edges, 3)
        #expect(data.u32(e1 + F.Edge.cumulativeCm) == data.u32(e0 + F.Edge.lengthCm))
        #expect((0..<5).map { data.u32(rec(.edges, $0) + F.Edge.fineEdges) } == [2, 3, 2, 3, 4])
        #expect(F.EdgeFlag(rawValue: data.u16(e1 + F.Edge.flags)) == [.forward, .withheld])
        #expect(data.u32(e1 + F.Edge.validFrom) == F.dayNumber(ofISODate: "2010-01-01"))
        #expect(F.EdgeFlag(rawValue: data.u16(e3 + F.Edge.flags)) == [.forward, .reverse, .hasRuns])
        #expect(data.u16(e3 + F.Edge.runCount) == 2 && data.u32(e3 + F.Edge.firstRun) == 1)
        // Edge lengths of a line sum to its closing cumulative position.
        let closing = rec(.edges, 4)
        #expect(data.u32(closing + F.Edge.cumulativeCm) + data.u32(closing + F.Edge.lengthCm) == 170_000)
        // The lane-split edge crosses from part 0 to part 1.
        #expect(data.u16(rec(.runs, 1) + F.Run.chain) == 0)
        #expect(data.u16(rec(.runs, 2) + F.Run.chain) == 1)
        #expect(data.u32(rec(.runs, 2) + F.Run.overviewToCm) == 19_000)

        // Links: a dated junction and a directed through service.
        let l0 = rec(.links, 0), l1 = rec(.links, 1)
        #expect(data.u32(l0 + F.Link.nodeA) == 1 && data.u32(l0 + F.Link.nodeB) == 3)
        #expect(F.LinkKind(rawValue: data.u8(l0 + F.Link.kind)) == .physicalJunction)
        #expect(str(data.u32(l0 + F.Link.registryID)) == "jct-test-1")
        #expect(str(data.u32(l1 + F.Link.registryID)) == "ts-test-1")
        #expect(F.LinkKind(rawValue: data.u8(l1 + F.Link.kind)) == .throughService)
        #expect(data.u8(l1 + F.Link.flags) == 1)

        // Identity row.
        let i0 = rec(.identities, 0)
        #expect(str(data.u32(i0 + F.Identity.name)) == "旧テストA線")
        // A pre-2000 bound survives (the data reaches back to 1872), and validTo is exclusive.
        #expect(data.u32(i0 + F.Identity.validFrom) == F.dayNumber(ofISODate: "1987-04-01"))
        #expect(data.u32(i0 + F.Identity.validTo) == F.dayNumber(ofISODate: "2010-01-01"))

        // Stops are sorted by key bytes and point into stopNodes.
        var keys: [[UInt8]] = []
        for i in 0..<h.count(.stops) {
            let s = rec(.stops, i)
            let key = str(data.u32(s + F.Stop.key))!
            #expect(Int(data.u16(s + F.Stop.keyLength)) == key.utf8.count)
            keys.append(Array(key.utf8))
        }
        #expect(keys.lexicographicallySorted)
        let multi = rec(.stops, 2)
        #expect(F.StopKind(rawValue: data.u8(multi + F.Stop.kind)) == .registryStationID)
        let first = Int(data.u32(multi + F.Stop.firstNode)), n = Int(data.u32(multi + F.Stop.nodeCount))
        #expect((first..<first + n).map { data.u32(rec(.stopNodes, $0)) } == [1, 3])
    }

    @Test("an encoder written from the constants reproduces the fixture byte for byte")
    func encoderRoundTrip() throws {
        let encoded = MiniTopologyEncoder.encode()
        let fixture = try Self.fixture()
        #expect(encoded == fixture)
        // And the reader entry point accepts it.
        let topology = try RailTopology(data: encoded)
        #expect(topology.header.region == "jp")
    }

    @Test("day numbers count from 1800-01-01, cover the 1870s data and reject nonsense")
    func dayNumbers() {
        #expect(F.dayNumber(ofISODate: "1800-01-01") == 1)
        #expect(F.dayNumber(ofISODate: "1800-12-31") == 365)
        #expect(F.dayNumber(ofISODate: "2000-01-01") == 73_049)
        #expect(F.dayNumber(ofISODate: "1872-10-14")! < F.dayNumber(ofISODate: "1993-03-01")!)
        #expect(F.dayNumber(ofISODate: "1993-03-01")! < F.dayNumber(ofISODate: "2000-01-01")!)
        #expect(F.dayNumber(ofISODate: "2010-01-01")! - F.dayNumber(ofISODate: "2009-12-31")! == 1)
        #expect(F.dayNumber(ofISODate: "1799-12-31") == nil)
        #expect(F.dayNumber(ofISODate: "2023-02-29") == nil)
        #expect(F.dayNumber(ofISODate: "2024-02-29") != nil)
        #expect(F.dayNumber(ofISODate: "2024-2-9") == nil)
        #expect(F.dayNumber(ofISODate: "2200-01-01") != nil)
    }

    @Test("validity is half-open like the sources, 0 is open, undated means no validTo")
    func validity() {
        #expect(F.isValid(on: 100, from: 0, to: 0))
        #expect(F.isValid(on: 100, from: 100, to: 0))
        #expect(!F.isValid(on: 99, from: 100, to: 0))
        // validTo is the first day the row no longer applies: the day before a closure
        // resolves differently from the day of it.
        #expect(F.isValid(on: 99, from: 0, to: 100))
        #expect(!F.isValid(on: 100, from: 0, to: 100))
        #expect(!F.isValid(on: 101, from: 0, to: 100))
        // Undated: exactly the rows with no validTo, whatever validFrom is (ADR 0011).
        #expect(F.isValid(on: nil, from: 100, to: 0))
        #expect(F.isValid(on: nil, from: 0, to: 0))
        #expect(!F.isValid(on: nil, from: 0, to: 100))
        #expect(!F.isValid(on: nil, from: 50, to: 100))
    }

    @Test("a truncated, mislabelled or inconsistent header is rejected")
    func headerRejections() throws {
        let good = try Self.fixture()
        #expect(throws: F.FormatError.truncated) { try F.parseHeader(good.prefix(100)) }
        var bad = good; bad[0] = 0x58
        #expect(throws: F.FormatError.badMagic) { try F.parseHeader(bad) }
        bad = good; bad[4] = 1
        #expect(throws: F.FormatError.unsupportedVersion(1)) { try F.parseHeader(bad) }
        #expect(throws: F.FormatError.lengthMismatch(declared: 1064, actual: 1063)) {
            try F.parseHeader(good.dropLast())
        }
        bad = good; bad[F.Header.directoryOffset + 8 + 4] = 0xFF  // nodes count far past the file
        bad[F.Header.directoryOffset + 8 + 5] = 0xFF
        #expect(throws: F.FormatError.badTable(.nodes)) { try F.parseHeader(bad) }
    }

    @Test("ride span packs into eight bytes and back")
    func rideSpanPacking() throws {
        let span = RideRefs.Span(
            span: RailTopology.Span(line: 513, fromNode: 7, toNode: 3, wraps: true),
            section: 0x1234, unproven: true)
        #expect(span.bytes.count == RideRefs.Span.byteCount)
        #expect(span.bytes == [0x01, 0x02, 0x07, 0x00, 0x03, 0x00, 0x34, 0xD2])
        #expect(RideRefs.Span(bytes: span.bytes) == span)
        #expect(RideRefs.Span(bytes: [1, 2, 3]) == nil)
    }

    @Test("a full circuit is two spans of one section split at an intermediate node")
    func fullCircuitIsTwoSpans() {
        // Yamanote-style loop of 6 nodes, from node 2 round to node 2: 2 -> 5, then 5 -> 2.
        let first = RideRefs.Span(span: RailTopology.Span(line: 4, fromNode: 2, toNode: 5), section: 3)
        let second = RideRefs.Span(span: RailTopology.Span(line: 4, fromNode: 5, toNode: 2, wraps: true), section: 3)
        #expect(first.span.fromNode != first.span.toNode && second.span.fromNode != second.span.toNode)
        #expect(first.section == second.section)
        #expect(RideRefs.Span(bytes: second.bytes) == second)
    }
}

private extension Array where Element == [UInt8] {
    var lexicographicallySorted: Bool {
        zip(self, dropFirst()).allSatisfy { $0.lexicographicallyPrecedes($1) }
    }
}

/// Encodes the mini network from the layout constants, interning strings in
/// first-use order exactly as the fixture's author did.
private enum MiniTopologyEncoder {
    typealias F = RailTopologyFormat

    struct Out {
        var bytes: [UInt8]
        init(size: Int) { bytes = Array(repeating: 0, count: size) }
        mutating func u8(_ at: Int, _ v: UInt8) { bytes[at] = v }
        mutating func u16(_ at: Int, _ v: UInt16) { bytes[at] = UInt8(v & 0xFF); bytes[at + 1] = UInt8(v >> 8) }
        mutating func u32(_ at: Int, _ v: UInt32) { u16(at, UInt16(v & 0xFFFF)); u16(at + 2, UInt16(v >> 16)) }
        mutating func f32(_ at: Int, _ v: Float) { u32(at, v.bitPattern) }
    }

    /// The content hashes the builder wrote into the fixture (the Python test regenerates the same
    /// bytes from the same records, so these pin the hash algorithm across the two languages).
    static let hashA: [UInt8] = [0xCF, 0xEC, 0xB0, 0x52, 0x0D, 0xAF, 0xAF, 0x61]
    static let hashB: [UInt8] = [0x44, 0x4E, 0x27, 0xCE, 0xE5, 0x33, 0x47, 0x4D]

    static func encode() -> Data {
        var strings: [UInt8] = []
        var interned: [String: UInt32] = [:]
        func s(_ text: String?) -> UInt32 {
            guard let text else { return F.noString }
            if let known = interned[text] { return known }
            let at = UInt32(strings.count)
            let utf8 = Array(text.utf8)
            strings += [UInt8(utf8.count & 0xFF), UInt8(utf8.count >> 8)] + utf8
            interned[text] = at
            return at
        }
        _ = s("")
        let d2010 = F.dayNumber(ofISODate: "2010-01-01")!
        let d1987 = F.dayNumber(ofISODate: "1987-04-01")!
        let d2020 = F.dayNumber(ofISODate: "2020-01-01")!
        let both: UInt16 = F.EdgeFlag([.forward, .reverse]).rawValue
        let runEdge: UInt16 = F.EdgeFlag([.forward, .reverse, .hasRuns]).rawValue

        func line(_ id: String, _ fam: String, _ name: String, _ alias: String, _ inst: UInt16,
                  _ cat: UInt16, _ flags: F.LineFlag, _ chains: UInt16, _ vf: UInt32, _ vt: UInt32,
                  _ fn: UInt32, _ nn: UInt32, _ fe: UInt32, _ ne: UInt32, _ fi: UInt32, _ ni: UInt16,
                  _ op: String, _ solver: String, _ hash: [UInt8]) -> [UInt8] {
            var o = Out(size: F.Line.size)
            o.u32(F.Line.id, s(id)); o.u32(F.Line.family, s(fam)); o.u32(F.Line.name, s(name))
            o.u32(F.Line.aliases, s(alias))
            o.u16(F.Line.institution, inst); o.u16(F.Line.categoryMask, cat); o.u16(F.Line.flags, flags.rawValue)
            o.u16(F.Line.chainCount, chains); o.u32(F.Line.validFrom, vf); o.u32(F.Line.validTo, vt)
            o.u32(F.Line.firstNode, fn); o.u32(F.Line.nodeCount, nn)
            o.u32(F.Line.firstEdge, fe); o.u32(F.Line.edgeCount, ne)
            o.u32(F.Line.firstIdentity, fi); o.u16(F.Line.identityCount, ni)
            o.u32(F.Line.operatorName, s(op)); o.u32(F.Line.solverName, s(solver))
            for (i, byte) in hash.enumerated() { o.u8(F.Line.contentHash + i, byte) }
            return o.bytes
        }
        let lines = [
            line("jp.test-a", "test-op/test-a", "テストA線", "A線\u{1F}Test A", 1, 1, [], 1, 0, 0, 0, 3, 0, 2, 0, 1, "test-op", "solver-a", hashA),
            line("jp.test-b", "test-op/test-b", "テストB環状線", "", 2, 2, [.loop, .retired, .nonContinuous],
                 2, d2010, d2020, 3, 3, 2, 3, 1, 0, "test-op-2", "solver-b", hashB),
        ]

        func node(_ code: String?, _ full: UInt32, _ ov: UInt32, _ lon: Float, _ lat: Float,
                  _ line: UInt16, _ chain: UInt16, _ flags: F.NodeFlag) -> [UInt8] {
            var o = Out(size: F.Node.size)
            o.u32(F.Node.stationCode, s(code)); o.u32(F.Node.fullMetres, full); o.u32(F.Node.overviewMetres, ov)
            o.f32(F.Node.longitude, lon); o.f32(F.Node.latitude, lat)
            o.u16(F.Node.line, line); o.u16(F.Node.chain, chain); o.u16(F.Node.flags, flags.rawValue)
            return o.bytes
        }
        let unset = F.unsetMetres
        let nodes = [
            node("A01", 0, 0, 139.0, 35.0, 0, 0, []),
            node("A02", 150_000, 140_000, 139.01, 35.0, 0, 0, []),
            node("A03", 400_050, unset, 139.03, 35.01, 0, 0, []),
            node("B01", 0, 0, 139.01, 35.0, 1, 0, []),
            node(nil, 50_000, 48_000, 139.02, 35.0, 1, 0, .junctionPoint),
            node("B03", 20_000, 19_000, 139.02, 35.02, 1, 1, []),
        ]

        func edge(_ len: UInt32, _ cum: UInt32, _ vf: UInt32, _ vt: UInt32, _ flags: UInt16,
                  _ runs: UInt16, _ first: UInt32, _ fine: UInt32) -> [UInt8] {
            var o = Out(size: F.Edge.size)
            o.u32(F.Edge.lengthCm, len); o.u32(F.Edge.cumulativeCm, cum)
            o.u32(F.Edge.validFrom, vf); o.u32(F.Edge.validTo, vt); o.u16(F.Edge.flags, flags)
            o.u16(F.Edge.runCount, runs); o.u32(F.Edge.firstRun, first); o.u32(F.Edge.fineEdges, fine)
            return o.bytes
        }
        let edges = [
            edge(150_000, 0, 0, 0, both, 0, 0, 2),
            edge(250_050, 150_000, d2010, 0, F.EdgeFlag([.forward, .withheld]).rawValue, 0, 0, 3),
            edge(50_000, 0, 0, 0, runEdge, 1, 0, 2),
            edge(90_000, 50_000, 0, 0, runEdge, 2, 1, 3),
            edge(30_000, 140_000, 0, 0, runEdge, 1, 3, 4),
        ]

        func run(_ chain: UInt16, _ a: UInt32, _ b: UInt32, _ c: UInt32, _ d: UInt32) -> [UInt8] {
            var o = Out(size: F.Run.size)
            o.u16(F.Run.chain, chain); o.u32(F.Run.fullFromCm, a); o.u32(F.Run.fullToCm, b)
            o.u32(F.Run.overviewFromCm, c); o.u32(F.Run.overviewToCm, d)
            return o.bytes
        }
        let runs = [run(0, 0, 50_000, 0, 48_000), run(0, 50_000, 80_000, 48_000, 76_000),
                    run(1, 0, 20_000, 0, 19_000), run(1, 20_000, 50_000, 19_000, 47_000)]

        func link(_ a: UInt32, _ b: UInt32, _ kind: F.LinkKind, _ flags: UInt8, _ vf: UInt32, _ vt: UInt32,
                  _ registry: String) -> [UInt8] {
            var o = Out(size: F.Link.size)
            o.u32(F.Link.nodeA, a); o.u32(F.Link.nodeB, b); o.u8(F.Link.kind, kind.rawValue)
            o.u8(F.Link.flags, flags); o.u32(F.Link.validFrom, vf); o.u32(F.Link.validTo, vt)
            o.u32(F.Link.registryID, s(registry))
            return o.bytes
        }
        let links = [link(1, 3, .physicalJunction, 0, d2010, 0, "jct-test-1"),
                     link(2, 5, .throughService, 1, 0, 0, "ts-test-1")]

        var identity = Out(size: F.Identity.size)
        identity.u32(F.Identity.line, 0); identity.u32(F.Identity.name, s("旧テストA線"))
        identity.u32(F.Identity.family, s("test-op/old-a")); identity.u32(F.Identity.validFrom, d1987)
        identity.u32(F.Identity.validTo, d2010)

        func stop(_ key: String, _ kind: F.StopKind, _ first: UInt32, _ count: UInt32) -> [UInt8] {
            var o = Out(size: F.Stop.size)
            o.u32(F.Stop.key, s(key)); o.u16(F.Stop.keyLength, UInt16(key.utf8.count))
            o.u8(F.Stop.kind, kind.rawValue); o.u32(F.Stop.firstNode, first); o.u32(F.Stop.nodeCount, count)
            return o.bytes
        }
        let stops = [stop("A01", .platformCode, 0, 1), stop("B01", .platformCode, 1, 1),
                     stop("st:test-a02", .registryStationID, 2, 2)]
        var stopNodes = Out(size: 16)
        for (i, v) in [UInt32(0), 3, 1, 3].enumerated() { stopNodes.u32(i * 4, v) }

        let tables: [[UInt8]] = [lines.flatMap { $0 }, nodes.flatMap { $0 }, edges.flatMap { $0 },
                                 runs.flatMap { $0 }, links.flatMap { $0 }, identity.bytes,
                                 stops.flatMap { $0 }, stopNodes.bytes]
        let counts = [lines.count, nodes.count, edges.count, runs.count, links.count, 1, stops.count, 4]
        var body: [UInt8] = []
        var header = Out(size: F.Header.size)
        var offset = F.Header.size
        for (i, table) in tables.enumerated() {
            header.u32(F.Header.directoryOffset + i * 8, UInt32(offset))
            header.u32(F.Header.directoryOffset + i * 8 + 4, UInt32(counts[i]))
            body += table; offset += table.count
        }
        header.u32(F.Header.directoryOffset + 8 * 8, UInt32(offset))
        header.u32(F.Header.directoryOffset + 8 * 8 + 4, UInt32(strings.count))
        body += strings + Array(repeating: 0, count: (4 - strings.count % 4) % 4)

        for (i, b) in F.magic.enumerated() { header.u8(F.Header.magicOffset + i, b) }
        header.u16(F.Header.versionOffset, F.formatVersion)
        header.u16(F.Header.headerSizeOffset, UInt16(F.Header.size))
        header.u8(F.Header.regionOffset, UInt8(ascii: "j")); header.u8(F.Header.regionOffset + 1, UInt8(ascii: "p"))
        for i in 0..<32 {
            header.u8(F.Header.packageSHA256Offset + i, 0x11)
            header.u8(F.Header.displaySHA256Offset + i, 0x22)
        }
        header.u32(F.Header.fileLengthOffset, UInt32(F.Header.size + body.count))
        return Data(header.bytes + body)
    }
}
