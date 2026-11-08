import Foundation
import Testing
@testable import RailCore

/// Regression guard: identities of one operator that meet at a surveyed vertex
/// are two separate nodes in the physical graph. The only join between two
/// different identities is a junction row in the physical rail junction
/// registry (no station, shared node or operator join; transfer connectors are
/// rejected under `.physicalRailway`). A missing row breaks a ride that crosses
/// the seam: 北大阪急行 箕面船場阪大前 (南北線 class 12/21), 広電 稲荷町 (本線/皆実線).
///
/// Tiers (JP, the only region with a junction registry; CN has no stations and
/// tw/hk/mo/kr ship no registry):
/// 1. Same operator and line, different railwayClassCode: hard failure.
/// 2. Different lines of one operator, ratcheted against
///    `Resources/topology-gap-baseline.json` (an unknown hit fails, a baseline
///    entry that no longer occurs fails, so the baseline only shrinks):
///    - R1 row geometry: within one package row interval the running
///      intersection of edge-identity sets empties, or two consecutive
///      intervals' end and start identity sets do not intersect.
///    - R2 catalog boundary: consecutive legs x to y of japan-through-services.json
///      arrive at and leave a station on disjoint identity sets.
///    - R4 structural terminus: a non-paired, non-loop row ends at a station
///      coded in stations.json under another line B of the same operator, and the
///      row's identity A and B share an exact vertex within 600 m.
///    - R4b package-coded terminus: as R4, but line B is read from the package rows
///      whose stations use the code, for the pairs R4 does not already ask about
///      (stations.json codes the station only under A, or B under a code of its own:
///      広島 008029 is 芸備線's code and 山陽線 runs through it in the package), and never
///      a pair R4 already reports at that station from the other line's row end.
///      Its own baseline section, seeded 2026-11-07; each entry carries a
///      `likely` triage tag (junction / notJunction / unknown) that regeneration keeps.
///    Paired alignments (alignmentOf != nil) are not read as rows in R1/R4/R4b.
/// 3. Registry consistency: a junction row's stationCode must be a code used by
///    every row in its lineIDs or by the stations of both identities.
///    Exceptions are ratcheted in the baseline (`registryStationCodes`).
///
/// A "joined" check is a JP registry row whose two identities are exactly A and
/// B with an endpoint within 30 m of the point (1500 m at a catalog boundary).
struct RegressionGuardTopologyGaps {
    private static let toleranceMeters = 5.0
    private static let junctionReachMeters = 30.0
    private static let boundaryReachMeters = 1500.0
    private static let terminusRangeMeters = 600.0
    private static let listedGapLimit = 40

    private static let registryPath = "app/data/physical-rail-junctions.json"
    private static let marksPath =
        "ios/RailKit/Tests/RailCoreTests/RegressionGuards/Resources/reviewed-unconnected-continuations.json"
    private static let baselinePath =
        "ios/RailKit/Tests/RailCoreTests/RegressionGuards/Resources/topology-gap-baseline.json"
    private static let documentPath = "docs/maintenance/2026-11-06-junction-gaps.md"
    private static let regenerateCommand =
        "JTM_REGENERATE_EXPECTATIONS=1 swift test --package-path ios/RailKit --filter RegressionGuardTopologyGaps"

    // MARK: - values

    private struct Identity: Hashable, Comparable {
        let operatorName: String
        let line: String
        let railwayClass: String
        static func < (a: Identity, b: Identity) -> Bool {
            (a.operatorName, a.line, a.railwayClass) < (b.operatorName, b.line, b.railwayClass)
        }
        var label: String { "\(line)[\(railwayClass)]" }
    }

    private struct Pair: Hashable {
        let a: Identity
        let b: Identity
        init(_ x: Identity, _ y: Identity) { (a, b) = x < y ? (x, y) : (y, x) }
    }

    private struct Gap {
        let pair: Pair
        let at: Coordinate
        var sameLine: Bool { pair.a.line == pair.b.line }
    }

    /// A vertex on the 1e-5 grid, the survey's own resolution.
    private struct Q: Hashable {
        let x: Int
        let y: Int
        init(_ c: Coordinate) { x = Int((c.lon * 1e5).rounded()); y = Int((c.lat * 1e5).rounded()) }
        var coordinate: Coordinate { Coordinate(lon: Double(x) / 1e5, lat: Double(y) / 1e5) }
    }

    private struct EdgeKey: Hashable {
        let a: Q
        let b: Q
        init(_ p: Q, _ q: Q) { if (p.x, p.y) < (q.x, q.y) { (a, b) = (p, q) } else { (a, b) = (q, p) } }
    }

    private struct MarksDocument: Decodable {
        struct Mark: Decodable {
            let `operator`: String
            let lineA: String
            let classA: String
            let lineB: String
            let classB: String
            let reason: String
        }
        let reasons: [String]
        let marks: [Mark]
    }

    private static func meters(_ p: Coordinate, _ q: Coordinate) -> Double {
        let dx = (p.lon - q.lon) * 111_320 * cos(p.lat * .pi / 180)
        let dy = (p.lat - q.lat) * 110_540
        return (dx * dx + dy * dy).squareRoot()
    }

    // MARK: - data

    private struct StationRecord { let name: String; let code: String; let at: Coordinate }

    private struct ThroughServices: Decodable {
        struct Pattern: Decodable {
            struct Leg: Decodable { let lineID: String; let fromStationCode: String; let toStationCode: String }
            let id: String
            let legs: [Leg]
        }
        let patterns: [Pattern]
    }

