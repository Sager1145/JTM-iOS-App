import Foundation

/// ADR 0013 §11.3, on the editor catalog import and completion already use.
///
/// Each step only removes candidates. Nothing here returns the first of several.
/// Reachability to the other endpoint is intentionally absent: that needs the
/// route solver, and a same-complex company choice is not the solver's to make.
public enum StationReferenceResolution {
    public struct Match: Hashable, Sendable {
        public var station: CatalogStation
        public var label: String

        public init(station: CatalogStation, label: String) {
            self.station = station
            self.label = label
        }
    }

    /// `limitingToRegion` applies only when the mention itself has no country.
    /// An explicit country always wins. An unsupported country matches nothing.
    public static func resolve(
        _ reference: StationReference,
        in catalogs: [String: EditorCatalog],
        limitingToRegion: String? = nil
    ) -> [Match] {
        if reference.unsupportedCountry || reference.name.isEmpty { return [] }
        let country = reference.country ?? limitingToRegion.flatMap(StationReference.canonicalCountry)
        let slug = country.map(StationReference.slug)
        var hits: [StationKey: (CatalogStation, EditorCatalog)] = [:]
        for catalog in catalogs.values {
            for station in catalog.candidates(named: reference.name, regionCode: slug) {
                if hits[station.key] == nil { hits[station.key] = (station, catalog) }
            }
        }
        var pending: [(CatalogStation, [StationLabel.LineChoice], EditorCatalog)] = []
        for (station, catalog) in hits.values {
            let matchedLines = matchingLineIDs(reference.line, station: station, catalog: catalog)
            if reference.line != nil && matchedLines.isEmpty { continue }
            let choices = StationLabel.lineChoices(for: station, catalog: catalog)
            let scoped = matchedLines.isEmpty
                ? choices
                : choices.filter { matchedLines.contains($0.id) }
            pending.append((station, scoped.isEmpty ? choices : scoped, catalog))
        }
        let labels = oneLineLabels(for: pending)
        var matches: [Match] = []
        for (station, _, _) in pending {
            let country = station.key.regionCode.uppercased()
            let label = labels[station.key] ?? StationLabel.countryOnly(
                name: station.name, countryCode: country).full
            matches.append(Match(station: station, label: label))
        }
        return matches.sorted { lhs, rhs in
            if lhs.station.key.sourceCode != rhs.station.key.sourceCode {
                return lhs.station.key.sourceCode < rhs.station.key.sourceCode
            }
            return lhs.station.key.regionCode < rhs.station.key.regionCode
        }
    }

    /// A bracket group is a qualifier when it names a supported country, a line
    /// alias in that country, or both. An unknown line, a platform, or `US`/`CA`
    /// is not a qualifier.
    static func recognizedQualifier(
        _ reference: StationReference, in catalogs: [String: EditorCatalog]
    ) -> Bool {
        if reference.unsupportedCountry || reference.name.isEmpty { return false }
        if reference.country == nil && reference.line == nil { return false }
        if let line = reference.line {
            return lineAliasKnown(line, country: reference.country, in: catalogs)
        }
        return reference.country != nil
    }

    /// One country-unique line label, `name (CC, lineLabel)`, using the catalog name.
    /// `preferredLineID` is the line the rider picked. Otherwise the context line,
    /// or the best-ranked line that no same-name peer already took.
    public static func copyLabel(
        for station: CatalogStation,
        catalog: EditorCatalog,
        contextLineIDs: Set<String> = [],
        preferredLineID: String? = nil
    ) -> String {
        if preferredLineID != nil {
            return StationLabel.text(
                for: station, catalog: catalog, preferredLineID: preferredLineID).full
        }
        let peers = catalog.candidates(named: station.name, regionCode: station.key.regionCode)
        let pool = peers.isEmpty ? [station] : peers
        let items = pool.map { peer -> (CatalogStation, [StationLabel.LineChoice], EditorCatalog) in
            let choices = StationLabel.lineChoices(for: peer, catalog: catalog)
            let context = peer.key == station.key ? contextLineIDs : []
            let filtered = context.isEmpty ? choices : choices.filter { context.contains($0.id) }
            return (peer, filtered.isEmpty ? choices : filtered, catalog)
        }
        let country = station.key.regionCode.uppercased()
        return oneLineLabels(for: items)[station.key] ?? StationLabel.countryOnly(
            name: station.name, countryCode: country).full
    }

