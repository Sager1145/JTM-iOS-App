import Foundation

// MARK: - RailTopology: the reader
//
// An immutable, `Sendable` view over a topology file (`RailTopologyFormat`).
// Opening validates the header, every table directory entry and the
// cross-references between tables once (O(records), no allocation per
// record); afterwards every query reads fixed-width records in place from the
// mapped bytes. The only derived structure is a sorted index of the link
// table (a few hundred to a few thousand rows) that the router needs to find a
// node's links.
//
// Nothing in this file is wired into the app yet.

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
    ///
    /// `lengthCm` is the distance the spans count: cumulative-length
    /// differences minus withheld edges (see ``RailTopology/lengthCm(of:)``).
    /// An `unproven` path carries its length too; consumers exclude it from
    /// distance by the flag.
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

    /// One row of the link index: `link` joins `node` to `other`.
    struct LinkEntry: Sendable {
        var node: UInt32
        var other: UInt32
        var link: UInt32
    }
    /// Link rows sorted by `node` then `link`; a directed link has one entry (A to B), an undirected one two.
    let linkEntries: [LinkEntry]

    /// Opens a file from bytes. Throws a ``RailTopologyFormat/FormatError``
    /// for a truncated, corrupt or wrong-version file. When
    /// `displayBlobSHA256` is given (the 32 bytes of the display blob this
    /// file must belong to) a different value in the header throws
    /// ``RailTopologyFormat/FormatError/displayBlobMismatch``. Production
    /// callers always pass it.
    public init(data: Data, displayBlobSHA256: [UInt8]? = nil) throws {
        let header = try RailTopologyFormat.parseHeader(data)
        if let displayBlobSHA256, displayBlobSHA256 != header.displaySHA256 {
            throw RailTopologyFormat.FormatError.displayBlobMismatch
        }
        self.header = header
        self.data = data
        self.linkEntries = try data.withUnsafeBytes { raw in
            let view = TopologyView(base: raw, header: header)
            try view.validate()
            return view.linkIndex()
        }
    }

    /// Opens `url` memory-mapped: no copy, no decode.
    public init(contentsOf url: URL, displayBlobSHA256: [UInt8]? = nil) throws {
        try self.init(data: Data(contentsOf: url, options: .alwaysMapped), displayBlobSHA256: displayBlobSHA256)
    }

    @inline(__always)
    func withView<R>(_ body: (TopologyView) throws -> R) rethrows -> R {
        try data.withUnsafeBytes { try body(TopologyView(base: $0, header: header)) }
    }

    // MARK: Lines and nodes

    public var lineCount: Int { header.count(.lines) }
    public var nodeTotal: Int { header.count(.nodes) }
    public var edgeTotal: Int { header.count(.edges) }
    public var linkCount: Int { header.count(.links) }

    /// The line index of a line id (for example `jp.jr-east.yamanote`), nil when absent.
    public func lineIndex(forID id: String) -> UInt16? {
        withView { v in
            let key = Array(id.utf8)
            return key.withUnsafeBytes { k in
                for line in 0..<v.lineCount where v.stringEquals(v.u32(v.lineBase(line) + RailTopologyFormat.Line.id), k) {
                    return UInt16(line)
                }
                return nil
            }
        }
    }

    public func lineID(_ line: UInt16) -> String? {
        guard Int(line) < lineCount else { return nil }
        return withView { v in v.string(v.u32(v.lineBase(Int(line)) + RailTopologyFormat.Line.id)) }
    }

    public func lineName(_ line: UInt16) -> String? {
        guard Int(line) < lineCount else { return nil }
        return withView { v in v.string(v.u32(v.lineBase(Int(line)) + RailTopologyFormat.Line.name)) }
    }

    public func lineFlags(_ line: UInt16) -> RailTopologyFormat.LineFlag {
        guard Int(line) < lineCount else { return [] }
        return withView { v in .init(rawValue: v.u16(v.lineBase(Int(line)) + RailTopologyFormat.Line.flags)) }
    }

    public func institution(ofLine line: UInt16) -> UInt16? {
        guard Int(line) < lineCount else { return nil }
        return withView { v in v.u16(v.lineBase(Int(line)) + RailTopologyFormat.Line.institution) }
    }

    public func nodeCount(ofLine line: UInt16) -> Int {
        guard Int(line) < lineCount else { return 0 }
        return withView { v in Int(v.u32(v.lineBase(Int(line)) + RailTopologyFormat.Line.nodeCount)) }
    }

    /// The station code of a node; nil for a junction point or an unknown node.
    public func stationCode(of node: NodeRef) -> String? {
        withView { v in
            guard let g = v.global(node) else { return nil }
            return v.string(v.u32(v.nodeBase(g) + RailTopologyFormat.Node.stationCode))
        }
    }

    // MARK: Stop lookup

    /// Nodes for a platform code, registry station id or group code, in
    /// ascending global node index. Empty when unknown. Binary search over the
    /// sorted stop table; nothing is decoded.
    public func nodes(forStop key: String) -> [NodeRef] {
        withView { v in
            Array(key.utf8).withUnsafeBytes { k in
                v.stopGlobalNodes(forKey: k).compactMap { v.nodeRef(global: $0) }
            }
        }
    }

    // MARK: Interval codes

    /// Spans for authored interval codes (`lineID@stA:stB` or `lineID@stA:stB~n`,
    /// the two station codes sorted, `n` the 1-based occurrence among the
    /// line's intervals with those two stations), in travel order; nil when
    /// any code does not resolve, is ambiguous, or consecutive codes do not
    /// join.
    ///
    /// A code carries no direction, so each interval's direction is solved
    /// from its neighbours: consecutive intervals join when they meet at the
    /// same node, at a node pair held by any link (validity ignored: an
    /// authored choice is never rerouted), or at the same station code. The
    /// solution must be unique. A lone interval, or any chain whose
    /// directions stay open, needs `departingFrom` (the nodes the ride starts
    /// at) to settle the first interval; without one it is nil. Edge
    /// direction flags and validity dates are not consulted: authored codes
    /// are not second-guessed here.
    public func spans(forIntervalCodes codes: [String], departingFrom start: [NodeRef] = []) -> [Span]? {
        guard !codes.isEmpty else { return [] }
        return withView { v in v.spans(forIntervalCodes: codes, departingFrom: start, linkEntries: linkEntries) }
    }

    // MARK: Lengths and geometry

    /// Surveyed length of a span in centimetres: a cumulative-length
    /// subtraction (the complement of the closing edge's side for a wrapping
    /// span) minus the length of each withheld edge inside the span. Zero for
    /// a span that does not lie on its line.
    public func lengthCm(of span: Span) -> UInt64 {
        withView { v in v.lengthCm(of: span) }
    }

    /// Whether the span contains a withheld (not proven) edge.
    public func containsWithheldEdge(_ span: Span) -> Bool {
        withView { v in v.containsWithheldEdge(span) }
    }

    /// The span as `StrokeRef`s on the given detail's ruler: one per
    /// contiguous piece (a new piece starts wherever the chain or part
    /// changes), in travel order, `from > to` when against the chain's own
    /// direction. Empty when a node has no chain slot, a ruler is unset, or
    /// the span does not lie on its line.
    ///
    /// The chain id is `"{region}|{lineID}#{chain}"`. For a non-continuous
    /// line the number is the flat part number; the display chunk's lane
    /// naming (`lineKey@lane#part`) is not in this file, so the map layer
    /// translates it.
    public func strokeRefs(of span: Span, detail: Detail) -> [StrokeRef] {
        withView { v in v.strokeRefs(of: span, detail: detail) }
    }
}

