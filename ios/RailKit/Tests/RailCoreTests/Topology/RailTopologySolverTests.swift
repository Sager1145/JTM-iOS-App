import Foundation
import Testing
@testable import RailCore

/// The attempt ladder (`RailTopology.solve`) against the production solver's
/// `buildSegmentRouteSolveAttempts` and `solveSection` ordering, on small hand-built topologies.
@Suite("RailTopology solver ladder")
struct RailTopologySolverTests {
    typealias Net = TestNetwork
    typealias Plan = RailTopology.SectionPlan

    static func plan(_ t: RailTopology, _ from: [(String, Int)], _ to: [(String, Int)]) -> Plan {
        Plan(from: from.map { t.ref($0.0, $0.1) }, to: to.map { t.ref($0.0, $0.1) })
    }

    static func names(_ plan: Plan) -> [String] { RailTopology.attempts(for: plan).map(\.name) }

    // MARK: The attempt list, in the solver's order

    @Test("explicit lines give two attempts and nothing else: home institution, then soft")
    func explicitLines() {
        var plan = Plan(from: [], to: [], explicitLineIDs: ["a"], explicitOperators: ["op"], commonLineIDs: ["c"], commonOperators: ["o"])
        #expect(Self.names(plan) == ["explicit lines, home institution", "explicit lines, soft institution"])
        let attempts = RailTopology.attempts(for: plan)
        #expect(attempts.map(\.home) == [true, false])
        #expect(attempts.allSatisfy { $0.lines == ["a"] && $0.operators == ["op"] })
        // Explicit lines win over explicit operators.
        plan.explicitOperators = []
        #expect(RailTopology.attempts(for: plan).count == 2)
    }

