import Foundation

// MARK: - RailTopologyRouter: deterministic shortest-length routing
//
// Dijkstra over the topology's nodes, in place on the mapped bytes. Edges
// join consecutive nodes of one line; the only way to change line is a link
// (reviewed junction or dated through service). Equal station codes, equal
// names and shared stations never join two lines.
//
// One call is one attempt of the production solver's ladder (`RailTopologySolver.swift`
// holds the ladder). Rules, each with a unit test in `RailTopologyRouterTests`:
//  - hard filters: `lineIDs`, `operators` and `institutions` limit which lines may be used,
//    and so which links (both end lines must be allowed);
//  - dated rows: a line, an edge or a link is usable on a day when
//    `validFrom <= day < validTo`; an undated query uses rows without a `validTo`;
//  - direction: the production graph is bidirectional and the solver excludes direction
//    section-locally (`RouteSolver.directionExclusion`, `:3318-3359`), only for a section
//    that names both ends by N02 code (an end by name only has no code: nothing is blocked):
//    on a line that holds both ends, between the first node of each end on that line, the
//    edges are blocked when the line's edge flags forbid that travel direction. Nowhere
//    else do the flags apply. A directed link is crossed only A to B;
//  - withheld edges are not used unless asked for;
//  - cost: edge `lengthCm` times a whole-number factor, the production solver's cost model
//    (`RouteSolver.swift:21-25`, `:4010-4026`): 1, plus 8 on a line outside a non-empty
//    preferred-line set, plus 6 on a line whose operator is outside a non-empty
//    preferred-operator set, plus 180 on a line whose institution is outside a non-empty
//    preferred-institution set; and for that institution, 5,000 m for each source step of
//    each edge (`Edge.fineEdges`). Links cost nothing. Integer costs only;
//  - hard exclusion: lines with an excluded institution are never used;
//  - detour guard (`RouteSolver.swift:3636-3640`): a path longer than max(3.8 x straight line
//    + 6,000 m, 12,000 m) between ends more than 1,500 m apart is rejected, and the search
//    goes on to the next end node it settles;
//  - same-name endpoint guard (`:3548-3570`): for an end given by name only, a path whose end
//    is more than twice as far from the other end as another same-name station, beyond
//    20 km, is rejected and kept only as the last resort, reported `unproven`;
//  - target choice (`RouteSolver.swift:3643-3647`, `:3683`, `:3723-3736`): production keeps
//    every settled target and takes the lowest `scoredCost` = Dijkstra cost + the line and
//    operator preference penalty a second time (`routeLineMismatchPenalty`, over the edges
//    of the path; institution factors are not repeated) + 4 x snap distance. The router
//    settles targets in cost order, scores each that passes the guards, and stops when the
//    heap floor exceeds the best score (the penalty is never negative). The snap term is
//    not modelled: a node carries no station-to-node distance, so it counts as zero. A
//    score tie keeps the first target settled;
//  - ties: among equal costs the path with the fewest row changes (links taken) wins,
//    then the first path found in settle order, ordered by (cost, row changes,
//    line id rank, node ordinal): a pure function of the line ids and the query,
//    independent of the order of `from` and `to` and of the order of lines in the file.
//  No A*: 751 edges are shorter than the straight line.

extension RailTopology {
    /// Cost factors of the production solver (`RouteSolver.nonPreferredLineLengthFactor` 8,
    /// `nonPreferredOperatorLengthFactor` 6 and `nonPreferredInstitutionLengthFactor` 180, each
    /// added to the length itself).
    public static let nonPreferredLineFactor: UInt64 = 9
    public static let nonPreferredOperatorFactor: UInt64 = 7
    public static let nonPreferredInstitutionFactor: UInt64 = 181
    /// `RouteSolver.nonPreferredInstitutionEdgePenalty` 5,000 m, in centimetres, per source step.
    public static let nonPreferredInstitutionEdgeCm: UInt64 = 500_000
    /// Detour guard constants (`RouteSolver.swift:3636-3640`), metres.
    static let detourMinStraightMetres = 1_500.0
    static let detourStraightFactor = 3.8
    static let detourSlackMetres = 6_000.0
    static let detourFloorMetres = 12_000.0
    /// Same-name endpoint guard constants (`RouteSolver.endpointAmbiguity*`), metres and ratio.
    static let sameNameMinStraightMetres = 20_000.0
    static let sameNameDistanceFactor = 2.0
    /// Nodes closer than this to the node an endpoint ended on are the same station, not an alternative.
    static let sameStationMetres = 200.0