// MARK: - In-place record access

/// Unchecked little-endian reads over the mapped bytes. Every offset a
/// method computes was validated by ``validate()`` at open; methods that take
/// caller input (`global(_:)`, spans) bounds-check it themselves.
struct TopologyView {
    typealias F = RailTopologyFormat

    let base: UnsafeRawBufferPointer
    let lines: Int, nodes: Int, edges: Int, runs: Int, links: Int
    let identities: Int, stops: Int, stopNodes: Int, strings: Int
    let lineCount: Int, nodeTotal: Int, edgeTotal: Int, runTotal: Int, linkTotal: Int
    let identityTotal: Int, stopTotal: Int, stopNodeTotal: Int, stringBytes: Int
    let region: String

    init(base: UnsafeRawBufferPointer, header h: F.ParsedHeader) {
        self.base = base
        lines = h.offset(.lines); nodes = h.offset(.nodes); edges = h.offset(.edges); runs = h.offset(.runs)
        links = h.offset(.links); identities = h.offset(.identities); stops = h.offset(.stops)
        stopNodes = h.offset(.stopNodes); strings = h.offset(.strings)
        lineCount = h.count(.lines); nodeTotal = h.count(.nodes); edgeTotal = h.count(.edges)
        runTotal = h.count(.runs); linkTotal = h.count(.links); identityTotal = h.count(.identities)
        stopTotal = h.count(.stops); stopNodeTotal = h.count(.stopNodes); stringBytes = h.count(.strings)
        region = h.region
    }