    @Test("explicit operators try the common lines under them first when there are any")
    func explicitOperators() {
        var plan = Plan(from: [], to: [], explicitOperators: ["op"], commonLineIDs: ["c"])
        #expect(Self.names(plan) == [
            "common lines under explicit operators, home institution", "common lines under explicit operators, soft institution",
            "explicit operators, home institution", "explicit operators, soft institution"])
        plan.commonLineIDs = []
        #expect(Self.names(plan) == ["explicit operators, home institution", "explicit operators, soft institution"])
        #expect(RailTopology.attempts(for: plan).allSatisfy { $0.lines.isEmpty && $0.operators == ["op"] })
    }

    @Test("with nothing explicit the ladder runs common lines and operators, soft hints, soft fallback, unbiased")
    func commonLadder() {
        var plan = Plan(from: [], to: [], commonLineIDs: ["c"], commonOperators: ["o"])
        #expect(Self.names(plan) == [
            "common lines and operators, home institution", "common lines, home institution", "common operators, home institution",
            "home institution, soft line and operator hints", "common lines, other operators", "soft fallback", "institution only, unbiased"])
        let attempts = RailTopology.attempts(for: plan)
        #expect(attempts.map(\.home) == [true, true, true, true, false, false, true])
        #expect(attempts.map(\.clearsPreferences) == [false, false, false, false, false, false, true])
        plan.commonOperators = []
        #expect(Self.names(plan) == [
            "common lines, home institution", "home institution, soft line and operator hints", "common lines, other operators",
            "soft fallback", "institution only, unbiased"])
        plan.commonLineIDs = []
        #expect(Self.names(plan) == ["home institution, soft line and operator hints", "soft fallback", "institution only, unbiased"])
    }

    // MARK: What each rung does

    /// s -> (p | q) -> t. p (institution `pInst`) is shorter than q (institution `qInst`).
    static func twoWays(p: UInt32 = 100_000, q: UInt32 = 300_000, pInst: UInt16 = 1, qInst: UInt16 = 2) -> Net {
        var net = Net()
        net.lines = [
            .chain("s", ["S0", "S1"], lengths: [10_000], institution: 0),
            .chain("p", ["P0", "P1"], lengths: [p], institution: pInst),
            .chain("q", ["Q0", "Q1"], lengths: [q], institution: qInst),
            .chain("t", ["T0", "T1"], lengths: [10_000], institution: 0),
        ]
        net.links = [.init(a: (0, 1), b: (1, 0)), .init(a: (0, 1), b: (2, 0)),
                     .init(a: (1, 1), b: (3, 0)), .init(a: (2, 1), b: (3, 0))]
        return net
    }

    static func line(_ t: RailTopology, _ path: RailTopology.SectionPath?) -> String? {
        path.flatMap { $0.spans.count > 1 ? t.lineID($0.spans[1].line) : nil }
    }

    @Test("the home institution is tried first: a much longer line of the trip's institution beats a shorter one of another")
    func homeBeforeSoft() throws {
        // q is 200 times as long as p. Soft pricing alone would take p (181 x its length plus the per-step charge is still
        // cheaper than q); the home rung is a hard filter and takes q.
        let t = try Self.twoWays(q: 20_000_000).topology()
        var plan = Self.plan(t, [("s", 0)], [("t", 1)])
        plan.allowedInstitutions = [2]
        #expect(Self.line(t, t.solve(plan)) == "q")
        // The soft rung on its own would choose p.
        let soft = try #require(t.route(t.query(for: .init(name: "soft", lines: [], operators: [], home: false), in: plan)))
        #expect(t.lineID(soft.spans[1].line) == "p")
        // Allowing both, plain length picks p.
        plan.allowedInstitutions = [1, 2]
        #expect(Self.line(t, t.solve(plan)) == "p")
    }

    @Test("when no way keeps to the home institution the soft attempt pays the penalty and goes through")
    func softAfterHome() throws {
        // Only p connects, and p is institution 1; the trip allows 2.
        var net = Self.twoWays()
        net.links.removeAll { $0.a.line == 0 && $0.b.line == 2 }
        let t = try net.topology()
        var plan = Self.plan(t, [("s", 0)], [("t", 1)])
        plan.allowedInstitutions = [2]
        let path = try #require(t.solve(plan))
        #expect(Self.line(t, path) == "p" && !path.unproven)
        // In hard mode the filter holds in every attempt and nothing is found.
        plan.hardInstitutionMode = true
        #expect(t.solve(plan) == nil)
    }

    @Test("a common line is required before the cheaper line outside it")
    func commonLineFirst() throws {
        let t = try Self.twoWays(q: 105_000, pInst: 1, qInst: 1).topology()
        var plan = Self.plan(t, [("s", 0)], [("t", 1)])
        plan.allowedInstitutions = [1, 2]
        #expect(Self.line(t, t.solve(plan)) == "p")
        plan.commonLineIDs = ["s", "q", "t"]
        #expect(Self.line(t, t.solve(plan)) == "q")
        // A common set that cannot connect the ends is dropped by the next rungs, not fatal.
        plan.commonLineIDs = ["nope"]
        #expect(Self.line(t, t.solve(plan)) == "p")
    }

    @Test("explicit lines are never dropped: a section naming a line that cannot connect has no answer")
    func explicitLinesAreKept() throws {
        let t = try Self.twoWays().topology()
        var plan = Self.plan(t, [("s", 0)], [("t", 1)])
        plan.explicitLineIDs = ["s", "q", "t"]
        #expect(Self.line(t, t.solve(plan)) == "q")
        plan.explicitLineIDs = ["s", "nope", "t"]
        #expect(t.solve(plan) == nil)
    }

    @Test("preferences steer the soft rungs and are cleared only by the last one")
    func preferencesSteer() throws {
        let t = try Self.twoWays(q: 105_000, pInst: 1, qInst: 1).topology()
        var plan = Self.plan(t, [("s", 0)], [("t", 1)])
        plan.preferredLineIDs = ["s", "q", "t"]
        #expect(Self.line(t, t.solve(plan)) == "q")
        let operatorNet = try { () -> RailTopology in
            var net = Self.twoWays(q: 105_000, pInst: 1, qInst: 1)
            net.lines[1].operatorName = "OpP"; net.lines[2].operatorName = "OpQ"
            return try net.topology()
        }()
        var byOperator = Self.plan(operatorNet, [("s", 0)], [("t", 1)])
        byOperator.preferredOperators = ["OpQ"]
        #expect(Self.line(operatorNet, operatorNet.solve(byOperator)) == "q")
        // The last rung is what is left when the earlier ones found nothing: preferences are cleared there.
        let attempts = RailTopology.attempts(for: plan)
        let last = operatorNet.query(for: attempts.last!, in: byOperator)
        #expect(last.preferredOperators.isEmpty && last.preferredLineIDs.isEmpty)
        let first = operatorNet.query(for: attempts[0], in: byOperator)
        #expect(first.preferredOperators == ["OpQ"])
    }

    @Test("institution preference maps to a hard filter on a home rung and a soft penalty on a soft one")
    func institutionMapping() throws {
        let t = try Self.twoWays().topology()
        var plan = Self.plan(t, [("s", 0)], [("t", 1)])
        plan.allowedInstitutions = [2]
        let home = t.query(for: .init(name: "h", lines: [], operators: [], home: true), in: plan)
        #expect(home.institutions == [2] && home.preferredInstitutions.isEmpty)
        let soft = t.query(for: .init(name: "s", lines: [], operators: [], home: false), in: plan)
        #expect(soft.institutions.isEmpty && soft.preferredInstitutions == [2])
        plan.hardInstitutionMode = true
        let hard = t.query(for: .init(name: "s", lines: [], operators: [], home: false), in: plan)
        #expect(hard.institutions == [2] && hard.preferredInstitutions.isEmpty)
        plan.excludedInstitutions = [1]
        #expect(t.query(for: .init(name: "s", lines: [], operators: [], home: false), in: plan).excludedInstitutions == [1])
    }

    @Test("the unpenalised fallback finds the way the penalty and the detour guard ruled out, in soft mode only")
    func unpenalisedFallback() throws {
        // Ends 5 km apart, joined by u. p (institution 1) is 6 km of track. q (institution 2) is 60 km, over the detour
        // limit of 25 km. The trip allows institution 2: the home rung can only use q, the soft rung's penalty on p makes q
        // the cheaper way, and the guard refuses q both times (the one end node settles once). Only the fallback, with no
        // penalty, takes p.
        var net = Net()
        net.lines = [
            RailTopologyRouterTests.placed("s", [0, 0], lengths: [100]),
            RailTopologyRouterTests.placed("p", [0, 0.045], lengths: [600_000]),
            RailTopologyRouterTests.placed("q", [0, 0.045], lengths: [6_000_000]),
            RailTopologyRouterTests.placed("u", [0.045, 0.045], lengths: [100]),
        ]
        net.lines[1].institution = 1
        net.lines[2].institution = 2
        net.links = [.init(a: (0, 1), b: (1, 0)), .init(a: (0, 1), b: (2, 0)),
                     .init(a: (1, 1), b: (3, 0)), .init(a: (2, 1), b: (3, 0))]
        let t = try net.topology()
        var plan = Plan(from: [t.ref("s", 0)], to: [t.ref("u", 1)])
        plan.allowedInstitutions = [2]
        let path = try #require(t.solve(plan))
        #expect(path.spans.map { t.lineID($0.line)! } == ["s", "p", "u"] && !path.unproven)
        // Every rung before the fallback fails.
        for attempt in RailTopology.attempts(for: plan) { #expect(t.route(t.query(for: attempt, in: plan)) == nil, "\(attempt.name)") }
        // Hard mode has no fallback: the filter holds, q is the only way, and it is refused.
        plan.hardInstitutionMode = true
        #expect(t.solve(plan) == nil)
        // An explicit line is kept by the fallback: asking for q never gets p.
        plan.hardInstitutionMode = false
        plan.explicitLineIDs = ["s", "q", "u"]
        #expect(t.solve(plan) == nil)
    }

    @Test("the first guard-rejected path is the answer of last resort, unproven, when nothing else is found")
    func guardedLastResort() throws {
        var net = Net()
        net.lines = [
            RailTopologyRouterTests.placed("f", [0, 0.9], lengths: [1_000_000]),
            RailTopologyRouterTests.placed("n", [0, 0.27], lengths: [4_000_000]),
        ]
        net.links = [.init(a: (0, 0), b: (1, 0))]
        let t = try net.topology()
        var plan = Plan(from: [t.ref("f", 0)], to: [t.ref("f", 1)], toNameOnly: true)
        // Only the far station is a candidate and it is the only same-name one: nothing to compare, proven.
        #expect(t.solve(plan)?.unproven == false)
        // The near station is a candidate but excluded by an explicit line: the far one is rejected everywhere.
        plan.to = [t.ref("f", 1), t.ref("n", 1)]
        plan.explicitLineIDs = ["f"]
        let path = try #require(t.solve(plan))
        #expect(path.unproven && path.spans == [t.span("f", 0, 1)])
    }
}
