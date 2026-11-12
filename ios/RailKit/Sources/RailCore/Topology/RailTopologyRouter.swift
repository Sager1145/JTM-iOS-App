import Foundation

// MARK: - RailTopologyRouter: deterministic shortest-length routing
//
// Dijkstra over the topology's nodes, in place on the mapped bytes. Edges
// join consecutive nodes of one line; the only way to change line is a link
// (reviewed junction or dated through service). Equal station codes, equal
// names and shared stations never join two lines.
//
// Rules, in the order the plan's resolver relies on them:
//  - hard filters: `lineIDs` and `institutions` limit which lines may be used,
//    and so which links (both end lines must be allowed);
//  - dated rows: a line, an edge or a link is usable on a day when
//    `validFrom <= day < validTo`; an undated query uses rows without a `validTo`;
//  - direction: an edge is travelled first-to-second only with `forward`,
//    second-to-first only with `reverse`; a directed link only A to B;
//  - withheld edges are not used unless asked for;
//  - length: edge `lengthCm` (a preferred line's edges cost 20% less); links cost nothing;
//  - ties: among equal lengths the path with the fewest row changes (links taken) wins,
//    then the first path found in settle order, ordered by (cost, row changes, global
//    node index): a pure function of the file and the query, independent of the
//    order of `from` and `to`;
//  - no path under the line filter: the same search without `lineIDs`
//    (institutions still apply), reported `unproven`.

extension RailTopology {
    /// Cost scale: a preferred line's edges cost `preferredWeight / baseWeight` of their length.
    static let baseWeight: UInt64 = 10
    static let preferredWeight: UInt64 = 8

    /// Deterministic shortest-length path between the two candidate node
    /// sets; nil when none exists. `includeWithheld` lets the path use
    /// withheld edges (the caller reports ``containsWithheldEdge(_:)``).
    ///
    /// A start node that is also a destination, or is joined to one by a
    /// link, gives a proven path with no spans and zero length. That is not
    /// a drawable route: the resolver must treat an empty path as a gap, or
    /// build a full loop circuit itself (two spans, per the format document).
    public func route(_ query: SectionQuery, includeWithheld: Bool = false) -> SectionPath? {
        withView { view in
            if let spans = view.shortestPath(query, applyLineIDs: true, includeWithheld: includeWithheld, links: linkEntries) {
                return SectionPath(spans: spans, lengthCm: spans.reduce(0) { $0 + view.lengthCm(of: $1) })
            }
            guard !query.lineIDs.isEmpty,
                  let spans = view.shortestPath(query, applyLineIDs: false, includeWithheld: includeWithheld, links: linkEntries)
            else { return nil }
            return SectionPath(spans: spans, lengthCm: spans.reduce(0) { $0 + view.lengthCm(of: $1) }, unproven: true)
        }
    }
}

/// Binary min-heap of (cost, row changes, node), ordered lexicographically.
private struct NodeHeap {
    typealias Item = (cost: UInt64, changes: UInt32, node: UInt32)
    private var items: [Item] = []
    var isEmpty: Bool { items.isEmpty }

    @inline(__always)
    private static func less(_ a: Item, _ b: Item) -> Bool {
        if a.cost != b.cost { return a.cost < b.cost }
        return a.changes != b.changes ? a.changes < b.changes : a.node < b.node
    }

    mutating func push(_ cost: UInt64, _ changes: UInt32, _ node: UInt32) {
        items.append((cost, changes, node))
        var i = items.count - 1
        while i > 0 {
            let parent = (i - 1) / 2
            guard Self.less(items[i], items[parent]) else { break }
            items.swapAt(i, parent)
            i = parent
        }
    }

    mutating func pop() -> Item? {
        guard let top = items.first else { return nil }
        let last = items.removeLast()
        if !items.isEmpty {
            items[0] = last
            var i = 0
            while true {
                let l = 2 * i + 1, r = l + 1
                var smallest = i
                if l < items.count, Self.less(items[l], items[smallest]) { smallest = l }
                if r < items.count, Self.less(items[r], items[smallest]) { smallest = r }
                if smallest == i { break }
                items.swapAt(i, smallest)
                i = smallest
            }
        }
        return top
    }
}

extension TopologyView {
    /// Predecessor edge markers.
    private static let noEdge = UInt32.max
    private static let viaLink = UInt32.max - 1

    private func idBytes(_ ids: Set<String>) -> [[UInt8]] { ids.map { Array($0.utf8) } }

    /// Per line: bit 0 usable (valid on the day and passing the hard filters), bit 1 preferred.
    private func lineFlags(_ query: RailTopology.SectionQuery, applyLineIDs: Bool) -> [UInt8] {
        let wanted = applyLineIDs ? idBytes(query.lineIDs) : []
        let preferred = idBytes(query.preferredLineIDs)
        var flags = [UInt8](repeating: 0, count: lineCount)
        for line in 0..<lineCount {
            let b = lineBase(line)
            guard F.isValid(on: query.day, from: u32(b + F.Line.validFrom), to: u32(b + F.Line.validTo)) else { continue }
            if !query.institutions.isEmpty, !query.institutions.contains(u16(b + F.Line.institution)) { continue }
            let id = u32(b + F.Line.id)
            if !wanted.isEmpty, !wanted.contains(where: { $0.withUnsafeBytes { stringEquals(id, $0) } }) { continue }
            var bits: UInt8 = 1
            if !preferred.isEmpty, preferred.contains(where: { $0.withUnsafeBytes { stringEquals(id, $0) } }) { bits |= 2 }
            flags[line] = bits
        }
        return flags
    }

