import Foundation
import Testing
@_spi(Testing) @testable import RailCore

/// Shadow comparison of the production solver and `RailTopologyRouter` (nothing here is
/// wired into the app). Opt-in: `JTM_TOPOLOGY_SHADOW=1`.
///
/// "Old" is the frozen ride oracle (`Resources/ride-oracle.json`, 287 trips, the output of
/// the production solver). "New" is the router on the real Japan topology file, asked the
/// same section question: the section's endpoints, the ride's date, and the section's and
/// the trip's line, institution and preference constraints, after the app's own canonical
/// input step (registry upgrade, timetable evidence), so the sections are the ones the
/// old solver was given. The old solver is not re-run; the oracle is its recorded answer.
///
/// Environment:
/// - `JTM_TOPOLOGY_JP`: path to a `jp.topology.bin` built by `build-display-network.py`
///   (required; the file is a build product, not a source file);
/// - `JTM_TOPOLOGY_SHADOW_OUT`: where to write the difference list (Markdown), default: print only.
///
///     JTM_TOPOLOGY_SHADOW=1 JTM_TOPOLOGY_JP=/path/jp.topology.bin \
///       swift test --package-path ios/RailKit -c release -Xswiftc -enable-testing \
///       --filter TopologyShadowComparison
@Suite("Topology shadow comparison", .serialized)
struct TopologyShadowComparisonTests {
    typealias Oracle = RegressionGuardRideOracle
    typealias Census = UserPathCensusTests
    typealias F = RailTopologyFormat

    static let enabled = ProcessInfo.processInfo.environment["JTM_TOPOLOGY_SHADOW"] == "1"

    // MARK: Model

    enum Category: String, CaseIterable {
        case same = "same lines, same km"
        case sameLinesKmDiffers = "same lines, km differs"
        case different = "different lines"
        case oldHasNoLineIDs = "old answer carries no line ids (km compared only)"
        case oldGap = "old solver drew no proven track here"
        case routerNoPath = "router found no path"
        case routerEmptyPath = "router: start is the destination (empty path)"
        case endpointNotInTopology = "endpoint not found in the topology"
        case intervalCodesMatch = "authored interval codes: same lines"
        case intervalCodesDiffer = "authored interval codes: different lines"
        case intervalCodesUnresolved = "authored interval codes: topology could not resolve them"
    }

    struct Answer {
        var lines: [String]
        var km: Double
    }

    /// The old answer's official interval codes resolved on the topology.
    struct IntervalCheck {
        var sections = 0
        var resolved = 0
        var sameLines = 0
        var different: [String] = []
        var unresolved: [String] = []
    }

    struct Row {
        var ride: String
        var store: String
        var section: Int
        var from: String
        var to: String
        var category: Category
        var old: Answer?
        var new: Answer?
        var unproven = false
        var explanation: String = ""
        var straightKm: Double?
        /// The router's spans, one per line: line, station codes at both ends, km.
        var spanDetail = ""
    }

    // MARK: Helpers

    static func collapsed(_ values: [String]) -> [String] {
        values.reduce(into: []) { if $0.last != $1 { $0.append($1) } }
    }

    static func answer(of spans: [RailTopology.Span], in topology: RailTopology) -> Answer {
        Answer(
            lines: collapsed(spans.compactMap { topology.lineID($0.line) }),
            km: Double(spans.reduce(0) { $0 + topology.lengthCm(of: $1) }) / 100_000)
    }

    static func spanDetail(_ spans: [RailTopology.Span], in topology: RailTopology) -> String {
        spans.map { span in
            let id = (topology.lineID(span.line) ?? "?").replacingOccurrences(of: "jp-", with: "")
            let from = topology.stationCode(of: .init(line: span.line, node: span.fromNode)) ?? "?"
            let to = topology.stationCode(of: .init(line: span.line, node: span.toNode)) ?? "?"
            return String(format: "%@ %@ to %@ %.1f km", id, from, to, Double(topology.lengthCm(of: span)) / 100_000)
        }.joined(separator: "; ")
    }

    static func describe(_ answer: Answer?) -> String {
        guard let answer else { return "none" }
        let names = answer.lines.map { $0.replacingOccurrences(of: "jp-", with: "") }
        return String(format: "%@ (%.1f km)", names.isEmpty ? "no lines" : names.joined(separator: " > "), answer.km)
    }

    static func kmClose(_ a: Double, _ b: Double) -> Bool { abs(a - b) <= max(0.3, 0.01 * max(a, b)) }

    /// What a section asks the ladder, built the way the production solver builds its hints
    /// (`RouteSolver.buildSegmentRouteHints`): explicit lines and operators from the section,
    /// the trip's preferences, and the lines and operators both ends have in common.
    struct Question {
        var plan: RailTopology.SectionPlan
        var intervalCodes: [String]
        var fromNodes: [RailTopology.NodeRef]
    }

