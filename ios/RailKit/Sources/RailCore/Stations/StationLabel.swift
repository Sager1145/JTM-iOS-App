import Foundation

/// Passenger-facing station labels from ADR 0013 §3.6 and §11.5.
///
/// A line's label is its name when that name is unique in the country.
/// Otherwise it is the operator's short label plus the line name
/// (`京成本線`, `JR東海 東海道線`). The stored journey keeps a station id;
/// these strings are derived.
public enum StationLabel {
    public struct LineChoice: Hashable, Sendable {
        public var id: String
        public var label: String
        public var rank: Int
        public var name: String
        /// Operator-qualified line name, even when `label` is already unique in the country.
        public var operatorLabel: String

        public init(id: String, label: String, rank: Int, name: String, operatorLabel: String? = nil) {
            self.id = id
            self.label = label
            self.rank = rank
            self.name = name
            self.operatorLabel = operatorLabel ?? label
        }
    }

    public struct Text: Hashable, Sendable {
        public var name: String
        public var countryCode: String
        /// Caption, including the parentheses: `(JP, 京王線)`.
        public var qualifier: String
        /// Round-trip string: `府中 (JP, 京王線)`.
        public var full: String
        /// The part VoiceOver says after the country name.
        public var spokenDetail: String

        public init(name: String, countryCode: String, qualifier: String, full: String, spokenDetail: String) {
            self.name = name
            self.countryCode = countryCode
            self.qualifier = qualifier
            self.full = full
            self.spokenDetail = spokenDetail
        }
    }

    /// `京成本線` when the short label is CJK, `JR東海 東海道線` when it contains Latin letters.
    public static func qualifiedLineName(_ lineName: String, operatorName: String?) -> String {
        let short = OperatorBranding.companyLabel(operatorName)
        if short.isEmpty || lineName.hasPrefix(short) { return lineName }
        if short.contains(where: { $0.isASCII && $0.isLetter }) {
            return short + " " + lineName
        }
        return short + lineName
    }

    public static func lineLabel(name: String, operatorName: String?, uniqueInCountry: Bool) -> String {
        uniqueInCountry ? name : qualifiedLineName(name, operatorName: operatorName)
    }

    public static func full(name: String, countryCode: String, lineLabel: String) -> String {
        "\(name) (\(countryCode), \(lineLabel))"
    }

    public static func transfer(name: String, countryCode: String, from: String, to: String) -> String {
        "\(name) (\(countryCode), \(from) → \(to))"
    }

    /// Context lines first, then rank (lower is more important), then name.
    /// At most two labels, then ` +N`.
    public static func search(
        name: String, countryCode: String, lines: [LineChoice], contextLineIDs: Set<String>
    ) -> String {
        let ordered = orderedLines(lines, contextLineIDs: contextLineIDs)
        guard !ordered.isEmpty else { return "\(name) (\(countryCode))" }
        let shown = ordered.prefix(2).map(\.label)
        var detail = shown.joined(separator: "・")
        let extra = ordered.count - shown.count
        if extra > 0 { detail += " +\(extra)" }
        return "\(name) (\(countryCode), \(detail))"
    }

    public static func orderedLines(_ lines: [LineChoice], contextLineIDs: Set<String>) -> [LineChoice] {
        var seen: Set<String> = []
        let unique = lines.filter { seen.insert($0.id).inserted }
        return unique.sorted { lhs, rhs in
            let lhsContext = contextLineIDs.contains(lhs.id)
            let rhsContext = contextLineIDs.contains(rhs.id)
            if lhsContext != rhsContext { return lhsContext && !rhsContext }
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            if lhs.name != rhs.name { return lhs.name < rhs.name }
            return lhs.id < rhs.id
        }
    }

    /// `府中，日本，京王線`. `countryName` is the app's localized country name; the code is the fallback.
    public static func accessibility(
        name: String, countryCode: String, spokenDetail: String, countryName: String?
    ) -> String {
        let country = countryName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = (country?.isEmpty == false) ? country! : countryCode
        if spokenDetail.isEmpty { return "\(name)，\(place)" }
        return "\(name)，\(place)，\(spokenDetail)"
    }

