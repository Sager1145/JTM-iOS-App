import Foundation
import Testing
@testable import RailCore

/// Correctness against an independent shortest-path computation, and explicit
/// micro-benchmarks (median and worst case) on a Japan-sized synthetic network.
/// The user's requirement: route calculation must be fast; the plan's budget
/// for the whole add-trip planning step is one second.
@Suite("RailTopology router benchmarks")
struct RailTopologyRouterBenchmarkTests {
    typealias F = RailTopologyFormat
    typealias Net = TestNetwork

    /// Deterministic generator (the tests must not depend on the system's).
    struct LCG {
        var state: UInt64
        mutating func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
    }

    // MARK: Correctness against Bellman-Ford

    /// Shortest length over the same graph, computed the slow way from the
    /// description (not from the file): arcs both ways over every valid edge and every
    /// usable link, except the section-local direction exclusion: when start and end are
    /// on one line, the edges between them are removed if their flags forbid that way.
    static func oracleDistance(_ net: Net, from: (Int, Int), to: (Int, Int), day: UInt32?) -> UInt64? {
        var base: [Int] = []
        var total = 0
        for line in net.lines { base.append(total); total += line.nodes.count }
        var arcs: [(Int, Int, UInt64)] = []
        var blocked = Set<Int>()
        if from.0 == to.0, from.1 != to.1 {
            let needed: F.EdgeFlag = from.1 < to.1 ? .forward : .reverse
            for k in min(from.1, to.1)..<max(from.1, to.1) where !net.lines[from.0].edges[k].flags.contains(needed) { blocked.insert(k) }
        }
        for (li, line) in net.lines.enumerated() {
            let n = line.nodes.count
            for (k, edge) in line.edges.enumerated() where F.isValid(on: day, from: edge.validFrom, to: edge.validTo) {
                if li == from.0 && blocked.contains(k) { continue }
                let a = base[li] + k, b = base[li] + (k + 1) % n
                arcs.append((a, b, UInt64(edge.length)))
                arcs.append((b, a, UInt64(edge.length)))
            }
        }
        for link in net.links where F.isValid(on: day, from: link.validFrom, to: link.validTo) {
            let a = base[link.a.line] + link.a.node, b = base[link.b.line] + link.b.node
            arcs.append((a, b, 0))
            if !link.directed { arcs.append((b, a, 0)) }
        }
        var dist = [UInt64?](repeating: nil, count: total)
        dist[base[from.0] + from.1] = 0
        var changed = true
        while changed {
            changed = false
            for (a, b, w) in arcs {
                guard let da = dist[a] else { continue }
                if dist[b] == nil || da + w < dist[b]! { dist[b] = da + w; changed = true }
            }
        }
        return dist[base[to.0] + to.1]
    }

    @Test("router lengths equal Bellman-Ford on random networks with loops, one-way edges, dated rows and directed links")
    func matchesBellmanFord() throws {
        var rng = LCG(state: 20_261_111)
        let days: [UInt32?] = [nil, F.dayNumber(ofISODate: "2005-06-01"), F.dayNumber(ofISODate: "2015-06-01"), F.dayNumber(ofISODate: "2025-06-01")]
        let dates = [0, F.dayNumber(ofISODate: "2000-01-01")!, F.dayNumber(ofISODate: "2010-01-01")!, F.dayNumber(ofISODate: "2020-01-01")!]
        var compared = 0, reachable = 0
        for _ in 0..<12 {
            var net = Net()
            for li in 0..<14 {
                let n = 3 + rng.next(8)
                let loop = rng.next(4) == 0
                let edgeCount = loop ? n : n - 1
                var line = Net.Line.chain("l\(li)", (0..<n).map { "l\(li)n\($0)" },
                                          lengths: (0..<edgeCount).map { _ in UInt32(1_000 + rng.next(9_000)) }, loop: loop)
                for e in 0..<edgeCount {
                    switch rng.next(10) {
                    case 0: line.edges[e].flags = [.forward]
                    case 1: line.edges[e].flags = [.reverse]
                    default: break
                    }
                    if rng.next(6) == 0 { line.edges[e].validFrom = UInt32(dates[rng.next(3)]) }
                    if rng.next(8) == 0 { line.edges[e].validTo = UInt32(dates[1 + rng.next(3)]) }
                }
                net.lines.append(line)
            }
            for _ in 0..<22 {
                let a = rng.next(14)
                var b = rng.next(14)
                if b == a { b = (b + 1) % 14 }
                var link = Net.Link(a: (a, rng.next(net.lines[a].nodes.count)), b: (b, rng.next(net.lines[b].nodes.count)))
                link.directed = rng.next(4) == 0
                if rng.next(5) == 0 { link.validFrom = UInt32(dates[1 + rng.next(2)]) }
                if rng.next(6) == 0 { link.validTo = UInt32(dates[2 + rng.next(2)]) }
                net.links.append(link)
            }
            let t = try net.topology()
            for _ in 0..<120 {
                let from = (rng.next(14), 0), to = (rng.next(14), 0)
                let f = (from.0, rng.next(net.lines[from.0].nodes.count)), g = (to.0, rng.next(net.lines[to.0].nodes.count))
                let day = days[rng.next(days.count)]
                let expected = Self.oracleDistance(net, from: f, to: g, day: day)
                var query = RailTopology.SectionQuery(from: [.init(line: UInt16(f.0), node: UInt16(f.1))],
                                                      to: [.init(line: UInt16(g.0), node: UInt16(g.1))], day: day)
                query.lineIDs = []
                let path = t.route(query)
                #expect(path?.lengthCm == expected, "\(f) -> \(g) on \(String(describing: day))")
                compared += 1
                if expected != nil { reachable += 1 }
                if let path {
                    // The spans themselves must walk from the source to the target.
                    #expect(path.spans.allSatisfy { $0.fromNode != $0.toNode })
                }
            }
        }
        #expect(compared == 1_440 && reachable > 200, "the generator must exercise reachable and unreachable pairs (\(reachable) reachable)")
    }

