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

    static func describe(_ answer: Answer?) -> String {
        guard let answer else { return "none" }
        let names = answer.lines.map { $0.replacingOccurrences(of: "jp-", with: "") }
        return String(format: "%@ (%.1f km)", names.isEmpty ? "no lines" : names.joined(separator: " > "), answer.km)
    }

    static func kmClose(_ a: Double, _ b: Double) -> Bool { abs(a - b) <= max(0.3, 0.01 * max(a, b)) }

    /// What a section asks the router, built the way the production solver builds its hints.
    struct Question {
        var query: RailTopology.SectionQuery
        var intervalCodes: [String]
        var fromNodes: [RailTopology.NodeRef]
    }

    static func question(
        section: RouteSection, train: Train, topology: RailTopology, lineIDsByName: [String: [String]]
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
        var preferredNames = Set((policy?.preferredLineNames ?? []).filter { !$0.isEmpty })
        preferredNames.formUnion((section.lineNames ?? []).filter { !$0.isEmpty })
        var query = RailTopology.SectionQuery(from: from, to: to, day: day)
        query.lineIDs = Set(section.lineIDs ?? [])
        query.preferredLineIDs = Set(preferredNames.flatMap { lineIDsByName[$0] ?? [] })
        query.excludedInstitutions = excluded
        query.excludeHighSpeed = excluded.contains(1)
        if (policy?.institutionFilterMode ?? "soft") == "hard" { query.institutions = allowed }
        else { query.preferredInstitutions = allowed }
        return Question(query: query, intervalCodes: section.sectionCodes ?? [], fromNodes: from)
    }

    /// Router answers with one rule removed at a time, to say which rule explains a difference.
    static func variants(_ q: RailTopology.SectionQuery, oldLines: [String]) -> [(name: String, query: RailTopology.SectionQuery)] {
        var noInstitution = q
        noInstitution.preferredInstitutions = []; noInstitution.excludedInstitutions = []; noInstitution.excludeHighSpeed = false
        var noPreference = q
        noPreference.preferredLineIDs = []; noPreference.preferredInstitutions = []
        var lengthOnly = noPreference
        lengthOnly.excludedInstitutions = []; lengthOnly.excludeHighSpeed = false; lengthOnly.lineIDs = []; lengthOnly.institutions = []
        var forced = q
        forced.lineIDs = Set(oldLines)
        return [("without the institution rules", noInstitution), ("without any preference", noPreference),
                ("plain length only", lengthOnly), ("restricted to the old lines", forced)]
    }

    // MARK: The run

    @Test("Solve every oracle trip with both solvers on the real Japan topology file and list the differences",
          .enabled(if: TopologyShadowComparisonTests.enabled))
    func shadow() throws {
        let environment = ProcessInfo.processInfo.environment
        let path = try #require(environment["JTM_TOPOLOGY_JP"], "set JTM_TOPOLOGY_JP to a built jp.topology.bin")
        let openStart = ContinuousClock.now
        let topology = try RailTopology(contentsOf: URL(filePath: path))
        let openMillis = Self.millis(openStart.duration(to: .now))

        var lineIDsByName: [String: [String]] = [:]
        for line in 0..<topology.lineCount {
            guard let name = topology.lineName(UInt16(line)), let id = topology.lineID(UInt16(line)) else { continue }
            lineIDsByName[name, default: []].append(id)
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
                                                   topology: topology, lineIDsByName: lineIDsByName),
                      !question.query.from.isEmpty, !question.query.to.isEmpty
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
                let path = topology.route(question.query)
                timings.append((old.id, oldSection.index, Self.millis(start.duration(to: .now))))
                guard let path else {
                    row.category = oldSection.parts.isEmpty ? .oldGap : .routerNoPath
                    if row.category == .routerNoPath { row.explanation = Self.explainNoPath(question, oldLines, topology) }
                    rows.append(row); continue
                }
                let new = Self.answer(of: path.spans, in: topology)
                row.new = new; row.unproven = path.unproven
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
                    row.explanation = Self.explain(question, old: row.old!, new: new, unproven: path.unproven, topology: topology,
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
    }

    // MARK: Explanations

    static func explainNoPath(_ q: Question, _ oldLines: [String], _ topology: RailTopology) -> String {
        var base = q.query
        base.preferredLineIDs = []; base.preferredInstitutions = []
        if !oldLines.isEmpty { base.lineIDs = Set(oldLines) }
        func works(date: Bool, institutions: Bool) -> Bool {
            var query = base
            if !date { query.day = nil }
            if !institutions { query.institutions = []; query.excludedInstitutions = []; query.excludeHighSpeed = false }
            return topology.route(query)?.unproven == false || (oldLines.isEmpty && topology.route(query) != nil)
        }
        let onOldLines = Set(q.query.from.map(\.line)).union(q.query.to.map(\.line))
        let oldIndexes = Set(oldLines.compactMap { topology.lineIndex(forID: $0) })
        if !oldIndexes.isEmpty, oldIndexes.isDisjoint(with: onOldLines) {
            return "an endpoint station is not on the old lines in the topology (station lookup finds only other lines)"
        }
        if works(date: false, institutions: true) { return "date rule: the ride date (\(q.query.day.map(String.init) ?? "none")) excludes a dated line or edge the old answer used" }
        if works(date: true, institutions: false) { return "institution rule: the hard institution exclusion or filter removes a line the old answer used" }
        if works(date: false, institutions: false) { return "date and institution rules together" }
        var free = base
        free.lineIDs = []; free.institutions = []; free.excludedInstitutions = []; free.excludeHighSpeed = false; free.day = nil
        return topology.route(free) == nil
            ? "the two ends are not connected in the topology even without any filter or date (missing link, or the line is outside the file)"
            : "connected only over other lines than the old answer's: a link between the old lines is missing in the topology"
    }

    static func explain(_ q: Question, old: Answer, new: Answer, unproven: Bool, topology: RailTopology,
                        temporal: [String]) -> String {
        var notes: [String] = []
        if temporal.contains(where: { $0 != "current" }) {
            notes.append("old answer uses \(Set(temporal.filter { $0 != "current" }).sorted().joined(separator: "/")) track: date rule")
        }
        if unproven { notes.append("router dropped the line filter (unproven)") }
        var matched: String?
        for variant in variants(q.query, oldLines: old.lines) where variant.name != "restricted to the old lines" {
            if let path = topology.route(variant.query), Self.answer(of: path.spans, in: topology).lines == old.lines {
                matched = variant.name; break
            }
        }
        if let matched { notes.append("the router gives the old lines \(matched): that rule decides it") }
        else if !old.lines.isEmpty {
            var forced = q.query
            forced.lineIDs = Set(old.lines)
            if let path = topology.route(forced), Self.answer(of: path.spans, in: topology).lines == old.lines {
                notes.append("the old route exists in the topology but costs more than the router's under the ported rules")
            } else if topology.route(forced) != nil {
                notes.append("over the old lines the router finds another way through them")
            } else {
                notes.append("the old route is not in the topology on that date: a link, a dated edge or line is missing")
            }
        }
        if new.km + 0.3 < old.km { notes.append("router is shorter: the old solver paid a preference the router prices differently or lacks (operator, per-edge institution penalty, same-name station guard)") }
        else if new.km > old.km + 0.3 { notes.append("router is longer: it cannot use a connection the old graph had") }
        else { notes.append("equal length: a tie-break") }
        return notes.joined(separator: "; ")
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
        line("Differences, one row each. Old is the production solver (frozen oracle); new is the router with the ported rules.")
        line()
        for category in [Category.different, .routerNoPath, .intervalCodesDiffer, .intervalCodesUnresolved, .oldGap, .routerEmptyPath, .endpointNotInTopology] {
            let list = (byCategory[category] ?? [])
            guard !list.isEmpty else { continue }
            line("## \(category.rawValue) (\(list.count))")
            line()
            for row in list {
                line("- trip \(row.ride.replacingOccurrences(of: "journey_", with: "")) (\(row.store)), section \(row.section) \(row.from) to \(row.to)")
                line("  - old: \(describe(row.old))")
                line("  - new: \(describe(row.new))\(row.unproven ? " [unproven]" : "")")
                if !row.explanation.isEmpty { line("  - likely rule: \(row.explanation)") }
            }
            line()
        }
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
