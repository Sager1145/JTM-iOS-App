import Foundation
import Testing

@_spi(Testing) @testable import RailCore

/// Regression guard: every geometry-bearing history event must keep its stamps.
///
/// Bug class: the history package knows about an opening/closure event, but a
/// builder match silently dropped or narrowed its stamp on the geometry (the
/// 富山駅南北接続線 2015-03-14 stamps: the sections bbox shrank to 1 of 4
/// features and the stations stamp vanished, so the section was solved before
/// its opening).
///
/// Events source: `app/scripts/railway/jp-rail-history-events.json` (in this
/// repo; the builder that turns it into `app/data/rail-history.json` is
/// website-side). Considered events: `events[]` (closures/relocations; no
/// `kind` means closure) and `temporal_events[]` of kind opening,
/// station_opening, closure, relocation, suspension, resumption. Renames,
/// operator transfers and station_closure are not geometry-stamped by design.
/// There is no reviewed-partial-opening list in this repo, so partial scope is
/// derived from the event itself (`expected.business_km`, `geometry.selector`).
///
/// Rules, per event `<id>` (stamp = history_id `<id>` or `<id>.*`):
/// 1. at least one stamp exists;
/// 2. every declared date (service_periods when present, else
///    valid_from/valid_to/date) is a bound on those stamps;
/// 3. every retirement stamp's bbox contains >= 1 real feature of its
///    line/operator (same containment rule as `RailHistory.apply`);
/// 4. for events that use bbox retirement stamps (openings, relocations):
///    - a line with sections needs a sections stamp, and a line with stations
///      needs a stations stamp;
///    - a whole-line event (line length <= 1.35 x `expected.business_km`, or
///      selector scope whole_identity when no km is declared) needs EVERY
///      section and station feature of the line (inside `selector.bbox` /
///      `selector.stations` when declared) inside some stamp bbox;
///    - a partial event needs stamped section length >= 0.6 x
///      `expected.business_km`, and every station inside a sections stamp bbox
///      must also be inside a stations stamp bbox.
/// Raw JSON bounds are used; decoding via the typed loaders costs ~15 s.
///
/// Pre-existing gaps live in the shrink-only `Resources/history-stamp-baseline.json`
/// (a new violation fails; a baseline entry that no longer occurs fails, remove
/// it). Regenerate with JTM_REGENERATE_EXPECTATIONS=1; listed in
/// docs/maintenance/2026-11-06-history-stamp-gaps.md.
@Suite("RegressionGuardHistoryStamps")
struct RegressionGuardHistoryStamps {
    static let baselinePath = "ios/RailKit/Tests/RailCoreTests/RegressionGuards/Resources/history-stamp-baseline.json"
    static let documentPath = "docs/maintenance/2026-11-06-history-stamp-gaps.md"
    static let regenerateCommand =
        "JTM_REGENERATE_EXPECTATIONS=1 swift test --package-path ios/RailKit --filter RegressionGuardHistoryStamps"
    static let baselineReason =
        "pre-existing since d44bdc5cd (earliest commit checked; no earlier revision stamped these features); "
        + "needs N02-edition review (new_since_release may exclude pre-existing features)"

    /// One rule violation. `key` identifies it in the shrink-only baseline.
    struct Violation {
        let event: String
        let line: String
        let kind: String
        let count: Int
        let of: Int
        let message: String
        var key: String { "\(event)|\(kind)|\(count)/\(of)" }
    }

    struct BaselineEntry: Codable {
        let event: String
        let line: String
        let kind: String
        let count: Int
        let of: Int
        let reason: String
        var key: String { "\(event)|\(kind)|\(count)/\(of)" }
    }

    struct Baseline: Codable {
        let format: String
        let entries: [BaselineEntry]
    }

    private static let geometryKinds: Set<String> = [
        "opening", "station_opening", "closure", "relocation", "suspension", "resumption",
    ]
    private static let coverageKinds: Set<String> = ["opening", "relocation"]