    private struct RegistryRow: Decodable {
        struct Endpoint: Decodable {
            struct Ident: Decodable { let operatorName: String; let lineName: String; let railwayClassCode: String }
            let identity: Ident
        }
        let id: String
        let region: String
        let stationCode: String?
        let lineIDs: [String]?
        let from: Endpoint
        let to: Endpoint
    }

    private struct RegistryDocument: Decodable { let junctions: [RegistryRow] }

    private struct Line {
        let id: String
        let own: Identity2?
        let isLoop: Bool
        let paired: Bool
        let stations: [(code: String, name: String, at: Coordinate)]
        let segments: [[Coordinate]]
    }

    private struct Identity2: Hashable { let operatorName: String; let line: String }

    private struct Context {
        var features: [RouteGraph.SectionFeature] = []
        var registryRows: [RegistryRow] = []
        var byLine: [Identity2: [StationRecord]] = [:]
        var linesOfCode: [String: Set<Identity2>] = [:]
        /// Package rows' own lines by the station codes their stations use.
        var packageLinesOfCode: [String: Set<Identity2>] = [:]
        var lines: [Line] = []
        var lineByID: [String: Line] = [:]
        var services: [ThroughServices.Pattern] = []
    }

    private static func loadContext(_ root: URL) throws -> Context {
        var ctx = Context()
        ctx.features = try RouteGraph.SectionFeatureCollection.load(
            contentsOf: root.appending(path: "app/data/rail-sections.json")).features
        ctx.registryRows = try JSONDecoder().decode(RegistryDocument.self,
            from: Data(contentsOf: root.appending(path: registryPath))).junctions
        let stations = try JSONSerialization.jsonObject(
            with: Data(contentsOf: root.appending(path: "app/data/stations.json"))) as? [String: Any]
        for case let feature as [String: Any] in (stations?["features"] as? [Any]) ?? [] {
            guard let p = feature["properties"] as? [String: Any],
                  let op = p["operator"] as? String, let line = p["line_name"] as? String,
                  let name = p["station_name"] as? String, let code = p["n02_station_code"] as? String,
                  let pt = p["display_point"] as? [Double], pt.count == 2 else { continue }
            let key = Identity2(operatorName: op, line: line)
            ctx.byLine[key, default: []].append(
                StationRecord(name: name, code: code, at: Coordinate(lon: pt[0], lat: pt[1])))
            ctx.linesOfCode[code, default: []].insert(key)
        }
        for row in try PortFixtures.package(country: "jp").lines {
            let line = Line(
                id: row.id, own: row.operator.map { Identity2(operatorName: $0, line: row.name) },
                isLoop: row.isLoop, paired: row.alignmentOf != nil,
                stations: row.stations.map { (code: $0.id, name: $0.name, at: $0.coordinate) },
                segments: row.segments.map(\.coordinates))
            ctx.lines.append(line)
            ctx.lineByID[row.id] = line
            if let own = line.own, !line.paired {
                for st in line.stations { ctx.packageLinesOfCode[st.code, default: []].insert(own) }
            }
        }
        ctx.services = try JSONDecoder().decode(ThroughServices.self, from: Data(contentsOf:
            root.appending(path: "ios/RailKit/Sources/RailCore/Resources/japan-through-services.json"))).patterns
        return ctx
    }

    // MARK: - survey network

    private struct Network {
        var verts: [Q: Set<Identity>] = [:]
        var ends: [Q: Set<Identity>] = [:]
        var edges: [EdgeKey: Set<Identity>] = [:]
        var touches: [(pair: Pair, at: Q)] = []
        var touchesOf: [Identity: [(other: Identity, at: Q)]] = [:]
        var endsOf: [Identity: [Coordinate]] = [:]

        init(_ features: [RouteGraph.SectionFeature]) {
            for f in features {
                let p = f.properties
                guard !p.operator.isEmpty, !p.lineName.isEmpty else { continue }
                let id = Identity(operatorName: p.operator, line: p.lineName, railwayClass: p.railwayClassCode)
                for line in f.lines {
                    for (j, c) in line.enumerated() {
                        let q = Q(c)
                        verts[q, default: []].insert(id)
                        if j == 0 || j == line.count - 1 { ends[q, default: []].insert(id) }
                    }
                    for (c1, c2) in zip(line, line.dropFirst()) {
                        let q1 = Q(c1), q2 = Q(c2)
                        if q1 != q2 { edges[EdgeKey(q1, q2), default: []].insert(id) }
                    }
                }
            }
            for (q, ids) in ends { for id in ids { endsOf[id, default: []].append(q.coordinate) } }
            for id in Array(endsOf.keys) { endsOf[id]?.sort { ($0.lon, $0.lat) < ($1.lon, $1.lat) } }
            for (q, ids) in verts where ids.count >= 2 {
                let sorted = ids.sorted()
                for i in 0..<sorted.count { for j in (i + 1)..<sorted.count {
                    let a = sorted[i], b = sorted[j]
                    guard a.operatorName == b.operatorName, a.line != b.line,
                          ends[q]?.contains(a) == true || ends[q]?.contains(b) == true else { continue }
                    touches.append((Pair(a, b), q))
                    touchesOf[a, default: []].append((b, q))
                    touchesOf[b, default: []].append((a, q))
                } }
            }
            // Dictionary order is random per process; every consumer sees one fixed order.
            touches.sort { ($0.pair.a, $0.pair.b, $0.at.x, $0.at.y) < ($1.pair.a, $1.pair.b, $1.at.x, $1.at.y) }
            for id in Array(touchesOf.keys) {
                touchesOf[id]?.sort { ($0.other, $0.at.x, $0.at.y) < ($1.other, $1.at.x, $1.at.y) }
            }
        }
    }

