import Foundation
import Testing
@testable import RailCore

@Suite("RailTopology router")
struct RailTopologyRouterTests {
    typealias F = RailTopologyFormat
    typealias Net = TestNetwork

    static func day(_ iso: String) -> UInt32 { F.dayNumber(ofISODate: iso)! }

    /// A query between (line id, ordinal) pairs.
    static func query(_ t: RailTopology, _ from: [(String, Int)], _ to: [(String, Int)], day: String? = nil,
                      lines: Set<String> = [], institutions: Set<UInt16> = [], preferred: Set<String> = [],
                      operators: Set<String> = [], preferredOperators: Set<String> = []) -> RailTopology.SectionQuery {
        RailTopology.SectionQuery(
            from: from.map { t.ref($0.0, $0.1) }, to: to.map { t.ref($0.0, $0.1) },
            day: day.map(Self.day), lineIDs: lines, operators: operators, institutions: institutions,
            preferredLineIDs: preferred, preferredOperators: preferredOperators)
    }

    /// x (5 stations) with a dated junction to y, a shared-code line z, a loop l, a one-way w.
    static func network() -> Net {
        var net = Net()
        net.lines = [
            .chain("x", ["X0", "X1", "X2", "X3", "X4"], lengths: [10_000, 10_000, 10_000, 10_000]),
            .chain("y", ["Y0", "Y1", "Y2"], lengths: [10_000, 10_000]),
            // Z0 carries the station code of X4 and the same name as nothing else: it must never join x.
            .chain("z", ["X4", "Z1"], lengths: [10_000], institution: 2),
            .chain("l", ["L0", "L1", "L2", "L3"], lengths: [10_000, 10_000, 10_000, 5_000], loop: true),
            .chain("w", ["W0", "W1", "W2"], lengths: [10_000, 10_000], flags: [.forward]),
        ]
        net.links = [
            .init(a: (0, 2), b: (1, 0), validFrom: day("2010-01-01"), registry: "jct-x-y"),
            .init(a: (0, 1), b: (3, 0), registry: "jct-x-l"),
            .init(a: (1, 2), b: (4, 0), registry: "jct-y-w"),
        ]
        return net
    }

    // MARK: Basics

    @Test("shortest path along one line, both ways, with its length")
    func straightLine() throws {
        let t = try Self.network().topology()
        let forward = try #require(t.route(Self.query(t, [("x", 0)], [("x", 4)])))
        #expect(forward.spans == [t.span("x", 0, 4)] && forward.lengthCm == 40_000 && !forward.unproven)
        let back = try #require(t.route(Self.query(t, [("x", 4)], [("x", 1)])))
        #expect(back.spans == [t.span("x", 4, 1)] && back.lengthCm == 30_000)
    }

    @Test("a source that is also a target is an empty path of length zero")
    func zeroLengthPath() throws {
        let t = try Self.network().topology()
        let same = try #require(t.route(Self.query(t, [("x", 2)], [("x", 2)])))
        #expect(same.spans.isEmpty && same.lengthCm == 0)
        // A junction link alone is also a path with no travel.
        let linked = try #require(t.route(Self.query(t, [("x", 1)], [("l", 0)])))
        #expect(linked.spans.isEmpty && linked.lengthCm == 0)
    }

    @Test("no path, empty candidate lists and out-of-range refs give nil")
    func noPath() throws {
        let t = try Self.network().topology()
        #expect(t.route(Self.query(t, [("x", 0)], [])) == nil)
        #expect(t.route(Self.query(t, [], [("x", 1)])) == nil)
        let outOfRange = RailTopology.SectionQuery(from: [.init(line: 0, node: 99), .init(line: 99, node: 0)], to: [t.ref("x", 1)])
        #expect(t.route(outOfRange) == nil)
        // A valid candidate beside a bad one still routes.
        let mixed = RailTopology.SectionQuery(from: [.init(line: 99, node: 0), t.ref("x", 0)], to: [t.ref("x", 1)])
        #expect(t.route(mixed)?.spans == [t.span("x", 0, 1)])
    }

    // MARK: Links are the only way to change rows

    @Test("no row change without a link: a shared station code or a shared name never joins two lines")
    func sharedCodeNeverJoins() throws {
        let t = try Self.network().topology()
        // X4 on x and Z0 on z have the same station code, but no link exists.
        #expect(t.nodes(forStop: "X4").count == 2)
        #expect(t.route(Self.query(t, [("x", 0)], [("z", 1)])) == nil)
        #expect(t.route(Self.query(t, [("x", 4)], [("z", 1)])) == nil)
        // Even with the filter dropped there is nothing to fall back on.
        #expect(t.route(Self.query(t, [("x", 0)], [("z", 1)], lines: ["x"])) == nil)
        // Offering both nodes of the station as candidates is the caller's way to say "this station".
        let both = try #require(t.route(Self.query(t, [("x", 0)], [("x", 4), ("z", 0)])))
        #expect(both.spans == [t.span("x", 0, 4)])

        // Same name on two lines: also nothing.
        var net = Self.network()
        net.lines[2].nodes[0].code = "SAME"
        net.lines[0].nodes[4].code = "SAME"
        let renamed = try net.topology()
        #expect(renamed.route(Self.query(renamed, [("x", 0)], [("z", 1)])) == nil)
    }