    // MARK: Japan-sized network

    /// 40 trunks of 300 nodes, 700 branches of 20, one isolated line: about 26,000 nodes and 1,000 links.
    static func japanSized() -> (net: Net, trunks: Int, branches: Int) {
        var rng = LCG(state: 7)
        var net = Net()
        let trunks = 40, branches = 700
        for i in 0..<trunks {
            net.lines.append(.chain("t\(i)", (0..<300).map { "t\(i)n\($0)" }, lengths: [UInt32](repeating: 500_000, count: 299)))
        }
        for k in 0..<branches {
            net.lines.append(.chain("b\(k)", (0..<20).map { "b\(k)n\($0)" }, lengths: [UInt32](repeating: 300_000, count: 19)))
        }
        net.lines.append(.chain("iso", (0..<10).map { "isn\($0)" }, lengths: [UInt32](repeating: 100_000, count: 9)))
        for i in 0..<(trunks - 1) {
            for k in 0..<6 {
                let o = (i * 37 + k * 47) % 300
                net.links.append(.init(a: (i, o), b: (i + 1, (o + 13 * k) % 300)))
            }
        }
        for k in 0..<branches {
            net.links.append(.init(a: (trunks + k, 0), b: (k % trunks, (k * 53) % 300)))
            if k % 5 == 0 {
                net.links.append(.init(a: (trunks + k, 19), b: ((k * 7 + 3) % trunks, (k * 91 + 7) % 300)))
            }
        }
        _ = rng.next(2)
        return (net, trunks, branches)
    }

    struct Timing {
        var name: String
        var millis: [Double]
        var median: Double { millis.sorted()[millis.count / 2] }
        var worst: Double { millis.max() ?? 0 }
    }

    static func time(_ name: String, runs: Int = 15, _ body: () -> Void) -> Timing {
        body()  // warm up caches and the allocator
        var samples: [Double] = []
        for _ in 0..<runs {
            let start = ContinuousClock.now
            body()
            let d = start.duration(to: .now)
            samples.append(Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15)
        }
        return Timing(name: name, millis: samples)
    }

    /// Wall-clock budgets depend on the machine's load, so the timing run is opt-in:
    /// `JTM_ROUTER_BENCHMARK=1 swift test --filter routeTimings`.
    static let benchmarkEnabled = ProcessInfo.processInfo.environment["JTM_ROUTER_BENCHMARK"] == "1"