    private struct Joins {
        var points: [Pair: [Coordinate]] = [:]
        var stationRows: [Pair: [(code: String, at: [Coordinate])]] = [:]
        init(_ rows: [RegistryRow], removing: Set<String>, coordinates: [String: [Coordinate]]) {
            func id(_ e: RegistryRow.Endpoint) -> Identity {
                Identity(operatorName: e.identity.operatorName, line: e.identity.lineName,
                         railwayClass: e.identity.railwayClassCode)
            }
            for r in rows where r.region == "jp" && !removing.contains(r.id) {
                points[Pair(id(r.from), id(r.to)), default: []] += coordinates[r.id] ?? []
                if let code = r.stationCode {
                    stationRows[Pair(id(r.from), id(r.to)), default: []].append((code, coordinates[r.id] ?? []))
                }
            }
        }
        func joined(_ a: Identity, _ b: Identity, _ p: Coordinate, reach: Double) -> Bool {
            (points[Pair(a, b)] ?? []).contains { RegressionGuardTopologyGaps.meters($0, p) <= reach }
        }
        /// A row for the pair coded to this station and lying within `reach` of it.
        func joined(_ a: Identity, _ b: Identity, atStation code: String, _ station: Coordinate, reach: Double) -> Bool {
            (stationRows[Pair(a, b)] ?? []).contains { row in
                row.code == code && row.at.contains { RegressionGuardTopologyGaps.meters($0, station) <= reach }
            }
        }
    }

    private struct Run {
        let first: Set<Identity>
        let last: Set<Identity>
        let crossings: [(at: Q, from: Set<Identity>, to: Set<Identity>)]
        let start: Coordinate
        let end: Coordinate
    }

    private static func carryRun(_ cs: [Coordinate], _ net: Network) -> Run? {
        var es: [(Q, Q, Set<Identity>)] = []
        for (a, b) in zip(cs, cs.dropFirst()) {
            let qa = Q(a), qb = Q(b)
            if qa != qb, let s = net.edges[EdgeKey(qa, qb)], !s.isEmpty { es.append((qa, qb, s)) }
        }
        guard let head = es.first, let tail = es.last else { return nil }
        var cur = head.2
        var crossings: [(at: Q, from: Set<Identity>, to: Set<Identity>)] = []
        for e in es.dropFirst() {
            let n = cur.intersection(e.2)
            if !n.isEmpty { cur = n } else { crossings.append((e.0, cur, e.2)); cur = e.2 }
        }
        var first = head.2
        for e in es.dropFirst() {
            let n = first.intersection(e.2)
            if n.isEmpty { break }
            first = n
        }
        return Run(first: first, last: cur, crossings: crossings, start: head.0.coordinate, end: tail.1.coordinate)
    }

    /// Suggested junction kind near `p`: an identical shared vertex is a zeroLength row;
    /// otherwise the nearest pair of endpoints decides shortLink (at most 30 m) or osmConnector.
    private static func junctionHint(_ pair: Pair, near p: Coordinate, _ net: Network) -> (at: Coordinate?, text: String) {
        var best: (d: Double, at: Coordinate)?
        for t in net.touchesOf[pair.a] ?? [] where t.other == pair.b {
            let d = meters(t.at.coordinate, p)
            if d <= boundaryReachMeters, d < (best?.d ?? .infinity) { best = (d, t.at.coordinate) }
        }
        if let best {
            return (best.at, String(format: "zeroLength at identical shared vertex (%.5f, %.5f), %.0f m from the site", best.at.lon, best.at.lat, best.d))
        }
        var gap: (d: Double, at: Coordinate)?
        for x in (net.endsOf[pair.a] ?? []) where meters(x, p) <= boundaryReachMeters {
            for y in (net.endsOf[pair.b] ?? []) where meters(y, p) <= boundaryReachMeters {
                let d = meters(x, y)
                if d < (gap?.d ?? .infinity) { gap = (d, x) }
            }
        }
        guard let gap else { return (nil, "no endpoints of both identities within 1500 m; needs survey review") }
        let kind = gap.d <= junctionReachMeters ? "shortLink" : "osmConnector"
        return (gap.at, String(format: "%@ across %.0f m between nearest endpoints (%.5f, %.5f)", kind, gap.d, gap.at.lon, gap.at.lat))
    }

    private static func unjoinedPairs(_ a: Set<Identity>, _ b: Set<Identity>, at p: Coordinate,
                                      reach: Double, _ joins: Joins) -> [Pair] {
        if !a.isDisjoint(with: b) { return [] }
        var out: [Pair] = []
        for x in a.sorted() { for y in b.sorted() {
            if joins.joined(x, y, p, reach: reach) { return [] }
            if x.operatorName == y.operatorName, x.line != y.line { out.append(Pair(x, y)) }
        } }
        return out
    }

    // MARK: - hits

    private struct Hit {
        let rule: String
        let pair: Pair
        let code: String
        let name: String
        let site: Coordinate?
        let evidence: String
        /// Documentation only (not part of the key): where the junction row would go and of which kind.
        var locus: Coordinate?
        var hint = ""

        var key: String {
            var k = "\(rule)|\(pair.a.operatorName)|\(pair.a.label)|\(pair.b.label)|\(code)"
            if let site { k += String(format: "|%.5f,%.5f", site.lon, site.lat) }
            return k
        }
    }