    static func question(
        section: RouteSection, train: Train, topology: RailTopology, lineIDsByName: [String: [String]],
        solverIDsByName: [String: [String]]
    ) -> Question? {
        func nodes(_ stationID: String?, _ code: String?) -> [RailTopology.NodeRef] {
            if let stationID, !stationID.isEmpty {
                let found = topology.nodes(forStop: stationID)
                if !found.isEmpty { return found }
            }
            if let code, !code.isEmpty { return topology.nodes(forStop: code) }
            return []
        }
        let from = nodes(section.fromStationID, section.fromN02StationCode)
        let to = nodes(section.toStationID, section.toN02StationCode)
        let day = Dates.normalizeDateString(train.date).flatMap { F.dayNumber(ofISODate: $0) }
        let policy = train.routePolicy
        let cacheTrain = RouteGraph.CacheKeyTrain(
            trainType: train.trainType ?? "", company: train.company ?? "",
            preferredLineNames: policy?.preferredLineNames ?? [],
            preferredOperatorNames: policy?.preferredOperatorNames ?? [],
            allowedInstitutionTypeCodes: policy?.allowedInstitutionTypeCodes,
            institutionFilterMode: policy?.institutionFilterMode ?? "soft")
        let allowed = Set(RouteGraph.allowedInstitutionTypeCodes(cacheTrain, country: "jp").compactMap { UInt16($0) })
        let excluded = Set(RouteGraph.hardExcludedInstitutionTypeCodes(
            trainType: train.trainType ?? "", company: train.company ?? "", country: "jp").compactMap { UInt16($0) })
        func ids(_ names: [String]) -> Set<String> { Set(names.filter { !$0.isEmpty }.flatMap { lineIDsByName[$0] ?? [] }) }
        // An alias is stored for the whole line (総武線-3 answers to 東海道線 for its 東京-鶴見 stretch), so it may let a
        // line through the hard filter but never earns the preference discount: preferences use only the lines whose
        // own solver name matches, and on a tie the line that is named so wins.
        func ownIDs(_ names: [String]) -> Set<String> { Set(names.filter { !$0.isEmpty }.flatMap { solverIDsByName[$0] ?? [] }) }

        // Explicit: the section's own line names and operator names. `lineIDs` is the solver's
        // `selectedLineIDs` (certification only), never an ordinary routing constraint.
        let explicitLines = ids(section.lineNames ?? [])
        let explicitOperators = Set((section.operatorNames ?? []).filter { !$0.isEmpty })

        // Common lines and operators of both ends.
        func linesOf(_ refs: [RailTopology.NodeRef]) -> Set<UInt16> { Set(refs.map(\.line)) }
        let commonLineIndexes = linesOf(from).intersection(linesOf(to))
        let commonLines = Set(commonLineIndexes.compactMap { topology.lineID($0) })
        func operatorsOf(_ refs: [RailTopology.NodeRef]) -> Set<String> { Set(linesOf(refs).compactMap { topology.operatorName(ofLine: $0) }) }
        let commonOperators = operatorsOf(from).intersection(operatorsOf(to))

        // Preferences: the trip's lines and operators, plus the explicit ones, plus the common endpoint lines.
        let serviceLines = Set((policy?.preferredLineNames ?? []).filter { !$0.isEmpty })
        var preferredLines = ownIDs(Array(serviceLines))
        preferredLines.formUnion(ownIDs(section.lineNames ?? []))
        if serviceLines.isEmpty { preferredLines.formUnion(commonLines) }
        var preferredOperators = Set((policy?.preferredOperatorNames ?? []).filter { !$0.isEmpty })
        preferredOperators.formUnion(RouteGraph.derivedPreferredOperatorNames(company: train.company ?? "", country: "jp"))
        preferredOperators.formUnion(explicitOperators)

        let plan = RailTopology.SectionPlan(
            from: from, to: to, day: day, explicitLineIDs: explicitLines, explicitOperators: explicitOperators,
            commonLineIDs: commonLines, commonOperators: commonOperators,
            preferredLineIDs: preferredLines, preferredOperators: preferredOperators,
            allowedInstitutions: allowed.isEmpty ? RailTopology.SectionPlan.allInstitutions : allowed,
            hardInstitutionMode: (policy?.institutionFilterMode ?? "soft") == "hard", excludedInstitutions: excluded)
        return Question(plan: plan, intervalCodes: section.sectionCodes ?? [], fromNodes: from)
    }

    /// Router answers with one rule removed at a time, to say which rule explains a difference.
    static func variants(_ plan: RailTopology.SectionPlan, oldLines: [String]) -> [(name: String, plan: RailTopology.SectionPlan)] {
        var noInstitution = plan
        noInstitution.allowedInstitutions = RailTopology.SectionPlan.allInstitutions; noInstitution.excludedInstitutions = []
        var noPreference = plan
        noPreference.preferredLineIDs = []; noPreference.preferredOperators = []
        var lengthOnly = noPreference
        lengthOnly.excludedInstitutions = []; lengthOnly.explicitLineIDs = []; lengthOnly.explicitOperators = []
        lengthOnly.commonLineIDs = []; lengthOnly.commonOperators = []
        lengthOnly.allowedInstitutions = RailTopology.SectionPlan.allInstitutions
        var forced = plan
        forced.explicitLineIDs = Set(oldLines)
        return [("without the institution rules", noInstitution), ("without any preference", noPreference),
                ("plain length only", lengthOnly), ("restricted to the old lines", forced)]
    }

    // MARK: The run

