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
                      lines: Set<String> = [], institutions: Set<UInt16> = [], preferred: Set<String> = []) -> RailTopology.SectionQuery {
        RailTopology.SectionQuery(
            from: from.map { t.ref($0.0, $0.1) }, to: to.map { t.ref($0.0, $0.1) },
            day: day.map(Self.day), lineIDs: lines, institutions: institutions, preferredLineIDs: preferred)
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

    @Test("one-way edges are travelled in their direction only, on chains and on loops")
    func oneWay() throws {
        var net = Self.network()
        net.lines.append(.chain("r", ["R0", "R1", "R2"], lengths: [10_000, 10_000], flags: [.reverse]))
        net.lines.append(.chain("f", ["F0", "F1", "F2", "F3"], lengths: [10_000, 10_000, 10_000, 10_000], loop: true, flags: [.forward]))
        let t = try net.topology()
        #expect(t.route(Self.query(t, [("w", 0)], [("w", 2)])) != nil)
        #expect(t.route(Self.query(t, [("w", 2)], [("w", 0)])) == nil)
        #expect(t.route(Self.query(t, [("r", 2)], [("r", 0)]))?.spans == [t.span("r", 2, 0)])
        #expect(t.route(Self.query(t, [("r", 0)], [("r", 2)])) == nil)
        // A forward-only loop must go all the way round to get back to the previous stop.
        let back = try #require(t.route(Self.query(t, [("f", 1)], [("f", 0)])))
        #expect(back.spans == [t.span("f", 1, 0, wraps: true)] && back.lengthCm == 30_000)
        let ahead = try #require(t.route(Self.query(t, [("f", 0)], [("f", 1)])))
        #expect(ahead.spans == [t.span("f", 0, 1)])
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

    @Test("hard line filters limit the lines; failing them falls back to an unproven path")
    func lineFilterAndFallback() throws {
        let t = try Self.parallelNetwork().topology()
        let free = try #require(t.route(Self.query(t, [("s", 0)], [("t", 1)])))
        #expect(free.spans.map(\.line) == [0, 1, 3].map { UInt16($0) } && !free.unproven)
        // Hard filter forcing the longer line.
        let viaQ = try #require(t.route(Self.query(t, [("s", 0)], [("t", 1)], lines: ["s", "q", "t"])))
        #expect(viaQ.spans.map(\.line) == [0, 2, 3].map { UInt16($0) } && !viaQ.unproven && viaQ.lengthCm == 205_000)
        // A filter that excludes the whole way finds nothing proven: same search without the line filter.
        let unproven = try #require(t.route(Self.query(t, [("s", 0)], [("t", 1)], lines: ["p"])))
        #expect(unproven.unproven && unproven.spans.map(\.line) == [0, 1, 3].map { UInt16($0) })
        // A line filter naming nothing known is the same.
        #expect(t.route(Self.query(t, [("s", 0)], [("t", 1)], lines: ["nope"]))?.unproven == true)
    }

    @Test("institution filters are hard and survive the fallback")
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
        // q is 5% longer, a 20% discount wins it, and the reported length is the real one.
        let preferred = try #require(t.route(Self.query(t, [("s", 0)], [("t", 1)], preferred: ["q"])))
        #expect(preferred.spans[1].line == t.lineIndex(forID: "q") && preferred.lengthCm == 205_000)
        // A much longer preferred line does not win.
        let far = try Self.parallelNetwork(q: 160_000).topology()
        let notWorth = try #require(far.route(Self.query(far, [("s", 0)], [("t", 1)], preferred: ["q"])))
        #expect(notWorth.spans[1].line == far.lineIndex(forID: "p"))
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
}