    func shortestPath(_ query: RailTopology.SectionQuery, applyLineIDs: Bool, includeWithheld: Bool,
                      links: [RailTopology.LinkEntry]) -> [RailTopology.Span]? {
        let flags = lineFlags(query, applyLineIDs: applyLineIDs)
        func usable(_ line: Int) -> Bool { flags[line] & 1 != 0 }

        var targets = Set<UInt32>()
        for ref in query.to {
            if let g = global(ref), usable(Int(ref.line)) { targets.insert(UInt32(g)) }
        }
        guard !targets.isEmpty else { return nil }

        var dist = [UInt64](repeating: .max, count: nodeTotal)
        var prev = [UInt32](repeating: .max, count: nodeTotal)
        var prevEdge = [UInt32](repeating: Self.noEdge, count: nodeTotal)
        var changes = [UInt32](repeating: 0, count: nodeTotal)
        var settled = [Bool](repeating: false, count: nodeTotal)
        var heap = NodeHeap()
        for ref in query.from {
            guard let g = global(ref), usable(Int(ref.line)), dist[g] != 0 else { continue }
            dist[g] = 0
            heap.push(0, 0, UInt32(g))
        }

        func relax(_ u: Int, _ v: Int, cost: UInt64, rowChange: UInt32, edge: UInt32) {
            let nd = dist[u] + cost, nc = changes[u] + rowChange
            if nd < dist[v] || (nd == dist[v] && nc < changes[v]) {
                dist[v] = nd; changes[v] = nc; prev[v] = UInt32(u); prevEdge[v] = edge
                heap.push(nd, nc, UInt32(v))
            }
        }

        while let (_, _, node) = heap.pop() {
            let u = Int(node)
            if settled[u] { continue }
            settled[u] = true
            if targets.contains(node) { return reconstruct(from: u, prev: prev, prevEdge: prevEdge) }

            let line = Int(u16(nodeBase(u) + F.Node.line))
            let n = lineNodeCount(line), firstNode = lineFirstNode(line)
            let ordinal = u - firstNode
            let loop = lineIsLoop(line)
            let weight = flags[line] & 2 != 0 ? RailTopology.preferredWeight : RailTopology.baseWeight

            func step(edge k: Int, to nextOrdinal: Int, needs direction: F.EdgeFlag) {
                let v = firstNode + nextOrdinal
                guard !settled[v] else { return }
                let eb = edgeBase(lineFirstEdge(line) + k)
                let edgeFlags = F.EdgeFlag(rawValue: u16(eb + F.Edge.flags))
                guard edgeFlags.contains(direction),
                      includeWithheld || !edgeFlags.contains(.withheld),
                      F.isValid(on: query.day, from: u32(eb + F.Edge.validFrom), to: u32(eb + F.Edge.validTo))
                else { return }
                relax(u, v, cost: UInt64(u32(eb + F.Edge.lengthCm)) * weight, rowChange: 0, edge: UInt32(k))
            }
            // Towards higher ordinals over edge `ordinal`.
            if loop { step(edge: ordinal, to: (ordinal + 1) % n, needs: .forward) }
            else if ordinal + 1 < n { step(edge: ordinal, to: ordinal + 1, needs: .forward) }
            // Towards lower ordinals over edge `ordinal - 1` (the closing edge from node 0 on a loop).
            if ordinal > 0 { step(edge: ordinal - 1, to: ordinal - 1, needs: .reverse) }
            else if loop { step(edge: n - 1, to: n - 1, needs: .reverse) }

            // Links, found by binary search of the sorted link index.
            var lo = 0, hi = links.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if links[mid].node < node { lo = mid + 1 } else { hi = mid }
            }
            while lo < links.count, links[lo].node == node {
                let entry = links[lo]
                lo += 1
                let v = Int(entry.other)
                guard !settled[v] else { continue }
                let otherLine = Int(u16(nodeBase(v) + F.Node.line))
                let lb = linkBase(Int(entry.link))
                guard usable(otherLine),
                      F.isValid(on: query.day, from: u32(lb + F.Link.validFrom), to: u32(lb + F.Link.validTo))
                else { continue }
                relax(u, v, cost: 0, rowChange: 1, edge: Self.viaLink)
            }
        }
        return nil
    }

    /// Spans from the predecessor chain: consecutive edge steps on one line in
    /// one direction make one span; a link ends it.
    private func reconstruct(from target: Int, prev: [UInt32], prevEdge: [UInt32]) -> [RailTopology.Span] {
        var steps: [(from: Int, to: Int, edge: UInt32)] = []
        var g = target
        while prev[g] != .max {
            steps.append((Int(prev[g]), g, prevEdge[g]))
            g = Int(prev[g])
        }
        steps.reverse()

        var spans: [RailTopology.Span] = []
        var current: (line: Int, up: Bool, from: Int, to: Int, wraps: Bool)?
        func flush() {
            if let c = current {
                spans.append(.init(line: UInt16(c.line), fromNode: UInt16(c.from), toNode: UInt16(c.to), wraps: c.wraps))
            }
            current = nil
        }
        for step in steps {
            guard step.edge != Self.viaLink else { flush(); continue }
            let line = Int(u16(nodeBase(step.to) + F.Node.line))
            let first = lineFirstNode(line)
            let fromOrdinal = step.from - first, toOrdinal = step.to - first
            // Leaving node `k` over edge `k` goes upward; the other direction uses edge `ordinal - 1`.
            let up = fromOrdinal == Int(step.edge)
            let crosses = lineIsLoop(line) && Int(step.edge) == lineNodeCount(line) - 1
            if var c = current, c.line == line, c.up == up {
                c.to = toOrdinal; c.wraps = c.wraps || crosses
                current = c
            } else {
                flush()
                current = (line, up, fromOrdinal, toOrdinal, crosses)
            }
        }
        flush()
        return spans
    }
}