    public static func caption(countryCode: String, detail: String?) -> String {
        guard let detail, !detail.isEmpty else { return "(\(countryCode))" }
        return "(\(countryCode), \(detail))"
    }

    /// Label for one catalog station. Always one line: the preferred line, else
    /// the best context line, else the best-ranked line. The search form is not
    /// a station reference. Pass `labels` from ``lineLabels(in:regionCode:)``
    /// when many stations on one screen share a country.
    public static func text(
        for station: CatalogStation,
        catalog: EditorCatalog,
        labels: [String: String],
        contextLineIDs: Set<String> = [],
        preferredLineID: String? = nil
    ) -> Text {
        let country = station.key.regionCode.uppercased()
        let choices = lineChoices(for: station, catalog: catalog, labels: labels)
        if let preferredLineID, let choice = choices.first(where: { $0.id == preferredLineID }) {
            return make(name: station.name, countryCode: country, detail: choice.label)
        }
        let scoped = contextLineIDs.isEmpty
            ? choices
            : choices.filter { contextLineIDs.contains($0.id) }
        let pool = scoped.isEmpty ? choices : scoped
        if let only = orderedLines(pool, contextLineIDs: contextLineIDs).first {
            return make(name: station.name, countryCode: country, detail: only.label)
        }
        return countryOnly(name: station.name, countryCode: country)
    }

    public static func text(
        for station: CatalogStation,
        catalog: EditorCatalog,
        contextLineIDs: Set<String> = [],
        preferredLineID: String? = nil
    ) -> Text {
        text(
            for: station,
            catalog: catalog,
            labels: lineLabels(in: catalog, regionCode: station.key.regionCode),
            contextLineIDs: contextLineIDs,
            preferredLineID: preferredLineID)
    }

    /// `(CC)` when the station has no line to name.
    public static func countryOnly(name: String, countryCode: String) -> Text {
        let qualifier = caption(countryCode: countryCode, detail: nil)
        return Text(
            name: name, countryCode: countryCode, qualifier: qualifier,
            full: "\(name) \(qualifier)", spokenDetail: "")
    }

    public static func make(name: String, countryCode: String, detail: String) -> Text {
        let full = self.full(name: name, countryCode: countryCode, lineLabel: detail)
        return Text(
            name: name,
            countryCode: countryCode,
            qualifier: caption(countryCode: countryCode, detail: detail),
            full: full,
            spokenDetail: detail)
    }

    public static func transferText(name: String, countryCode: String, from: String, to: String) -> Text {
        let full = transfer(name: name, countryCode: countryCode, from: from, to: to)
        let detail = "\(from) → \(to)"
        return Text(
            name: name,
            countryCode: countryCode,
            qualifier: caption(countryCode: countryCode, detail: detail),
            full: full,
            spokenDetail: detail)
    }

    /// Display labels for every line in one country, keyed by line id.
    /// The catalog computes this once; this reads that table.
    public static func lineLabels(in catalog: EditorCatalog, regionCode: String) -> [String: String] {
        catalog.storedLineLabels(regionCode: regionCode)
    }

    /// Build the per-country table. Does not read an ``EditorCatalog``, so the
    /// catalog can call this while it is still initializing.
    static func lineLabels(lines: [CatalogLine], operators: [CatalogOperator]) -> [String: String] {
        var counts: [String: Int] = [:]
        for line in lines { counts[line.name, default: 0] += 1 }
        let operatorNames = Dictionary(
            operators.map { ($0.id, $0.name) },
            uniquingKeysWith: { first, _ in first })
        var labels: [String: String] = [:]
        for line in lines {
            let operatorName = line.operatorIDs.compactMap { operatorNames[$0] }.first { !$0.isEmpty }
            labels[line.id] = lineLabel(
                name: line.name,
                operatorName: operatorName,
                uniqueInCountry: (counts[line.name] ?? 0) <= 1)
        }
        return labels
    }