    @inline(__always) func u16(_ o: Int) -> UInt16 { UInt16(littleEndian: base.loadUnaligned(fromByteOffset: o, as: UInt16.self)) }
    @inline(__always) func u32(_ o: Int) -> UInt32 { UInt32(littleEndian: base.loadUnaligned(fromByteOffset: o, as: UInt32.self)) }

    @inline(__always) func lineBase(_ i: Int) -> Int { lines + i * F.Line.size }
    @inline(__always) func nodeBase(_ g: Int) -> Int { nodes + g * F.Node.size }
    @inline(__always) func edgeBase(_ g: Int) -> Int { edges + g * F.Edge.size }
    @inline(__always) func runBase(_ i: Int) -> Int { runs + i * F.Run.size }
    @inline(__always) func linkBase(_ i: Int) -> Int { links + i * F.Link.size }
    @inline(__always) func stopBase(_ i: Int) -> Int { stops + i * F.Stop.size }

    @inline(__always) func lineFirstNode(_ line: Int) -> Int { Int(u32(lineBase(line) + F.Line.firstNode)) }
    @inline(__always) func lineNodeCount(_ line: Int) -> Int { Int(u32(lineBase(line) + F.Line.nodeCount)) }
    @inline(__always) func lineFirstEdge(_ line: Int) -> Int { Int(u32(lineBase(line) + F.Line.firstEdge)) }
    @inline(__always) func lineEdgeCount(_ line: Int) -> Int { Int(u32(lineBase(line) + F.Line.edgeCount)) }
    @inline(__always) func lineIsLoop(_ line: Int) -> Bool {
        F.LineFlag(rawValue: u16(lineBase(line) + F.Line.flags)).contains(.loop)
    }

    /// Global node index of a ref; nil when out of range.
    func global(_ ref: RailTopology.NodeRef) -> Int? {
        let line = Int(ref.line)
        guard line < lineCount, Int(ref.node) < lineNodeCount(line) else { return nil }
        return lineFirstNode(line) + Int(ref.node)
    }

    func nodeRef(global g: Int) -> RailTopology.NodeRef? {
        guard g >= 0, g < nodeTotal else { return nil }
        let line = Int(u16(nodeBase(g) + F.Node.line))
        return .init(line: UInt16(line), node: UInt16(g - lineFirstNode(line)))
    }

    // MARK: Strings

    /// The UTF-8 bytes of a string-table entry; nil for `noString` or a bad reference.
    func stringBytes(_ ref: UInt32) -> UnsafeRawBufferPointer? {
        guard ref != F.noString else { return nil }
        let at = Int(ref)
        guard at + 2 <= stringBytes else { return nil }
        let length = Int(u16(strings + at))
        guard at + 2 + length <= stringBytes else { return nil }
        return UnsafeRawBufferPointer(rebasing: base[(strings + at + 2)..<(strings + at + 2 + length)])
    }

