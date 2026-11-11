import Foundation
import Testing

/// Regression guard: recorded train times must never depend on the phone's
/// zone, calendar or locale (see `docs/maintenance/2026-11-07-timezone-audit.md`).
///
/// Bug class: `Calendar.current` / `TimeZone.current` read the device setting, so
/// a traveller's recorded 09:30 departure shifts or lands on another day when the
/// phone zone, region or calendar (Buddhist, Japanese era) differs from the
/// railway's. Recorded times use `region.clock` (`region.clock.calendar`, `region.clock.timeZone`).
///
/// Scanned: every `*.swift` under `ios/RailMap`, `ios/RailKit/Sources` and
/// `ios/auxiliary`, skipping any file with a path component `Tests`, `.build`,
/// `build`, `DerivedData` or `checkouts`. Comment lines (first non-blank characters
/// `//`) are blanked before scanning; trailing `//` comments are NOT stripped.
///
/// Rules are PER SITE. Each hit is one site and is reported as `file:line: rule`.
/// A. Forbidden literals, one hit per occurrence: `Calendar.current`, `TimeZone.current`,
///    `.autoupdatingCurrent`, `NSTimeZone.local`, `NSTimeZone.system`, `NSTimeZone.default`,
///    `NSCalendar` (identifier-bounded), `Locale.current.calendar`, `MultiDatePicker(`,
///    `.formatted(date:`, `.formatted(.dateTime`.
///    Also one hit per occurrence: `DateFormatter.localizedString(`, `FormatStyle.dateTime`
///    (so `Date.FormatStyle.dateTime` too).
/// B. Regexes, one hit per match: `(timeZone|calendar)\s*[:=]\s*\.current\b`;
///    `:\s*(Calendar|TimeZone|Locale)\s*=\s*\.current\b`; `\.locale\s*=\s*\.current\b`;
///    `\\\.(timeZone|calendar|locale)\s*,\s*\.current\b` (i.e. `.environment(\.timeZone, .current)`);
///    `@Environment\(\\\.(timeZone|calendar|locale)\)` (reading the device-injected value).
/// C. `Locale.current` (not followed by `.calendar`), one hit per occurrence, only on a
///    line that also matches `(?i)(\bdate|formatter|calendar)`.
/// D. `Calendar(identifier:` and `DateFormatter()` (identifier-bounded, so
///    `ISO8601DateFormatter()` is exempt). Let L be the site's line.
///    - Calendar on a line containing `.environment(\.calendar`: pinned only if L..L+2
///      contains `.environment(\.timeZone`.
///    - Otherwise, if L declares `let|var NAME [: Type] = Type(` or assigns
///      `NAME.calendar = Calendar(identifier:`, pinned only if L..L+6 (Calendar) or
///      L..L+8 (DateFormatter) contains `NAME.timeZone =`.
///    - Otherwise pinned only if L itself contains `timeZone`.
///    An unpinned site is one hit.
/// E. `Date.FormatStyle(`: hit unless its balanced parentheses contain `timeZone:`.
/// F. `TextField(` is checked like `Text(` for `format: .dateTime` / `Date.FormatStyle`.
///    `Text(`: hit when its balanced parentheses contain `, style: .date`/`.time`
///    (zone-dependent styles; `.timer`/`.relative`/`.offset` are instants and exempt)
///    or `format: .dateTime`.
/// G. `DatePicker(` (identifier-bounded, so `MultiDatePicker(` is rule A only). The site
///    window is the call's balanced parentheses, an optional trailing `{...}` closure,
///    the rest of that line, then each following line whose first non-blank character is
///    `.` (comment lines are skipped but count), at most 15 lines, stopping at the first
///    other line (blank included). The window must contain BOTH `.environment(\.timeZone`
///    and `.environment(\.calendar`; each missing one is one hit. A pin counts only if it
///    is not `, .current` (`.environment(\.timeZone, .current)` is no pin). A pin on the
///    nearest enclosing `Group|VStack|HStack|Form|Section {` block also counts: found by
///    walking outward over unmatched `{` (balanced braces) to the first whose line has such a
///    container keyword before the `{`; that block's window is the rest of its closing-brace
///    line plus its following `.`-modifier lines (same 15-line rule).
///
/// Ratchet: `baseline` holds today's hit count per file and may only shrink. More hits,
/// or a hit in a file not listed, fails; fewer hits also fails until the number is
/// lowered (or the entry deleted at zero), so fixes lock in. Failure messages list
/// every site in the file as `file:line: rule | source`.
@Suite("RegressionGuardDeviceClock")
struct RegressionGuardDeviceClock {
    /// Shrink-only. Path is relative to `ios/`. Each entry says what the code is.
    static let baseline: [String: Int] = [
        // Diagnostics: `DateFormatter()` for an export file-name stamp (POSIX, "now"); filename only, not a record.
        "RailMap/Diagnostics/DevTools/DevDiagnostics.swift": 1,
        // Import: 2x `Date.FormatStyle(date:time:)` showing a backup's creation instant in the UI; display of a real instant, not a record time.
        "RailMap/Import/DataManagerView.swift": 2,
        // Subscription: `resetsAt.formatted(date:time:)` shows a usage-limit reset instant in an error message; display only, not a record.
        "RailMap/Infrastructure/Subscription/ChatGPTSubscriptionService.swift": 1,
        // Statistics: `Calendar(identifier: .gregorian)` used only for localized month/weekday symbols (locale set, no dates); not a record.
        "RailMap/Statistics/StatisticsFormatting.swift": 1,
        // jtm-area CLI: `DateFormatter()` for a patch-id stamp from "now"; developer tooling, not a record.
        "auxiliary/RailDiagnostics/Modules/AreaRepair/Sources/jtm-area/main.swift": 1,
    ]