    /// Deterministic shortest-cost path between the two candidate node sets; nil when none
    /// exists. `includeWithheld` lets the path use withheld edges (the caller reports
    /// ``containsWithheldEdge(_:)``).
    ///
    /// A start node that is also a destination, or is joined to one by a link, gives a proven
    /// path with no spans and zero length. That is not a drawable route: the resolver must
    /// treat an empty path as a gap, or build a full loop circuit itself (two spans, per the
    /// format document).
    ///
    /// The path is `unproven` only when the same-name guard rejected every path found and this
    /// one is the lowest scored of them.
    public func route(_ query: SectionQuery, includeWithheld: Bool = false) -> SectionPath? {
        withView { view in
            view.shortestPath(query, includeWithheld: includeWithheld, links: linkEntries, lineRank: lineRank)
        }
    }
}

/// Heap item ordered lexicographically by (cost, row changes, key, node); `key` is
/// the line's id rank in the high 32 bits and the node ordinal in the low 32.
struct NodeItem: HeapOrdered {
    var cost: UInt64
    var changes: UInt32
    var key: UInt64
    var node: UInt32

    @inline(__always)
    func precedes(_ b: NodeItem) -> Bool {
        if cost != b.cost { return cost < b.cost }
        if changes != b.changes { return changes < b.changes }
        return key != b.key ? key < b.key : node < b.node
    }
}

extension TopologyView {
    /// Predecessor edge markers.
    private static let noEdge = UInt32.max
    private static let viaLink = UInt32.max - 1

    private func idBytes(_ ids: Set<String>) -> [[UInt8]] { ids.map { Array($0.utf8) } }

    /// Whether the string at `ref` equals one of `set`; an absent string equals none.
    private func stringIn(_ ref: UInt32, _ set: [[UInt8]]) -> Bool {
        guard ref != F.noString else { return false }
        return set.contains { $0.withUnsafeBytes { stringEquals(ref, $0) } }
    }

    /// Per line: factor 0 when unusable (not valid on the day, or failing a hard filter),
    /// otherwise the cost factor applied to the length of its edges (at least 1); and the
    /// flat centimetres charged for each source step of each of its edges.
    private func lineCosts(_ query: RailTopology.SectionQuery)
        -> (factor: [UInt64], perStepCm: [UInt64], mismatch: [UInt64]) {
        let wanted = idBytes(query.lineIDs)
        let wantedOperators = idBytes(query.operators)
        let preferred = idBytes(query.preferredLineIDs)
        let preferredOperators = idBytes(query.preferredOperators)
        var factors = [UInt64](repeating: 0, count: lineCount)
        var perStep = [UInt64](repeating: 0, count: lineCount)
        // The line and operator part of the factor, charged a second time when scoring a target.
        var mismatch = [UInt64](repeating: 0, count: lineCount)
        for line in 0..<lineCount {
            let b = lineBase(line)
            guard F.isValid(on: query.day, from: u32(b + F.Line.validFrom), to: u32(b + F.Line.validTo)) else { continue }
            let institution = u16(b + F.Line.institution)
            // Institution 0 is "unknown" and passes, as an empty institution code does in the solver
            // (`RouteSolver.edgeHasPreferredInstitution`, `:266-280`).
            if !query.institutions.isEmpty, institution != 0, !query.institutions.contains(institution) { continue }
            if query.excludedInstitutions.contains(institution) { continue }
            let id = u32(b + F.Line.id)
            let operatorRef = u32(b + F.Line.operatorName)
            if !wanted.isEmpty, !stringIn(id, wanted) { continue }
            if !wantedOperators.isEmpty, !stringIn(operatorRef, wantedOperators) { continue }
            var factor: UInt64 = 1
            if !preferred.isEmpty, !stringIn(id, preferred) {
                factor += RailTopology.nonPreferredLineFactor - 1
                mismatch[line] += RailTopology.nonPreferredLineFactor - 1
            }
            if !preferredOperators.isEmpty, operatorRef != F.noString, !stringIn(operatorRef, preferredOperators) {
                factor += RailTopology.nonPreferredOperatorFactor - 1
                mismatch[line] += RailTopology.nonPreferredOperatorFactor - 1
            }
            if !query.preferredInstitutions.isEmpty, institution != 0, !query.preferredInstitutions.contains(institution) {
                factor += RailTopology.nonPreferredInstitutionFactor - 1
                perStep[line] = RailTopology.nonPreferredInstitutionEdgeCm
            }
            factors[line] = factor
        }
        return (factors, perStep, mismatch)
    }