    /// Each station takes the best-ranked line whose label resolves to exactly
    /// itself. A line shared with another same-name candidate does not count.
    /// When no line does, the label uses the operator-qualified line name.
    static func oneLineLabels(
        for items: [(CatalogStation, [StationLabel.LineChoice], EditorCatalog)]
    ) -> [StationKey: String] {
        let groups = Dictionary(grouping: items) { item in
            "\(item.0.key.regionCode)\0\(item.0.name)"
        }
        var labels: [StationKey: String] = [:]
        for group in groups.values {
            let peers = group.map { (station: $0.0, catalog: $0.2) }
            for (station, choices, _) in group {
                let country = station.key.regionCode.uppercased()
                let ranked = choices.sorted { lhs, rhs in
                    if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
                    if lhs.name != rhs.name { return lhs.name < rhs.name }
                    return lhs.id < rhs.id
                }
                let picked = ranked.first { choice in
                    resolvesExclusively(choice.label, station: station, peers: peers)
                }
                let full: String
                if let picked {
                    full = StationLabel.full(
                        name: station.name, countryCode: country, lineLabel: picked.label)
                } else if let fallback = ranked.first {
                    full = StationLabel.full(
                        name: station.name, countryCode: country, lineLabel: fallback.operatorLabel)
                } else {
                    full = StationLabel.countryOnly(name: station.name, countryCode: country).full
                }
                labels[station.key] = full
            }
        }
        return labels
    }

    /// True when `lineQuery` matches this station and no other same-name peer.
    private static func resolvesExclusively(
        _ lineQuery: String,
        station: CatalogStation,
        peers: [(station: CatalogStation, catalog: EditorCatalog)]
    ) -> Bool {
        let hits = peers.filter { peer in
            !matchingLineIDs(lineQuery, station: peer.station, catalog: peer.catalog).isEmpty
        }
        return hits.count == 1 && hits[0].station.key == station.key
    }

    private static func lineAliasKnown(
        _ query: String, country: String?, in catalogs: [String: EditorCatalog]
    ) -> Bool {
        let needle = fold(query)
        guard !needle.isEmpty else { return false }
        let slugs = country.map { [StationReference.slug($0)] } ?? Array(StationReference.regionSlugs)
        for catalog in catalogs.values {
            for region in slugs {
                let labels = StationLabel.lineLabels(in: catalog, regionCode: region)
                let operators = Dictionary(
                    catalog.operators(in: region).map { ($0.id, $0) },
                    uniquingKeysWith: { first, _ in first })
                for line in catalog.lines(in: region) {
                    if aliases(of: line, labels: labels, operators: operators).contains(needle) {
                        return true
                    }
                }
            }
        }
        return false
    }

    /// Line aliases: the line name, that name without a leading `N号線`, the
    /// operator-qualified label, the line code, stored aliases, and the
    /// company's short label when it identifies the station.
    static func matchingLineIDs(
        _ query: String?, station: CatalogStation, catalog: EditorCatalog
    ) -> Set<String> {
        guard let query else { return [] }
        let needle = fold(query)
        guard !needle.isEmpty else { return [] }
        var matched: Set<String> = []
        let labels = StationLabel.lineLabels(in: catalog, regionCode: station.key.regionCode)
        let operators = Dictionary(
            catalog.operators(in: station.key.regionCode).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first })
        var seen: Set<String> = []
        for member in catalog.memberships(stationKey: station.key) {
            guard seen.insert(member.lineID).inserted,
                  let line = catalog.line(id: member.lineID, regionCode: member.regionCode) else { continue }
            if aliases(of: line, labels: labels, operators: operators).contains(needle) {
                matched.insert(line.id)
            }
        }
        return matched
    }

    private static func aliases(
        of line: CatalogLine, labels: [String: String], operators: [String: CatalogOperator]
    ) -> Set<String> {
        var raw: [String] = [line.name]
        raw.append(contentsOf: line.aliases)
        if let code = line.lineCode, !code.isEmpty { raw.append(code) }
        if let label = labels[line.id] { raw.append(label) }
        let numbered = raw
        for name in numbered {
            if let stripped = withoutLeadingLineNumber(name) { raw.append(stripped) }
        }
        for operatorID in line.operatorIDs {
            guard let company = operators[operatorID] else { continue }
            raw.append(company.name)
            raw.append(contentsOf: company.aliases)
            if let short = company.shortName { raw.append(short) }
            let branded = OperatorBranding.companyLabel(company.name)
            if !branded.isEmpty { raw.append(branded) }
            raw.append(StationLabel.qualifiedLineName(line.name, operatorName: company.name))
            let compact = OperatorBranding.companyLabel(company.name)
            if !compact.isEmpty {
                raw.append(compact + line.name)
                raw.append(compact + " " + line.name)
            }
        }
        return Set(raw.map(fold).filter { !$0.isEmpty })
    }

    /// `4号線丸ノ内線` → `丸ノ内線`, `1号線(御堂筋線)` → `御堂筋線`.
    static func withoutLeadingLineNumber(_ name: String) -> String? {
        guard let match = name.range(of: #"^[0-9]+号線"#, options: .regularExpression) else { return nil }
        var rest = name[match.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        let wrappers: [(Character, Character)] = [("(", ")"), ("（", "）")]
        if rest.count >= 2, let pair = wrappers.first(where: { rest.first == $0.0 && rest.last == $0.1 }) {
            rest = rest.dropFirst().dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
            _ = pair
        }
        if rest.isEmpty || rest == name { return nil }
        return rest
    }

    static func fold(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCompatibilityMapping
            .lowercased()
    }
}