    private struct BaselineEntry: Codable {
        let rule: String
        let operatorName: String
        let a: String
        let b: String
        let stationCode: String
        let stationName: String
        let site: [Double]?
        let evidence: String
        /// R4b triage only: junction, notJunction or unknown. Not part of the key.
        var likely: String? = nil
        var key: String {
            var k = "\(rule)|\(operatorName)|\(a)|\(b)|\(stationCode)"
            if let site { k += String(format: "|%.5f,%.5f", site[0], site[1]) }
            return k
        }
    }

    private struct Baseline: Codable {
        var format: String
        var r1r2: [BaselineEntry]
        var r4: [BaselineEntry]
        var r4b: [BaselineEntry]?
        var registryStationCodes: [String]
    }

    private static func entry(_ h: Hit) -> BaselineEntry {
        BaselineEntry(rule: h.rule, operatorName: h.pair.a.operatorName, a: h.pair.a.label, b: h.pair.b.label,
                      stationCode: h.code, stationName: h.name,
                      site: h.site.map { [(($0.lon * 1e5).rounded()) / 1e5, (($0.lat * 1e5).rounded()) / 1e5] },
                      evidence: h.evidence)
    }

    private static func nearestStation(_ operatorName: String, _ p: Coordinate, _ ctx: Context) -> (code: String, name: String) {
        var best: (d: Double, code: String, name: String)?
        for (id, list) in ctx.byLine where id.operatorName == operatorName {
            for s in list {
                let d = meters(s.at, p)
                if d < (best?.d ?? .infinity) || (d == best?.d && s.code < (best?.code ?? "")) { best = (d, s.code, s.name) }
            }
        }
        return best.map { ($0.code, $0.name) } ?? ("none", "no station")
    }

    private struct Scan {
        var sameLine: [(Gap, String)] = []
        var r1r2: [Hit] = []
        var r4: [Hit] = []
        var r4b: [Hit] = []
        var registryCodes: [String] = []
    }

    /// Everything that does not depend on which junction rows are removed, built once per process:
    /// the 12 MB section survey, its 400k-vertex network, the package and the station index.
    private struct Shared {
        let ctx: Context
        let net: Network
        let coordinates: [String: [Coordinate]]
        let reviewed: Set<Pair>
        let markReasonProblems: [String]
    }

    private static let shared: Result<Shared, Error> = Result {
        let root = try PortFixtures.repositoryRoot()
        let ctx = try loadContext(root)
        let registry = try PhysicalRailJunctionRegistry(
            data: Data(contentsOf: root.appending(path: registryPath)))
        var coordinates: [String: [Coordinate]] = [:]
        for j in registry.junctions(for: "jp") {
            coordinates[j.id] = [Q(j.from.coordinate).coordinate, Q(j.to.coordinate).coordinate]
        }
        let marks = try JSONDecoder().decode(
            MarksDocument.self, from: Data(contentsOf: root.appending(path: marksPath)))
        var reviewed = Set<Pair>()
        var problems: [String] = []
        for mark in marks.marks {
            if !marks.reasons.contains(mark.reason) {
                problems.append("mark \(mark.operator) \(mark.lineA)/\(mark.lineB) has reason '\(mark.reason)' outside \(marks.reasons)")
            }
            reviewed.insert(Pair(
                Identity(operatorName: mark.operator, line: mark.lineA, railwayClass: mark.classA),
                Identity(operatorName: mark.operator, line: mark.lineB, railwayClass: mark.classB)))
        }
        return Shared(ctx: ctx, net: Network(ctx.features), coordinates: coordinates,
                      reviewed: reviewed, markReasonProblems: problems)
    }

    private static func scan(removingJunctionIDs: Set<String> = []) throws -> Scan {
        let shared = try Self.shared.get()
        let (ctx, net, reviewed) = (shared.ctx, shared.net, shared.reviewed)
        #expect(shared.markReasonProblems.isEmpty, "\(shared.markReasonProblems)")
        let joins = Joins(ctx.registryRows, removing: removingJunctionIDs, coordinates: shared.coordinates)

        var result = Scan()
        result.sameLine = sameLineGaps(ctx, joins, reviewed)
        result.r1r2 = r1Hits(ctx, net, joins, reviewed) + r2Hits(ctx, net, joins, reviewed)
        result.r4 = r4Hits(ctx, net, joins, reviewed, sharedCode: false)
        // A pair R4 reports at a station (from either line's row end) is not reported again by R4b.
        let r4Sites = Set(result.r4.map { "\($0.pair.a.operatorName)|\($0.pair.a.label)|\($0.pair.b.label)|\($0.code)" })
        result.r4b = r4Hits(ctx, net, joins, reviewed, sharedCode: true).filter {
            !r4Sites.contains("\($0.pair.a.operatorName)|\($0.pair.a.label)|\($0.pair.b.label)|\($0.code)")
        }
        result.registryCodes = registryCodeIssues(ctx)
        return result
    }

    // MARK: tier 1