    func string(_ ref: UInt32) -> String? {
        stringBytes(ref).map { String(decoding: $0, as: UTF8.self) }
    }

    func stringEquals(_ ref: UInt32, _ key: UnsafeRawBufferPointer) -> Bool {
        guard let bytes = stringBytes(ref), bytes.count == key.count else { return false }
        return key.count == 0 || memcmp(bytes.baseAddress!, key.baseAddress!, key.count) == 0
    }

    static func compare(_ a: UnsafeRawBufferPointer, _ b: UnsafeRawBufferPointer) -> Int {
        let common = min(a.count, b.count)
        if common > 0 {
            let c = memcmp(a.baseAddress!, b.baseAddress!, common)
            if c != 0 { return c < 0 ? -1 : 1 }
        }
        return a.count == b.count ? 0 : (a.count < b.count ? -1 : 1)
    }

    // MARK: Validation

    /// Cross-table checks run once at open. Failures reuse `badTable` of the
    /// table whose record is inconsistent.
    func validate() throws {
        func fail(_ table: F.Table) -> Error { F.FormatError.badTable(table) }
        func stringOK(_ ref: UInt32) -> Bool { ref == F.noString || stringBytes(ref) != nil }

        for line in 0..<lineCount {
            let b = lineBase(line)
            let firstNode = Int(u32(b + F.Line.firstNode)), nodeCount = Int(u32(b + F.Line.nodeCount))
            let firstEdge = Int(u32(b + F.Line.firstEdge)), edgeCount = Int(u32(b + F.Line.edgeCount))
            let flags = F.LineFlag(rawValue: u16(b + F.Line.flags))
            let firstIdentity = Int(u32(b + F.Line.firstIdentity)), identityCount = Int(u16(b + F.Line.identityCount))
            guard nodeCount <= F.maxNodesPerLine, firstNode + nodeCount <= nodeTotal,
                  firstEdge + edgeCount <= edgeTotal, firstIdentity + identityCount <= identityTotal,
                  edgeCount == (nodeCount == 0 ? 0 : (flags.contains(.loop) ? nodeCount : nodeCount - 1)),
                  !(flags.contains(.loop) && nodeCount < 2),
                  stringBytes(u32(b + F.Line.id)) != nil, stringOK(u32(b + F.Line.family)),
                  stringOK(u32(b + F.Line.name)), stringOK(u32(b + F.Line.aliases))
            else { throw fail(.lines) }
            let chainCount = Int(u16(b + F.Line.chainCount))
            for n in firstNode..<(firstNode + nodeCount) {
                let nb = nodeBase(n)
                guard Int(u16(nb + F.Node.line)) == line, Int(u16(nb + F.Node.chain)) < max(chainCount, 1),
                      stringOK(u32(nb + F.Node.stationCode)) else { throw fail(.nodes) }
            }
            for e in firstEdge..<(firstEdge + edgeCount) {
                let eb = edgeBase(e)
                let flagBits = F.EdgeFlag(rawValue: u16(eb + F.Edge.flags))
                let runCount = Int(u16(eb + F.Edge.runCount)), firstRun = Int(u32(eb + F.Edge.firstRun))
                guard !flagBits.contains(.hasRuns) || (runCount > 0 && firstRun + runCount <= runTotal)
                else { throw fail(.edges) }
            }
        }
        for link in 0..<linkTotal {
            let b = linkBase(link)
            guard Int(u32(b + F.Link.nodeA)) < nodeTotal, Int(u32(b + F.Link.nodeB)) < nodeTotal,
                  stringBytes(u32(b + F.Link.registryID)) != nil else { throw fail(.links) }
        }
        for identity in 0..<identityTotal {
            let b = identities + identity * F.Identity.size
            guard Int(u32(b + F.Identity.line)) < lineCount, stringOK(u32(b + F.Identity.name)),
                  stringOK(u32(b + F.Identity.family)) else { throw fail(.identities) }
        }
        var previous: (UnsafeRawBufferPointer, UInt8)?
        for stop in 0..<stopTotal {
            let b = stopBase(stop)
            guard let key = stringBytes(u32(b + F.Stop.key)), key.count == Int(u16(b + F.Stop.keyLength)),
                  Int(u32(b + F.Stop.firstNode)) + Int(u32(b + F.Stop.nodeCount)) <= stopNodeTotal
            else { throw fail(.stops) }
            let kind = base[b + F.Stop.kind]
            if let (pk, pkind) = previous {
                let c = Self.compare(pk, key)
                guard c < 0 || (c == 0 && pkind < kind) else { throw fail(.stops) }
            }
            previous = (key, kind)
        }
        for i in 0..<stopNodeTotal where Int(u32(stopNodes + i * 4)) >= nodeTotal { throw fail(.stopNodes) }
    }

