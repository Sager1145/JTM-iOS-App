import Foundation
@testable import RailCore

/// Builds topology files for tests from a readable description. It writes the
/// layout through `RailTopologyFormat`'s constants, so a layout change breaks
/// `RailTopologyFormatTests` first (the hand-built fixture) and these next.
struct TestNetwork {
    typealias F = RailTopologyFormat

    struct Run { var chain: UInt16; var full: (UInt32, UInt32); var overview: (UInt32, UInt32) }

    struct Edge {
        var length: UInt32
        var flags: F.EdgeFlag = [.forward, .reverse]
        var validFrom: UInt32 = 0
        var validTo: UInt32 = 0
        var runs: [Run] = []
    }

    struct Node {
        var code: String?
        var full: UInt32 = 0
        var overview: UInt32 = F.unsetMetres
        var chain: UInt16 = 0
        var flags: F.NodeFlag = []
    }

    struct Line {
        var id: String
        var institution: UInt16 = 1
        var flags: F.LineFlag = []
        var chainCount: UInt16 = 1
        var validFrom: UInt32 = 0
        var validTo: UInt32 = 0
        var nodes: [Node]
        var edges: [Edge]

        /// A plain chain: stations `codes` joined by edges of the given lengths
        /// (centimetres), positions on one chain equal to the cumulative length.
        static func chain(_ id: String, _ codes: [String], lengths: [UInt32], institution: UInt16 = 1,
                          loop: Bool = false, flags: F.EdgeFlag = [.forward, .reverse]) -> Line {
            var position: UInt32 = 0
            var nodes: [Node] = []
            for (i, code) in codes.enumerated() {
                nodes.append(Node(code: code, full: position, overview: position))
                if i < lengths.count { position += lengths[i] }
            }
            return Line(id: id, institution: institution, flags: loop ? [.loop] : [], nodes: nodes,
                        edges: lengths.map { Edge(length: $0, flags: flags) })
        }
    }

    struct Link {
        var a: (line: Int, node: Int)
        var b: (line: Int, node: Int)
        var kind: F.LinkKind = .physicalJunction
        var directed = false
        var validFrom: UInt32 = 0
        var validTo: UInt32 = 0
        var registry = "jct-test"
    }

    var region = "jp"
    var packageSHA: UInt8 = 0x11
    var displaySHA: UInt8 = 0x22
    var lines: [Line] = []
    var links: [Link] = []
    /// Extra stop keys beyond each node's own station code: key, kind, (line, node) pairs.
    var extraStops: [(key: String, kind: F.StopKind, nodes: [(line: Int, node: Int)])] = []