    @Test("a km gap gets a templated reason only inside the measurement bounds; every other gap is left for a hand reason")
    func kmGapBounds() {
        func row(old: Double, new: Double, straight: Double) -> Row {
            Row(ride: "journey_x", store: "s", section: 0, from: "a", to: "b", category: .sameLinesKmDiffers,
                old: Answer(lines: ["l"], km: old), new: Answer(lines: ["l"], km: new), straightKm: straight)
        }
        // Snapping at the ends: at most 0.5 km, whatever the route's shape.
        #expect(Self.kmReason(row(old: 6.2, new: 6.6, straight: 6.3), hasOldLines: true) != nil)
        #expect(Self.kmReason(row(old: 10.3, new: 10.6, straight: 6.4), hasOldLines: true) != nil)
        // Up to 5% and 1 km, with the new km at most 1.5 x the straight line.
        #expect(Self.kmReason(row(old: 40, new: 40.9, straight: 30), hasOldLines: true) != nil)
        #expect(Self.kmReason(row(old: 40, new: 40.9, straight: 20), hasOldLines: true) == nil)   // a long way round
        // More than 5% or more than 1 km: no template. 馬喰町 to 両国 (4.9 km over a 1.0 km straight line),
        // 敦賀 to 新疋田 (9.7 against 6.4) and 折尾 to 赤間 (16.3 against 23.7) are all out.
        #expect(Self.kmReason(row(old: 1.1, new: 4.9, straight: 1.0), hasOldLines: false) == nil)
        #expect(Self.kmReason(row(old: 6.4, new: 9.7, straight: 6.1), hasOldLines: true) == nil)
        #expect(Self.kmReason(row(old: 23.7, new: 16.3, straight: 14.5), hasOldLines: true) == nil)
        #expect(Self.kmReason(row(old: 20, new: 21.2, straight: 19), hasOldLines: true) == nil)   // over 1 km
        // The template never says the old geometry is "simplified" for a gap the numbers contradict.
        #expect(Self.kmReason(row(old: 10, new: 10.4, straight: 9), hasOldLines: true)?.contains("simplified") == true)
    }

    @Test("Solve every oracle trip with both solvers on the real Japan topology file and list the differences",
          .enabled(if: TopologyShadowComparisonTests.enabled))
    func shadow() throws {
        let environment = ProcessInfo.processInfo.environment
        let path = try #require(environment["JTM_TOPOLOGY_JP"], "set JTM_TOPOLOGY_JP to a built jp.topology.bin")
        let openStart = ContinuousClock.now
        let topology = try RailTopology(contentsOf: URL(filePath: path))
        let openMillis = Self.millis(openStart.duration(to: .now))

        var lineIDsByName: [String: [String]] = [:]
        var solverIDsByName: [String: [String]] = [:]
        for line in 0..<topology.lineCount {
            guard let name = topology.solverName(ofLine: UInt16(line)), let id = topology.lineID(UInt16(line)) else { continue }
            solverIDsByName[name, default: []].append(id)
            for each in [name] + topology.aliasNames(ofLine: UInt16(line)) { lineIDsByName[each, default: []].append(id) }
        }

        let root = try PortFixtures.repositoryRoot()
        let fixture = try Oracle.loadFixture()
        let rides = try Oracle.sampleRides(root: root)
        let canonical = try Self.canonicalTrains(rides: rides, root: root)
        let frozen = Dictionary(uniqueKeysWithValues: fixture.rides.map { ($0.id, $0) })

        var rows: [Row] = []
        var timings: [(trip: String, section: Int, ms: Double)] = []
        var skippedTrips: [(id: String, why: String)] = []
        var comparedTrips = Set<String>()
        var intervalCheck = IntervalCheck()

        for ride in rides {
            guard let old = frozen[ride.train.id] else { continue }
            guard old.disposition != "skipped", !old.sections.isEmpty else {
                skippedTrips.append((old.id, "the app never solves it (\(old.disposition))")); continue
            }
            guard old.scope == "jp", let train = canonical[old.id] else {
                skippedTrips.append((old.id, "scope \(old.scope): not in the Japan topology")); continue
            }
            comparedTrips.insert(old.id)
            let sections = train.routeSections ?? []
            for oldSection in old.sections {
                var row = Row(ride: old.id, store: old.store, section: oldSection.index,
                              from: oldSection.from ?? "?", to: oldSection.to ?? "?", category: .endpointNotInTopology)
                let oldLines = Self.collapsed(oldSection.parts.flatMap(\.lineIDs))
                let oldKm = oldSection.parts.reduce(0) { $0 + $1.sourceKm }
                if !oldSection.parts.isEmpty { row.old = Answer(lines: oldLines, km: oldKm) }
                guard sections.indices.contains(oldSection.index),
                      let question = Self.question(section: sections[oldSection.index], train: train,
                                                   topology: topology, lineIDsByName: lineIDsByName,
                                                   solverIDsByName: solverIDsByName),
                      !question.plan.from.isEmpty, !question.plan.to.isEmpty
                else { rows.append(row); continue }

                // The old answer's own official interval codes, laid on the topology: can the file
                // express the old route at all, independently of the router's choice?
                let oldCodes = oldSection.parts.flatMap(\.intervalCodes)
                if !oldCodes.isEmpty, !oldLines.isEmpty {
                    intervalCheck.sections += 1
                    if let spans = topology.spans(forIntervalCodes: oldCodes, departingFrom: question.fromNodes) {
                        intervalCheck.resolved += 1
                        if Self.answer(of: spans, in: topology).lines == oldLines { intervalCheck.sameLines += 1 }
                        else { intervalCheck.different.append("\(old.id) #\(oldSection.index) \(row.from) to \(row.to)") }
                    } else { intervalCheck.unresolved.append("\(old.id) #\(oldSection.index) \(row.from) to \(row.to)") }
                }

                // Authored interval codes come first and are never rerouted.
                if !question.intervalCodes.isEmpty {
                    if let spans = topology.spans(forIntervalCodes: question.intervalCodes, departingFrom: question.fromNodes) {
                        let new = Self.answer(of: spans, in: topology)
                        row.new = new
                        row.category = (oldLines.isEmpty || new.lines == oldLines) ? .intervalCodesMatch : .intervalCodesDiffer
                        if row.category == .intervalCodesDiffer {
                            row.explanation = "the topology lays the same authored intervals over different line ids; check line identity in the builder"
                        }
                    } else {
                        row.category = .intervalCodesUnresolved
                        row.explanation = "the topology could not find, join or direct the authored intervals"
                    }
                    rows.append(row); continue
                }

                let start = ContinuousClock.now
                let path = topology.solve(question.plan)
                timings.append((old.id, oldSection.index, Self.millis(start.duration(to: .now))))
                guard let path else {
                    row.category = oldSection.parts.isEmpty ? .oldGap : .routerNoPath
                    if row.category == .routerNoPath {
                        row.explanation = (environment["JTM_TOPOLOGY_SHADOW_DEBUG"] == "1" ? Self.trace(question, topology) : "")
                            + Self.explainNoPath(question, oldLines, topology)
                    }
                    rows.append(row); continue
                }
                let new = Self.answer(of: path.spans, in: topology)
                row.new = new; row.unproven = path.unproven
                row.spanDetail = Self.spanDetail(path.spans, in: topology)
                if let first = path.spans.first, let last = path.spans.last,
                   let p = topology.coordinate(of: .init(line: first.line, node: first.fromNode)),
                   let q = topology.coordinate(of: .init(line: last.line, node: last.toNode)) {
                    row.straightKm = Geometry.distanceMeters(Coordinate(lon: p.lon, lat: p.lat), Coordinate(lon: q.lon, lat: q.lat)) / 1000
                }
                if path.spans.isEmpty { row.category = .routerEmptyPath; rows.append(row); continue }
                if oldSection.parts.isEmpty || oldSection.gap != "none" && oldSection.parts.isEmpty {
                    row.category = .oldGap; rows.append(row); continue
                }
                if oldLines.isEmpty {
                    row.category = .oldHasNoLineIDs
                    row.explanation = Self.kmClose(oldKm, new.km) ? "km agree" : "km differ"
                } else if new.lines == oldLines {
                    row.category = Self.kmClose(oldKm, new.km) ? .same : .sameLinesKmDiffers
                    if row.category == .sameLinesKmDiffers {
                        row.explanation = "the old km is the length of the drawn solver path, the router counts the edge lengths of the file"
                    }
                } else {
                    row.category = .different
                    row.explanation = (environment["JTM_TOPOLOGY_SHADOW_DEBUG"] == "1" ? Self.trace(question, topology) : "")
                        + Self.explain(question, old: row.old!, new: new, unproven: path.unproven, topology: topology,
                                       temporal: oldSection.parts.map(\.temporalKind))
                }
                rows.append(row)
            }
        }

        let report = Self.report(
            rows: rows, comparedTrips: comparedTrips, skipped: skippedTrips, timings: timings,
            topology: topology, openMillis: openMillis, topologyPath: path,
            stress: Self.stressTimings(topology), intervalCheck: intervalCheck)
        print(report)
        if let out = environment["JTM_TOPOLOGY_SHADOW_OUT"] {
            try report.write(toFile: out, atomically: true, encoding: .utf8)
        }
        #expect(!rows.isEmpty)
        #expect(!report.contains("UNEXPLAINED"), "every remaining difference needs a reason")
    }

