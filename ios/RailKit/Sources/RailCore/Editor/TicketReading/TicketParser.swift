import Foundation

/// Reads the text of a paper ticket into fields. Pure text in, text out: the
/// recognition itself happens elsewhere and station names are not resolved.
public enum TicketParser {
    public static func parse(lines: [RecognizedLine], region: TicketRegion) -> TicketReadingResult {
        let scan = lines.compactMap(TicketLine.init)
        switch region {
        case .jp: return TicketParserJP.parse(scan)
        case .tw: return TicketParserTW.parse(scan)
        case .kr: return TicketParserKR.parse(scan)
        }
    }
}

// MARK: - Shared support

/// A recognised line after width folding (NFKC: full-width digits, letters, ￥, ：, ～ …)
/// and whitespace collapsing.
struct TicketLine {
    var text: String
    var confidence: Double

    init?(_ line: RecognizedLine) {
        let folded = line.text.precomposedStringWithCompatibilityMapping
        let collapsed = folded.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        text = collapsed
        confidence = min(max(line.confidence, 0), 1)
    }
}

/// Collects the best candidate per field.
struct TicketDraft {
    var result: TicketReadingResult

    init(region: TicketRegion) { result = TicketReadingResult(region: region) }

    mutating func offer<V>(
        _ keyPath: WritableKeyPath<TicketReadingResult, TicketField<V>?>,
        _ value: V, _ line: TicketLine, strength: Double
    ) {
        offer(keyPath, value, confidence: line.confidence * strength)
    }

    /// Keeps the highest-confidence candidate; the earlier one wins ties.
    mutating func offer<V>(
        _ keyPath: WritableKeyPath<TicketReadingResult, TicketField<V>?>,
        _ value: V, confidence: Double
    ) {
        if let current = result[keyPath: keyPath], current.confidence >= confidence { return }
        result[keyPath: keyPath] = TicketField(value, confidence: confidence)
    }
}

enum TicketText {
    /// Capture groups of the first match (index 0 is the whole match; unmatched groups are "").
    static func groups(_ pattern: String, in text: String, ignoreCase: Bool = false) -> [String]? {
        all(pattern, in: text, ignoreCase: ignoreCase).first
    }

    static func all(_ pattern: String, in text: String, ignoreCase: Bool = false) -> [[String]] {
        guard
            let regex = try? NSRegularExpression(
                pattern: pattern, options: ignoreCase ? [.caseInsensitive] : [])
        else { return [] }
        let whole = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: whole).map { match in
            (0..<match.numberOfRanges).map { index in
                Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
            }
        }
    }

    static func matches(_ pattern: String, in text: String, ignoreCase: Bool = false) -> Bool {
        groups(pattern, in: text, ignoreCase: ignoreCase) != nil
    }

    static func replacing(_ pattern: String, in text: String, with template: String = " ") -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        return regex.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    /// The text either side of the first arrow-like separator, both non-empty.
    static func splitRoute(_ text: String, extra: [String] = []) -> (left: String, right: String)? {
        let arrows = ["→", "⇒", "➔", "➡", "➝", "⟶", "▶", "▷", "►", "->", "=>", ">>", "~", "〜"]
            .map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        let pattern = (["\\s*(?:\(arrows))\\s*", "\\s-\\s"] + extra).joined(separator: "|")
        guard let regex = try? NSRegularExpression(pattern: "(?:\(pattern))"),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let range = Range(match.range, in: text)
        else { return nil }
        let left = text[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
        let right = text[range.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !left.isEmpty, !right.isEmpty else { return nil }
        return (left, right)
    }

    /// Strips leading zeros: `05` -> `5`, `0` -> `0`.
    static func trimmedNumber(_ text: String) -> String {
        Int(text).map(String.init) ?? text
    }

    static func validDate(year: Int?, month: Int, day: Int) -> TicketDate? {
        guard (1...12).contains(month), day >= 1 else { return nil }
        let limit = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1]
        guard day <= limit else { return nil }
        return TicketDate(year: year, month: month, day: day)
    }

    /// The printed arrival: a clock next to one of `markers` (着, 抵達, 도착 …),
    /// else the clock right of the route arrow (`10:30 → 12:15`).
    static func arrival(in text: String, markers: [String]) -> (value: ServiceClockTime, strength: Double)? {
        for pattern in markers {
            if let g = groups(pattern, in: text), let time = clock(hour: g[1], minute: g[2]) {
                return (time, 1.0)
            }
        }
        if let parts = splitRoute(text),
            groups("(\\d{1,2}):(\\d{2})", in: parts.left) != nil,
            let g = groups("(\\d{1,2}):(\\d{2})", in: parts.right),
            let time = clock(hour: g[1], minute: g[2])
        {
            return (time, 0.8)
        }
        return nil
    }

    static func clock(hour: String, minute: String) -> ServiceClockTime? {
        guard let hour = Int(hour), let minute = Int(minute), hour < 30, minute < 60 else {
            return nil
        }
        return ServiceClockTime(dayOffset: hour / 24, hour: hour % 24, minute: minute)
    }

    /// `14,720`, `14.720` (misread comma) or `14720`.
    static func amount(_ text: String) -> Int? {
        if groups("^\\d{1,3}(?:[,.]\\d{3})+$", in: text) != nil {
            return Int(text.filter(\.isNumber))
        }
        guard text.allSatisfy(\.isNumber) else { return nil }
        return Int(text)
    }

    /// The last / first whole match of `runPattern` in `text`.
    static func lastRun(_ runPattern: String, in text: String) -> String? {
        all(runPattern, in: text).last?.first
    }

    static func firstRun(_ runPattern: String, in text: String) -> String? {
        all(runPattern, in: text).first?.first
    }
}

/// Fare selection shared by the regions: a line carrying a total label wins,
/// otherwise the largest amount (supplements are listed beside the sum).
struct TicketFareCandidates {
    private var labelled: (amount: Int, line: TicketLine)?
    private var largest: (amount: Int, line: TicketLine)?
    private var count = 0

    mutating func add(_ amount: Int, from line: TicketLine, isLabelled: Bool) {
        guard amount >= 10 else { return }
        count += 1
        if isLabelled, labelled.map({ amount > $0.amount }) ?? true { labelled = (amount, line) }
        if largest.map({ amount > $0.amount }) ?? true { largest = (amount, line) }
    }

    func apply(to draft: inout TicketDraft, currency: String, minorUnitFactor: Int) {
        let chosen: (amount: Int, line: TicketLine, strength: Double)
        if let labelled {
            chosen = (labelled.amount, labelled.line, 1.0)
        } else if let largest {
            chosen = (largest.amount, largest.line, count == 1 ? 0.9 : 0.75)
        } else {
            return
        }
        draft.offer(\.fare, chosen.amount * minorUnitFactor, chosen.line, strength: chosen.strength)
        draft.offer(\.currency, currency, chosen.line, strength: chosen.strength)
    }
}
