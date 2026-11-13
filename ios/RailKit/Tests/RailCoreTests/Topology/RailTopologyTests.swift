import Foundation
import Testing
@testable import RailCore

/// The reader against the hand-built mini fixture and small generated networks.
@Suite("RailTopology reader")
struct RailTopologyTests {
    typealias F = RailTopologyFormat

    static func mini() throws -> RailTopology {
        try RailTopology(data: RailTopologyFormatTests.fixture())
    }

    // MARK: Open and corruption

    @Test("a truncated file throws at every length short of the whole")
    func truncatedFileThrows() throws {
        let good = try RailTopologyFormatTests.fixture()
        for length in stride(from: 0, to: good.count, by: 7) {
            #expect(throws: F.FormatError.self) { try RailTopology(data: good.prefix(length)) }
        }
        #expect(throws: F.FormatError.self) { try RailTopology(data: good.dropLast()) }
    }

    @Test("corrupt records are refused at open, not trapped at query time")
    func corruptRecordsThrow() throws {
        let good = try RailTopologyFormatTests.fixture()
        let h = try F.parseHeader(good)
        func corrupted(_ table: F.Table, record: Int, field: Int, to value: UInt32) -> Data {
            var bad = good
            let at = h.offset(table) + record * table.recordSize + field
            for i in 0..<4 { bad[at + i] = UInt8((value >> (8 * UInt32(i))) & 0xFF) }
            return bad
        }
        // A line's node range past the nodes table.
        #expect(throws: F.FormatError.badTable(.lines)) {
            try RailTopology(data: corrupted(.lines, record: 1, field: F.Line.firstNode, to: 99))
        }
        // A line's edge count that fits neither a loop nor a chain.
        #expect(throws: F.FormatError.badTable(.lines)) {
            try RailTopology(data: corrupted(.lines, record: 0, field: F.Line.edgeCount, to: 3))
        }
        // A line id pointing outside the string table.
        #expect(throws: F.FormatError.badTable(.lines)) {
            try RailTopology(data: corrupted(.lines, record: 0, field: F.Line.id, to: 100_000))
        }
        // A link to a node that does not exist.
        #expect(throws: F.FormatError.badTable(.links)) {
            try RailTopology(data: corrupted(.links, record: 0, field: F.Link.nodeB, to: 500))
        }
        // An edge flagged as having runs but pointing past the run table.
        #expect(throws: F.FormatError.badTable(.edges)) {
            try RailTopology(data: corrupted(.edges, record: 2, field: F.Edge.firstRun, to: 50))
        }
        // A stop whose node list runs past stopNodes.
        #expect(throws: F.FormatError.badTable(.stops)) {
            try RailTopology(data: corrupted(.stops, record: 2, field: F.Stop.nodeCount, to: 90))
        }
        // Stops out of order.
        var swapped = good
        let a = h.offset(.stops), b = a + F.Stop.size
        for i in 0..<F.Stop.size { swapped.swapAt(a + i, b + i) }
        #expect(throws: F.FormatError.badTable(.stops)) { try RailTopology(data: swapped) }
        // Lines must tile the node and edge tables: a gap leaves nodes no line vouches for.
        #expect(throws: F.FormatError.badTable(.lines)) {
            try RailTopology(data: corrupted(.lines, record: 0, field: F.Line.firstNode, to: 1))
        }
        #expect(throws: F.FormatError.badTable(.lines)) {
            try RailTopology(data: corrupted(.lines, record: 1, field: F.Line.firstEdge, to: 3))
        }
        // Cumulative lengths must be the running sum of edge lengths.
        #expect(throws: F.FormatError.badTable(.edges)) {
            try RailTopology(data: corrupted(.edges, record: 1, field: F.Edge.cumulativeCm, to: 10))
        }
        #expect(throws: F.FormatError.badTable(.edges)) {
            try RailTopology(data: corrupted(.edges, record: 0, field: F.Edge.lengthCm, to: 1))
        }
        // A stop node outside the nodes table.
        #expect(throws: F.FormatError.badTable(.stopNodes)) {
            try RailTopology(data: corrupted(.stopNodes, record: 0, field: 0, to: 77))
        }
    }

    @Test("a file with more lines than a region may hold is refused at open")
    func tooManyLinesRefused() {
        var net = TestNetwork()
        net.lines = (0...F.maxLinesPerRegion).map { TestNetwork.Line(id: "l\($0)", nodes: [], edges: []) }
        let data = net.encode()
        #expect(throws: F.FormatError.badTable(.lines)) { try RailTopology(data: data) }
    }

    @Test("a node, link or stop that no line covers is refused at open")
    func uncoveredNodesRefused() throws {
        // Two chains of two stations; shrink the last line's node count so its last node is uncovered,
        // and point a link and a stop node at it.
        var net = TestNetwork()
        net.lines = [.chain("p", ["P0", "P1"], lengths: [10_000]), .chain("q", ["Q0", "Q1", "Q2"], lengths: [10_000, 10_000])]
        net.links = [.init(a: (0, 1), b: (1, 2))]
        let good = net.encode()
        let h = try F.parseHeader(good)
        // q's node count 3 -> 2 with one edge fewer: node 4 is then in no line, yet the link names it.
        var bad = good
        func put(_ table: F.Table, _ record: Int, _ field: Int, _ value: UInt32) {
            let at = h.offset(table) + record * table.recordSize + field
            for i in 0..<4 { bad[at + i] = UInt8((value >> (8 * UInt32(i))) & 0xFF) }
        }
        put(.lines, 1, F.Line.nodeCount, 2); put(.lines, 1, F.Line.edgeCount, 1)
        #expect(throws: F.FormatError.badTable(.nodes)) { try RailTopology(data: bad) }
    }

    @Test("a display blob SHA-256 mismatch is rejected, a match is accepted")
    func displayBlobMismatchRejected() throws {
        let data = try RailTopologyFormatTests.fixture()
        let matching = Array(repeating: UInt8(0x22), count: 32)
        let other = Array(repeating: UInt8(0x23), count: 32)
        #expect(throws: F.FormatError.displayBlobMismatch) { try RailTopology(data: data, displayBlobSHA256: other) }
        #expect(throws: F.FormatError.displayBlobMismatch) { try RailTopology(data: data, displayBlobSHA256: []) }
        let topology = try RailTopology(data: data, displayBlobSHA256: matching)
        #expect(topology.lineCount == 2)
    }

    @Test("a file opens memory-mapped from a URL")
    func opensFromMappedFile() throws {
        let topology = try RailTopology(contentsOf: RailTopologyFormatTests.fixtureURL,
                                        displayBlobSHA256: Array(repeating: 0x22, count: 32))
        #expect(topology.lineID(1) == "jp.test-b")
        #expect(topology.nodes(forStop: "A01") == [.init(line: 0, node: 0)])
    }

    // MARK: Lookups

    @Test("lines, flags and node codes read in place")
    func lineAccessors() throws {
        let t = try Self.mini()
        #expect(t.lineCount == 2 && t.nodeTotal == 6 && t.edgeTotal == 5 && t.linkCount == 2)
        #expect(t.lineIndex(forID: "jp.test-b") == 1 && t.lineIndex(forID: "jp.test") == nil)
        #expect(t.lineID(0) == "jp.test-a" && t.lineID(9) == nil)
        #expect(t.lineName(1) == "テストB環状線")
        #expect(t.lineFlags(1) == [.loop, .retired, .nonContinuous])
        #expect(t.institution(ofLine: 1) == 2)
        #expect(t.nodeCount(ofLine: 0) == 3)
        #expect(t.stationCode(of: .init(line: 0, node: 2)) == "A03")
        // A junction point has no station code.
        #expect(t.stationCode(of: .init(line: 1, node: 1)) == nil)
        #expect(t.stationCode(of: .init(line: 5, node: 0)) == nil)
    }

    @Test("operator, solver name, aliases and content hash read in place")
    func v2LineAccessors() throws {
        let t = try Self.mini()
        #expect(t.operatorName(ofLine: 0) == "test-op" && t.operatorName(ofLine: 1) == "test-op-2" && t.operatorName(ofLine: 9) == nil)
        #expect(t.solverName(ofLine: 0) == "solver-a" && t.solverName(ofLine: 1) == "solver-b" && t.solverName(ofLine: 9) == nil)
        #expect(t.aliasNames(ofLine: 0) == ["A線", "Test A"] && t.aliasNames(ofLine: 1).isEmpty && t.aliasNames(ofLine: 9).isEmpty)
        #expect(t.contentHash(ofLine: 0) == 0x61AF_AF0D_52B0_ECCF && t.contentHash(ofLine: 1) == 0x4D47_33E5_CE27_4E44)
        #expect(t.contentHash(ofLine: 0) != t.contentHash(ofLine: 1) && t.contentHash(ofLine: 9) == nil)
        #expect(t.rideStamps.stamps.count == 2 && t.rideStamps.stamps[0].contentHash == 0x61AF_AF0D_52B0_ECCF)
    }

    @Test("a line record whose operator or solver name points outside the string table is refused at open")
    func badV2Strings() throws {
        let good = try RailTopologyFormatTests.fixture()
        for field in [F.Line.operatorName, F.Line.solverName] {
            var bytes = good
            let h = try F.parseHeader(good)
            let at = h.offset(.lines) + field
            bytes[at] = 0xFE; bytes[at + 1] = 0xFF; bytes[at + 2] = 0xFF; bytes[at + 3] = 0x7F
            #expect(throws: F.FormatError.self) { try RailTopology(data: bytes) }
        }
        // A fine-edge count of zero is refused too.
        var zero = good
        let h = try F.parseHeader(good)
        for i in 0..<4 { zero[h.offset(.edges) + F.Edge.fineEdges + i] = 0 }
        #expect(throws: F.FormatError.self) { try RailTopology(data: zero) }
    }

    @Test("stop keys find nodes across lines in ascending order; unknown keys find none")
    func stopLookup() throws {
        let t = try Self.mini()
        #expect(t.nodes(forStop: "A01") == [.init(line: 0, node: 0)])
        #expect(t.nodes(forStop: "st:test-a02") == [.init(line: 0, node: 1), .init(line: 1, node: 0)])
        #expect(t.nodes(forStop: "A") == [] && t.nodes(forStop: "") == [] && t.nodes(forStop: "ZZZ") == [])
    }

    @Test("a key held under two kinds returns the union once")
    func stopKeyAcrossKinds() throws {
        var net = TestNetwork()
        net.lines = [.chain("a", ["S1", "S2"], lengths: [100]), .chain("b", ["T1", "T2"], lengths: [100])]
        net.extraStops = [("S1", .groupCode, [(0, 0), (1, 1)]), ("grp:1", .groupCode, [(1, 0), (0, 1)])]
        let t = try net.topology()
        #expect(t.nodes(forStop: "S1") == [.init(line: 0, node: 0), .init(line: 1, node: 1)])
        #expect(t.nodes(forStop: "grp:1") == [.init(line: 0, node: 1), .init(line: 1, node: 0)])
    }

    // MARK: Lengths

    @Test("length is a cumulative subtraction, minus withheld edges")
    func lengths() throws {
        let t = try Self.mini()
        // Line A: edge 0 is 150,000 cm, edge 1 is a withheld 250,050 cm.
        #expect(t.lengthCm(of: t.span("jp.test-a", 0, 1)) == 150_000)
        #expect(t.lengthCm(of: t.span("jp.test-a", 1, 0)) == 150_000)
        #expect(t.lengthCm(of: t.span("jp.test-a", 0, 2)) == 150_000)
        #expect(t.containsWithheldEdge(t.span("jp.test-a", 0, 2)))
        #expect(!t.containsWithheldEdge(t.span("jp.test-a", 0, 1)))
        // Loop B: edges 50,000 / 90,000 / 30,000 closing; the wrap takes the other way round.
        #expect(t.lengthCm(of: t.span("jp.test-b", 0, 2)) == 140_000)
        #expect(t.lengthCm(of: t.span("jp.test-b", 0, 2, wraps: true)) == 30_000)
        #expect(t.lengthCm(of: t.span("jp.test-b", 2, 0, wraps: true)) == 30_000)
        #expect(t.lengthCm(of: t.span("jp.test-b", 1, 0, wraps: true)) == 120_000)
        // Spans that do not lie on the line measure nothing.
        #expect(t.lengthCm(of: .init(line: 0, fromNode: 1, toNode: 1)) == 0)
        #expect(t.lengthCm(of: .init(line: 0, fromNode: 0, toNode: 9)) == 0)
        #expect(t.lengthCm(of: .init(line: 0, fromNode: 0, toNode: 2, wraps: true)) == 0)
        #expect(t.lengthCm(of: .init(line: 7, fromNode: 0, toNode: 1)) == 0)
    }

    // MARK: Stroke refs

    @Test("a continuous span is one stroke ref on each ruler, reversed against the chain")
    func continuousStrokeRefs() throws {
        let t = try Self.mini()
        let a = "jp.test-a"
        #expect(t.strokeRefs(of: t.span(a, 0, 1), detail: .full)
                == [StrokeRef(chainID: "jp|jp.test-a#0", from: 0, to: 1500)])
        #expect(t.strokeRefs(of: t.span(a, 0, 1), detail: .overview)
                == [StrokeRef(chainID: "jp|jp.test-a#0", from: 0, to: 1400)])
        // Two edges merge into one piece; against the chain, from > to.
        #expect(t.strokeRefs(of: t.span(a, 2, 0), detail: .full)
                == [StrokeRef(chainID: "jp|jp.test-a#0", from: 4000.5, to: 0)])
        // Node 2 has no overview position: nothing at overview, full still works.
        #expect(t.strokeRefs(of: t.span(a, 0, 2), detail: .overview).isEmpty)
        #expect(t.strokeRefs(of: t.span(a, 0, 2), detail: .full).count == 1)
    }

    @Test("a span over parts splits at the part change, in travel order, and honours the loop's closing edge")
    func partStrokeRefs() throws {
        let t = try Self.mini()
        let b = "jp.test-b"
        #expect(t.strokeRefs(of: t.span(b, 0, 2), detail: .full) == [
            StrokeRef(chainID: "jp|jp.test-b#0", from: 0, to: 800),
            StrokeRef(chainID: "jp|jp.test-b#1", from: 0, to: 200)])
        #expect(t.strokeRefs(of: t.span(b, 0, 2), detail: .overview) == [
            StrokeRef(chainID: "jp|jp.test-b#0", from: 0, to: 760),
            StrokeRef(chainID: "jp|jp.test-b#1", from: 0, to: 190)])
        // Reversed: runs in reverse order with swapped ends, merged where they continue.
        #expect(t.strokeRefs(of: t.span(b, 2, 0), detail: .full) == [
            StrokeRef(chainID: "jp|jp.test-b#1", from: 200, to: 0),
            StrokeRef(chainID: "jp|jp.test-b#0", from: 800, to: 0)])
        // The closing edge, crossed upward from the last node to node 0.
        #expect(t.strokeRefs(of: t.span(b, 2, 0, wraps: true), detail: .full)
                == [StrokeRef(chainID: "jp|jp.test-b#1", from: 200, to: 500)])
        // A span that does not lie on the line yields nothing.
        #expect(t.strokeRefs(of: .init(line: 1, fromNode: 0, toNode: 9), detail: .full).isEmpty)
    }

    @Test("a node with no chain slot makes the span undrawable")
    func noChainSlotIsUndrawable() throws {
        var net = TestNetwork()
        var line = TestNetwork.Line.chain("a", ["P", "Q", "R"], lengths: [100, 100])
        line.nodes[1] = TestNetwork.Node(code: "Q", full: F.unsetMetres, overview: F.unsetMetres, chain: 0, flags: [.noChainSlot])
        net.lines = [line]
        let t = try net.topology()
        #expect(t.strokeRefs(of: t.span("a", 0, 2), detail: .full).isEmpty)
        #expect(t.strokeRefs(of: t.span("a", 0, 1), detail: .full).isEmpty)
        #expect(t.lengthCm(of: t.span("a", 0, 2)) == 200)
    }

    @Test("adjacent pieces on one chain that do not continue in one direction stay separate")
    func outAndBackPiecesDoNotMerge() throws {
        var net = TestNetwork()
        var line = TestNetwork.Line.chain("a", ["P", "Q", "R"], lengths: [100, 100])
        // The first edge runs to 100 and the second comes back from 100 to 50 on the same chain.
        line.edges[0].runs = [.init(chain: 0, full: (0, 100), overview: (0, 100))]
        line.edges[1].runs = [.init(chain: 0, full: (100, 50), overview: (100, 50))]
        net.lines = [line]
        let t = try net.topology()
        #expect(t.strokeRefs(of: t.span("a", 0, 2), detail: .full).count == 2)
    }

    // MARK: Interval codes

    static func intervalNetwork() -> TestNetwork {
        var net = TestNetwork()
        net.lines = [
            .chain("x", ["X0", "X1", "X2", "X3"], lengths: [100, 100, 100]),
            .chain("y", ["Y0", "Y1", "Y2"], lengths: [100, 100]),
            // Two stations joined twice, as a two-stop loop: the codes carry ~1 and ~2.
            .chain("dup", ["D0", "D1"], lengths: [100, 100], loop: true),
            // The same station code as X3, unlinked.
            .chain("z", ["X3", "Z1"], lengths: [100]),
        ]
        net.links = [.init(a: (0, 2), b: (1, 0))]
        return net
    }

    @Test("interval codes resolve to spans in travel order, merged along a line and split at a link")
    func intervalCodesResolve() throws {
        let t = try Self.intervalNetwork().topology()
        let spans = t.spans(forIntervalCodes: ["x@X0:X1", "x@X1:X2", "y@Y0:Y1"])
        #expect(spans == [t.span("x", 0, 2), t.span("y", 0, 1)])
        // The same chain walked the other way round (codes list the trip in travel order).
        #expect(t.spans(forIntervalCodes: ["y@Y0:Y1", "x@X1:X2", "x@X0:X1"]) == [t.span("y", 1, 0), t.span("x", 2, 0)])
        #expect(t.spans(forIntervalCodes: []) == [])
    }

    @Test("a lone interval needs the departure to know its direction")
    func loneIntervalNeedsDeparture() throws {
        let t = try Self.intervalNetwork().topology()
        #expect(t.spans(forIntervalCodes: ["x@X0:X1"]) == nil)
        #expect(t.spans(forIntervalCodes: ["x@X0:X1"], departingFrom: [t.ref("x", 0)]) == [t.span("x", 0, 1)])
        #expect(t.spans(forIntervalCodes: ["x@X0:X1"], departingFrom: [t.ref("x", 1)]) == [t.span("x", 1, 0)])
        // A departure that is neither end leaves it open.
        #expect(t.spans(forIntervalCodes: ["x@X0:X1"], departingFrom: [t.ref("x", 3)]) == nil)
    }

    @Test("codes that do not resolve, do not join, or are ambiguous give nil")
    func intervalCodeRejections() throws {
        let t = try Self.intervalNetwork().topology()
        #expect(t.spans(forIntervalCodes: ["x@X0:X9"]) == nil)
        #expect(t.spans(forIntervalCodes: ["nope@X0:X1"]) == nil)
        #expect(t.spans(forIntervalCodes: ["x@X0:X2"]) == nil)       // not adjacent
        #expect(t.spans(forIntervalCodes: ["malformed"]) == nil)
        #expect(t.spans(forIntervalCodes: ["x@X0:X1~0"]) == nil)
        // X0:X1 then X2:X3 never meet.
        #expect(t.spans(forIntervalCodes: ["x@X0:X1", "x@X2:X3"]) == nil)
        // Without a link the code on `z` shares a station code with `x`, which is enough for an authored join.
        #expect(t.spans(forIntervalCodes: ["x@X2:X3", "z@X3:Z1"]) == [t.span("x", 2, 3), t.span("z", 0, 1)])
        // Duplicated pair without a ~n is ambiguous; ~n picks the n-th in line order.
        #expect(t.spans(forIntervalCodes: ["dup@D0:D1"], departingFrom: [t.ref("dup", 0)]) == nil)
        #expect(t.spans(forIntervalCodes: ["dup@D0:D1~1"], departingFrom: [t.ref("dup", 0)]) == [t.span("dup", 0, 1)])
        #expect(t.spans(forIntervalCodes: ["dup@D0:D1~2"], departingFrom: [t.ref("dup", 1)])
                == [t.span("dup", 1, 0, wraps: true)])
        #expect(t.spans(forIntervalCodes: ["dup@D0:D1~3"], departingFrom: [t.ref("dup", 1)]) == nil)
    }

    @Test("a full circuit of a loop stays several spans, never from equal to to")
    func loopCircuitSplits() throws {
        var net = TestNetwork()
        net.lines = [.chain("l", ["L0", "L1", "L2"], lengths: [100, 100, 100], loop: true)]
        let t = try net.topology()
        let spans = try #require(t.spans(forIntervalCodes: ["l@L0:L1", "l@L1:L2", "l@L0:L2"]))
        #expect(spans.allSatisfy { $0.fromNode != $0.toNode })
        #expect(spans == [t.span("l", 0, 2), t.span("l", 2, 0, wraps: true)])
        #expect(spans.reduce(0) { $0 + t.lengthCm(of: $1) } == 300)
    }
}