    // MARK: Explanations

    /// Plan and attempt trace for a section with no path (`JTM_TOPOLOGY_SHADOW_DEBUG=1`).
    static func trace(_ q: Question, _ topology: RailTopology) -> String {
        func short(_ ids: Set<String>) -> String { ids.sorted().map { $0.replacingOccurrences(of: "jp-", with: "") }.joined(separator: ",") }
        var out = "TRACE prefLines=[\(short(q.plan.preferredLineIDs))] prefOps=\(q.plan.preferredOperators.sorted()) hard=\(q.plan.hardInstitutionMode) explicit=[\(short(q.plan.explicitLineIDs))] ops=\(q.plan.explicitOperators.sorted()) common=[\(short(q.plan.commonLineIDs))] "
        out += "from=[\(short(Set(q.plan.from.compactMap { topology.lineID($0.line) })))] to=[\(short(Set(q.plan.to.compactMap { topology.lineID($0.line) })))] "
        out += "allowed=\(q.plan.allowedInstitutions.sorted()) excluded=\(q.plan.excludedInstitutions.sorted()) day=\(q.plan.day.map(String.init) ?? "-") "
        for attempt in RailTopology.attempts(for: q.plan) {
            out += "[\(attempt.name): \(topology.route(topology.query(for: attempt, in: q.plan)) == nil ? "none" : "found")] "
        }
        var free = RailTopology.SectionQuery(from: q.plan.from, to: q.plan.to, day: q.plan.day)
        out += "[plain: \(topology.route(free) == nil ? "none" : "found")] "
        free.day = nil
        out += "[plain undated: \(topology.route(free) == nil ? "none" : "found")] "
        free.excludedInstitutions = []
        return out + "; "
    }

    static func explainNoPath(_ q: Question, _ oldLines: [String], _ topology: RailTopology) -> String {
        var base = q.plan
        base.preferredLineIDs = []; base.preferredOperators = []
        if !oldLines.isEmpty { base.explicitLineIDs = Set(oldLines) }
        func works(date: Bool, institutions: Bool) -> Bool {
            var plan = base
            if !date { plan.day = nil }
            if !institutions { plan.allowedInstitutions = RailTopology.SectionPlan.allInstitutions; plan.excludedInstitutions = [] }
            return topology.solve(plan)?.unproven == false
        }
        let onOldLines = Set(q.plan.from.map(\.line)).union(q.plan.to.map(\.line))
        let oldIndexes = Set(oldLines.compactMap { topology.lineIndex(forID: $0) })
        if !oldIndexes.isEmpty, oldIndexes.isDisjoint(with: onOldLines) {
            return "an endpoint station is not on the old lines in the topology (station lookup finds only other lines)"
        }
        if works(date: false, institutions: true) { return "date rule: the ride date (\(q.plan.day.map(String.init) ?? "none")) excludes a dated line or edge the old answer used" }
        if works(date: true, institutions: false) { return "institution rule: the hard institution exclusion or filter removes a line the old answer used" }
        if works(date: false, institutions: false) { return "date and institution rules together" }
        var free = base
        free.explicitLineIDs = []; free.explicitOperators = []; free.allowedInstitutions = RailTopology.SectionPlan.allInstitutions
        free.excludedInstitutions = []; free.day = nil
        return topology.solve(free) == nil
            ? "the two ends are not connected in the topology even without any filter or date (missing link, or the line is outside the file)"
            : "connected only over other lines than the old answer's: a link between the old lines is missing in the topology"
    }