    @Test("a path across a link is one span per line, in travel order")
    func pathAcrossLinks() throws {
        let t = try Self.network().topology()
        let path = try #require(t.route(Self.query(t, [("x", 0)], [("y", 2)])))
        #expect(path.spans == [t.span("x", 0, 2), t.span("y", 0, 2)] && path.lengthCm == 40_000)
        // Three lines.
        let three = try #require(t.route(Self.query(t, [("x", 0)], [("w", 2)])))
        #expect(three.spans == [t.span("x", 0, 2), t.span("y", 0, 2), t.span("w", 0, 2)] && three.lengthCm == 60_000)
        // Back the other way: links are undirected unless marked.
        let back = try #require(t.route(Self.query(t, [("y", 1)], [("x", 0)])))
        #expect(back.spans == [t.span("y", 1, 0), t.span("x", 2, 0)])
    }

    @Test("a dated link is refused the day before validFrom and honoured from it; undated uses rows without validTo")
    func linkValidFrom() throws {
        let t = try Self.network().topology()
        let q = { (day: String?) in t.route(Self.query(t, [("x", 0)], [("y", 2)], day: day)) }
        #expect(q("2009-12-31") == nil)
        #expect(q("2010-01-01") != nil)
        #expect(q("2024-06-01") != nil)
        #expect(q(nil) != nil)
    }

    @Test("a link is refused on its validTo day and after; an undated ride refuses a link that ended")
    func linkValidTo() throws {
        var net = Self.network()
        net.links[0].validFrom = 0
        net.links[0].validTo = Self.day("2020-01-01")
        let t = try net.topology()
        let q = { (day: String?) in t.route(Self.query(t, [("x", 0)], [("y", 2)], day: day)) }
        #expect(q("2019-12-31") != nil)
        #expect(q("2020-01-01") == nil)
        #expect(q("2021-01-01") == nil)
        #expect(q(nil) == nil)
    }

    @Test("a directed link is crossed only from A to B")
    func directedLink() throws {
        var net = Self.network()
        net.links[0].directed = true
        net.links[0].kind = .throughService
        let t = try net.topology()
        #expect(t.route(Self.query(t, [("x", 0)], [("y", 2)])) != nil)
        #expect(t.route(Self.query(t, [("y", 2)], [("x", 0)])) == nil)
    }

    // MARK: Loops and one-way

    @Test("on a loop the shorter way round wins, over the closing edge when that is shorter")
    func loopWraps() throws {
        let t = try Self.network().topology()
        // L2 to L0: up through L3 and the closing edge is 15,000; down through L1 is 20,000.
        let up = try #require(t.route(Self.query(t, [("l", 2)], [("l", 0)])))
        #expect(up.spans == [t.span("l", 2, 0, wraps: true)] && up.lengthCm == 15_000)
        // L0 to L3: the closing edge alone, downward.
        let down = try #require(t.route(Self.query(t, [("l", 0)], [("l", 3)])))
        #expect(down.spans == [t.span("l", 0, 3, wraps: true)] && down.lengthCm == 5_000)
        let plain = try #require(t.route(Self.query(t, [("l", 0)], [("l", 1)])))
        #expect(plain.spans == [t.span("l", 0, 1)] && plain.lengthCm == 10_000)
        // A loop reached through a link continues over the closing edge in one span.
        let viaLink = try #require(t.route(Self.query(t, [("x", 0)], [("l", 3)])))
        #expect(viaLink.spans == [t.span("x", 0, 1), t.span("l", 0, 3, wraps: true)] && viaLink.lengthCm == 15_000)
    }

    @Test("direction is excluded section-locally: only between a start and an end node on the same line")
    func directionExclusion() throws {
        var net = Self.network()
        net.lines.append(.chain("r", ["R0", "R1", "R2"], lengths: [10_000, 10_000], flags: [.reverse]))
        net.lines.append(.chain("f", ["F0", "F1", "F2", "F3"], lengths: [10_000, 10_000, 10_000, 10_000], loop: true, flags: [.forward]))
        net.lines.append(.chain("a", ["A0", "A1"], lengths: [10_000]))
        net.links.append(.init(a: (7, 1), b: (5, 0), registry: "jct-a-r"))
        let t = try net.topology()
        // Start and end on the one-way line: the edges between them are blocked against the arrow.
        #expect(t.route(Self.query(t, [("w", 0)], [("w", 2)])) != nil)
        #expect(t.route(Self.query(t, [("w", 2)], [("w", 0)])) == nil)
        #expect(t.route(Self.query(t, [("r", 2)], [("r", 0)]))?.spans == [t.span("r", 2, 0)])
        #expect(t.route(Self.query(t, [("r", 0)], [("r", 2)])) == nil)
        // The flags apply nowhere else: a path that only passes through r (its start is on a) goes against the arrow.
        let through = try #require(t.route(Self.query(t, [("a", 0)], [("r", 2)])))
        #expect(through.spans == [t.span("a", 0, 1), t.span("r", 0, 2)] && through.lengthCm == 30_000)
        // A loop with forward-only edges: the edges between the two ordinals are blocked, the way round over the
        // closing edge is not (the solver blocks by station order, not by the wrap).
        let back = try #require(t.route(Self.query(t, [("f", 1)], [("f", 0)])))
        #expect(back.spans == [t.span("f", 1, 0, wraps: true)] && back.lengthCm == 30_000)
        let ahead = try #require(t.route(Self.query(t, [("f", 0)], [("f", 1)])))
        #expect(ahead.spans == [t.span("f", 0, 1)])
        // Several candidates: the pair decides, the other line's candidate is unaffected.
        let mixed = try #require(t.route(Self.query(t, [("w", 2), ("x", 0)], [("w", 0), ("x", 2)])))
        #expect(mixed.spans == [t.span("x", 0, 2)])
    }

