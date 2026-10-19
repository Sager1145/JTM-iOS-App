import Foundation

/// A station mention in pasted journey text (ADR 0013 §11.2).
///
/// Four forms: `name`, `name (CC)`, `name (line)`, `name (CC, line)`.
/// Brackets may be half-width `()` or full-width `（）`. Separators inside
/// the brackets are `,` `，` `、` only. `·` and `・` stay inside a line name
/// (`日暮里・舎人ライナー`). Space around the brackets and the separator is optional.
///
/// One element inside the brackets is a country code only when it is in the
/// supported set (`JP TW HK MO KR CN`, any case, or the region slug `jp` …
/// `cn`). Otherwise it is a line name. Two elements are always country then
/// line, so a line code that collides with a country (`MO` for 東京モノレール)
/// has to be written `浜松町 (JP, MO)`. `浜松町 (MO)` is Macau.
/// `US` and `CA` are not countries here.
public struct StationReference: Hashable, Sendable {
    public var name: String
    /// Uppercase supported country code, when the mention names one.
    public var country: String?
    public var line: String?
    /// The first of two elements was present and is not a supported country.
    /// Callers must not guess a station in some other country.
    public var unsupportedCountry: Bool

    public init(name: String, country: String? = nil, line: String? = nil, unsupportedCountry: Bool = false) {
        self.name = name
        self.country = country
        self.line = line
        self.unsupportedCountry = unsupportedCountry
    }

    /// ISO codes this importer accepts. North America is retired.
    public static let supportedCountryCodes: Set<String> = ["JP", "TW", "HK", "MO", "KR", "CN"]

    /// Region slugs stored on catalog stations. They are the lowercase codes.
    public static let regionSlugs: Set<String> = ["jp", "tw", "hk", "mo", "kr", "cn"]

    /// `JP` for `jp`, `JP`, or `Jp`. `nil` for a line name, `US`, or `CA`.
    public static func canonicalCountry(_ token: String) -> String? {
        let upper = token.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCompatibilityMapping
            .uppercased()
        guard supportedCountryCodes.contains(upper) else { return nil }
        return upper
    }

    public static func slug(_ country: String) -> String {
        country.lowercased()
    }

    /// Parse one mention. Text after a bracket group is not part of the name,
    /// so `府中 (JP, 京王線) 09:03` is still 府中. With no brackets the whole
    /// trimmed string is the name; the importer then finds a catalog name inside it.
    ///
    /// When `names` holds a bracketed official name, that name — or its longest
    /// leading part — stays the station name. Only a bracket group after it is
    /// a qualifier. Half-width and full-width brackets match the stored spelling.
    public static func parse(
        _ text: String, names: StationNameDirectory? = nil
    ) -> StationReference? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let names, let leading = names.leadingOfficialName(in: trimmed) {
            return named(leading.official, remainder: leading.remainder)
        }
        return parseBrackets(in: trimmed)
    }

    /// A bracket that belongs to `official` is not a qualifier. A following group is.
    private static func named(_ official: String, remainder: String) -> StationReference {
        guard !remainder.isEmpty else { return StationReference(name: official) }
        let wrapped = parseBrackets(in: "N \(remainder)")
        guard let wrapped, wrapped.name == "N" else { return StationReference(name: official) }
        return StationReference(
            name: official, country: wrapped.country, line: wrapped.line,
            unsupportedCountry: wrapped.unsupportedCountry)
    }

    private static func parseBrackets(in trimmed: String) -> StationReference? {
        guard !trimmed.isEmpty else { return nil }
        guard let bracket = firstBracket(in: trimmed) else {
            return StationReference(name: trimmed)
        }
        let name = trimmed[..<bracket.open]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let parts = elements(in: bracket.inside)
        if parts.isEmpty {
            return StationReference(name: name)
        }
        if parts.count == 1 {
            if let country = canonicalCountry(parts[0]) {
                return StationReference(name: name, country: country)
            }
            return StationReference(name: name, line: parts[0])
        }
        let line = parts.dropFirst().joined(separator: ", ")
        if let country = canonicalCountry(parts[0]) {
            return StationReference(name: name, country: country, line: line)
        }
        return StationReference(name: name, line: line, unsupportedCountry: true)
    }

    /// Name immediately before the first closed bracket. Nil when the text has
    /// no closed bracket or the prefix is empty. Callers still decide whether
    /// that bracket is a qualifier or part of the station name.
    static func immediateBracketName(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let bracket = firstBracket(in: trimmed) else { return nil }
        let name = trimmed[..<bracket.open].trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// The portion of `text` a catalog name may be found in. Bracket contents
    /// are a country or a line, never a second station.
    static func nameScope(in text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let bracket = firstBracket(in: trimmed) else { return trimmed }
        let name = trimmed[..<bracket.open].trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? trimmed : name
    }

    private struct Bracket {
        var open: String.Index
        var inside: String
    }

    private static func firstBracket(in text: String) -> Bracket? {
        let closers: [Character: Character] = ["(": ")", "（": "）"]
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if let closer = closers[character] {
                var depth = 1
                var cursor = text.index(after: index)
                let insideStart = cursor
                while cursor < text.endIndex {
                    let next = text[cursor]
                    if next == character { depth += 1 }
                    else if next == closer {
                        depth -= 1
                        if depth == 0 {
                            return Bracket(open: index, inside: String(text[insideStart..<cursor]))
                        }
                    }
                    cursor = text.index(after: cursor)
                }
                return nil
            }
            index = text.index(after: index)
        }
        return nil
    }

    private static func isSeparator(_ character: Character) -> Bool {
        character == "," || character == "，" || character == "、"
    }

    /// Split on a separator that is not inside nested brackets.
    private static func elements(in inside: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        for character in inside {
            if character == "(" || character == "（" {
                depth += 1
                current.append(character)
                continue
            }
            if character == ")" || character == "）" {
                depth = max(0, depth - 1)
                current.append(character)
                continue
            }
            if depth == 0, isSeparator(character) {
                parts.append(current)
                current = ""
                continue
            }
            current.append(character)
        }
        parts.append(current)
        return parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