    @Test("route calculation is fast on a Japan-sized network: median and worst case per scenario",
          .enabled(if: RailTopologyRouterBenchmarkTests.benchmarkEnabled))
    func routeTimings() throws {
        let (net, trunks, branches) = Self.japanSized()
        let data = net.encode()
        let topology = try RailTopology(data: data)
        let t = topology
        func ref(_ line: Int, _ node: Int) -> RailTopology.NodeRef { .init(line: UInt16(line), node: UInt16(node)) }
        let trunkIDs = Set((0..<trunks).map { "t\($0)" })
        let day = F.dayNumber(ofISODate: "2024-06-01")

        var results: [Timing] = []
        func scenario(_ name: String, _ query: RailTopology.SectionQuery, expectPath: Bool = true, expectUnproven: Bool = false) {
            var found: RailTopology.SectionPath?
            results.append(Self.time(name) { found = t.route(query) })
            #expect((found != nil) == expectPath, "\(name)")
            if let found { #expect(found.unproven == expectUnproven, "\(name)") }
        }
        scenario("short, one line (10 stations)", .init(from: [ref(5, 100)], to: [ref(5, 110)]))
        scenario("cross-country trunk 0 start to trunk 39 end", .init(from: [ref(0, 0)], to: [ref(trunks - 1, 299)]))
        scenario("cross-country, dated", .init(from: [ref(0, 0)], to: [ref(trunks - 1, 299)], day: day))
        scenario("branch end to branch end", .init(from: [ref(trunks, 19)], to: [ref(trunks + branches - 1, 19)]))
        scenario("three candidates each end", .init(
            from: [ref(0, 0), ref(1, 5), ref(2, 9)], to: [ref(trunks - 1, 299), ref(trunks - 2, 290), ref(trunks + 400, 19)]))
        scenario("cross-country, trunk filter and preference", .init(
            from: [ref(0, 0)], to: [ref(trunks - 1, 299)], lineIDs: trunkIDs, preferredLineIDs: ["t10", "t11", "t12"]))
        scenario("unreachable target under a filter (fallback exhausts the network)",
                 .init(from: [ref(0, 0)], to: [ref(trunks + branches, 9)], lineIDs: ["t0"]), expectPath: false)
        scenario("unreachable target, no filter (exhausts the network)",
                 .init(from: [ref(0, 0)], to: [ref(trunks + branches, 9)]), expectPath: false)
        scenario("filter excludes the way: proven search fails, unfiltered fallback succeeds",
                 .init(from: [ref(0, 0)], to: [ref(trunks - 1, 299)], lineIDs: ["t0", "t1"]), expectUnproven: true)

        // A via trip: two legs routed in sequence, the whole plan step's routing.
        var viaOK = false
        results.append(Self.time("via: three stations, two legs") {
            let a = t.route(.init(from: [ref(5, 10)], to: [ref(20, 150)]))
            let b = t.route(.init(from: [ref(20, 150)], to: [ref(trunks + 333, 19)]))
            viaOK = a != nil && b != nil
        })
        #expect(viaOK)

        // A long multi-section trip with random ends anywhere in the network, the worst realistic plan step.
        var planOK = true
        results.append(Self.time("12 random cross-network sections in a row", runs: 5) {
            var rng = LCG(state: 99)
            for _ in 0..<12 {
                let a = rng.next(trunks + branches), b = rng.next(trunks + branches)
                let p = t.route(.init(from: [ref(a, rng.next(a < trunks ? 300 : 20))], to: [ref(b, rng.next(b < trunks ? 300 : 20))]))
                if p == nil { planOK = false }
            }
        })
        #expect(planOK)

        // Reader operations.
        let open = Self.time("open (validate + link index)", runs: 10) { _ = try? RailTopology(data: data) }
        results.append(open)
        let keys = (0..<200).map { "t\($0 % trunks)n\(($0 * 7) % 300)" }
        results.append(Self.time("200 stop lookups") { for k in keys { _ = t.nodes(forStop: k) } })
        let trunkCodes = (0..<299).map { "t7@t7n\($0):t7n\($0 + 1)" }
        var codesOK = false
        results.append(Self.time("299 authored interval codes on one trunk") {
            codesOK = t.spans(forIntervalCodes: trunkCodes) == [t.span("t7", 0, 299)]
        })
        #expect(codesOK)
        let long = try #require(t.route(.init(from: [ref(0, 0)], to: [ref(trunks - 1, 299)])))
        results.append(Self.time("stroke refs for the cross-country path") {
            for span in long.spans { _ = t.strokeRefs(of: span, detail: .full) }
        })

        print("\n=== RailTopology router timings (\(t.nodeTotal) nodes, \(t.linkCount) links, \(data.count) bytes) ===")
        for r in results {
            print(String(format: "%-72@ median %8.3f ms   worst %8.3f ms", r.name as NSString, r.median, r.worst))
        }
        print("cross-country path: \(long.spans.count) spans, \(long.lengthCm / 100_000) km")

        // The plan budgets one second for the whole add-trip planning step. Every scenario, including
        // twelve random sections in a row, must stay inside it in a Debug build on a loaded machine.
        for r in results where r.name.hasPrefix("open") == false {
            #expect(r.median < 1_000, "\(r.name) median \(r.median) ms")
        }
        #expect(open.median < 250)
    }
}