    /// Permanent exemptions: exact path relative to `ios/`, with the reason. Never a folder.
    static let allowlist: [(path: String, reason: String)] = [
        ("RailMap/Diagnostics/DevTools/DevToolsViews.swift",
         "debug-ball UI: device year for a hide-filter shortcut and the device clock in a log-line timestamp; never records journey times"),
    ]

    private static let excludedComponents: Set<String> = ["Tests", ".build", "build", "DerivedData", "checkouts"]
    private static let roots = ["RailMap", "RailKit/Sources", "auxiliary"]
    private static let ident = #"(?<![A-Za-z0-9_])"#
    private static let envZone = ".environment(\\.timeZone"
    private static let envCalendar = ".environment(\\.calendar"

    private static func re(_ pattern: String) -> NSRegularExpression { try! NSRegularExpression(pattern: pattern) }

    private static let literalRules: [(label: String, re: NSRegularExpression)] = [
        "Calendar.current", "TimeZone.current", ".autoupdatingCurrent", "NSTimeZone.local",
        "NSTimeZone.system", "NSTimeZone.default", "Locale.current.calendar", "MultiDatePicker(",
        ".formatted(date:", ".formatted(.dateTime", "DateFormatter.localizedString(",
    ].map { ($0, re(NSRegularExpression.escapedPattern(for: $0))) }
        + [("NSCalendar", re(ident + "NSCalendar")),
           ("FormatStyle.dateTime", re(#"FormatStyle\.dateTime\b"#))]
    private static let patternRules: [(label: String, re: NSRegularExpression)] = [
        ("timeZone/calendar = .current", re(#"(timeZone|calendar)\s*[:=]\s*\.current\b"#)),
        (": Calendar|TimeZone|Locale = .current", re(#":\s*(Calendar|TimeZone|Locale)\s*=\s*\.current\b"#)),
        (".locale = .current", re(#"\.locale\s*=\s*\.current\b"#)),
        ("\\.timeZone|calendar|locale, .current", re(#"\\\.(timeZone|calendar|locale)\s*,\s*\.current\b"#)),
        ("@Environment(\\.timeZone|calendar|locale)", re(#"@Environment\(\\\.(timeZone|calendar|locale)\)"#)),
    ]
    private static let validZonePin = re(#"\.environment\(\\\.timeZone(?!\s*,\s*\.current\b)"#)
    private static let validCalendarPin = re(#"\.environment\(\\\.calendar(?!\s*,\s*\.current\b)"#)
    private static let containerOpener = re(#"(?<![A-Za-z0-9_])(Group|VStack|HStack|Form|Section)\b[^{]*$"#)
    private static let localeCurrent = re(#"Locale\.current(?!\.calendar)"#)
    private static let localeContext = re(#"(?i)(\bdate|formatter|calendar)"#)

    struct Hit { let line: Int; let rule: String }

    private static func balanced(_ u: [UInt16], from i: Int, open: UInt16, close: UInt16, limit: Int) -> Int? {
        var depth = 0
        var j = i
        while j < min(u.count, i + limit) {
            if u[j] == open { depth += 1 }
            else if u[j] == close {
                depth -= 1
                if depth == 0 { return j + 1 }
            }
            j += 1
        }
        return nil
    }

    static func hits(in source: String) -> (hits: [Hit], lines: [String]) {
        let raw = source.components(separatedBy: "\n")
        let isComment = raw.map { $0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        let lines = zip(raw, isComment).map { $1 ? "" : $0 }
        let code = lines.joined(separator: "\n")
        let ns = code as NSString
        let u = Array(code.utf16)
        var starts = [0]
        for (i, c) in u.enumerated() where c == 10 { starts.append(i + 1) }
        func line(of offset: Int) -> Int { starts.lastIndex(where: { $0 <= offset })! + 1 } // 1-based
        func window(_ l: Int, _ extra: Int) -> String { lines[(l - 1)..<min(lines.count, l + extra)].joined(separator: "\n") }
        func all(_ regex: NSRegularExpression) -> [NSTextCheckingResult] {
            regex.matches(in: code, range: NSRange(location: 0, length: ns.length))
        }
        /// Last line (1-based) of the modifier chain that follows the code ending at `offset`.
        func chainEnd(afterOffset offset: Int) -> Int {
            let last = line(of: max(offset - 1, 0))
            var endLine = last
            var j = last // 0-based index of the next line
            var seen = 0
            while j < lines.count, seen < 15 {
                if isComment[j] { j += 1; seen += 1; continue }
                if lines[j].trimmingCharacters(in: .whitespaces).hasPrefix(".") { endLine = j + 1; j += 1; seen += 1 } else { break }
            }
            return endLine
        }
        var out: [Hit] = []

        for rule in literalRules + patternRules {
            for m in all(rule.re) { out.append(Hit(line: line(of: m.range.location), rule: rule.label)) }
        }
        for (i, l) in lines.enumerated() {
            let n = (l as NSString).length
            let whole = NSRange(location: 0, length: n)
            let count = localeCurrent.numberOfMatches(in: l, range: whole)
            if count > 0, localeContext.firstMatch(in: l, range: whole) != nil {
                for _ in 0..<count { out.append(Hit(line: i + 1, rule: "Locale.current with dates")) }
            }
        }

        // D. Calendar(identifier:) / DateFormatter(): the zone must be set at the site.
        func zoneSites(type: String, literal: String, rule: String, span: Int) {
            let declaration = re(#"(?:let|var)\s+(\w+)\s*(?::\s*"# + type + #")?\s*=\s*"# + type + #"\("#)
            let assignment = re(#"(\w+)\.calendar\s*=\s*"# + type + #"\("#)
            for m in all(re(ident + literal)) {
                let l = line(of: m.range.location)
                let text = lines[l - 1]
                let whole = NSRange(location: 0, length: (text as NSString).length)
                if type == "Calendar", text.contains(envCalendar) {
                    if !window(l, 2).contains(envZone) { out.append(Hit(line: l, rule: rule)) }
                    continue
                }
                let named = declaration.firstMatch(in: text, range: whole)
                    ?? (type == "Calendar" ? assignment.firstMatch(in: text, range: whole) : nil)
                if let named {
                    let name = (text as NSString).substring(with: named.range(at: 1))
                    let pinned = re(ident + NSRegularExpression.escapedPattern(for: name) + #"\.timeZone\s*="#)
                    let w = window(l, span)
                    if pinned.firstMatch(in: w, range: NSRange(location: 0, length: (w as NSString).length)) == nil {
                        out.append(Hit(line: l, rule: rule))
                    }
                } else if !text.contains("timeZone") {
                    out.append(Hit(line: l, rule: rule))
                }
            }
        }
        zoneSites(type: "Calendar", literal: #"Calendar\(identifier:"#, rule: "Calendar(identifier:) without .timeZone =", span: 6)
        zoneSites(type: "DateFormatter", literal: #"DateFormatter\(\)"#, rule: "DateFormatter() without .timeZone =", span: 8)

        // E. Date.FormatStyle(
        for m in all(re(ident + #"Date\.FormatStyle\("#)) {
            let end = balanced(u, from: m.range.upperBound - 1, open: 40, close: 41, limit: 2000)
            let body = end.map { ns.substring(with: NSRange(location: m.range.upperBound, length: $0 - m.range.upperBound)) } ?? ""
            if !body.contains("timeZone:") { out.append(Hit(line: line(of: m.range.location), rule: "Date.FormatStyle( without timeZone:")) }
        }

        // F. Text(date, style:/format:)
        let textStyle = re(#",\s*style:\s*\.(date|time)\b"#)
        let textFormat = re(#"format:\s*\.dateTime"#)
        for m in all(re(ident + #"(?:Text|TextField)\("#)) {
            let isField = ns.substring(with: m.range).hasPrefix("TextField")
            guard let end = balanced(u, from: m.range.upperBound - 1, open: 40, close: 41, limit: 2000) else { continue }
            let body = ns.substring(with: NSRange(location: m.range.upperBound, length: end - m.range.upperBound))
            let whole = NSRange(location: 0, length: (body as NSString).length)
            let hit = isField
                ? textFormat.firstMatch(in: body, range: whole) != nil || body.contains("Date.FormatStyle")
                : textStyle.firstMatch(in: body, range: whole) != nil || textFormat.firstMatch(in: body, range: whole) != nil
            if hit {
                out.append(Hit(line: line(of: m.range.location), rule: isField ? "TextField(date format)" : "Text(date, style:/format: .dateTime)"))
            }
        }

        // G. DatePicker(
        for m in all(re(ident + #"DatePicker\("#)) {
            let startLine = line(of: m.range.location)
            guard var p = balanced(u, from: m.range.upperBound - 1, open: 40, close: 41, limit: 2000) else {
                out.append(Hit(line: startLine, rule: "DatePicker( unbalanced"))
                continue
            }
            let nl = ns.range(of: "\n", range: NSRange(location: p, length: ns.length - p))
            let restEnd = nl.location == NSNotFound ? ns.length : nl.location
            let rest = ns.substring(with: NSRange(location: p, length: restEnd - p))
            if rest.trimmingCharacters(in: .whitespaces).hasPrefix("{"),
               let b = balanced(u, from: p + (rest as NSString).range(of: "{").location, open: 123, close: 125, limit: 4000) {
                p = b
            }
            let w = lines[(startLine - 1)..<min(lines.count, chainEnd(afterOffset: p))].joined(separator: "\n")
            var scope = w
            var k = m.range.location - 1
            var depth = 0
            while k >= max(0, m.range.location - 8000) {
                if u[k] == 125 { depth += 1 }
                else if u[k] == 123 {
                    if depth == 0 {
                        let l = line(of: k)
                        let prefix = ns.substring(with: NSRange(location: starts[l - 1], length: k - starts[l - 1]))
                        if containerOpener.firstMatch(in: prefix, range: NSRange(location: 0, length: (prefix as NSString).length)) != nil {
                            if let close = balanced(u, from: k, open: 123, close: 125, limit: 20000) {
                                let closeLine = line(of: close - 1)
                                scope += "\n" + lines[(closeLine - 1)..<min(lines.count, chainEnd(afterOffset: close))].joined(separator: "\n")
                            }
                            break
                        }
                    } else { depth -= 1 }
                }
                k -= 1
            }
            let whole = NSRange(location: 0, length: (scope as NSString).length)
            if validZonePin.firstMatch(in: scope, range: whole) == nil { out.append(Hit(line: startLine, rule: "DatePicker( without .environment(\\.timeZone")) }
            if validCalendarPin.firstMatch(in: scope, range: whole) == nil { out.append(Hit(line: startLine, rule: "DatePicker( without .environment(\\.calendar")) }
        }
        return (out.sorted { ($0.line, $0.rule) < ($1.line, $1.rule) }, lines)
    }

    @Test("device zone and calendar never decide recorded times")
    func deviceClockRatchet() throws {
        let ios = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // RegressionGuards
            .deletingLastPathComponent() // RailCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // RailKit
            .deletingLastPathComponent() // ios
        let fix = "use region.clock for recorded times (region.clock.calendar / region.clock.timeZone, instance properties), set .timeZone on every Calendar/DateFormatter you build, and pin every DatePicker with .environment(\\.timeZone, region.clock.timeZone) and .environment(\\.calendar, region.clock.calendar)"
        var problems: [String] = []
        var seen = Set<String>()
        var scanned: [String: Int] = [:]
        for root in Self.roots {
            let rootURL = ios.appendingPathComponent(root)
            guard let walker = FileManager.default.enumerator(at: rootURL, includingPropertiesForKeys: nil) else {
                problems.append("cannot enumerate \(root)")
                continue
            }
            while let file = walker.nextObject() as? URL {
                if Self.excludedComponents.contains(file.lastPathComponent) { walker.skipDescendants(); continue }
                guard file.pathExtension == "swift" else { continue }
                let rel = String(file.path.dropFirst(ios.path.count + 1))
                scanned[root, default: 0] += 1
                if Self.allowlist.contains(where: { $0.path == rel }) { continue }
                let (found, lines) = Self.hits(in: try String(contentsOf: file, encoding: .utf8))
                let allowed = Self.baseline[rel] ?? 0
                if !found.isEmpty { seen.insert(rel) }
                let sites = found.map { "  \(rel):\($0.line): \($0.rule) | \(lines[$0.line - 1].trimmingCharacters(in: .whitespaces).prefix(100))" }
                    .joined(separator: "\n")
                if found.count > allowed {
                    problems.append("\(rel): \(found.count) device-clock hit(s), baseline \(allowed). Fix: \(fix).\n\(sites)")
                } else if found.count < allowed {
                    problems.append("\(rel): improved to \(found.count) hit(s), baseline \(allowed). Lower the number in DeviceClockRegressionGuardTests.baseline (delete the entry at 0).")
                }
            }
        }
        for root in Self.roots {
            #expect((scanned[root] ?? 0) > 0, "scanned no files under \(root); #filePath resolution is broken")
        }
        for entry in Self.allowlist where !FileManager.default.fileExists(atPath: ios.appendingPathComponent(entry.path).path) {
            problems.append("\(entry.path): allowlisted but missing. Remove the stale allowlist entry in DeviceClockRegressionGuardTests.")
        }
        for rel in Self.baseline.keys where !seen.contains(rel) && !problems.contains(where: { $0.hasPrefix(rel + ":") }) {
            problems.append("\(rel): baseline lists it but it has no hits or no longer exists. Delete the entry from DeviceClockRegressionGuardTests.baseline.")
        }
        #expect(problems.isEmpty, Comment(rawValue: problems.sorted().joined(separator: "\n")))
    }
}