    static func explain(_ q: Question, old: Answer, new: Answer, unproven: Bool, topology: RailTopology,
                        temporal: [String]) -> String {
        var notes: [String] = []
        if temporal.contains(where: { $0 != "current" }) {
            notes.append("old answer uses \(Set(temporal.filter { $0 != "current" }).sorted().joined(separator: "/")) track: date rule")
        }
        if unproven { notes.append("the router kept a guard-rejected path as the last resort (unproven)") }
        var matched: String?
        for variant in variants(q.plan, oldLines: old.lines) where variant.name != "restricted to the old lines" {
            if let path = topology.solve(variant.plan), Self.answer(of: path.spans, in: topology).lines == old.lines {
                matched = variant.name; break
            }
        }
        if let matched { notes.append("the router gives the old lines \(matched): that rule decides it") }
        else if !old.lines.isEmpty {
            var forced = q.plan
            forced.explicitLineIDs = Set(old.lines)
            if let path = topology.solve(forced), Self.answer(of: path.spans, in: topology).lines == old.lines {
                notes.append("the old route exists in the topology but costs more than the router's under the ported rules")
            } else if topology.solve(forced) != nil {
                notes.append("over the old lines the router finds another way through them")
            } else {
                notes.append("the old route is not in the topology on that date: a link, a dated edge or line is missing")
            }
        }
        if new.km + 0.3 < old.km { notes.append("router is shorter") }
        else if new.km > old.km + 0.3 { notes.append("router is longer") }
        else { notes.append("equal length: a tie-break") }
        return notes.joined(separator: "; ")
    }

    // MARK: Reasons

    static func knownKey(_ row: Row) -> String { "\(row.ride.replacingOccurrences(of: "journey_", with: "").prefix(8))#\(row.section)" }
    static func gapOf(_ row: Row) -> Double { abs((row.new?.km ?? 0) - (row.old?.km ?? 0)) }

    /// Hand-written reasons (see the difference list). Keyed by the first 8 characters of the trip id and the
    /// section index. A reason that starts with `FOR REVIEW:` says what the numbers show and that the cause is
    /// not settled: the row is counted in the report for the user to decide, never silently accepted.
    static let knownReasons: [String: String] = [
        "07159EDC#2": "FOR REVIEW: the router doubles back. Spans: 総武線 3.0 km out to the junction (003639), then 総武線-2 1.9 km back to 両国, 4.9 km for stations 1.0 km apart. The old answer is a 1.1 km straight bridge of unnamed junction track between the two stations. The file has no link that joins them directly, so the longer way is the only path its reviewed links allow; whether a direct track exists is for the user to decide (a junction row, or leave it).",
        "D8755000#0": "FOR REVIEW: old 21.7 km with no line id, router 16.6 km (1.1 x the 15.1 km straight line): 東北線 to the 赤羽 junction (11.1 km) and 赤羽線 to 池袋 (5.5 km). The router path has no detour; the old answer is 5.0 km longer over track with no current line id (relocated or bridged). Cause of the extra 5.0 km in the old drawing not established.",
        "65F43AE4#0": "FOR REVIEW: old 6.4 km, router 9.7 km on the paired track 北陸線-p1, 1.6 x the 6.1 km straight line. One line, one span, no link. The paired alignment is probably the longer of two parallel tracks here (the old graph took the other, shorter one); not checked against the edge flags of the pair.",
        "425FC76F#0": "The old drawn path has no length (0.0 km: both tram stops snap to one old graph vertex); the router's 0.5 km is the stop spacing and equals the 0.5 km straight line.",
        "6F379655#12": "Router is one span on one line, 16.3 km for a 14.5 km straight line (1.1 x), no detour; the old answer is 7.3 km longer on the same line. The router's path shows no detour; the extra length is on the old side (not traced further).",
        "B113D590#2": "Router is one span on one line, 17.4 km for a 14.9 km straight line (1.2 x), no detour; the old answer is 4.4 km longer on the same line. The router's path shows no detour; the extra length is on the old side (not traced further).",
        "A9554752#2": "Router is one span on one line, 3.9 km for a 3.6 km straight line (1.1 x), no detour; the old answer is 1.8 km longer on the same line. The router's path shows no detour; the extra length is on the old side (not traced further).",
        "6F379655#9": "Router is one span on one line, 6.2 km for a 5.9 km straight line (1.05 x), no detour; the old answer is 1.5 km longer on the same line. The router's path shows no detour; the extra length is on the old side (not traced further).",
        "71102CEF#1": "Split of one stretch at 立野 (a switchback station): this section 17.5 km in the router against 15.5 km in the old answer, and the next section (立野 to 肥後大津) 9.6 km against 11.1 km. The two sections add up to 27.1 km against 26.6 km, within 0.5 km: the old graph places 立野 about 2 km differently along the line.",
        "71102CEF#2": "The other half of 阿蘇 to 立野 above: 9.6 km in the router against 11.1 km in the old answer; the pair adds up to 27.1 km against 26.6 km. The station 立野 sits at a different place along the line in the old graph.",
        "6F379655#3": "Same stations, same 23.0 km, same track: both take 日豊線 and its paired track 日豊線-p1 through the 西屋敷-立石 tunnel section. The old answer's label list ends on a second -p1 piece (its labels are read back from the drawn geometry); the router ends on 日豊線. Not a route difference.",
        "1C77A103#0": "The old label is wrong: 踊り子 is a conventional limited express, so the solver hard-excludes the Shinkansen for it, and 20.3 km against the router's 20.4 km on 東海道線 is the same track; the old label was read back from the drawn geometry, which the parallel Shinkansen alignment also matches.",
        "1367E2AD#0": "Data difference, not a defect: the file has two parallel lines between 東京 and 品川, 東海道線 (6.8 km) and the Yokosuka-Sobu rapid line 総武線-3 (6.7 km); the router takes the 0.1 km shorter one. The old graph has one track here (6.3 km) named 東海道線. Both are real tracks.",
        "F3AE7313#23": "The section names 東海道線, and the only track between 大崎 and 西大井 in the file is the branch 大崎支線, a line of its own, so the named-line rule leaves no path. The old solver bridged the gap with 1.7 km of reviewed junction track that has no line name. Needs the branch to answer to the name 東海道線 in the file (not done: the N02 data has no section there to take it from).",
        "856C6D19#6": "Same as 大崎 to 西大井 above: the section names 東海道線 and 山手線, the only track is the branch 大崎支線, the old solver used 2.6 km of unnamed bridging junction track.",
        "510175D3#0": "Missing data: 佃 is the station where 徳島線 meets 土讃線 (the same station code on both lines in the file) but no reviewed junction row joins them, and shared station codes never link lines, so 阿波池田 (土讃線) cannot reach 阿波加茂 (徳島線). A junction row at 佃 with a source is needed; not added, no source was at hand.",
    ]