    func encode() -> Data {
        var strings: [UInt8] = [0, 0]  // offset 0 is the empty string
        var interned: [String: UInt32] = ["": 0]
        func s(_ text: String?) -> UInt32 {
            guard let text else { return F.noString }
            if let known = interned[text] { return known }
            let at = UInt32(strings.count)
            let utf8 = Array(text.utf8)
            strings += [UInt8(utf8.count & 0xFF), UInt8(utf8.count >> 8)] + utf8
            interned[text] = at
            return at
        }

        var firstNode: [Int] = [], firstEdge: [Int] = []
        var nodeTotal = 0, edgeTotal = 0
        for line in lines {
            firstNode.append(nodeTotal); firstEdge.append(edgeTotal)
            nodeTotal += line.nodes.count; edgeTotal += line.edges.count
        }
        let runTotal = lines.reduce(0) { $0 + $1.edges.reduce(0) { $0 + $1.runs.count } }

        var lineBytes = [UInt8](repeating: 0, count: lines.count * F.Line.size)
        var nodeBytes = [UInt8](repeating: 0, count: nodeTotal * F.Node.size)
        var edgeBytes = [UInt8](repeating: 0, count: edgeTotal * F.Edge.size)
        var runBytes = [UInt8](repeating: 0, count: runTotal * F.Run.size)
        func put16(_ a: inout [UInt8], _ at: Int, _ v: UInt16) { a[at] = UInt8(v & 0xFF); a[at + 1] = UInt8(v >> 8) }
        func put32(_ a: inout [UInt8], _ at: Int, _ v: UInt32) { put16(&a, at, UInt16(v & 0xFFFF)); put16(&a, at + 2, UInt16(v >> 16)) }

        var nextRun = 0
        var stopTable: [String: [F.StopKind: [Int]]] = [:]
        for (li, line) in lines.enumerated() {
            let lb = li * F.Line.size
            put32(&lineBytes, lb + F.Line.id, s(line.id)); put32(&lineBytes, lb + F.Line.family, s("fam/" + line.id))
            put32(&lineBytes, lb + F.Line.name, s(line.id)); put32(&lineBytes, lb + F.Line.aliases, 0)
            put16(&lineBytes, lb + F.Line.institution, line.institution)
            put16(&lineBytes, lb + F.Line.flags, line.flags.rawValue)
            put16(&lineBytes, lb + F.Line.chainCount, line.chainCount)
            put32(&lineBytes, lb + F.Line.validFrom, line.validFrom); put32(&lineBytes, lb + F.Line.validTo, line.validTo)
            put32(&lineBytes, lb + F.Line.firstNode, UInt32(firstNode[li])); put32(&lineBytes, lb + F.Line.nodeCount, UInt32(line.nodes.count))
            put32(&lineBytes, lb + F.Line.firstEdge, UInt32(firstEdge[li])); put32(&lineBytes, lb + F.Line.edgeCount, UInt32(line.edges.count))
            for (ni, node) in line.nodes.enumerated() {
                let nb = (firstNode[li] + ni) * F.Node.size
                put32(&nodeBytes, nb + F.Node.stationCode, s(node.code))
                put32(&nodeBytes, nb + F.Node.fullMetres, node.full); put32(&nodeBytes, nb + F.Node.overviewMetres, node.overview)
                put16(&nodeBytes, nb + F.Node.line, UInt16(li)); put16(&nodeBytes, nb + F.Node.chain, node.chain)
                put16(&nodeBytes, nb + F.Node.flags, node.flags.rawValue)
                if let code = node.code { stopTable[code, default: [:]][.platformCode, default: []].append(firstNode[li] + ni) }
            }
            var cumulative: UInt32 = 0
            for (ei, edge) in line.edges.enumerated() {
                let eb = (firstEdge[li] + ei) * F.Edge.size
                var flags = edge.flags
                if !edge.runs.isEmpty { flags.insert(.hasRuns) }
                put32(&edgeBytes, eb + F.Edge.lengthCm, edge.length); put32(&edgeBytes, eb + F.Edge.cumulativeCm, cumulative)
                put32(&edgeBytes, eb + F.Edge.validFrom, edge.validFrom); put32(&edgeBytes, eb + F.Edge.validTo, edge.validTo)
                put16(&edgeBytes, eb + F.Edge.flags, flags.rawValue); put16(&edgeBytes, eb + F.Edge.runCount, UInt16(edge.runs.count))
                put32(&edgeBytes, eb + F.Edge.firstRun, UInt32(nextRun))
                for run in edge.runs {
                    let rb = nextRun * F.Run.size
                    put16(&runBytes, rb + F.Run.chain, run.chain)
                    put32(&runBytes, rb + F.Run.fullFromCm, run.full.0); put32(&runBytes, rb + F.Run.fullToCm, run.full.1)
                    put32(&runBytes, rb + F.Run.overviewFromCm, run.overview.0); put32(&runBytes, rb + F.Run.overviewToCm, run.overview.1)
                    nextRun += 1
                }
                cumulative += edge.length
            }
        }

        var linkBytes = [UInt8](repeating: 0, count: links.count * F.Link.size)
        for (i, link) in links.enumerated() {
            let b = i * F.Link.size
            put32(&linkBytes, b + F.Link.nodeA, UInt32(firstNode[link.a.line] + link.a.node))
            put32(&linkBytes, b + F.Link.nodeB, UInt32(firstNode[link.b.line] + link.b.node))
            linkBytes[b + F.Link.kind] = link.kind.rawValue; linkBytes[b + F.Link.flags] = link.directed ? 1 : 0
            put32(&linkBytes, b + F.Link.validFrom, link.validFrom); put32(&linkBytes, b + F.Link.validTo, link.validTo)
            put32(&linkBytes, b + F.Link.registryID, s(link.registry))
        }
        for extra in extraStops {
            stopTable[extra.key, default: [:]][extra.kind, default: []] += extra.nodes.map { firstNode[$0.line] + $0.node }
        }

        // Stops sorted by (key UTF-8 bytes, kind).
        var stopRows: [(key: [UInt8], text: String, kind: F.StopKind, nodes: [Int])] = []
        for (key, kinds) in stopTable {
            for (kind, nodes) in kinds { stopRows.append((Array(key.utf8), key, kind, Array(Set(nodes)).sorted())) }
        }
        stopRows.sort { $0.key == $1.key ? $0.kind.rawValue < $1.kind.rawValue : $0.key.lexicographicallyPrecedes($1.key) }
        var stopBytes = [UInt8](repeating: 0, count: stopRows.count * F.Stop.size)
        var stopNodeValues: [UInt32] = []
        for (i, row) in stopRows.enumerated() {
            let b = i * F.Stop.size
            put32(&stopBytes, b + F.Stop.key, s(row.text)); put16(&stopBytes, b + F.Stop.keyLength, UInt16(row.key.count))
            stopBytes[b + F.Stop.kind] = row.kind.rawValue
            put32(&stopBytes, b + F.Stop.firstNode, UInt32(stopNodeValues.count)); put32(&stopBytes, b + F.Stop.nodeCount, UInt32(row.nodes.count))
            stopNodeValues += row.nodes.map(UInt32.init)
        }
        var stopNodeBytes = [UInt8](repeating: 0, count: stopNodeValues.count * 4)
        for (i, v) in stopNodeValues.enumerated() { put32(&stopNodeBytes, i * 4, v) }

        let tables: [[UInt8]] = [lineBytes, nodeBytes, edgeBytes, runBytes, linkBytes, [], stopBytes, stopNodeBytes]
        let counts = [lines.count, nodeTotal, edgeTotal, runTotal, links.count, 0, stopRows.count, stopNodeValues.count]
        var header = [UInt8](repeating: 0, count: F.Header.size)
        var body: [UInt8] = []
        var offset = F.Header.size
        for (i, table) in tables.enumerated() {
            put32(&header, F.Header.directoryOffset + i * 8, UInt32(offset)); put32(&header, F.Header.directoryOffset + i * 8 + 4, UInt32(counts[i]))
            body += table; offset += table.count
        }
        put32(&header, F.Header.directoryOffset + 8 * 8, UInt32(offset)); put32(&header, F.Header.directoryOffset + 8 * 8 + 4, UInt32(strings.count))
        body += strings + [UInt8](repeating: 0, count: (4 - strings.count % 4) % 4)
        for (i, b) in F.magic.enumerated() { header[F.Header.magicOffset + i] = b }
        put16(&header, F.Header.versionOffset, F.formatVersion); put16(&header, F.Header.headerSizeOffset, UInt16(F.Header.size))
        for (i, b) in region.utf8.enumerated() { header[F.Header.regionOffset + i] = b }
        for i in 0..<32 { header[F.Header.packageSHA256Offset + i] = packageSHA; header[F.Header.displaySHA256Offset + i] = displaySHA }
        put32(&header, F.Header.fileLengthOffset, UInt32(F.Header.size + body.count))
        return Data(header + body)
    }

    func topology(displayBlobSHA256: [UInt8]? = nil) throws -> RailTopology {
        try RailTopology(data: encode(), displayBlobSHA256: displayBlobSHA256)
    }
}

extension RailTopology {
    /// A ref by line id and node ordinal, for readable tests.
    func ref(_ line: String, _ node: Int) -> NodeRef { NodeRef(line: lineIndex(forID: line)!, node: UInt16(node)) }
    func span(_ line: String, _ from: Int, _ to: Int, wraps: Bool = false) -> Span {
        Span(line: lineIndex(forID: line)!, fromNode: UInt16(from), toNode: UInt16(to), wraps: wraps)
    }
}