    // MARK: Link index

    func linkIndex() -> [RailTopology.LinkEntry] {
        var entries: [RailTopology.LinkEntry] = []
        entries.reserveCapacity(linkTotal * 2)
        for link in 0..<linkTotal {
            let b = linkBase(link)
            let a = u32(b + F.Link.nodeA), c = u32(b + F.Link.nodeB)
            let directed = base[b + F.Link.flags] & 1 != 0
            // Nodes of one line are never joined by a link (they need none).
            guard Int(u16(nodeBase(Int(a)) + F.Node.line)) != Int(u16(nodeBase(Int(c)) + F.Node.line)) else { continue }
            entries.append(.init(node: a, other: c, link: UInt32(link)))
            if !directed { entries.append(.init(node: c, other: a, link: UInt32(link))) }
        }
        entries.sort { ($0.node, $0.link) < ($1.node, $1.link) }
        return entries
    }

    // MARK: Stops

    /// Global node indices for a key across all stop kinds, ascending and unique.
    func stopGlobalNodes(forKey key: UnsafeRawBufferPointer) -> [Int] {
        var lo = 0, hi = stopTotal
        while lo < hi {
            let mid = (lo + hi) / 2
            let k = stringBytes(u32(stopBase(mid) + F.Stop.key)) ?? UnsafeRawBufferPointer(start: nil, count: 0)
            if Self.compare(k, key) < 0 { lo = mid + 1 } else { hi = mid }
        }
        var result: [Int] = []
        var i = lo
        while i < stopTotal, let k = stringBytes(u32(stopBase(i) + F.Stop.key)), Self.compare(k, key) == 0 {
            let first = Int(u32(stopBase(i) + F.Stop.firstNode)), count = Int(u32(stopBase(i) + F.Stop.nodeCount))
            for j in first..<(first + count) { result.append(Int(u32(stopNodes + j * 4))) }
            i += 1
        }
        return Array(Set(result)).sorted()
    }

    // MARK: Edges, lengths

    /// Global edge index for a line-local edge ordinal.
    @inline(__always) func edgeGlobal(line: Int, ordinal: Int) -> Int { lineFirstEdge(line) + ordinal }

    /// Cumulative length at node `ordinal` of a line (length of every edge before it).
    func cumulative(line: Int, node ordinal: Int) -> UInt64 {
        let edgeCount = lineEdgeCount(line)
        if ordinal < edgeCount { return UInt64(u32(edgeBase(edgeGlobal(line: line, ordinal: ordinal)) + F.Edge.cumulativeCm)) }
        let last = edgeBase(edgeGlobal(line: line, ordinal: edgeCount - 1))
        return UInt64(u32(last + F.Edge.cumulativeCm)) + UInt64(u32(last + F.Edge.lengthCm))
    }

    /// Edge ordinals a span covers, as up to two half-open ranges, or nil
    /// when the span does not lie on its line.
    func edgeRanges(of span: RailTopology.Span) -> [Range<Int>]? {
        let line = Int(span.line)
        guard line < lineCount else { return nil }
        let n = lineNodeCount(line), a = Int(span.fromNode), b = Int(span.toNode)
        guard a < n, b < n, a != b else { return nil }
        let lo = min(a, b), hi = max(a, b)
        if !span.wraps { return [lo..<hi] }
        guard lineIsLoop(line) else { return nil }
        return [hi..<n, 0..<lo].filter { !$0.isEmpty }
    }