    /// `(CC, …)` for each station source code. Built once per picker load.
    public static func qualifiersBySourceCode(in catalog: EditorCatalog, regionCode: String) -> [String: String] {
        let labels = lineLabels(in: catalog, regionCode: regionCode)
        var result: [String: String] = [:]
        for station in catalog.stations(in: regionCode) {
            result[station.key.sourceCode] = text(
                for: station, catalog: catalog, labels: labels).qualifier
        }
        return result
    }

    static func lineChoices(for station: CatalogStation, catalog: EditorCatalog) -> [LineChoice] {
        lineChoices(for: station, catalog: catalog, labels: lineLabels(in: catalog, regionCode: station.key.regionCode))
    }

    static func lineChoices(
        for station: CatalogStation, catalog: EditorCatalog, labels: [String: String]
    ) -> [LineChoice] {
        var seen: Set<String> = []
        var choices: [LineChoice] = []
        let operators = Dictionary(
            catalog.operators(in: station.key.regionCode).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first })
        for member in catalog.memberships(stationKey: station.key) {
            guard seen.insert(member.lineID).inserted,
                  let line = catalog.line(id: member.lineID, regionCode: member.regionCode) else { continue }
            let operatorName = line.operatorIDs.compactMap { operators[$0]?.name }.first { !$0.isEmpty }
            choices.append(LineChoice(
                id: line.id,
                label: labels[line.id] ?? line.name,
                rank: line.rank,
                name: line.name,
                operatorLabel: qualifiedLineName(line.name, operatorName: operatorName)))
        }
        return choices
    }

    static func qualifierSuffix(name: String, full: String) -> String {
        let prefix = name + " "
        guard full.hasPrefix(prefix) else { return full }
        return String(full.dropFirst(prefix.count))
    }

    public struct Presentation: Hashable, Sendable {
        /// The large station name. A status marker shows the base; every other name stays official.
        public var label: String
        /// Small secondary text. A status marker leads with the localized word and the stored bracket.
        public var secondary: String
        /// Official full name plus the existing qualifier, so copy and share round-trip.
        public var copy: String

        public init(label: String, secondary: String, copy: String) {
            self.label = label
            self.secondary = secondary
            self.copy = copy
        }
    }

    /// Display parts from the stored split. `statusWord` is already localized.
    /// Status is display data only and never removes the station from a dated ride.
    /// A subname, including an infix, keeps the official spelling as the label.
    public static func presented(
        officialName: String,
        qualifier: String,
        parts: StationNameRecord?,
        statusWord: String?
    ) -> Presentation {
        let copy = copyText(officialName: officialName, qualifier: qualifier)
        guard let parts, parts.kind == .status else {
            return Presentation(label: officialName, secondary: qualifier, copy: copy)
        }
        return Presentation(
            label: parts.base,
            secondary: statusSecondary(bracket: parts.bracket, statusWord: statusWord, qualifier: qualifier),
            copy: copy)
    }

    /// `预留 · (CN, 某线)`, or `Reserved · 预留 · (CN, 某线)` when the localized word differs.
    public static func statusSecondary(bracket: String, statusWord: String?, qualifier: String) -> String {
        let word = statusWord?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var pieces: [String] = []
        if word.isEmpty {
            pieces.append(bracket)
        } else if word.compare(bracket, options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX")) == .orderedSame {
            pieces.append(word)
        } else {
            pieces.append(word)
            if !bracket.isEmpty { pieces.append(bracket) }
        }
        if !qualifier.isEmpty { pieces.append(qualifier) }
        return pieces.joined(separator: " · ")
    }

    public static func copyText(officialName: String, qualifier: String) -> String {
        if qualifier.isEmpty { return officialName }
        if qualifier.hasPrefix("(") { return officialName + " " + qualifier }
        return officialName
    }

    public static func spokenDetail(in qualifier: String) -> String {
        guard qualifier.count >= 2, qualifier.hasPrefix("("), qualifier.hasSuffix(")") else { return qualifier }
        let inner = qualifier.dropFirst().dropLast()
        let separators: [Character] = [",", "，"]
        guard let separator = separators.compactMap({ inner.firstIndex(of: $0) }).min() else {
            return String(inner)
        }
        return inner[inner.index(after: separator)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