    @Test("a paired alignment carries the way the base line's one-way edge forbids, joined at the shared stations")
    func pairedAlignment() throws {
        var net = Net()
        net.lines = [
            .chain("m", ["M0", "M1", "M2", "M3"], lengths: [10_000, 20_000, 10_000]),
            .chain("p", ["M1", "M2"], lengths: [21_000]),
        ]
        net.lines[0].edges[1].flags = [.forward]     // the base line's middle interval: with the arrow only
        net.lines[1].edges[0].flags = [.reverse]     // its pair carries the other direction
        net.links = [.init(a: (0, 1), b: (1, 0), kind: .pairedAlignment, registry: "alignment:p"),
                     .init(a: (0, 2), b: (1, 1), kind: .pairedAlignment, registry: "alignment:p")]
        let t = try net.topology()
        // With the arrow: straight along the base line.
        #expect(t.route(Self.query(t, [("m", 0)], [("m", 3)]))?.spans == [t.span("m", 0, 3)])
        // Against it: the base line's edge is blocked between the ends, so the trip takes the pair and comes back.
        let back = try #require(t.route(Self.query(t, [("m", 3)], [("m", 0)])))
        #expect(back.spans == [t.span("m", 3, 2), t.span("p", 1, 0), t.span("m", 1, 0)] && back.lengthCm == 41_000)
        // Without the alignment links the pair is unreachable and there is no way.
        net.links = []
        let apart = try net.topology()
        #expect(apart.route(Self.query(apart, [("m", 3)], [("m", 0)])) == nil)
    }

    // MARK: Dated rows

    @Test("a retired line is routable the day before it closes and not on the day it closes")
    func retiredLine() throws {
        var net = Self.network()
        net.lines[1].validTo = Self.day("2020-01-01")
        net.lines[1].flags.insert(.retired)
        let t = try net.topology()
        let q = { (day: String?) in t.route(Self.query(t, [("x", 0)], [("y", 2)], day: day)) }
        #expect(q("2019-12-31") != nil)
        #expect(q("2020-01-01") == nil)
        #expect(q(nil) == nil)
        // A line that opens later is not usable before.
        var opening = Self.network()
        opening.lines[1].validFrom = Self.day("2015-01-01")
        let u = try opening.topology()
        #expect(u.route(Self.query(u, [("x", 0)], [("y", 2)], day: "2014-12-31")) == nil)
        #expect(u.route(Self.query(u, [("x", 0)], [("y", 2)], day: "2015-01-01")) != nil)
    }

    @Test("an edge that does not exist yet is not used")
    func edgeValidity() throws {
        var net = Self.network()
        net.lines[0].edges[1].validFrom = Self.day("2016-03-26")
        net.lines[0].edges[2].validTo = Self.day("2019-01-01")
        let t = try net.topology()
        let q = { (day: String?) in t.route(Self.query(t, [("x", 0)], [("x", 3)], day: day)) }
        #expect(q("2016-03-25") == nil)
        #expect(q("2016-03-26") != nil)
        #expect(q("2018-12-31") != nil)
        #expect(q("2019-01-01") == nil)
        #expect(q(nil) == nil)
    }

    // MARK: Filters, preference, withheld

    /// s -> (p | q) -> t, p shorter than q.
    static func parallelNetwork(p: UInt32 = 100_000, q: UInt32 = 105_000) -> Net {
        var net = Net()
        net.lines = [
            .chain("s", ["S0", "S1"], lengths: [50_000]),
            .chain("p", ["P0", "P1"], lengths: [p]),
            .chain("q", ["Q0", "Q1"], lengths: [q]),
            .chain("t", ["T0", "T1"], lengths: [50_000], institution: 2),
        ]
        net.links = [
            .init(a: (0, 1), b: (1, 0)), .init(a: (0, 1), b: (2, 0)),
            .init(a: (1, 1), b: (3, 0)), .init(a: (2, 1), b: (3, 0)),
        ]
        return net
    }

    @Test("hard line filters limit the lines; a filter that excludes every way finds nothing")
    func lineFilter() throws {
        let t = try Self.parallelNetwork().topology()
        let free = try #require(t.route(Self.query(t, [("s", 0)], [("t", 1)])))
        #expect(free.spans.map(\.line) == [0, 1, 3].map { UInt16($0) } && !free.unproven)
        // Hard filter forcing the longer line.
        let viaQ = try #require(t.route(Self.query(t, [("s", 0)], [("t", 1)], lines: ["s", "q", "t"])))
        #expect(viaQ.spans.map(\.line) == [0, 2, 3].map { UInt16($0) } && !viaQ.unproven && viaQ.lengthCm == 205_000)
        // A filter that excludes the whole way finds nothing: dropping the filter is the ladder's job, not one attempt's.
        #expect(t.route(Self.query(t, [("s", 0)], [("t", 1)], lines: ["p"])) == nil)
        #expect(t.route(Self.query(t, [("s", 0)], [("t", 1)], lines: ["nope"])) == nil)
    }

    @Test("institution filters are hard")
    func institutionFilter() throws {
        let t = try Self.parallelNetwork().topology()
        #expect(t.route(Self.query(t, [("s", 0)], [("t", 1)], institutions: [1, 2]))?.unproven == false)
        // Lines `t` (institution 2) are excluded: nothing, not even unproven.
        #expect(t.route(Self.query(t, [("s", 0)], [("t", 1)], institutions: [1])) == nil)
        #expect(t.route(Self.query(t, [("s", 0)], [("t", 1)], lines: ["s"], institutions: [1])) == nil)
    }