    private static func sameLineGaps(_ ctx: Context, _ joins: Joins, _ reviewed: Set<Pair>) -> [(Gap, String)] {
        struct End { let identity: Identity; let at: Coordinate }
        var cells: [[Int]: [End]] = [:]
        func cell(_ c: Coordinate) -> [Int] { [Int((c.lon * 1000).rounded()), Int((c.lat * 1000).rounded())] }
        for feature in ctx.features {
            let p = feature.properties
            guard !p.operator.isEmpty, !p.lineName.isEmpty else { continue }
            let identity = Identity(operatorName: p.operator, line: p.lineName, railwayClass: p.railwayClassCode)
            for line in feature.lines {
                for c in [line.first, line.last].compactMap({ $0 }) {
                    cells[cell(c), default: []].append(End(identity: identity, at: c))
                }
            }
        }
        var found: [Pair: [Coordinate]] = [:]
        for (key, ends) in cells {
            for dx in -1...1 { for dy in -1...1 {
                guard let others = cells[[key[0] + dx, key[1] + dy]] else { continue }
                for e in ends { for o in others
                where e.identity.operatorName == o.identity.operatorName && e.identity.line == o.identity.line
                    && e.identity < o.identity && meters(e.at, o.at) <= toleranceMeters {
                    found[Pair(e.identity, o.identity), default: []].append(e.at)
                } }
            } }
        }
        var gaps: [(Gap, String)] = []
        for (pair, points) in found.sorted(by: { ($0.key.a, $0.key.b) < ($1.key.a, $1.key.b) })
        where !reviewed.contains(pair) {
            var seen: [Coordinate] = []
            for p in points.sorted(by: { ($0.lon, $0.lat) < ($1.lon, $1.lat) }) where !joins.joined(pair.a, pair.b, p, reach: junctionReachMeters)
                && !seen.contains(where: { meters($0, p) <= toleranceMeters }) {
                seen.append(p)
                let n = nearestStation(pair.a.operatorName, p, ctx)
                gaps.append((Gap(pair: pair, at: p), "\(n.code) \(n.name)"))
            }
        }
        return gaps
    }

    // MARK: R1

    private static func r1Hits(_ ctx: Context, _ net: Network, _ joins: Joins, _ reviewed: Set<Pair>) -> [Hit] {
        var hits: [String: Hit] = [:]
        func add(_ pair: Pair, _ p: Coordinate, _ detail: String) {
            guard !reviewed.contains(pair) else { return }
            let n = nearestStation(pair.a.operatorName, p, ctx)
            var hit = Hit(rule: "R1", pair: pair, code: n.code, name: n.name, site: p, evidence: detail)
            let h = junctionHint(pair, near: p, net)
            (hit.locus, hit.hint) = (h.at ?? p, h.text)
            hits[hit.key] = hits[hit.key] ?? hit
        }
        for line in ctx.lines where !line.paired {
            let runs = line.segments.map { carryRun($0, net) }
            for run in runs.compactMap({ $0 }) {
                for c in run.crossings {
                    for pair in unjoinedPairs(c.from, c.to, at: c.at.coordinate, reach: junctionReachMeters, joins) {
                        add(pair, c.at.coordinate, "row \(line.id), crossing inside one interval")
                    }
                }
            }
            for (r1, r2) in zip(runs, runs.dropFirst()) {
                guard let r1, let r2 else { continue }
                for pair in unjoinedPairs(r1.last, r2.first, at: r1.end, reach: boundaryReachMeters, joins) {
                    add(pair, r1.end, "row \(line.id), seam between consecutive intervals")
                }
            }
        }
        return hits.values.sorted { $0.key < $1.key }
    }

    // MARK: R2

    private static func legInterval(_ leg: ThroughServices.Pattern.Leg, boundaryIsTo: Bool,
                                    _ ctx: Context, _ net: Network) -> (set: Set<Identity>, at: Coordinate)? {
        guard let line = ctx.lineByID[leg.lineID] else { return nil }
        let codes = line.stations.map(\.code)
        guard let i = codes.firstIndex(of: leg.fromStationCode),
              let j = codes.firstIndex(of: leg.toStationCode) else { return nil }
        let forward = j > i
        let k = boundaryIsTo ? (forward ? j - 1 : j) : (forward ? i : i - 1)
        guard line.segments.indices.contains(k), let run = carryRun(line.segments[k], net) else { return nil }
        if boundaryIsTo { return (forward ? run.last : run.first, forward ? run.end : run.start) }
        return (forward ? run.first : run.last, forward ? run.start : run.end)
    }

    private static func r2Hits(_ ctx: Context, _ net: Network, _ joins: Joins, _ reviewed: Set<Pair>) -> [Hit] {
        var hits: [String: (Hit, Set<String>)] = [:]
        for pattern in ctx.services {
            for (x, y) in zip(pattern.legs, pattern.legs.dropFirst()) {
                guard let a = legInterval(x, boundaryIsTo: true, ctx, net),
                      let b = legInterval(y, boundaryIsTo: false, ctx, net) else { continue }
                for pair in unjoinedPairs(a.set, b.set, at: a.at, reach: boundaryReachMeters, joins)
                where !reviewed.contains(pair) {
                    let name = ctx.lineByID[x.lineID]?.stations.first { $0.code == x.toStationCode }?.name ?? "?"
                    var hit = Hit(rule: "R2", pair: pair, code: x.toStationCode, name: name, site: nil, evidence: "")
                    let h = junctionHint(pair, near: a.at, net)
                    (hit.locus, hit.hint) = (h.at ?? a.at, h.text)
                    var entry = hits[hit.key] ?? (hit, [])
                    entry.1.insert(pattern.id)
                    hits[hit.key] = entry
                }
            }
        }
        return hits.values.map { h, services in
            Hit(rule: h.rule, pair: h.pair, code: h.code, name: h.name, site: nil,
                evidence: "service " + services.sorted().joined(separator: ","), locus: h.locus, hint: h.hint)
        }.sorted { $0.key < $1.key }
    }

    // MARK: R4