    /// Global edge indices the section may not use. Only when both ends are given by code (not by
    /// name only): on each line that holds both ends, the edges between the first node of the start
    /// and the first node of the end when the edge's flags forbid travelling that way
    /// (`RouteSolver.directionExclusion`).
    private func directionBlocked(_ query: RailTopology.SectionQuery) -> Set<Int> {
        guard !query.fromNameOnly, !query.toNameOnly else { return [] }
        var starts: [Int: Int] = [:], ends: [Int: Int] = [:]
        for ref in query.from where global(ref) != nil {
            starts[Int(ref.line)] = min(starts[Int(ref.line)] ?? Int.max, Int(ref.node))
        }
        for ref in query.to where global(ref) != nil {
            ends[Int(ref.line)] = min(ends[Int(ref.line)] ?? Int.max, Int(ref.node))
        }
        var blocked = Set<Int>()
        for (line, f) in starts {
            guard let t = ends[line], t != f else { continue }
            let needed: F.EdgeFlag = f < t ? .forward : .reverse
            for k in min(f, t)..<max(f, t) {
                let edge = edgeGlobal(line: line, ordinal: k)
                if !F.EdgeFlag(rawValue: u16(edgeBase(edge) + F.Edge.flags)).contains(needed) { blocked.insert(edge) }
            }
        }
        return blocked
    }

    private func coordinate(_ node: Int) -> Coordinate {
        let b = nodeBase(node)
        return Coordinate(lon: Double(Float(bitPattern: u32(b + F.Node.longitude))),
                          lat: Double(Float(bitPattern: u32(b + F.Node.latitude))))
    }