    @Test("a preferred line costs less, but only softly")
    func preferredLine() throws {
        let t = try Self.parallelNetwork().topology()
        let plain = try #require(t.route(Self.query(t, [("s", 0)], [("t", 1)])))
        #expect(plain.spans[1].line == t.lineIndex(forID: "p"))
        // q is 5% longer; every line outside the preferred set costs 9 times its length (the
        // production solver's 1 + 8), and the reported length is the real one.
        let preferred = try #require(t.route(Self.query(t, [("s", 0)], [("t", 1)], preferred: ["q"])))
        #expect(preferred.spans[1].line == t.lineIndex(forID: "q") && preferred.lengthCm == 205_000)
        // A preferred line 8 times as long still wins (the other rows are outside the set and cost 9x too).
        let longer = try Self.parallelNetwork(q: 800_000).topology()
        let wins = try #require(longer.route(Self.query(longer, [("s", 0)], [("t", 1)], preferred: ["q"])))
        #expect(wins.spans[1].line == longer.lineIndex(forID: "q"))
        // A preferred line 10 times as long does not.
        let far = try Self.parallelNetwork(q: 1_000_000).topology()
        let notWorth = try #require(far.route(Self.query(far, [("s", 0)], [("t", 1)], preferred: ["q"])))
        #expect(notWorth.spans[1].line == far.lineIndex(forID: "p"))
        // No preference at all: plain length.
        let plainFar = try #require(far.route(Self.query(far, [("s", 0)], [("t", 1)])))
        #expect(plainFar.spans[1].line == far.lineIndex(forID: "p"))
    }

    @Test("a non-preferred institution costs 181 times its length; an excluded institution is never used")
    func institutionPreferenceAndExclusion() throws {
        // p (institution 1) and q (institution 2) side by side; q is 50 times as long.
        var net = Net()
        net.lines = [
            .chain("s", ["S0", "S1"], lengths: [50_000], institution: 0),
            .chain("p", ["P0", "P1"], lengths: [100_000], institution: 1),
            .chain("q", ["Q0", "Q1"], lengths: [5_000_000], institution: 2),
            .chain("t", ["T0", "T1"], lengths: [50_000], institution: 0),
        ]
        net.links = [
            .init(a: (0, 1), b: (1, 0)), .init(a: (0, 1), b: (2, 0)),
            .init(a: (1, 1), b: (3, 0)), .init(a: (2, 1), b: (3, 0)),
        ]
        let t = try net.topology()
        func route(preferred: Set<UInt16> = [], excluded: Set<UInt16> = []) -> RailTopology.SectionPath? {
            var q = Self.query(t, [("s", 0)], [("t", 1)])
            q.preferredInstitutions = preferred; q.excludedInstitutions = excluded
            return t.route(q)
        }
        #expect(route()?.spans[1].line == t.lineIndex(forID: "p"))
        // Institution 0 (unknown) is never penalised; q wins at 50x as long, below the 181 factor.
        #expect(route(preferred: [2])?.spans[1].line == t.lineIndex(forID: "q"))
        #expect(route(preferred: [1])?.spans[1].line == t.lineIndex(forID: "p"))
        // Hard exclusion: p is excluded, q is the only way; excluding both leaves nothing, even unproven.
        #expect(route(excluded: [1])?.spans[1].line == t.lineIndex(forID: "q"))
        #expect(route(excluded: [1, 2]) == nil)
        // The hard filter: unknown (0) passes like an empty code does in the solver, others must be in the set.
        func hard(_ set: Set<UInt16>) -> RailTopology.SectionPath? {
            var q = Self.query(t, [("s", 0)], [("t", 1)]); q.institutions = set
            return t.route(q)
        }
        #expect(hard([1])?.spans[1].line == t.lineIndex(forID: "p"))
        #expect(hard([2])?.spans[1].line == t.lineIndex(forID: "q"))
        #expect(hard([3]) == nil)
    }

    @Test("equal-cost ties are decided by line id, not by the order of lines in the file")
    func tiesFollowLineIDsNotFileOrder() throws {
        func network(_ order: [String]) -> Net {
            let all: [String: Net.Line] = [
                "s": .chain("s", ["S0", "S1"], lengths: [50_000]),
                "p": .chain("p", ["P0", "P1"], lengths: [100_000]),
                "q": .chain("q", ["Q0", "Q1"], lengths: [100_000]),
                "t": .chain("t", ["T0", "T1"], lengths: [50_000]),
            ]
            var net = Net()
            net.lines = order.map { all[$0]! }
            func at(_ id: String, _ node: Int) -> (line: Int, node: Int) { (order.firstIndex(of: id)!, node) }
            net.links = [
                .init(a: at("s", 1), b: at("p", 0)), .init(a: at("s", 1), b: at("q", 0)),
                .init(a: at("p", 1), b: at("t", 0)), .init(a: at("q", 1), b: at("t", 0)),
            ]
            return net
        }
        for order in [["s", "p", "q", "t"], ["s", "q", "p", "t"], ["t", "q", "p", "s"]] {
            let t = try network(order).topology()
            let path = try #require(t.route(Self.query(t, [("s", 0)], [("t", 1)])))
            #expect(t.lineID(path.spans[1].line) == "p", "file order \(order)")
        }
    }