    /// `sharedCode` false is R4 (line B from stations.json, only when it does not code the
    /// station under the row's own line); true is R4b (line B from the package rows using
    /// the code, minus every pair R4 asks about).
    private static func r4Hits(_ ctx: Context, _ net: Network, _ joins: Joins, _ reviewed: Set<Pair>,
                               sharedCode: Bool) -> [Hit] {
        let rule = sharedCode ? "R4b" : "R4"
        var best: [String: (d: Double, hit: Hit)] = [:]
        for line in ctx.lines where !line.paired && !line.isLoop && !line.segments.isEmpty {
            for end in [0, line.stations.count - 1] where line.stations.indices.contains(end) {
                let s = line.stations[end]
                guard let run = carryRun(line.segments[end == 0 ? 0 : line.segments.count - 1], net) else { continue }
                let owners = ctx.linesOfCode[s.code] ?? []
                let packageOwners = ctx.packageLinesOfCode[s.code] ?? []
                for a in end == 0 ? run.first : run.last {
                    func otherLines(_ set: Set<Identity2>) -> Set<String> {
                        Set(set.filter { $0.operatorName == a.operatorName && $0.line != a.line }.map(\.line))
                    }
                    let r4Others = owners.contains(Identity2(operatorName: a.operatorName, line: a.line))
                        ? [] : otherLines(owners)
                    let others = sharedCode ? otherLines(packageOwners).subtracting(r4Others) : r4Others
                    if others.isEmpty { continue }
                    for t in net.touchesOf[a] ?? [] where others.contains(t.other.line) {
                        let site = t.at.coordinate
                        let d = meters(site, s.at)
                        guard d <= terminusRangeMeters else { continue }
                        let pair = Pair(a, t.other)
                        // R4 asks whether the pair meets at this terminus: a registry row for the
                        // pair coded to this station and within the terminus range of it joins it,
                        // so another coincident vertex of the same joined pair is not a new hit.
                        if reviewed.contains(pair) || joins.joined(a, t.other, site, reach: junctionReachMeters)
                            || joins.joined(a, t.other, atStation: s.code, s.at, reach: terminusRangeMeters) { continue }
                        let hit = Hit(rule: rule, pair: pair, code: s.code, name: s.name, site: site,
                                      evidence: "row \(line.id) ends at \(s.code) \(s.name), coded under another line" + (sharedCode ? " in the package" : ""),
                                      locus: site, hint: String(format: "zeroLength at identical shared vertex (%.5f, %.5f), %.0f m from the station", site.lon, site.lat, d))
                        // One hit per (pair, station): keep the unjoined shared vertex nearest the station.
                        let id = "\(pair.a.label)|\(pair.b.label)|\(pair.a.operatorName)|\(s.code)"
                        if d < (best[id]?.d ?? .infinity) || (d == best[id]?.d && hit.key < (best[id]?.hit.key ?? "")) {
                            best[id] = (d, hit)
                        }
                    }
                }
            }
        }
        return best.values.map(\.hit).sorted { $0.key < $1.key }
    }

    // MARK: tier 3

    private static func registryCodeIssues(_ ctx: Context) -> [String] {
        ctx.registryRows.filter { row in
            guard row.region == "jp", let code = row.stationCode else { return false }
            let lineIDs = row.lineIDs ?? []
            if !lineIDs.isEmpty, lineIDs.allSatisfy({ id in
                ctx.lineByID[id]?.stations.contains { $0.code == code } == true }) { return false }
            func uses(_ e: RegistryRow.Endpoint) -> Bool {
                ctx.byLine[Identity2(operatorName: e.identity.operatorName, line: e.identity.lineName)]?
                    .contains { $0.code == code } == true
            }
            return !(uses(row.from) && uses(row.to))
        }.map(\.id).sorted()
    }

    // MARK: - messages

    private static func fix(_ h: Hit) -> String {
        let what: String
        switch h.rule {
        case "R1": what = "need a crossing inside one package row"
        case "R2": what = "are crossed by a through service"
        case "R4b": what = "meet where a row terminates at a station another package row of the operator uses"
        default: what = "meet where a row terminates"
        }
        return "[\(h.rule)] \(h.pair.a.operatorName): \(h.pair.a.label) and \(h.pair.b.label) \(what) at \(h.code) \(h.name)"
            + (h.site.map { String(format: " (%.5f, %.5f)", $0.lon, $0.lat) } ?? "")
            + " without a junction (\(h.evidence)): add a junction row to \(registryPath) (pattern: astram-kencho-class16-class24)"
            + " or a reviewed mark to \(marksPath); a gap that was already known belongs in \(baselinePath)"
    }

    /// R4b entries for a regenerated baseline, keeping each surviving entry's triage tag
    /// (a new entry is `unknown` until reviewed).
    private static func triaged(_ hits: [Hit], previous: [BaselineEntry]) -> [BaselineEntry] {
        let tags = Dictionary(previous.map { ($0.key, $0.likely) }, uniquingKeysWith: { a, _ in a })
        return hits.map { h -> BaselineEntry in
            var e = Self.entry(h)
            e.likely = (tags[e.key] ?? nil) ?? "unknown"
            return e
        }.sorted { $0.key < $1.key }
    }

    private static func loadBaseline() throws -> Baseline? {
        let url = try PortFixtures.repositoryRoot().appending(path: baselinePath)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try JSONDecoder().decode(Baseline.self, from: data)
    }

    // MARK: - maintenance document