    /// Bounds under which a km gap is a plain measurement difference (simplified geometry, snapping at the
    /// two stations): at most 0.5 km (both answers agree on the length, whatever the route's shape), or at
    /// most 5% of the longer km and at most 1 km with a new km at most 1.5 times the straight line between
    /// the ends.
    /// Any other gap may be a real route difference (a double-back, a loop taken the wrong way) and has no template.
    static let kmGapShare = 0.05, kmGapMaxKm = 1.0, kmSnapGapKm = 0.5, kmDetourFactor = 1.5

    static func kmGapIsMeasurement(_ row: Row) -> Bool {
        guard let old = row.old?.km, let new = row.new?.km else { return false }
        let gap = abs(new - old)
        let straight = row.straightKm ?? 0
        if gap < kmSnapGapKm { return true }
        return gap <= kmGapShare * max(old, new) && gap <= kmGapMaxKm && new <= kmDetourFactor * max(straight, 1.0)
    }

    /// A km-gap reason from the row's own numbers and the straight line between the ends; nil when the gap
    /// is outside the measurement bounds (`kmGapIsMeasurement`), so the row is UNEXPLAINED until looked at by hand
    /// (an entry in `knownReasons`).
    static func kmReason(_ row: Row, hasOldLines: Bool) -> String? {
        guard let old = row.old?.km, let new = row.new?.km else { return "no comparison possible" }
        guard kmGapIsMeasurement(row) else { return nil }
        let gap = abs(new - old)
        let straight = row.straightKm ?? 0
        let straightText = String(format: "straight line %.1f km", straight)
        let who = hasOldLines ? "same lines" : "old track has no line id, the router takes the current line"
        if old + 0.3 < straight {
            return String(format: "%@; the old %.1f km is shorter than the %@ between the stations, so the old drawn path is cut short (old answer wrong by %.1f km); the file's %.1f km is plausible.", who, old, straightText, gap, new)
        }
        if new < old {
            return String(format: "%@; the old drawn path is %.1f km longer than the file's surveyed %.1f km (%@): the old km is the length of the old graph's vertex chain, including any snapping or detour at the ends, the file's is the sum of surveyed edge lengths.", who, gap, new, straightText)
        }
        return String(format: "%@; the file's surveyed %.1f km is %.1f km longer than the old drawn path's %.1f km (%@): the old graph's simplified geometry is shorter than the surveyed intervals.", who, new, gap, old, straightText)
    }

    // MARK: Output

    static func millis(_ d: Duration) -> Double { Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15 }