    func lengthCm(of span: RailTopology.Span) -> UInt64 {
        guard let ranges = edgeRanges(of: span) else { return 0 }
        let line = Int(span.line)
        var total: UInt64 = 0
        for range in ranges {
            total += cumulative(line: line, node: range.upperBound) - cumulative(line: line, node: range.lowerBound)
            for k in range {
                let eb = edgeBase(edgeGlobal(line: line, ordinal: k))
                if F.EdgeFlag(rawValue: u16(eb + F.Edge.flags)).contains(.withheld) { total -= UInt64(u32(eb + F.Edge.lengthCm)) }
            }
        }
        return total
    }

    func containsWithheldEdge(_ span: RailTopology.Span) -> Bool {
        guard let ranges = edgeRanges(of: span) else { return false }
        let line = Int(span.line)
        for range in ranges {
            for k in range where F.EdgeFlag(rawValue: u16(edgeBase(edgeGlobal(line: line, ordinal: k)) + F.Edge.flags)).contains(.withheld) {
                return true
            }
        }
        return false
    }

    // MARK: Stroke refs

    func strokeRefs(of span: RailTopology.Span, detail: RailTopology.Detail) -> [StrokeRef] {
        guard edgeRanges(of: span) != nil else { return [] }
        let line = Int(span.line)
        let n = lineNodeCount(line), loop = lineIsLoop(line)
        let a = Int(span.fromNode), b = Int(span.toNode)
        let up = (a < b) != span.wraps
        let steps = loop ? (up ? (b - a + n) % n : (a - b + n) % n) : abs(b - a)
        let lineID = string(u32(lineBase(line) + F.Line.id)) ?? ""
        let firstNode = lineFirstNode(line)
        let unset = F.unsetMetres
        func metres(_ cm: UInt32) -> Double { Double(cm) / 100 }

        struct Piece { var chain: UInt16; var from: UInt32; var to: UInt32 }
        var pieces: [Piece] = []
        var ordinal = a
        for _ in 0..<steps {
            let next = up ? (ordinal + 1) % n : (ordinal - 1 + n) % n
            let k = up ? ordinal : next
            let eb = edgeBase(edgeGlobal(line: line, ordinal: k))
            if F.EdgeFlag(rawValue: u16(eb + F.Edge.flags)).contains(.hasRuns) {
                let first = Int(u32(eb + F.Edge.firstRun)), count = Int(u16(eb + F.Edge.runCount))
                let indices = up ? Array(first..<(first + count)) : Array((first..<(first + count)).reversed())
                for r in indices {
                    let rb = runBase(r)
                    var from = u32(rb + (detail == .full ? F.Run.fullFromCm : F.Run.overviewFromCm))
                    var to = u32(rb + (detail == .full ? F.Run.fullToCm : F.Run.overviewToCm))
                    if !up { swap(&from, &to) }
                    guard from != unset, to != unset else { return [] }
                    pieces.append(Piece(chain: u16(rb + F.Run.chain), from: from, to: to))
                }
            } else {
                let start = nodeBase(firstNode + ordinal), end = nodeBase(firstNode + next)
                let chain = u16(start + F.Node.chain)
                guard chain == u16(end + F.Node.chain) else { return [] }
                let field = detail == .full ? F.Node.fullMetres : F.Node.overviewMetres
                let from = u32(start + field), to = u32(end + field)
                guard from != unset, to != unset else { return [] }
                pieces.append(Piece(chain: chain, from: from, to: to))
            }
            ordinal = next
        }

        var merged: [Piece] = []
        for piece in pieces {
            if var last = merged.last, last.chain == piece.chain, last.to == piece.from,
               (last.to >= last.from) == (piece.to >= piece.from) {
                last.to = piece.to
                merged[merged.count - 1] = last
            } else {
                merged.append(piece)
            }
        }
        return merged.map {
            StrokeRef(chainID: "\(region)|\(lineID)#\($0.chain)", from: metres($0.from), to: metres($0.to))
        }
    }