    private static func junctionGapsDocument(_ scan: Scan, _ r4b: [BaselineEntry]) -> String {
        func likely(_ tag: String) -> Int { r4b.filter { $0.likely == tag }.count }
        func section(_ hits: [Hit]) -> String {
            hits.map { h in
                var lines = ["- **\(h.pair.a.operatorName)**: \(h.pair.a.label) / \(h.pair.b.label) at \(h.code) \(h.name)"]
                if let l = h.locus { lines.append(String(format: "  - site: (%.5f, %.5f)", l.lon, l.lat)) }
                lines.append("  - evidence: \(h.evidence)")
                lines.append("  - suggested junction: \(h.hint)")
                return lines.joined(separator: "\n")
            }.joined(separator: "\n")
        }
        let r1 = scan.r1r2.filter { $0.rule == "R1" }, r2 = scan.r1r2.filter { $0.rule == "R2" }
        return """
            # Junction gaps (2026-11-06)

            Generated by `RegressionGuardTopologyGaps`; it matches `\(baselinePath)` exactly.
            Regenerate both with:

            `\(regenerateCommand)`

            Each entry is a different-line pair of one operator that the physical graph cannot cross
            because no junction row in `\(registryPath)` joins the two identities there. Fix an entry
            by adding a row (pattern: `astram-kencho-class16-class24`, kind as suggested) or a reviewed
            mark in `\(marksPath)`, then delete its baseline entry (the guard fails until you do).
            Suggested kinds are mechanical: a shared vertex of both identities is `zeroLength`;
            otherwise the nearest endpoint pair decides `shortLink` (at most 30 m) or `osmConnector`.
            Registry rows whose `stationCode` is not shared by their lines are listed under
            `registryStationCodes` in the baseline JSON (\(scan.registryCodes.count) today).

            ## 1. Certification gaps (R1 row geometry \(r1.count), R2 through-service boundary \(r2.count))

            ### R1 (\(r1.count))

            \(section(r1))

            ### R2 (\(r2.count))

            \(section(r2))

            ## 2. Structural branch-end sites (R4, \(scan.r4.count))

            A package row ends at a station coded under another line of the operator, and the two
            identities share a vertex within 600 m. Not every one is a missing through-service; each needs review.

            \(section(scan.r4))

            ## 3. Package-coded branch-end sites (R4b, \(scan.r4b.count))

            As R4, but the other line is a package row of the operator that uses the station's code,
            where stations.json does not code it under that line (広島 芸備線/山陽線 was one: 008029 is
            芸備線's code and the package's 山陽線 row runs through it). Seeded 2026-11-07 and triaged in the
            baseline's `likely` field (junction \(likely("junction")), notJunction \(likely("notJunction")),
            unknown \(likely("unknown"))). Each needs review before a row is added.

            \(section(scan.r4b))

            """
    }

    // MARK: - tests