    @Test("withheld edges are not used unless asked for, and count for no distance")
    func withheldEdges() throws {
        var net = Self.network()
        net.lines[0].edges[1].flags = [.forward, .reverse, .withheld]
        let t = try net.topology()
        #expect(t.route(Self.query(t, [("x", 0)], [("x", 4)])) == nil)
        let path = try #require(t.route(Self.query(t, [("x", 0)], [("x", 4)]), includeWithheld: true))
        #expect(path.spans == [t.span("x", 0, 4)] && path.lengthCm == 30_000)
        #expect(t.containsWithheldEdge(path.spans[0]))
        // Routes that avoid the withheld edge are unaffected.
        let before = try #require(t.route(Self.query(t, [("x", 0)], [("x", 1)])))
        #expect(!t.containsWithheldEdge(before.spans[0]))
    }

    // MARK: Determinism and candidates

    @Test("equal-length alternatives resolve the same way every time, whatever the order of candidates")
    func deterministicTies() throws {
        let t = try Self.parallelNetwork(p: 100_000, q: 100_000).topology()
        let first = try #require(t.route(Self.query(t, [("s", 0)], [("t", 1)])))
        // Documented rule: equal cost and equal row changes keep the first path found in (cost, changes, node index) settle order, here line p.
        #expect(first.spans[1].line == t.lineIndex(forID: "p"))
        for _ in 0..<20 {
            let again = try #require(t.route(Self.query(t, [("s", 0)], [("t", 1)])))
            #expect(again.spans == first.spans && again.lengthCm == first.lengthCm)
        }
        let multi = Self.query(t, [("s", 0), ("p", 0), ("q", 1)], [("t", 1), ("t", 0)])
        var reversed = multi
        reversed.from.reverse(); reversed.to.reverse()
        let a = try #require(t.route(multi)), b = try #require(t.route(reversed))
        #expect(a.spans == b.spans && a.lengthCm == b.lengthCm)
    }

    @Test("equal lengths prefer the path with fewer row changes, even when another row settles first")
    func fewerRowChangesWinTies() throws {
        // Rows a and b run side by side with equal intervals and are linked at every station.
        // Row a has the lower node indices, so it settles first at every equal cost.
        var net = Net()
        let codes = ["R0", "R1", "R2", "R3"]
        net.lines = [.chain("a", codes.map { "a" + $0 }, lengths: [10_000, 10_000, 10_000]),
                     .chain("b", codes.map { "b" + $0 }, lengths: [10_000, 10_000, 10_000])]
        net.links = (0..<4).map { .init(a: (0, $0), b: (1, $0)) }
        let t = try net.topology()
        let ride = try #require(t.route(Self.query(t, [("b", 0)], [("b", 3)])))
        #expect(ride.spans == [t.span("b", 0, 3)] && ride.lengthCm == 30_000)
        let back = try #require(t.route(Self.query(t, [("a", 3)], [("a", 0)])))
        #expect(back.spans == [t.span("a", 3, 0)])
        // A real change is still taken when it is shorter or the only way.
        let across = try #require(t.route(Self.query(t, [("a", 0)], [("b", 3)])))
        #expect(across.lengthCm == 30_000 && across.spans.count == 1)
    }

    @Test("the router over the hand-built mini fixture bytes: dated link, loop wrap, withheld and one-way edges")
    func miniFixtureRoutes() throws {
        let t = try RailTopology(data: RailTopologyFormatTests.fixture())
        let a = "jp.test-a", b = "jp.test-b"
        // A01 to B03 over the 2010 junction, then the short way round the loop (backwards over its closing edge).
        let q = Self.query(t, [(a, 0)], [(b, 2)], day: "2015-06-01")
        let path = try #require(t.route(q))
        #expect(path.spans == [t.span(a, 0, 1), t.span(b, 0, 2, wraps: true)] && path.lengthCm == 150_000 + 30_000)
        // Undated queries cannot use line B (it ends in 2020).
        #expect(t.route(Self.query(t, [(a, 0)], [(b, 2)])) == nil)
        // Before the junction opened the same trip has no path.
        #expect(t.route(Self.query(t, [(a, 0)], [(b, 2)], day: "2005-01-01")) == nil)
        // The withheld one-way edge A02 to A03 is only used when asked for.
        let toThird = Self.query(t, [(a, 0)], [(a, 2)], day: "2015-06-01")
        #expect(t.route(toThird) == nil)
        let withheld = try #require(t.route(toThird, includeWithheld: true))
        #expect(withheld.spans == [t.span(a, 0, 2)] && withheld.lengthCm == 150_000)  // withheld edges count for no distance
        // The directed through service goes A03 to B03 at no length, and not back.
        let through = try #require(t.route(Self.query(t, [(a, 2)], [(b, 2)], day: "2015-06-01")))
        #expect(through.spans.isEmpty && through.lengthCm == 0)
        #expect(t.route(Self.query(t, [(b, 2)], [(a, 2)], day: "2015-06-01")) == nil)
    }

    @Test("several candidate nodes per end pick the best pair")
    func candidateSets() throws {
        let t = try Self.network().topology()
        // From a station on two lines (x1 and l0 are joined), to y.
        let path = try #require(t.route(Self.query(t, [("l", 2), ("x", 1)], [("y", 1), ("w", 2)])))
        #expect(path.spans == [t.span("x", 1, 2), t.span("y", 0, 1)] && path.lengthCm == 20_000)
        // A target on a line the query excludes by institution is ignored.
        let z = try #require(t.route(Self.query(t, [("x", 4)], [("z", 0), ("x", 3)])))
        #expect(z.spans == [t.span("x", 4, 3)])
    }