    func shortestPath(_ query: RailTopology.SectionQuery, includeWithheld: Bool,
                      links: [RailTopology.LinkEntry], lineRank: [UInt32]) -> RailTopology.SectionPath? {
        let (factors, perStepCm, mismatchFactor) = lineCosts(query)
        let blocked = directionBlocked(query)
        func usable(_ line: Int) -> Bool { factors[line] != 0 }
        /// Settle-order tie-break key: line id rank, then node ordinal.
        func key(_ node: Int) -> UInt64 {
            let line = Int(u16(nodeBase(node) + F.Node.line))
            return UInt64(lineRank[line]) << 32 | UInt64(node - lineFirstNode(line))
        }

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
        var heap = BinaryMinHeap<NodeItem>()
        for ref in query.from {
            guard let g = global(ref), usable(Int(ref.line)), dist[g] != 0 else { continue }
            dist[g] = 0
            heap.push(NodeItem(cost: 0, changes: 0, key: key(g), node: UInt32(g)))
        }

        func relax(_ u: Int, _ v: Int, cost: UInt64, rowChange: UInt32, edge: UInt32) {
            let nd = dist[u] + cost, nc = changes[u] + rowChange
            if nd < dist[v] || (nd == dist[v] && nc < changes[v]) {
                dist[v] = nd; changes[v] = nc; prev[v] = UInt32(u); prevEdge[v] = edge
                heap.push(NodeItem(cost: nd, changes: nc, key: key(v), node: UInt32(v)))
            }
        }

        // Candidate stations for the same-name guard: every same-name node the caller gave, usable or
        // not, as the solver compares against every same-name station.
        let fromCandidates = query.fromNameOnly ? query.from.compactMap { global($0) } : []
        let toCandidates = query.toNameOnly ? query.to.compactMap { global($0) } : []
        /// Distance to the nearest candidate that is another station than `node`.
        func nearestAlternative(_ candidates: [Int], excluding node: Int, from point: Coordinate) -> Double? {
            let here = coordinate(node)
            var nearest: Double?
            for candidate in candidates {
                let c = coordinate(candidate)
                if Geometry.distanceMeters(c, here) <= RailTopology.sameStationMetres { continue }
                let d = Geometry.distanceMeters(c, point)
                if nearest == nil || d < nearest! { nearest = d }
            }
            return nearest
        }
        func endpointImplausible(root: Int, target: Int, straight: Double) -> Bool {
            guard query.fromNameOnly || query.toNameOnly, straight > RailTopology.sameNameMinStraightMetres else { return false }
            if query.toNameOnly,
               let alternative = nearestAlternative(toCandidates, excluding: target, from: coordinate(root)),
               straight > alternative * RailTopology.sameNameDistanceFactor { return true }
            if query.fromNameOnly,
               let alternative = nearestAlternative(fromCandidates, excluding: root, from: coordinate(target)),
               straight > alternative * RailTopology.sameNameDistanceFactor { return true }
            return false
        }
        var lastResort: RailTopology.SectionPath?
        var lastResortScore = UInt64.max
        var best: RailTopology.SectionPath?
        var bestScore = UInt64.max

        while let popped = heap.pop() {
            let popCost = popped.cost, node = popped.node
            // Every target settling from here on costs at least this much, and its score is never lower.
            if popCost > bestScore { break }
            let u = Int(node)
            if settled[u] { continue }
            settled[u] = true
            if targets.contains(node) {
                let built = chain(to: u, prev: prev, prevEdge: prevEdge, mismatchFactor: mismatchFactor)
                let score = dist[u] + built.mismatchCm
                let straight = Geometry.distanceMeters(coordinate(built.root), coordinate(u))
                let pathMetres = Double(built.edgeCm) / 100
                let tooLong = straight > RailTopology.detourMinStraightMetres
                    && pathMetres > max(straight * RailTopology.detourStraightFactor + RailTopology.detourSlackMetres,
                                        RailTopology.detourFloorMetres)
                if !tooLong {
                    if !endpointImplausible(root: built.root, target: u, straight: straight) {
                        if score < bestScore {
                            let spans = spans(of: built.steps)
                            best = RailTopology.SectionPath(spans: spans, lengthCm: spans.reduce(0) { $0 + lengthCm(of: $1) })
                            bestScore = score
                        }
                    } else if score < lastResortScore {
                        let spans = spans(of: built.steps)
                        lastResort = RailTopology.SectionPath(
                            spans: spans, lengthCm: spans.reduce(0) { $0 + lengthCm(of: $1) }, unproven: true)
                        lastResortScore = score
                    }
                }
            }

            let line = Int(u16(nodeBase(u) + F.Node.line))
            let n = lineNodeCount(line), firstNode = lineFirstNode(line)
            let ordinal = u - firstNode
            let loop = lineIsLoop(line)
            let weight = factors[line]
            let stepCm = perStepCm[line]

            func step(edge k: Int, to nextOrdinal: Int) {
                let v = firstNode + nextOrdinal
                guard !settled[v] else { return }
                let global = lineFirstEdge(line) + k
                let eb = edgeBase(global)
                let edgeFlags = F.EdgeFlag(rawValue: u16(eb + F.Edge.flags))
                guard !blocked.contains(global),
                      includeWithheld || !edgeFlags.contains(.withheld),
                      F.isValid(on: query.day, from: u32(eb + F.Edge.validFrom), to: u32(eb + F.Edge.validTo))
                else { return }
                let cost = UInt64(u32(eb + F.Edge.lengthCm)) * weight + stepCm * UInt64(u32(eb + F.Edge.fineEdges))
                relax(u, v, cost: cost, rowChange: 0, edge: UInt32(k))
            }
            // Towards higher ordinals over edge `ordinal`.
            if loop { step(edge: ordinal, to: (ordinal + 1) % n) }
            else if ordinal + 1 < n { step(edge: ordinal, to: ordinal + 1) }
            // Towards lower ordinals over edge `ordinal - 1` (the closing edge from node 0 on a loop).
            if ordinal > 0 { step(edge: ordinal - 1, to: ordinal - 1) }
            else if loop { step(edge: n - 1, to: n - 1) }

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
        return best ?? lastResort
    }

    private struct Step { var from: Int; var to: Int; var edge: UInt32 }

    /// The predecessor chain to `target`: its steps in travel order, the node it started at,
    /// the summed length of its edge steps in centimetres, and the preference penalty
    /// (length times `mismatchFactor` of the edge's line) those steps are charged again when scored.
    private func chain(to target: Int, prev: [UInt32], prevEdge: [UInt32], mismatchFactor: [UInt64])
        -> (steps: [Step], root: Int, edgeCm: UInt64, mismatchCm: UInt64) {
        var steps: [Step] = []
        var g = target
        var edgeCm: UInt64 = 0
        var mismatchCm: UInt64 = 0
        while prev[g] != .max {
            steps.append(Step(from: Int(prev[g]), to: g, edge: prevEdge[g]))
            if prevEdge[g] != Self.viaLink {
                let line = Int(u16(nodeBase(g) + F.Node.line))
                let length = UInt64(u32(edgeBase(lineFirstEdge(line) + Int(prevEdge[g])) + F.Edge.lengthCm))
                edgeCm += length
                mismatchCm += length * mismatchFactor[line]
            }
            g = Int(prev[g])
        }
        steps.reverse()
        return (steps, g, edgeCm, mismatchCm)
    }

    /// Spans from the steps: consecutive edge steps on one line in one direction make one
    /// span; a link ends it.
    private func spans(of steps: [Step]) -> [RailTopology.Span] {
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