    struct Event {
        let id: String
        let kind: String
        let line: String
        let operatorName: String
        let dates: Set<String>
        let expectedKm: Double?
        let scope: String?
        let selectorBox: [Double]?
        let selectorStations: Set<String>?
    }

    struct Bounds {
        let minLon, minLat, maxLon, maxLat, km: Double
        let name: String?
        func inside(_ b: [Double]) -> Bool {
            minLon >= b[0] && minLat >= b[1] && maxLon <= b[2] && maxLat <= b[3]
        }
    }

    typealias Geometry = [String: [String: [Bounds]]]  // target -> "line\u{1}op" -> features

    // MARK: parsing

    private static func object(_ url: URL) throws -> [String: Any] {
        try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private static func dates(of entry: [String: Any]) -> Set<String> {
        var out = Set<String>()
        // service_periods are the event's service bounds; its valid_to is then
        // only the later legal date (typhoon suspension before formal closure).
        if let periods = entry["service_periods"] as? [[Any]] {
            for period in periods { for case let s as String in period { out.insert(s) } }
            if !out.isEmpty { return out }
        }
        for key in ["valid_from", "valid_to", "date"] {
            if let s = entry[key] as? String { out.insert(s) }
        }
        for key in ["service_validity", "infrastructure_validity"] {
            for case let s as String in (entry[key] as? [Any]) ?? [] { out.insert(s) }
        }
        return out
    }

    private static func doubles(_ value: Any?) -> [Double]? {
        guard let items = value as? [Any] else { return nil }
        let out = items.compactMap { ($0 as? NSNumber)?.doubleValue }
        return out.count == items.count ? out : nil
    }

    private static func events(_ source: [String: Any]) -> [Event] {
        var out: [Event] = []
        func make(_ e: [String: Any], id: String, kind: String) -> Event {
            let after = e["after"] as? [String: Any]
            let selector = (e["geometry"] as? [String: Any])?["selector"] as? [String: Any]
            let km = (e["expected"] as? [String: Any])?["business_km"] as? NSNumber
            return Event(
                id: id, kind: kind,
                line: (e["line"] as? String) ?? (after?["line"] as? String) ?? "?",
                operatorName: (e["operator"] as? String) ?? (after?["operator"] as? String) ?? "?",
                dates: dates(of: e), expectedKm: km?.doubleValue,
                scope: selector?["scope"] as? String,
                selectorBox: doubles(selector?["bbox"]).flatMap { $0.count == 4 ? $0 : nil },
                selectorStations: (selector?["stations"] as? [String]).map(Set.init))
        }
        for e in (source["events"] as? [[String: Any]]) ?? [] {
            guard let id = e["id"] as? String else { continue }
            out.append(make(e, id: id, kind: (e["kind"] as? String) ?? "closure"))
        }
        for e in (source["temporal_events"] as? [[String: Any]]) ?? [] {
            guard let id = e["id"] as? String, let kind = e["kind"] as? String,
                geometryKinds.contains(kind)
            else { continue }
            out.append(make(e, id: id, kind: kind))
        }
        return out
    }

    private static func collect(_ value: Any, into out: inout [[(Double, Double)]]) {
        guard let items = value as? [Any], !items.isEmpty else { return }
        if items[0] is NSNumber { return }
        if let first = items[0] as? [Any], first.first is NSNumber {
            var line: [(Double, Double)] = []
            for case let p as [Any] in items where p.count >= 2 {
                if let lon = (p[0] as? NSNumber)?.doubleValue,
                    let lat = (p[1] as? NSNumber)?.doubleValue
                { line.append((lon, lat)) }
            }
            out.append(line)
            return
        }
        for item in items { collect(item, into: &out) }
    }

    private static func featureBounds(root: URL) throws -> Geometry {
        var result: Geometry = [:]
        for (target, file) in [("sections", "rail-sections.json"), ("stations", "stations.json")] {
            let collection = try object(root.appending(path: "app/data/\(file)"))
            for case let f as [String: Any] in (collection["features"] as? [Any]) ?? [] {
                let p = (f["properties"] as? [String: Any]) ?? [:]
                let line = (p["line_name"] ?? p["N02_003"]) as? String ?? ""
                let op = (p["operator"] ?? p["N02_004"]) as? String ?? ""
                var lines: [[(Double, Double)]] = []
                collect((f["geometry"] as? [String: Any])?["coordinates"] as Any, into: &lines)
                let pts = lines.flatMap { $0 }
                guard let first = pts.first else { continue }
                var b = (first.0, first.1, first.0, first.1)
                for q in pts {
                    b = (min(b.0, q.0), min(b.1, q.1), max(b.2, q.0), max(b.3, q.1))
                }
                var km = 0.0
                for l in lines {
                    for (a, c) in zip(l, l.dropFirst()) {
                        let dx = (c.0 - a.0) * 111.32 * cos(a.1 * .pi / 180)
                        let dy = (c.1 - a.1) * 110.57
                        km += (dx * dx + dy * dy).squareRoot()
                    }
                }
                result[target, default: [:]]["\(line)\u{1}\(op)", default: []].append(
                    Bounds(minLon: b.0, minLat: b.1, maxLon: b.2, maxLat: b.3, km: km,
                           name: p["station_name"] as? String))
            }
        }
        return result
    }

    // MARK: the guard

    /// Returns one message per violation. `only` restricts the events checked.
    static func violations(
        events: [Event], history: [String: Any], geometry: Geometry, only: Set<String>? = nil
    ) -> [Violation] {
        var stampDates: [String: Set<String>] = [:]
        func addStamp(_ entry: [String: Any]) {
            guard let id = entry["history_id"] as? String else { return }
            stampDates[id, default: []].formUnion(dates(of: entry))
        }
        for key in ["retirements", "identity_periods"] {
            for case let e as [String: Any] in (history[key] as? [Any]) ?? [] { addStamp(e) }
        }
        for key in ["sections", "stations"] {
            for case let f as [String: Any] in (history[key] as? [Any]) ?? [] {
                addStamp((f["properties"] as? [String: Any]) ?? [:])
            }
        }
        struct Retirement {
            let id, line, op: String
            let box: [Double]
            let targets: [String]
        }
        var retirements: [Retirement] = []
        for case let r as [String: Any] in (history["retirements"] as? [Any]) ?? [] {
            guard let id = r["history_id"] as? String, let m = r["match"] as? [String: Any],
                let line = m["line_name"] as? String, let op = m["operator"] as? String,
                let box = doubles(m["bbox"]), box.count == 4
            else { continue }
            retirements.append(Retirement(
                id: id, line: line, op: op, box: box,
                targets: (m["targets"] as? [String]) ?? ["sections", "stations"]))
        }
        func stamps(_ e: Event) -> [Retirement] {
            retirements.filter { $0.id == e.id || $0.id.hasPrefix(e.id + ".") }
        }
        // Rule 3 input: retirement ids whose bbox contains no feature of their line.
        var deadStamps = Set<String>()
        for r in retirements {
            let hit = r.targets.contains { t in
                (geometry[t]?["\(r.line)\u{1}\(r.op)"] ?? []).contains { $0.inside(r.box) }
            }
            if !hit { deadStamps.insert(r.id) }
        }

        let fixTail = "restore the stamp (see git log -S <id>) and bump revision; builder source: "
            + "jp-rail-history-events.json allow_preexisting_geometry (website-side builder)"
        var out: [Violation] = []
        for event in events where only?.contains(event.id) ?? true {
            let fix = fixTail.replacingOccurrences(of: "<id>", with: event.id)
            let ids = stampDates.keys.filter { $0 == event.id || $0.hasPrefix(event.id + ".") }
            let date = event.dates.sorted().joined(separator: "/")
            let head = "event \(event.id) (\(event.line), \(date), \(event.kind))"
            var problems: [Violation] = []
            func add(_ kind: String, _ count: Int, of total: Int, _ message: String) {
                problems.append(Violation(
                    event: event.id, line: event.line, kind: kind, count: count, of: total,
                    message: message))
            }
            if ids.isEmpty {
                add("no-stamp", 0, of: 0, "\(head) has no geometry stamp in rail-history.json: \(fix)")
            } else {
                let carried = ids.reduce(into: Set<String>()) { $0.formUnion(stampDates[$1]!) }
                let missing = event.dates.subtracting(carried).sorted()
                if !missing.isEmpty {
                    add("date-bound", missing.count, of: event.dates.count,
                        "\(head) stamps carry no bound for \(missing.joined(separator: ", ")): "
                        + "align valid_from/valid_to with the event date; \(fix)")
                }
                let dead = ids.filter { deadStamps.contains($0) }.sorted()
                if !dead.isEmpty {
                    add("dead-bbox", dead.count, of: ids.count,
                        "\(head) stamp bbox matches no geometry of line \(event.line) "
                        + "(stamps \(dead.joined(separator: ", "))): fix the match bbox/line/operator; \(fix)")
                }
            }
            // Rule 4: coverage of the line's real geometry.
            let mine = stamps(event).filter { $0.line == event.line && $0.op == event.operatorName }
            if coverageKinds.contains(event.kind), !mine.isEmpty || event.kind == "opening" {
                let key = "\(event.line)\u{1}\(event.operatorName)"
                func scoped(_ target: String) -> [Bounds] {
                    (geometry[target]?[key] ?? []).filter { f in
                        if let box = event.selectorBox, !f.inside(box) { return false }
                        if target == "stations", let names = event.selectorStations,
                            !names.contains(f.name ?? "")
                        { return false }
                        return true
                    }
                }
                let secs = scoped("sections"), stas = scoped("stations")
                let secBoxes = mine.filter { $0.targets.contains("sections") }.map(\.box)
                let staBoxes = mine.filter { $0.targets.contains("stations") }.map(\.box)
                func uncovered(_ fs: [Bounds], _ boxes: [[Double]]) -> [Bounds] {
                    fs.filter { f in !boxes.contains { f.inside($0) } }
                }
                let secKm = secs.reduce(0) { $0 + $1.km }
                let whole: Bool = event.expectedKm.map { secKm <= 1.35 * $0 }
                    ?? (event.scope == "whole_identity")
                if !secs.isEmpty && secBoxes.isEmpty {
                    add("no-sections-stamp", secs.count, of: secs.count,
                        "\(head) has no sections stamp for its \(secs.count) section features: \(fix)")
                }
                if whole {
                    if !stas.isEmpty && staBoxes.isEmpty {
                        add("no-stations-stamp", stas.count, of: stas.count,
                            "\(head) has no stations stamp for its \(stas.count) station features: \(fix)")
                    }
                    let us = uncovered(secs, secBoxes), ut = uncovered(stas, staBoxes)
                    if !secBoxes.isEmpty && !us.isEmpty {
                        add("sections-uncovered", us.count, of: secs.count,
                            "\(head) stamp bboxes leave \(us.count) of \(secs.count) section features "
                            + "of the line outside every sections stamp (stamp narrowed?): \(fix)")
                    }
                    if !staBoxes.isEmpty && !ut.isEmpty {
                        add("stations-uncovered", ut.count, of: stas.count,
                            "\(head) stamp bboxes leave \(ut.count) of \(stas.count) station features "
                            + "of the line outside every stations stamp: \(fix)")
                    }
                } else {
                    if let km = event.expectedKm {
                        let covered = secs.filter { f in secBoxes.contains { f.inside($0) } }
                            .reduce(0) { $0 + $1.km }
                        if covered < 0.6 * km {
                            add("km-short", Int(covered.rounded()), of: Int(km.rounded()),
                                "\(head) sections stamps cover \(String(format: "%.1f", covered)) km "
                                + "but the event expects \(km) km (stamp narrowed?): \(fix)")
                        }
                    }
                    let inSections = stas.filter { f in secBoxes.contains { f.inside($0) } }
                    if !inSections.isEmpty && staBoxes.isEmpty {
                        add("no-stations-stamp", inSections.count, of: stas.count,
                            "\(head) has no stations stamp for \(inSections.count) stations on its "
                            + "stamped sections: \(fix)")
                    }
                }
            }
            out += problems
        }
        return out
    }

    // MARK: tests

    @Test("every opening/closure event keeps full geometry stamps; only baselined gaps remain")
    func everyEventKeepsItsStamps() throws {
        let root = try PortFixtures.repositoryRoot()
        let eventsSource = try Self.object(
            root.appending(path: "app/scripts/railway/jp-rail-history-events.json"))
        let history = try Self.object(root.appending(path: "app/data/rail-history.json"))
        let events = Self.events(eventsSource)
        #expect(events.count > 100, "event source read nothing: guard would pass vacuously")
        let found = Self.violations(
            events: events, history: history, geometry: try Self.featureBounds(root: root))

        let baselineURL = root.appending(path: Self.baselinePath)
        if ProcessInfo.processInfo.environment["JTM_REGENERATE_EXPECTATIONS"] == "1" {
            let baseline = Baseline(
                format: "jtm-history-stamp-baseline/1",
                entries: found.map {
                    BaselineEntry(event: $0.event, line: $0.line, kind: $0.kind, count: $0.count,
                                  of: $0.of, reason: Self.baselineReason)
                }.sorted { $0.key < $1.key })
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            var data = try encoder.encode(baseline)
            data.append(0x0A)
            try data.write(to: baselineURL)
            return
        }
        let baseline = try JSONDecoder().decode(Baseline.self, from: Data(contentsOf: baselineURL))
        let known = Set(baseline.entries.map(\.key))
        var problems: [String] = []
        for v in found where !known.contains(v.key) { problems.append(v.message) }
        let foundKeys = Set(found.map(\.key))
        for e in baseline.entries where !foundKeys.contains(e.key) {
            problems.append("baseline entry \(e.key) (\(e.line)) no longer occurs; remove it from "
                + "\(Self.baselinePath) (regenerate with \(Self.regenerateCommand))")
        }
        #expect(problems.isEmpty, Comment(rawValue: problems.joined(separator: "\n")))
    }

    /// The pre-restore HEAD package (sections bbox narrowed to 1 of 4 features,
    /// stations stamp gone) must be flagged; the current package must not be.
    @Test("the narrowed Toyama station-connection stamps are detected")
    func toyamaRegressionIsDetected() throws {
        let root = try PortFixtures.repositoryRoot()
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appending(path: "Resources/rail-history-toyama-head.json")
        let eventsSource = try Self.object(
            root.appending(path: "app/scripts/railway/jp-rail-history-events.json"))
        let events = Self.events(eventsSource)
        let geometry = try Self.featureBounds(root: root)
        let only: Set<String> = ["jp.opening.toyama-station-connection"]

        let broken = Self.violations(
            events: events, history: try Self.object(fixture), geometry: geometry, only: only)
        #expect(broken.contains { $0.message.contains("toyama-station-connection") && $0.message.contains("stations stamp") },
                "missing stations stamp not detected: \(broken.map(\.message))")
        #expect(broken.contains { $0.message.contains("toyama-station-connection") && $0.message.contains("section features") },
                "narrowed sections stamp not detected: \(broken.map(\.message))")

        let current = Self.violations(
            events: events,
            history: try Self.object(root.appending(path: "app/data/rail-history.json")),
            geometry: geometry, only: only)
        #expect(current.isEmpty, Comment(rawValue: current.map(\.message).joined(separator: "\n")))
    }
}
