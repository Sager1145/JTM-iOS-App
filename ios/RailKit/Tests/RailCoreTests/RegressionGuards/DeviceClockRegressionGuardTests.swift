import Foundation
import Testing

/// Regression guard: recorded train times must never depend on the phone's
/// zone or calendar (see `docs/maintenance/2026-11-07-timezone-audit.md`).
///
/// Bug class: `Calendar.current` / `TimeZone.current` read the device setting, so
/// a traveller's recorded 09:30 departure shifts or lands on another day when the
/// phone zone, region or calendar (Buddhist, Japanese era) differs from the
/// railway's. Recorded times use `region.clock` (`region.clock.calendar`, `region.clock.timeZone`).
///
/// Rule, per scanned file (all `*.swift` under `ios/RailMap` and
/// `ios/RailKit/Sources`; comment lines, i.e. first non-blank characters `//`, ignored):
///   hits = occurrences of `Calendar.current`, `TimeZone.current`,
///          `.autoupdatingCurrent`, `NSTimeZone.local`, `NSTimeZone.system`,
///          `Locale.current.calendar`
///        + occurrences of `timeZone:`/`timeZone =`/`calendar:`/`calendar =` followed by
///          `.current` (type-inferred device zone or calendar), and of
///          `: Calendar|TimeZone|Locale = .current`
///        + 1 if the file contains `Calendar(identifier:` but never `.timeZone =`
///          (a calendar built and left on the device zone; one hit per file)
///        + max(0, count(`DatePicker(`) - count(`.environment(\.timeZone`))
///        + 1 if the file has any `DatePicker(` but no `.environment(\.calendar`
/// (Every DatePicker needs its own pinned time zone; the file needs a pinned calendar.)
///
/// Known limits, deliberately not scanned because they are too noisy: bare
/// `DateFormatter()` without a `timeZone`, and `FormatStyle` / `.formatted(...)`
/// use. Review those by hand when touching record dates.
///
/// Ratchet: `baseline` holds today's hits per file and may only shrink. More hits,
/// or a hit in a file not listed, fails; fewer hits also fails until the number
/// here is lowered (or the entry deleted at zero), so fixes lock in.
@Suite("RegressionGuardDeviceClock")
struct RegressionGuardDeviceClock {
    /// Shrink-only. Path is relative to `ios/`.
    static let baseline: [String: Int] = [:]

    /// Permanent exemptions (path prefix relative to `ios/`, reason).
    static let allowlist: [(prefix: String, reason: String)] = [
        ("RailMap/Diagnostics/", "developer tooling; reads the device year for a debug filter, never records journey times"),
    ]

    private static let forbidden = [
        "Calendar.current", "TimeZone.current", ".autoupdatingCurrent",
        "NSTimeZone.local", "NSTimeZone.system", "Locale.current.calendar",
    ]

    private static let patterns: [NSRegularExpression] = [
        #"(timeZone|calendar)\s*[:=]\s*\.current\b"#,
        #":\s*(Calendar|TimeZone|Locale)\s*=\s*\.current\b"#,
    ].map { try! NSRegularExpression(pattern: $0) }

    private static func count(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    static func hits(in source: String) -> Int {
        let code = source.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        var total = forbidden.reduce(0) { $0 + count($1, in: code) }
        let whole = NSRange(code.startIndex..., in: code)
        total += patterns.reduce(0) { $0 + $1.numberOfMatches(in: code, range: whole) }
        if count("Calendar(identifier:", in: code) > 0, count(".timeZone =", in: code) == 0 { total += 1 }
        let pickers = count("DatePicker(", in: code)
        if pickers > 0 {
            total += max(0, pickers - count(".environment(\\.timeZone", in: code))
            if count(".environment(\\.calendar", in: code) == 0 { total += 1 }
        }
        return total
    }

    @Test("device zone and calendar never decide recorded times")
    func deviceClockRatchet() throws {
        let ios = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // RegressionGuards
            .deletingLastPathComponent() // RailCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // RailKit
            .deletingLastPathComponent() // ios
        let fix = "use region.clock for recorded times (region.clock.calendar / region.clock.timeZone, instance properties), and pin every DatePicker with .environment(\\.timeZone, region.clock.timeZone) and .environment(\\.calendar, region.clock.calendar)"
        var problems: [String] = []
        var seen = Set<String>()
        var scanned: [String: Int] = [:]
        for root in ["RailMap", "RailKit/Sources"] {
            let rootURL = ios.appendingPathComponent(root)
            guard let walker = FileManager.default.enumerator(at: rootURL, includingPropertiesForKeys: nil) else {
                problems.append("cannot enumerate \(root)")
                continue
            }
            for case let file as URL in walker where file.pathExtension == "swift" {
                scanned[root, default: 0] += 1
                let rel = String(file.path.dropFirst(ios.path.count + 1))
                if Self.allowlist.contains(where: { rel.hasPrefix($0.prefix) }) { continue }
                let n = Self.hits(in: try String(contentsOf: file, encoding: .utf8))
                let allowed = Self.baseline[rel] ?? 0
                if n > 0 { seen.insert(rel) }
                if n > allowed {
                    problems.append("\(rel): \(n) device-clock hit(s), baseline \(allowed). Fix: \(fix).")
                } else if n < allowed {
                    problems.append("\(rel): improved to \(n) hit(s), baseline \(allowed). Lower the number in DeviceClockRegressionGuardTests.baseline (delete the entry at 0).")
                }
            }
        }
        for root in ["RailMap", "RailKit/Sources"] {
            #expect((scanned[root] ?? 0) > 0, "scanned no files under \(root); #filePath resolution is broken")
        }
        for rel in Self.baseline.keys where !seen.contains(rel) && !problems.contains(where: { $0.hasPrefix(rel + ":") }) {
            problems.append("\(rel): baseline lists it but it has no hits or no longer exists. Delete the entry from DeviceClockRegressionGuardTests.baseline.")
        }
        #expect(problems.isEmpty, Comment(rawValue: problems.sorted().joined(separator: "\n")))
    }
}