    // MARK: Interval codes

    private struct Interval {
        var line: Int
        var edge: Int
        /// Global node indices of the edge's first and second node.
        var first: Int
        var second: Int
        var nodeCount: Int
        var loop: Bool
    }

    func spans(forIntervalCodes codes: [String], departingFrom start: [RailTopology.NodeRef],
               linkEntries: [RailTopology.LinkEntry]) -> [RailTopology.Span]? {
        var lineIndexByID: [String: Int] = [:]
        var intervals: [Interval] = []
        for code in codes {
            guard let at = code.lastIndex(of: "@"), at != code.startIndex else { return nil }
            let lineID = String(code[..<at])
            var body = code[code.index(after: at)...]
            var occurrence: Int?
            if let tilde = body.lastIndex(of: "~") {
                guard let n = Int(body[body.index(after: tilde)...]), n >= 1 else { return nil }
                occurrence = n
                body = body[..<tilde]
            }
            let pair = body.split(separator: ":", omittingEmptySubsequences: false)
            guard pair.count == 2, !pair[0].isEmpty, !pair[1].isEmpty else { return nil }
            let line: Int
            if let known = lineIndexByID[lineID] { line = known } else {
                let found = Array(lineID.utf8).withUnsafeBytes { key -> Int? in
                    for l in 0..<lineCount where stringEquals(u32(lineBase(l) + F.Line.id), key) { return l }
                    return nil
                }
                guard let found else { return nil }
                lineIndexByID[lineID] = found
                line = found
            }
            guard let interval = findInterval(line: line, a: String(pair[0]), b: String(pair[1]), occurrence: occurrence)
            else { return nil }
            intervals.append(interval)
        }
        guard let orientations = solveOrientations(intervals, start: start, linkEntries: linkEntries) else { return nil }

        var spans: [RailTopology.Span] = []
        var run: (line: Int, up: Bool, from: Int, to: Int, wraps: Bool, edges: Int, n: Int)?
        func flush() {
            if let r = run {
                spans.append(.init(line: UInt16(r.line), fromNode: UInt16(r.from), toNode: UInt16(r.to), wraps: r.wraps))
            }
            run = nil
        }
        for (interval, forward) in zip(intervals, orientations) {
            let firstOrd = interval.first - lineFirstNode(interval.line)
            let secondOrd = interval.second - lineFirstNode(interval.line)
            let startOrd = forward ? firstOrd : secondOrd, endOrd = forward ? secondOrd : firstOrd
            // Going upward over the closing edge of a loop is the edge whose ordinal is nodeCount - 1.
            let crosses = interval.loop && interval.edge == interval.nodeCount - 1
            if var r = run, r.line == interval.line, r.up == forward, r.to == startOrd, r.edges + 1 < r.n {
                r.to = endOrd; r.wraps = r.wraps || crosses; r.edges += 1
                run = r
            } else {
                flush()
                run = (interval.line, forward, startOrd, endOrd, crosses, 1, interval.nodeCount)
            }
        }
        flush()
        return spans
    }

    private func findInterval(line: Int, a: String, b: String, occurrence: Int?) -> Interval? {
        let n = lineNodeCount(line), loop = lineIsLoop(line), first = lineFirstNode(line)
        let aBytes = Array(a.utf8), bBytes = Array(b.utf8)
        var matches: [Int] = []
        func codeIs(_ g: Int, _ key: [UInt8]) -> Bool {
            key.withUnsafeBytes { stringEquals(u32(nodeBase(g) + F.Node.stationCode), $0) }
        }
        // Candidate edges come from the stop index: edges touching a node of `a` on this line.
        let candidates = aBytes.withUnsafeBytes { stopGlobalNodes(forKey: $0) }.filter {
            Int(u16(nodeBase($0) + F.Node.line)) == line
        }
        var found = Set<Int>()
        for g in candidates {
            let o = g - first
            let edgeOrdinals = [o, (o - 1 + n) % n].filter { $0 < lineEdgeCount(line) }
            for k in edgeOrdinals {
                let (x, y) = (first + k, first + (k + 1) % n)
                guard (codeIs(x, aBytes) && codeIs(y, bBytes)) || (codeIs(x, bBytes) && codeIs(y, aBytes)) else { continue }
                found.insert(k)
            }
        }
        matches = found.sorted()
        let pick: Int
        if let occurrence {
            guard occurrence <= matches.count else { return nil }
            pick = matches[occurrence - 1]
        } else {
            guard matches.count == 1 else { return nil }
            pick = matches[0]
        }
        return Interval(line: line, edge: pick, first: first + pick, second: first + (pick + 1) % n, nodeCount: n, loop: loop)
    }