    @Test("Same-line class seams have a junction or a reviewed mark")
    func jpSameLineSeamsAreJoined() throws {
        let scan = try Self.scan()
        let lines = scan.sameLine.map { g, station in
            "\(g.pair.a.operatorName): \(g.pair.a.label) and \(g.pair.b.label) meet at \(station) (\(g.at.lon), \(g.at.lat)) without a junction: add a junction row to \(Self.registryPath) (pattern: astram-kencho-class16-class24) or a reviewed mark to \(Self.marksPath)"
        }
        #expect(lines.isEmpty, """
            \(lines.count) same-line class seam(s) without a junction:
            \(lines.prefix(Self.listedGapLimit).joined(separator: "\n"))
            """)
    }

    @Test("Different-line gaps (R1, R2, R4, R4b) and registry station codes match the checked-in baseline")
    func differentLineGapsMatchBaseline() throws {
        let scan = try Self.scan()
        if ProcessInfo.processInfo.environment["JTM_REGENERATE_EXPECTATIONS"] == "1" {
            let baseline = Baseline(
                format: "jtm-topology-gap-baseline/1",
                r1r2: scan.r1r2.map(Self.entry).sorted { $0.key < $1.key },
                r4: scan.r4.map(Self.entry).sorted { $0.key < $1.key },
                r4b: Self.triaged(scan.r4b, previous: (try? Self.loadBaseline())?.r4b ?? []),
                registryStationCodes: scan.registryCodes)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            var data = try encoder.encode(baseline)
            data.append(0x0A)
            let root = try PortFixtures.repositoryRoot()
            try data.write(to: root.appending(path: Self.baselinePath))
            try Self.junctionGapsDocument(scan, baseline.r4b ?? []).write(
                to: root.appending(path: Self.documentPath), atomically: true, encoding: .utf8)
            return
        }
        guard let baseline = try Self.loadBaseline() else {
            Issue.record("\(Self.baselinePath) is missing. Generate it with:\n  \(Self.regenerateCommand)")
            return
        }
        print("""
            INFO topology gap baseline: R1+R2 \(baseline.r1r2.count) \
            (R1 \(baseline.r1r2.filter { $0.rule == "R1" }.count), R2 \(baseline.r1r2.filter { $0.rule == "R2" }.count)), \
            R4 \(baseline.r4.count), R4b \(baseline.r4b?.count ?? 0), registry station-code exceptions \(baseline.registryStationCodes.count)
            """)

        var problems: [String] = []
        func ratchet(_ hits: [Hit], _ known: [BaselineEntry], _ section: String) {
            let knownKeys = Set(known.map(\.key)), hitKeys = Set(hits.map(\.key))
            for h in hits where !knownKeys.contains(h.key) { problems.append(Self.fix(h)) }
            for e in known where !hitKeys.contains(e.key) {
                problems.append("[\(e.rule)] \(section) baseline entry \(e.operatorName): \(e.a) / \(e.b) at \(e.stationCode) \(e.stationName) no longer occurs; remove it from \(Self.baselinePath) (the gap is fixed)")
            }
        }
        ratchet(scan.r1r2, baseline.r1r2, "r1r2")
        ratchet(scan.r4, baseline.r4, "r4")
        ratchet(scan.r4b, baseline.r4b ?? [], "r4b")
        for e in baseline.r4b ?? [] where !["junction", "notJunction", "unknown"].contains(e.likely ?? "") {
            problems.append("[R4b] baseline entry \(e.operatorName): \(e.a) / \(e.b) at \(e.stationCode) has likely '\(e.likely ?? "")'; use junction, notJunction or unknown")
        }
        for id in scan.registryCodes where !baseline.registryStationCodes.contains(id) {
            problems.append("registry row \(id) has a stationCode that is not used by every row in its lineIDs nor by both identities' stations (TripConnectivity matches codes exactly): use the package code in \(Self.registryPath), or list the row in \(Self.baselinePath) registryStationCodes if the lines genuinely share no code")
        }
        for id in baseline.registryStationCodes where !scan.registryCodes.contains(id) {
            problems.append("registryStationCodes baseline entry \(id) no longer occurs; remove it from \(Self.baselinePath) (the code is fixed)")
        }
        #expect(problems.isEmpty, """
            \(problems.count) topology gap difference(s) against \(Self.baselinePath):
            \(problems.prefix(Self.listedGapLimit).joined(separator: "\n"))
            """)
    }

    /// Removing the 稲荷町 row must move the nearest unjoined shared vertex of 本線/皆実線 to
    /// the station, giving an R4 hit that the baseline (built with the row present) lacks.
    @Test("Without its junction row 稲荷町 本線/皆実線 is a new R4 hit")
    func inarichoWouldBeCaught() throws {
        let baseline = try #require(try Self.loadBaseline(), "\(Self.baselinePath) is missing")
        let scan = try Self.scan(removingJunctionIDs: ["hiroden-inaricho-main-minami"])
        let known = Set(baseline.r4.map(\.key))
        let fresh = scan.r4.filter {
            $0.pair.a.operatorName == "広島電鉄" && $0.name == "稲荷町"
                && Set([$0.pair.a.line, $0.pair.b.line]) == ["本線", "皆実線"] && !known.contains($0.key)
        }
        #expect(!fresh.isEmpty, "removing hiroden-inaricho-main-minami must add an R4 hit at 稲荷町 that is not in the baseline")
    }

    /// 芸備線 ends at 広島 008029, which stations.json codes only under 芸備線 (山陽線 is 008031),
    /// so R4 skips it; the package's 山陽線 row uses 008029, so R4b must report the pair once the row is gone.
    @Test("Without its junction row 広島 山陽線/芸備線 is a new R4b hit")
    func hiroshimaWouldBeCaught() throws {
        let baseline = try #require(try Self.loadBaseline(), "\(Self.baselinePath) is missing")
        let known = Set((baseline.r4b ?? []).map(\.key))
        func hits(_ scan: Scan) -> [Hit] {
            scan.r4b.filter {
                $0.pair.a.operatorName == "西日本旅客鉄道" && $0.code == "008029"
                    && Set([$0.pair.a.line, $0.pair.b.line]) == ["山陽線", "芸備線"]
            }
        }
        #expect(hits(try Self.scan()).isEmpty, "with hiroshima-sanyo-geibi present 広島 山陽線/芸備線 must not be an R4b hit")
        let fresh = hits(try Self.scan(removingJunctionIDs: ["hiroshima-sanyo-geibi"])).filter { !known.contains($0.key) }
        #expect(!fresh.isEmpty, "removing hiroshima-sanyo-geibi must add an R4b hit at 広島 that is not in the baseline")
    }

    @Test("稲荷町 本線@v and 皆実線@v are joined only by the registry row")
    func inarichoBoundaryNeedsItsRow() throws {
        let root = try PortFixtures.repositoryRoot()
        let v = Coordinate(lon: 132.47195523, lat: 34.39289541)
        let sections = try Self.shared.get().ctx.features.filter { f in
            f.properties.operator == "広島電鉄" && ["本線", "皆実線"].contains(f.properties.lineName)
                && f.lines.contains { line in [line.first, line.last].contains { $0.map { Self.meters($0, v) < 1 } ?? false } }
        }
        #expect(Set(sections.map(\.properties.lineName)) == ["本線", "皆実線"])
        func identity(_ line: String) -> RouteGraph.TrackIdentity {
            .init(operatorName: "広島電鉄", lineName: line, railwayClassCode: "21")
        }
        let main = RouteGraph.physicalNodeKey(v, identity: identity("本線"))
        let minami = RouteGraph.physicalNodeKey(v, identity: identity("皆実線"))
        let registry = try PhysicalRailJunctionRegistry(
            data: Data(contentsOf: root.appending(path: Self.registryPath)))
        let junction = try #require(registry.junctions(for: "jp").first { $0.id == "hiroden-inaricho-main-minami" })

        let absent = RouteGraph.build(from: sections, policy: .physicalRailway)
        #expect(!RouteSolver.physicalBoundaryIsProven(from: main, to: minami, graph: absent, rideDate: "2026-10-10"))
        let linked = RouteGraph.build(from: sections, policy: .physicalRailway, junctions: [junction])
        #expect(linked.rejectedPhysicalJunctionIDs.isEmpty)
        #expect(RouteSolver.physicalBoundaryIsProven(from: main, to: minami, graph: linked, rideDate: "2026-10-10"))
        #expect(!RouteSolver.physicalBoundaryIsProven(from: main, to: minami, graph: linked, rideDate: "2025-08-02"))
    }
}