    static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        return sorted[min(sorted.count - 1, Int((Double(sorted.count - 1) * p).rounded(.up)))]
    }

    static func report(
        rows: [Row], comparedTrips: Set<String>, skipped: [(id: String, why: String)],
        timings: [(trip: String, section: Int, ms: Double)], topology: RailTopology, openMillis: Double,
        topologyPath: String, stress: [(name: String, ms: [Double], found: Int)], intervalCheck: IntervalCheck
    ) -> String {
        var out = ""
        func line(_ s: String = "") { out += s + "\n" }
        let byCategory = Dictionary(grouping: rows, by: \.category)
        let sameTrips = comparedTrips.filter { id in
            rows.filter { $0.ride == id }.allSatisfy { [.same, .intervalCodesMatch, .oldHasNoLineIDs, .sameLinesKmDiffers].contains($0.category) }
        }
        line("# Topology router against the production solver: difference list")
        line()
        line("Old is what the production solver drew for each bundled sample trip (the frozen ride oracle). New is the prebuilt-topology router asked the same question on the real Japan file. Nothing here is wired into the app. Generated by `TopologyShadowComparisonTests` (JTM_TOPOLOGY_SHADOW=1).")
        line()
        line("## Totals")
        line()
        line("- Trips compared: \(comparedTrips.count) of 287 (\(skipped.count) not compared: scope outside Japan, or never solved by the app)")
        line("- Trips where every section has the same lines: \(sameTrips.count)")
        line("- Trips with at least one section that differs, has no router path, or could not be compared: \(comparedTrips.count - sameTrips.count)")
        line("- Sections compared: \(rows.count)")
        for category in Category.allCases { line("  - \(category.rawValue): \(byCategory[category]?.count ?? 0)") }
        let kmGaps = (byCategory[.sameLinesKmDiffers] ?? []).compactMap { r in r.old.flatMap { o in r.new.map { abs($0.km - o.km) } } }.sorted()
        if !kmGaps.isEmpty {
            line()
            line(String(format: "Same lines but km differs: median gap %.2f km, largest %.2f km (the old km is the length of the drawn solver path; the router adds the edge lengths of the file). Tolerance for \"same km\": the larger of 0.3 km and 1%%.", percentile(kmGaps, 0.5), kmGaps.last ?? 0))
        }
        let noIDs = byCategory[.oldHasNoLineIDs] ?? []
        if !noIDs.isEmpty {
            let agree = noIDs.filter { r in r.old.flatMap { o in r.new.map { kmClose(o.km, $0.km) } } ?? false }.count
            line()
            line("Old answers without line ids: \(agree) of \(noIDs.count) agree with the router on km (these are mostly relocated or historical track the old solver drew without a current line id).")
        }
        line()
        line("Old answers drawn from official interval codes (with line ids): \(intervalCheck.sections) sections. The topology resolves \(intervalCheck.resolved) of them from the codes alone, and \(intervalCheck.sameLines) of those give the old line sequence. Unresolved: \(intervalCheck.unresolved.count); resolved to other lines: \(intervalCheck.different.count).")
        for item in intervalCheck.unresolved.prefix(20) { line("  - codes not resolved: \(item)") }
        for item in intervalCheck.different.prefix(20) { line("  - codes resolve to other lines: \(item)") }
        line()
        line("Topology file: \(topologyPath.split(separator: "/").last ?? ""),\(topology.lineCount) lines, \(topology.nodeTotal) nodes, \(topology.edgeTotal) edges, \(topology.linkCount) links.")
        line()
        line("## Remaining differences, one row each")
        line()
        line("Old is the production solver (frozen oracle): lines and km. New is the router with the ported rules on this file. Reason: one plain sentence; every row is explained by hand (see `knownReasons` in the test; FOR REVIEW means the cause is not settled) or, for a km gap inside the measurement bounds (at most 0.5 km, or 5% and 1 km with the new km at most 1.5 x the straight line), by a template from the row's numbers. A km gap outside those bounds with no hand reason is flagged in capitals as unexplained, which fails the test.")
        line()
        var unexplained = 0, forReview = 0
        func entry(_ row: Row, _ reason: String) {
            if reason.hasPrefix("FOR REVIEW") { forReview += 1 }
            line("- trip \(row.ride.replacingOccurrences(of: "journey_", with: "")) (\(row.store)), section \(row.section) \(row.from) to \(row.to)")
            line("  - old: \(describe(row.old))")
            line("  - new: \(describe(row.new))\(row.unproven ? " [unproven]" : "")")
            if !row.spanDetail.isEmpty, reason.hasPrefix("UNEXPLAINED") { line("  - router spans: \(row.spanDetail)") }
            line("  - reason: \(reason)")
        }
        func kmEntry(_ row: Row, hasOldLines: Bool) {
            if let reason = knownReasons[knownKey(row)] ?? kmReason(row, hasOldLines: hasOldLines) { entry(row, reason) }
            else {
                unexplained += 1
                entry(row, String(format: "UNEXPLAINED (%@): km gap %.1f km outside the measurement bounds (at most 0.5 km, or 5%% and 1 km; new km at most 1.5 x the %.1f km straight line); look at the route by hand.",
                                  knownKey(row), abs((row.new?.km ?? 0) - (row.old?.km ?? 0)), row.straightKm ?? 0))
            }
        }
        for category in [Category.different, .routerNoPath, .intervalCodesDiffer, .intervalCodesUnresolved, .oldGap, .routerEmptyPath, .endpointNotInTopology] {
            let list = byCategory[category] ?? []
            guard !list.isEmpty else { continue }
            line("### \(category.rawValue) (\(list.count))")
            line()
            for row in list {
                let key = knownKey(row)
                if let reason = knownReasons[key] { entry(row, reason) } else { unexplained += 1; entry(row, "UNEXPLAINED (\(key)): \(row.explanation)") }
            }
            line()
        }
        let noIDDiffers = noIDs.filter { r in !(r.old.flatMap { o in r.new.map { kmClose(o.km, $0.km) } } ?? true) }
        if !noIDDiffers.isEmpty {
            line("### old answer carries no line ids, km disagree (\(noIDDiffers.count))")
            line()
            line("The old solver drew these over track with no current line id (relocated, historical or bridged by reviewed junction track).")
            line()
            for row in noIDDiffers { kmEntry(row, hasOldLines: false) }
            line()
        }
        let gaps = (byCategory[.sameLinesKmDiffers] ?? []).sorted { gapOf($0) > gapOf($1) }
        if !gaps.isEmpty {
            line("### same lines, km differs (\(gaps.count))")
            line()
            line("Same line sequence; the km differ by more than the larger of 0.3 km and 1%. Largest gap first. A gap gets a templated reason only when it is at most 0.5 km, or at most 5% and 1 km, and the new km is at most 1.5 x the straight line; every other row is flagged in capitals as unexplained until a hand-written reason is added.")
            line()
            for row in gaps { kmEntry(row, hasOldLines: true) }
            line()
        }
        if forReview > 0 { line("ROWS FOR REVIEW (the numbers are shown, the cause is not settled): \(forReview)"); line() }
        if unexplained > 0 { line("UNEXPLAINED ROWS: \(unexplained)"); line() }
        if !skipped.isEmpty {
            line("## Not compared (\(skipped.count))")
            line()
            let grouped = Dictionary(grouping: skipped, by: \.why)
            for (why, items) in grouped.sorted(by: { $0.key < $1.key }) { line("- \(items.count) trips: \(why)") }
            line()
        }
        let sorted = timings.map(\.ms).sorted()
        line("## Router timing on this file")
        line()
        line("Measured by the shadow test around `RailTopology.route` for each of the \(sorted.count) sections it solved (not interval-coded ones), one call each, after the file was open and warm. Open (validate and link index): \(String(format: "%.1f", openMillis)) ms.")
        line()
        line(String(format: "- median %.3f ms, p95 %.3f ms, p99 %.3f ms, max %.3f ms", percentile(sorted, 0.5), percentile(sorted, 0.95), percentile(sorted, 0.99), sorted.last ?? 0))
        if let worst = timings.max(by: { $0.ms < $1.ms }) { line("- slowest: trip \(worst.trip), section \(worst.section)") }
        line()
        line("Worst-case probes (no oracle trip is long): seeded random pairs of nodes anywhere in the file, one call each, undated.")
        line()
        for probe in stress {
            let s = probe.ms.sorted()
            line(String(format: "- %@: %d calls, %d found a path; median %.3f ms, p95 %.3f ms, p99 %.3f ms, max %.3f ms",
                        probe.name as NSString, s.count, probe.found, percentile(s, 0.5), percentile(s, 0.95), percentile(s, 0.99), s.last ?? 0))
        }
        return out
    }

    /// Seeded random node pairs over the whole file: free search, hard filter on the start line
    /// (which forces the unproven second search when the target is elsewhere), and a trip of five legs.
    static func stressTimings(_ topology: RailTopology) -> [(name: String, ms: [Double], found: Int)] {
        var nodes: [RailTopology.NodeRef] = []
        for line in 0..<topology.lineCount {
            for node in 0..<topology.nodeCount(ofLine: UInt16(line)) { nodes.append(.init(line: UInt16(line), node: UInt16(node))) }
        }
        var state: UInt64 = 20_261_112
        func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
        func time(_ body: () -> Bool) -> (Double, Bool) {
            let start = ContinuousClock.now
            let ok = body()
            return (millis(start.duration(to: .now)), ok)
        }
        var results: [(name: String, ms: [Double], found: Int)] = []
        var free: [Double] = [], freeFound = 0, filtered: [Double] = [], filteredFound = 0, trips: [Double] = [], tripsFound = 0
        for _ in 0..<2_000 {
            let a = nodes[next(nodes.count)], b = nodes[next(nodes.count)]
            let (t1, ok1) = time { topology.route(.init(from: [a], to: [b])) != nil }
            free.append(t1); if ok1 { freeFound += 1 }
            var q = RailTopology.SectionQuery(from: [a], to: [b])
            if let id = topology.lineID(a.line) { q.lineIDs = [id] }
            let (t2, ok2) = time { topology.route(q) != nil }
            filtered.append(t2); if ok2 { filteredFound += 1 }
        }
        for _ in 0..<400 {
            let legs = (0..<6).map { _ in nodes[next(nodes.count)] }
            let (t3, ok3) = time {
                var all = true
                for pair in zip(legs, legs.dropFirst()) { if topology.route(.init(from: [pair.0], to: [pair.1])) == nil { all = false } }
                return all
            }
            trips.append(t3); if ok3 { tripsFound += 1 }
        }
        results.append(("random pair, no filter", free, freeFound))
        results.append(("random pair, hard filter on the start line (second, unfiltered search when unreachable)", filtered, filteredFound))
        results.append(("five legs in a row between random nodes (every leg must find a path to count)", trips, tripsFound))
        return results
    }

    // MARK: Canonical input

    /// The trip as the old solver was given it (`RideOracleGuardTests.resolve`, canonical input step only).
    static func canonicalTrains(rides: [Census.Ride], root: URL) throws -> [String: Train] {
        let data = root.appending(path: "app/data")
        var bundles: [String: RegistryBundle] = [:]
        for region in Set(rides.flatMap { Census.regionsTouched($0.train) }) {
            let url = data.appending(path: "registry-bundle/\(region).json")
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let bundle = try JSONDecoder().decode(RegistryBundle.self, from: Data(contentsOf: url))
            if bundle.region.lowercased() == region { bundles[region] = bundle }
        }
        let registry = Census.Registry(bundles: bundles, identities: bundles.mapValues(RegistryIdentity.init(bundle:)))
        let identities = registry.identities
        let timetable = Census.TimetableEvidence(
            url: data.appending(path: "train-service-history/derived/train-service-timetable.sqlite"))
        var result: [String: Train] = [:]
        RegistryIdentityLookup.withTestPhase({ region in
            identities[region.lowercased()].map(RegistryPhase.ready) ?? .unavailable
        }) {
            for ride in rides where !ride.train.requiresRouteConfirmation {
                result[ride.train.id] = Census.canonicalRouteInput(
                    ride.train, country: "jp", registry: registry, timetable: timetable).train
            }
        }
        return result
    }
}