    /// For each interval, whether it is travelled first node to second.
    /// Nil unless the assignment that joins every neighbour (and prefers the
    /// given start) is unique.
    private func solveOrientations(_ intervals: [Interval], start: [RailTopology.NodeRef],
                                   linkEntries: [RailTopology.LinkEntry]) -> [Bool]? {
        let m = intervals.count
        guard m > 0 else { return [] }
        let startGlobals = Set(start.compactMap { global($0) })
        func ends(_ i: Interval, _ o: Int) -> (start: Int, end: Int) {
            o == 0 ? (i.first, i.second) : (i.second, i.first)
        }
        func sameCode(_ a: Int, _ b: Int) -> Bool {
            guard let bytes = stringBytes(u32(nodeBase(a) + F.Node.stationCode)) else { return false }
            return stringEquals(u32(nodeBase(b) + F.Node.stationCode), bytes)
        }
        func linked(_ a: Int, _ b: Int) -> Bool {
            var lo = 0, hi = linkEntries.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if linkEntries[mid].node < UInt32(a) { lo = mid + 1 } else { hi = mid }
            }
            while lo < linkEntries.count, linkEntries[lo].node == UInt32(a) {
                if linkEntries[lo].other == UInt32(b) { return true }
                lo += 1
            }
            return false
        }
        /// 0: the two do not join.
        func join(_ end: Int, _ next: Int) -> Int {
            if end == next { return 3 }
            if linked(end, next) { return 2 }
            return sameCode(end, next) ? 1 : 0
        }

        // score[i][o]: best total joining intervals 0...i with interval i in orientation o (-1 unreachable);
        // ways[i][o]: how many assignments reach that score.
        var score = [[Int]](repeating: [-1, -1], count: m), ways = [[Int]](repeating: [0, 0], count: m)
        for o in 0..<2 {
            score[0][o] = startGlobals.contains(ends(intervals[0], o).start) ? 1 : 0
            ways[0][o] = 1
        }
        for i in 1..<max(m, 1) {
            for o in 0..<2 {
                for p in 0..<2 where score[i - 1][p] >= 0 {
                    let w = join(ends(intervals[i - 1], p).end, ends(intervals[i], o).start)
                    guard w > 0 else { continue }
                    let s = score[i - 1][p] + w
                    if s > score[i][o] { score[i][o] = s; ways[i][o] = ways[i - 1][p] }
                    else if s == score[i][o] { ways[i][o] += ways[i - 1][p] }
                }
            }
        }
        let top = score[m - 1].max() ?? -1
        guard top >= 0 else { return nil }
        let winners = (0..<2).filter { score[m - 1][$0] == top }
        guard winners.count == 1, ways[m - 1][winners[0]] == 1 else { return nil }

        var forward = [Bool](repeating: true, count: m)
        var o = winners[0]
        forward[m - 1] = o == 0
        var i = m - 1
        while i > 0 {
            for p in 0..<2 where score[i - 1][p] >= 0 {
                let w = join(ends(intervals[i - 1], p).end, ends(intervals[i], o).start)
                if w > 0, score[i - 1][p] + w == score[i][o] { o = p; break }
            }
            forward[i - 1] = o == 0
            i -= 1
        }
        return forward
    }
}