    @Test("a long through service chain keeps spans on their own lines")
    func spansNeverCrossLines() throws {
        let t = try Self.network().topology()
        let path = try #require(t.route(Self.query(t, [("x", 0)], [("w", 2)])))
        for span in path.spans { #expect(span.fromNode != span.toNode) }
        #expect(Set(path.spans.map(\.line)).count == path.spans.count)
    }

    // MARK: Production rules ported with the topology v2 data

    /// s -> (p | q) -> t as `parallelNetwork`, with operators on the middle lines.
    static func operatorNetwork(p: UInt32 = 100_000, q: UInt32 = 100_000, pOperator: String? = "OpP",
                                qOperator: String? = "OpQ") -> Net {
        var net = parallelNetwork(p: p, q: q)
        net.lines[1].operatorName = pOperator
        net.lines[2].operatorName = qOperator
        return net
    }

    @Test("a non-preferred operator costs 7 times its length; a line without an operator is never penalised")
    func preferredOperator() throws {
        // q is 6.5 times as long as p: below 7, so the preferred operator wins; at 7.5 times it does not.
        let near = try Self.operatorNetwork(q: 650_000).topology()
        func line(_ t: RailTopology, preferred: Set<String>) -> String? {
            t.route(Self.query(t, [("s", 0)], [("t", 1)], preferredOperators: preferred)).flatMap { t.lineID($0.spans[1].line) }
        }
        #expect(line(near, preferred: []) == "p")
        #expect(line(near, preferred: ["OpQ"]) == "q")
        #expect(line(near, preferred: ["OpP"]) == "p")
        let far = try Self.operatorNetwork(q: 750_000).topology()
        #expect(line(far, preferred: ["OpQ"]) == "p")
        // p has no operator name: it is not penalised even when another operator is preferred.
        let anonymous = try Self.operatorNetwork(q: 150_000, pOperator: nil).topology()
        #expect(line(anonymous, preferred: ["OpQ"]) == "p")
        // The reported length stays the real one.
        let real = try #require(near.route(Self.query(near, [("s", 0)], [("t", 1)], preferredOperators: ["OpQ"])))
        #expect(real.lengthCm == 50_000 + 650_000 + 50_000)
    }

    @Test("a line and an operator that are both non-preferred add up: factor 1 + 8 + 6")
    func lineAndOperatorFactorsAdd() throws {
        // p is non-preferred on both counts (factor 15), q on neither. q may be up to 15 times as long.
        let net = Self.operatorNetwork(p: 100_000, q: 1_400_000)
        let t = try net.topology()
        var query = Self.query(t, [("s", 0)], [("t", 1)], preferred: ["q", "s", "t"], preferredOperators: ["OpQ"])
        #expect(t.lineID(t.route(query)!.spans[1].line) == "q")
        let beyond = try Self.operatorNetwork(p: 100_000, q: 1_600_000).topology()
        query = Self.query(beyond, [("s", 0)], [("t", 1)], preferred: ["q", "s", "t"], preferredOperators: ["OpQ"])
        #expect(beyond.lineID(beyond.route(query)!.spans[1].line) == "p")
    }

    @Test("the operator is a hard filter when required; a line without an operator name never passes it")
    func requiredOperators() throws {
        let t = try Self.operatorNetwork().topology()
        // s and t have no operator name, so no path survives an operator filter that needs them.
        #expect(t.route(Self.query(t, [("s", 0)], [("t", 1)], operators: ["OpQ"])) == nil)
        var net = Self.operatorNetwork()
        net.lines[0].operatorName = "OpQ"; net.lines[3].operatorName = "OpQ"
        let named = try net.topology()
        let path = try #require(named.route(Self.query(named, [("s", 0)], [("t", 1)], operators: ["OpQ"])))
        #expect(path.spans.map { named.lineID($0.line)! } == ["s", "q", "t"])
        #expect(named.route(Self.query(named, [("s", 0)], [("t", 1)], operators: ["Nobody"])) == nil)
    }

    @Test("a non-preferred institution also pays 5,000 m for each source step of each edge")
    func institutionPaysPerSourceStep() throws {
        // p: 1 km, institution 1, 40 source steps. q: 1.2 km, institution 2, 1 step. Prefer institution 2:
        // p pays 181 x 1 km + 40 x 5 km = 381 km of cost, q pays nothing. With 1 step p would pay 186 km.
        func network(steps: UInt32, qLength: UInt32) -> Net {
            var net = Net()
            net.lines = [
                .chain("s", ["S0", "S1"], lengths: [1_000], institution: 0),
                .chain("p", ["P0", "P1"], lengths: [100_000], institution: 1, fineEdges: steps),
                .chain("q", ["Q0", "Q1"], lengths: [qLength], institution: 2),
                .chain("t", ["T0", "T1"], lengths: [1_000], institution: 0),
            ]
            net.links = [.init(a: (0, 1), b: (1, 0)), .init(a: (0, 1), b: (2, 0)),
                         .init(a: (1, 1), b: (3, 0)), .init(a: (2, 1), b: (3, 0))]
            return net
        }
        func pick(_ net: Net) throws -> String {
            let t = try net.topology()
            var q = Self.query(t, [("s", 0)], [("t", 1)])
            q.preferredInstitutions = [2]
            return t.lineID(try #require(t.route(q)).spans[1].line)!
        }
        // q is 1.9 times... in centimetres: p costs 100_000 x 181 + steps x 500_000.
        // One step: 18.6 M. q at 15 M wins; at 19 M p wins. Forty steps: p costs 38.1 M, so q at 19 M wins.
        #expect(try pick(network(steps: 1, qLength: 15_000_000 / 1)) == "q")
        #expect(try pick(network(steps: 1, qLength: 19_000_000)) == "p")
        #expect(try pick(network(steps: 40, qLength: 19_000_000)) == "q")
        // Unknown institution (0) pays nothing, however many steps.
        var unknown = network(steps: 40, qLength: 19_000_000)
        unknown.lines[1].institution = 0
        #expect(try pick(unknown) == "p")
    }

    /// Nodes of a one-line network placed by latitude (degrees north of 35), 1 degree = about 111.2 km.
    static func placed(_ id: String, _ lats: [Float], lengths: [UInt32]) -> Net.Line {
        .chain(id, lats.indices.map { "\(id.uppercased())\($0)" }, lengths: lengths,
               at: lats.map { (lon: 139, lat: 35 + $0) })
    }

    @Test("detour guard: a path over 3.8 x the straight line + 6 km (12 km at least) is refused and the next end node is tried")
    func detourGuard() throws {
        var net = Net()
        // From F (35.00) to T1 (5 km away) by 50 km of track, to T2 (40 km away) by 60 km of track.
        net.lines = [
            Self.placed("f", [0, 0.045], lengths: [5_000_000]),   // F0 .. T1 candidate F1: 50 km, straight 5 km
            Self.placed("g", [0, 0.36], lengths: [6_000_000]),    // G0 .. G1: 60 km, straight 40 km
        ]
        net.links = [.init(a: (0, 0), b: (1, 0))]
        let t = try net.topology()
        // To F1 alone: 50 km over a 5 km straight line; the limit is max(3.8 x 5 + 6, 12) = 25 km. Refused.
        #expect(t.route(Self.query(t, [("f", 0)], [("f", 1)])) == nil)
        // To F1 or G1: F1 settles first and is refused, the search goes on and G1 passes (limit 158 km).
        let path = try #require(t.route(Self.query(t, [("f", 0)], [("f", 1), ("g", 1)])))
        #expect(path.spans == [t.span("g", 0, 1)] && path.lengthCm == 6_000_000 && !path.unproven)
        // Ends closer than 1.5 km are never refused: a long way round is allowed.
        var near = Net()
        near.lines = [Self.placed("f", [0, 0.01], lengths: [5_000_000])]
        let n = try near.topology()
        #expect(n.route(Self.query(n, [("f", 0)], [("f", 1)]))?.lengthCm == 5_000_000)
        // The floor: a 12 km path over a 4 km straight line is fine (limit 21.2 km); 25 km is not.
        var floor = Net()
        floor.lines = [Self.placed("a", [0, 0.036], lengths: [1_200_000]), Self.placed("b", [0, 0.036], lengths: [2_500_000])]
        let f = try floor.topology()
        #expect(f.route(Self.query(f, [("a", 0)], [("a", 1)])) != nil)
        #expect(f.route(Self.query(f, [("b", 0)], [("b", 1)])) == nil)
    }

    @Test("same-name guard: a name-only end whose station is over twice as far as another same-name station is unproven, last resort")
    func sameNameGuard() throws {
        // Start F0 at 35.00. Two stations named alike: NEAR 30 km north, FAR 100 km north. The path to FAR is short
        // in kilometres of track (the file is hand-built), the path to NEAR is long.
        var net = Net()
        net.lines = [
            Self.placed("f", [0, 0.9], lengths: [1_000_000]),      // F0 .. FAR: 10 km of track, 100 km straight
            Self.placed("n", [0, 0.27], lengths: [4_000_000]),     // N0 .. NEAR: 40 km of track, 30 km straight
        ]
        net.links = [.init(a: (0, 0), b: (1, 0))]
        let t = try net.topology()
        func answer(nameOnly: Bool, targets: [(String, Int)]) -> RailTopology.SectionPath? {
            var q = Self.query(t, [("f", 0)], targets)
            q.toNameOnly = nameOnly
            return t.route(q)
        }
        // Not named by name only: the cheaper FAR wins, proven.
        let plain = try #require(answer(nameOnly: false, targets: [("f", 1), ("n", 1)]))
        #expect(plain.spans == [t.span("f", 0, 1)] && !plain.unproven)
        // Named by name only: FAR is 100 km straight, NEAR 30 km: 100 > 2 x 30 and beyond 20 km. NEAR is proven.
        let guarded = try #require(answer(nameOnly: true, targets: [("f", 1), ("n", 1)]))
        #expect(guarded.spans == [t.span("n", 0, 1)] && !guarded.unproven)
        // Only FAR is a candidate: nothing to compare, nothing rejected.
        let alone = try #require(answer(nameOnly: true, targets: [("f", 1)]))
        #expect(alone.spans == [t.span("f", 0, 1)] && !alone.unproven)
        // NEAR cannot be reached (its line is filtered out): FAR is kept as the last resort, unproven.
        var q = Self.query(t, [("f", 0)], [("f", 1), ("n", 1)], lines: ["f"])
        q.toNameOnly = true
        let lastResort = try #require(t.route(q))
        #expect(lastResort.spans == [t.span("f", 0, 1)] && lastResort.unproven)
        // Under 20 km straight the guard is silent: NEAR at 12 km, FAR at 24 km? FAR 24 > 2 x 12 but is it beyond 20 km: yes.
        // So test the other side of the threshold: FAR at 18 km, NEAR at 6 km.
        var small = Net()
        small.lines = [Self.placed("f", [0, 0.162], lengths: [1_000_000]), Self.placed("n", [0, 0.054], lengths: [4_000_000])]
        small.links = [.init(a: (0, 0), b: (1, 0))]
        let s = try small.topology()
        var sq = Self.query(s, [("f", 0)], [("f", 1), ("n", 1)])
        sq.toNameOnly = true
        #expect(s.route(sq)?.spans == [s.span("f", 0, 1)] && s.route(sq)?.unproven == false)
        // The ratio: FAR at 100 km against NEAR at 60 km is under twice as far: FAR stays.
        var ratio = Net()
        ratio.lines = [Self.placed("f", [0, 0.9], lengths: [1_000_000]), Self.placed("n", [0, 0.54], lengths: [4_000_000])]
        ratio.links = [.init(a: (0, 0), b: (1, 0))]
        let r = try ratio.topology()
        var rq = Self.query(r, [("f", 0)], [("f", 1), ("n", 1)])
        rq.toNameOnly = true
        #expect(r.route(rq)?.spans == [r.span("f", 0, 1)] && r.route(rq)?.unproven == false)
        // A start named by name only is checked the same way, from the other end: the best path to F0 starts at the
        // far station (100 km straight, the near one is 30 km), so it is refused and kept as the last resort. As in the
        // solver, each end node keeps its single best source: the near one is not tried for the same end node.
        var back = Self.query(t, [("f", 1), ("n", 1)], [("f", 0)])
        back.fromNameOnly = true
        let fromSide = try #require(t.route(back))
        #expect(fromSide.spans == [t.span("f", 1, 0)] && fromSide.unproven)
    }

    // MARK: Production mirror: target scoring and direction scope

    /// s -> p or q; the end station has one node on each of p and q, and the two are not joined.
    static func twoEndNodes(p: UInt32, q: UInt32) -> Net {
        var net = Net()
        net.lines = [
            .chain("s", ["S0", "S1"], lengths: [50_000]),
            .chain("p", ["P0", "P1"], lengths: [p]),
            .chain("q", ["Q0", "Q1"], lengths: [q]),
        ]
        net.links = [.init(a: (0, 1), b: (1, 0)), .init(a: (0, 1), b: (2, 0))]
        return net
    }

    @Test("a target is scored as production does: the line preference penalty counts twice, and can flip the end node")
    func targetScoreDoublesThePreferencePenalty() throws {
        func line(_ p: UInt32, _ q: UInt32, preferred: Set<String>) throws -> (String?, UInt64) {
            let t = try Self.twoEndNodes(p: p, q: q).topology()
            let path = try #require(t.route(Self.query(t, [("s", 0)], [("p", 1), ("q", 1)], preferred: preferred)))
            return (t.lineID(path.spans[1].line), path.lengthCm)
        }
        // p 100,000 cm, not preferred; q 1,200,000 cm, preferred. Dijkstra cost: p 900,000 against q 1,200,000, so p
        // settles first. Score: p 900,000 + 800,000 again = 1,700,000 against q 1,200,000: production keeps q.
        let flipped = try line(100_000, 1_200_000, preferred: ["q", "s"])
        #expect(flipped.0 == "q" && flipped.1 == 50_000 + 1_200_000)   // the reported length is the real one
        // Without a preference the plain minimum cost stays: p.
        #expect(try line(100_000, 1_200_000, preferred: []).0 == "p")
        // Past the doubled penalty (17 times) the cheaper-cost line wins again.
        #expect(try line(100_000, 1_800_000, preferred: ["q", "s"]).0 == "p")
        // Below the single penalty (9 times) q wins on cost already.
        #expect(try line(100_000, 800_000, preferred: ["q", "s"]).0 == "q")
    }

    @Test("direction is blocked only when both ends are given by code, and only between each end's first node on the line")
    func directionNeedsBothCodes() throws {
        var net = Net()
        net.lines = [.chain("w", ["W0", "W1", "W2"], lengths: [20_000, 10_000], flags: [.forward])]
        let t = try net.topology()
        // By code: W2 -> W0 goes against the one-way line: no path.
        #expect(t.route(Self.query(t, [("w", 2)], [("w", 0)])) == nil)
        // A name-only end has no code: production blocks nothing, the path is free.
        var nameOnly = Self.query(t, [("w", 2)], [("w", 0)])
        nameOnly.toNameOnly = true
        #expect(t.route(nameOnly)?.spans == [t.span("w", 2, 0)])
        var fromName = Self.query(t, [("w", 2)], [("w", 0)])
        fromName.fromNameOnly = true
        #expect(t.route(fromName)?.spans == [t.span("w", 2, 0)])
        // First node per line only: start candidates W0 and W2 towards W1. The solver looks at W0 -> W1 (forward, allowed)
        // and never at W2 -> W1 (the second node of the start), so W2 -> W1 (10,000) is not blocked and beats W0 -> W1 (20,000).
        let twice = try #require(t.route(Self.query(t, [("w", 0), ("w", 2)], [("w", 1)])))
        #expect(twice.spans == [t.span("w", 2, 1)] && twice.lengthCm == 10_000)
    }
}
