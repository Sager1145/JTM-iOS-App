import Foundation

/// Passenger-facing label derived from one company station and one line part.
public struct RegistryStationLabel: Equatable, Sendable {
    /// Large name and status secondary, from ``StationLabel/presented``.
    public var presentation: StationLabel.Presentation
    /// Country caption built from ``presentation.label`` and the chosen line.
    public var text: StationLabel.Text
    /// Line part used for the caption. Nil when the station lists none.
    public var lineID: String?

    public init(presentation: StationLabel.Presentation, text: StationLabel.Text, lineID: String?) {
        self.presentation = presentation
        self.text = text
        self.lineID = lineID
    }
}

/// Read-only identity queries over one ``RegistryBundle``.
///
/// Schema 1 files decode with empty reverse maps, so station, complex, and
/// label queries miss. ``stationID(forCode:operator:)`` still answers from the
/// forward code tables. The value is pure: it does not read the clock or disk.
public struct RegistryIdentity: Equatable, Sendable {
    public var bundle: RegistryBundle
    /// NFKC exact key → the one operator that owns it. A key two operators share is omitted.
    private var exactOperatorByName: [String: String]
    /// Identity code → the one operator that stores it. A code two records share is omitted.
    private var operatorByIdentityCode: [String: String]
    /// Line-part name → how many parts in this bundle use that exact name.
    private var lineNameCounts: [String: Int]
    /// Folded name, label, alias, or identity display name → operator ids.
    /// The raw identity code is not a query key. Built once with the identity.
    private var operatorsByHaystack: [String: Set<String>]
    /// Repeat queries reuse the substring scan. Copies share the cache.
    private let queryMatchCache = QueryMatchCache()
    /// Bracket-folded official name → station ids. An exact name wins over a base.
    private var stationIDsByOfficialName: [String: [String]]
    /// Bracket-folded base → station ids whose stored parts use that base.
    private var stationIDsByBase: [String: [String]]
    /// Official names and bases, longest first, for free-text span proposals.
    private var stationNameNeedles: [String]

    public init(bundle: RegistryBundle) {
        self.bundle = bundle
        let maps = Self.conversionMaps(bundle)
        self.exactOperatorByName = maps.exact
        self.operatorByIdentityCode = maps.byCode
        self.lineNameCounts = maps.lineNames
        var byHaystack: [String: Set<String>] = [:]
        for (haystack, identifier) in maps.haystacks {
            byHaystack[haystack, default: []].insert(identifier)
        }
        self.operatorsByHaystack = byHaystack
        let names = Self.stationNameMaps(bundle)
        self.stationIDsByOfficialName = names.official
        self.stationIDsByBase = names.base
        self.stationNameNeedles = names.needles
    }

    public static func == (lhs: RegistryIdentity, rhs: RegistryIdentity) -> Bool {
        lhs.bundle == rhs.bundle
    }

    /// Unique exact name or identity-code string. Ambiguous and unknown names are nil.
    public func operatorID(forExactName name: String) -> String? {
        let key = Self.exactKey(name, region: bundle.region)
        guard !key.isEmpty else { return nil }
        return exactOperatorByName[key]
    }

    /// Folded query as a substring of a name, label, alias, or identity display name.
    /// An empty query and a query that names no operator both return an empty set.
    /// The raw identity code is not a match key: a query is UI text.
    public func operatorIDs(matchingQuery query: String) -> Set<String> {
        let folded = SearchFold.fold(JSString.trim(query))
        guard !folded.isEmpty else { return [] }
        return queryMatchCache.matches(folded) {
            var matched: Set<String> = []
            for (haystack, identifiers) in operatorsByHaystack where haystack.contains(folded) {
                matched.formUnion(identifiers)
            }
            return matched
        }
    }

    /// Catalog company text → operator ids. A slash-joined string that is itself a
    /// bundle name stays one operator. Otherwise each `/` part converts on its own,
    /// and a part that does not convert is dropped.
    public func operatorIDs(forCatalogName name: String) -> [String] {
        let trimmed = JSString.trim(name)
        guard !trimmed.isEmpty else { return [] }
        if let whole = operatorID(forExactName: trimmed) { return [whole] }
        let parts = trimmed.components(separatedBy: CharacterSet(charactersIn: "/／"))
        guard parts.count > 1 else { return [] }
        var seen: Set<String> = []
        var result: [String] = []
        for part in parts {
            guard let identifier = operatorID(forExactName: part), seen.insert(identifier).inserted else { continue }
            result.append(identifier)
        }
        return result
    }

    /// Exact catalog name, then a stored identity code, then `jp.` plus a timetable token.
    public func operatorID(forCatalogOrTimetableToken token: String) -> String? {
        let trimmed = JSString.trim(token)
        guard !trimmed.isEmpty else { return nil }
        if let exact = operatorID(forExactName: trimmed) { return exact }
        if let coded = operatorID(forIdentityCode: trimmed) { return coded }
        let prefixed = trimmed.hasPrefix("jp.") ? trimmed : "jp." + trimmed
        if prefixed != trimmed {
            if let coded = operatorID(forIdentityCode: prefixed) { return coded }
            if let exact = operatorID(forExactName: prefixed) { return exact }
        }
        return nil
    }

    /// Passenger label. The stored short label wins; a schema-1 record falls back to its first name.
    public func operatorLabel(_ identifier: String) -> String? {
        guard let record = bundle.operatorRecords[identifier] else { return nil }
        if !record.label.isEmpty { return record.label }
        return record.names.first
    }

    /// Logo path stored on the operator. Empty and missing logos are nil.
    public func operatorLogo(_ identifier: String) -> String? {
        guard let logo = bundle.operatorRecords[identifier]?.logo, !logo.isEmpty else { return nil }
        return logo
    }

    private static func exactKey(_ value: String, region: String) -> String {
        let folded = JSString.trim(value).precomposedStringWithCompatibilityMapping
        guard region.lowercased() == "tw" else { return folded }
        return OperatorBranding.normalizeTaiwanCompanyName(folded)
    }

    private static func conversionMaps(
        _ bundle: RegistryBundle
    ) -> (exact: [String: String], byCode: [String: String], lineNames: [String: Int], haystacks: [(String, String)]) {
        var owners: [String: Set<String>] = [:]
        var haystacks: [(String, String)] = []
        var seenHaystack: Set<String> = []
        var codeOwners: [String: Set<String>] = [:]
        for (identifier, record) in bundle.operatorRecords {
            var exactSources = record.names
            if let identity = record.identity, !identity.isEmpty {
                exactSources.append(identity)
                codeOwners[identity, default: []].insert(identifier)
            }
            for raw in exactSources {
                let key = exactKey(raw, region: bundle.region)
                guard !key.isEmpty else { continue }
                owners[key, default: []].insert(identifier)
            }
            var foldSources = record.names
            if !record.label.isEmpty { foldSources.append(record.label) }
            if let identity = record.identity, !identity.isEmpty {
                for name in OperatorIdentity.searchNames(for: identity) where name != identity {
                    foldSources.append(name)
                }
            }
            for raw in foldSources {
                let key = SearchFold.fold(raw)
                guard !key.isEmpty else { continue }
                let token = key + "\u{0}" + identifier
                guard seenHaystack.insert(token).inserted else { continue }
                haystacks.append((key, identifier))
            }
        }
        var exact: [String: String] = [:]
        for (key, identifiers) in owners where identifiers.count == 1 {
            exact[key] = identifiers.first
        }
        var byCode: [String: String] = [:]
        for (code, identifiers) in codeOwners where identifiers.count == 1 {
            byCode[code] = identifiers.first
        }
        var lineNames: [String: Int] = [:]
        for part in bundle.lineParts.values {
            lineNames[part.name, default: 0] += 1
        }
        return (exact, byCode, lineNames, haystacks)
    }

    /// One company station a typed, pasted, or guide name resolved to.
    public struct StationInputMatch: Hashable, Sendable {
        public var stationID: String
        public var name: String
        public var codes: [String]
        public var complexID: String
        public var label: String

        public init(
            stationID: String, name: String, codes: [String], complexID: String, label: String
        ) {
            self.stationID = stationID
            self.name = name
            self.codes = codes
            self.complexID = complexID
            self.label = label
        }
    }

    /// ADR 0013 §11.2 against this region's station records.
    ///
    /// An exact official name wins, including a bracket-folded spelling.
    /// A bare base matches only when `baseNameCounts` is 1 and no station is
    /// officially named that base. A line keeps stations that line serves.
    /// Several hits stay a list. Nothing here returns the first of several.
    public func stations(for reference: StationReference) -> [StationInputMatch] {
        if reference.unsupportedCountry || reference.name.isEmpty { return [] }
        if let country = reference.country,
           country.lowercased() != bundle.region.lowercased() {
            return []
        }
        let identified = stationIDs(named: reference.name)
        let lined: [String]
        if let line = reference.line {
            lined = identified.filter { !matchingLineIDs($0, query: line).isEmpty }
        } else {
            lined = identified
        }
        return lined.compactMap { stationID in
            let requested = reference.line.flatMap { matchingLineIDs(stationID, query: $0).first }
            return inputMatch(stationID, lineID: requested)
        }
    }

    /// Station ids whose official name is `name`, or the unique base when no
    /// official name is exactly `name`. Several exact names, or a shared base,
    /// stay a list.
    public func stationIDs(named name: String) -> [String] {
        let key = Self.stationNameKey(name)
        guard !key.isEmpty else { return [] }
        if let exact = stationIDsByOfficialName[key], !exact.isEmpty {
            return exact
        }
        let count = baseCount(name, key: key)
        guard count > 0 else { return [] }
        return stationIDsByBase[key] ?? []
    }

    /// Longest official names and bases that occur in `text`, without overlap.
    /// Each returned string is a span for ``stations(for:)``, not a chosen station.
    public func containedNameSpans(in text: String) -> [String] {
        let haystack = Self.spanKey(text)
        guard !haystack.isEmpty else { return [] }
        var claimed: [Range<String.Index>] = []
        var spans: [String] = []
        for needle in stationNameNeedles {
            let folded = Self.spanKey(needle)
            guard !folded.isEmpty else { continue }
            var search = haystack.startIndex
            while let range = haystack.range(of: folded, range: search..<haystack.endIndex) {
                let overlaps = claimed.contains { $0.overlaps(range) }
                if !overlaps {
                    claimed.append(range)
                    spans.append(needle)
                }
                search = range.upperBound
                if search >= haystack.endIndex { break }
            }
        }
        return spans
    }

    /// §11.5 caption for one complex: up to two line labels, then ` +N`.
    public func searchQualifier(complexID: String) -> String? {
        guard let complex = bundle.complexes[complexID] else { return nil }
        var choices: [StationLabel.LineChoice] = []
        var seen: Set<String> = []
        for stationID in complex.stations {
            guard let station = bundle.stations[stationID] else { continue }
            for lineID in station.lines {
                guard seen.insert(lineID).inserted, let part = bundle.lineParts[lineID] else { continue }
                let caption = lineLabel(for: lineID) ?? part.name
                choices.append(StationLabel.LineChoice(
                    id: lineID, label: caption, rank: part.rank, name: part.name))
            }
        }
        let full = StationLabel.search(
            name: complex.name, countryCode: bundle.region.uppercased(),
            lines: choices, contextLineIDs: [])
        let prefix = complex.name + " "
        guard full.hasPrefix(prefix) else { return nil }
        return String(full.dropFirst(prefix.count))
    }

    /// Exact operator text, including a joint `A/B` or `A・B` whose every part converts.
    /// A part that does not convert rejects the whole string.
    public func operatorCommit(forExactText text: String) -> RegistryOperatorCommit.Choice? {
        let trimmed = JSString.trim(text)
        guard !trimmed.isEmpty else { return nil }
        if let whole = operatorID(forExactName: trimmed) {
            return operatorChoice(ids: [whole])
        }
        let parts = trimmed.components(separatedBy: CharacterSet(charactersIn: "/／・"))
            .map { JSString.trim($0) }
            .filter { !$0.isEmpty }
        guard parts.count > 1 else { return nil }
        var ids: [String] = []
        var seen: Set<String> = []
        for part in parts {
            guard let identifier = operatorID(forExactName: part) else { return nil }
            if seen.insert(identifier).inserted { ids.append(identifier) }
        }
        guard !ids.isEmpty else { return nil }
        return operatorChoice(ids: ids)
    }

    private func operatorChoice(ids: [String]) -> RegistryOperatorCommit.Choice {
        let official = ids.map { identifier -> String in
            if let name = bundle.operatorRecords[identifier]?.names.first, !name.isEmpty { return name }
            return operatorLabel(identifier) ?? identifier
        }
        let display = ids.enumerated().map { index, identifier -> String in
            if let label = operatorLabel(identifier), !label.isEmpty { return label }
            return official[index]
        }
        return RegistryOperatorCommit.Choice(
            ids: ids,
            company: display.joined(separator: "/"),
            preferredNames: official)
    }

    public func station(_ identifier: String) -> RegistryStationRecord? {
        bundle.stations[identifier]
    }

    public func codes(of stationID: String) -> [String] {
        bundle.stations[stationID]?.codes ?? []
    }

    public func complex(of stationID: String) -> RegistryComplexRecord? {
        guard let complexID = bundle.stations[stationID]?.cx else { return nil }
        return bundle.complexes[complexID]
    }

    public func stations(in complexID: String) -> [String] {
        bundle.complexes[complexID]?.stations ?? []
    }

    public func `operator`(for identifier: String) -> RegistryOperatorRecord? {
        bundle.operatorRecords[identifier]
    }

    /// The operator whose stored identity code equals `code`. Nil unless exactly one does.
    public func operatorID(forIdentityCode code: String) -> String? {
        operatorByIdentityCode[code]
    }

    /// Same fail-closed rule ``RegistryIdentityUpgrade`` used before this facade.
    ///
    /// Canonicalize the code, then a direct `stationCodes` hit wins. A group
    /// code with one station is that station. Several stations narrow to one
    /// only when `operator` owns exactly one of them. Anything else is nil.
    public func stationID(forCode rawCode: String, operator operatorID: String?) -> String? {
        let code = StationCodeAliases.canonical(rawCode)
        if let direct = bundle.stationCodes[code] {
            return direct
        }
        guard let candidates = bundle.groupCodes[code] else { return nil }
        if candidates.count == 1 { return candidates[0] }
        guard let operatorID else { return nil }
        let narrowed = candidates.filter { candidate in
            guard let owner = bundle.stationOperator[candidate] else { return false }
            return sameCodeUnits(owner, operatorID)
        }
        return narrowed.count == 1 ? narrowed[0] : nil
    }

    /// Nil when the bundle has no station record (including every schema 1 file).
    ///
    /// `line` is used only when it serves the station. Otherwise the best line
    /// by rank, then name, then id. A line name that appears once in the country
    /// is shown bare; a repeated name is qualified with the operator's short label.
    public func label(for stationID: String, line requested: String? = nil, country: String) -> RegistryStationLabel? {
        guard let station = bundle.stations[stationID] else { return nil }
        let countryCode = country.uppercased()
        let lineID = chosenLineID(station: station, requested: requested)
        let detail = lineID.flatMap { lineLabel(for: $0) }
        let qualifier = StationLabel.caption(countryCode: countryCode, detail: detail)
        let presentation = StationLabel.presented(
            officialName: station.name,
            qualifier: qualifier,
            parts: station.parts,
            statusWord: nil)
        let text = detail.map {
            StationLabel.make(name: presentation.label, countryCode: countryCode, detail: $0)
        } ?? StationLabel.countryOnly(name: presentation.label, countryCode: countryCode)
        return RegistryStationLabel(presentation: presentation, text: text, lineID: lineID)
    }

    private static func stationNameKey(_ value: String) -> String {
        spanKey(JSString.trim(value))
    }

    /// Bracket fold plus NFKC. Length is not stable, so callers use it as a search key.
    private static func spanKey(_ value: String) -> String {
        StationNameDirectory.foldBrackets(value.precomposedStringWithCompatibilityMapping)
    }

    private static func stationNameMaps(
        _ bundle: RegistryBundle
    ) -> (official: [String: [String]], base: [String: [String]], needles: [String]) {
        var official: [String: [String]] = [:]
        var base: [String: [String]] = [:]
        var needleSet: [String: Int] = [:]
        for (identifier, record) in bundle.stations {
            let nameKey = stationNameKey(record.name)
            if !nameKey.isEmpty {
                var list = official[nameKey] ?? []
                if !list.contains(identifier) { list.append(identifier) }
                official[nameKey] = list
                needleSet[record.name] = max(needleSet[record.name] ?? 0, nameKey.count)
            }
            if let baseName = record.parts?.base {
                let key = stationNameKey(baseName)
                if !key.isEmpty {
                    var list = base[key] ?? []
                    if !list.contains(identifier) { list.append(identifier) }
                    base[key] = list
                    needleSet[baseName] = max(needleSet[baseName] ?? 0, key.count)
                }
            }
            for alias in record.aka ?? [] {
                let key = stationNameKey(alias)
                guard !key.isEmpty, key != nameKey else { continue }
                var list = official[key] ?? []
                if !list.contains(identifier) { list.append(identifier) }
                official[key] = list
                needleSet[alias] = max(needleSet[alias] ?? 0, key.count)
            }
        }
        for key in official.keys { official[key]?.sort() }
        for key in base.keys { base[key]?.sort() }
        for (baseName, _) in bundle.baseNameCounts {
            let key = stationNameKey(baseName)
            guard !key.isEmpty else { continue }
            needleSet[baseName] = max(needleSet[baseName] ?? 0, key.count)
        }
        let needles = needleSet.keys.sorted { lhs, rhs in
            let left = needleSet[lhs] ?? 0
            let right = needleSet[rhs] ?? 0
            if left != right { return left > right }
            return lhs < rhs
        }
        return (official, base, needles)
    }

    private func baseCount(_ name: String, key: String) -> Int {
        if let count = bundle.baseNameCounts[name] { return count }
        if let count = bundle.baseNameCounts[key] { return count }
        let folded = bundle.baseNameCounts.first { Self.stationNameKey($0.key) == key }
        return folded?.value ?? 0
    }

    private func matchingLineIDs(_ stationID: String, query: String) -> [String] {
        guard let station = bundle.stations[stationID] else { return [] }
        let needle = StationReferenceResolution.fold(query)
        guard !needle.isEmpty else { return [] }
        return station.lines.filter { lineID in
            guard let part = bundle.lineParts[lineID] else { return false }
            var raw = [part.name]
            if let network = part.ln, !network.isEmpty { raw.append(network) }
            if let record = bundle.operatorRecords[part.op] {
                raw.append(contentsOf: record.names)
                if !record.label.isEmpty { raw.append(record.label) }
                let source = record.label.isEmpty ? record.names.first : record.label
                if let source, !source.isEmpty {
                    raw.append(StationLabel.qualifiedLineName(part.name, operatorName: source))
                }
            }
            return raw.contains { StationReferenceResolution.fold($0) == needle }
        }
    }

    private func inputMatch(_ stationID: String, lineID: String?) -> StationInputMatch? {
        guard let record = bundle.stations[stationID] else { return nil }
        let label = label(for: stationID, line: lineID, country: bundle.region)?.text.full ?? record.name
        return StationInputMatch(
            stationID: stationID, name: record.name, codes: record.codes,
            complexID: record.cx, label: label)
    }

    private func chosenLineID(station: RegistryStationRecord, requested: String?) -> String? {
        if let requested, station.lines.contains(requested), bundle.lineParts[requested] != nil {
            return requested
        }
        let choices = station.lines.compactMap { identifier -> StationLabel.LineChoice? in
            guard let part = bundle.lineParts[identifier] else { return nil }
            return StationLabel.LineChoice(id: identifier, label: part.name, rank: part.rank, name: part.name)
        }
        return StationLabel.orderedLines(choices, contextLineIDs: []).first?.id
    }

    private func lineLabel(for lineID: String) -> String? {
        guard let part = bundle.lineParts[lineID] else { return nil }
        let copies = lineNameCounts[part.name] ?? 1
        return StationLabel.lineLabel(
            name: part.name,
            operatorName: brandingSource(for: part.op),
            uniqueInCountry: copies <= 1)
    }

    /// A package name whose ``OperatorBranding/companyLabel(_:)`` equals the stored
    /// short label. Prefer one that the short label actually changes, so a
    /// UTF-16-first spelling such as "JR East" is not the only string offered.
    private func brandingSource(for operatorID: String) -> String? {
        guard let record = bundle.operatorRecords[operatorID] else { return nil }
        let stored = record.label
        guard !stored.isEmpty else { return record.names.first }
        if let changing = record.names.first(where: { name in
            let short = OperatorBranding.companyLabel(name)
            return sameCodeUnits(short, stored) && !sameCodeUnits(short, name)
        }) {
            return changing
        }
        if let exact = record.names.first(where: { sameCodeUnits(OperatorBranding.companyLabel($0), stored) }) {
            return exact
        }
        return stored
    }
}

/// Company text the editor stores after an exact operator match.
public enum RegistryOperatorCommit {
    public struct Choice: Equatable, Sendable {
        public var ids: [String]
        public var company: String
        public var preferredNames: [String]

        public init(ids: [String], company: String, preferredNames: [String]) {
            self.ids = ids
            self.company = company
            self.preferredNames = preferredNames
        }
    }

    public static func choice(forExactText text: String, region: String) -> Choice? {
        RegistryIdentityCache.identity(forRegion: region)?.operatorCommit(forExactText: text)
    }

    /// Writes `company`, operator ids, and `preferred_operator_names` from the ids.
    /// A text that is not an exact operator name leaves the train unchanged.
    @discardableResult
    public static func apply(text: String, region: String, to train: inout Train) -> Bool {
        guard let choice = choice(forExactText: text, region: region) else { return false }
        if train.company != choice.company {
            RegistryIdentityUpgrade.reassignCompany(choice.company, on: &train)
        }
        train.company = choice.company
        if choice.ids.count == 1 {
            train.operatorID = choice.ids[0]
            train.operatorIDs = nil
        } else {
            train.operatorID = nil
            train.operatorIDs = choice.ids
        }
        if train.routePolicy != nil {
            train.routePolicy?.preferredOperatorNames = choice.preferredNames
        }
        return true
    }

    /// Each token that exactly names an operator is replaced by that operator's official name.
    /// A token that does not convert is left as typed so a partial word is not eaten.
    public static func preferredNames(from names: [String], region: String) -> [String] {
        guard let identity = RegistryIdentityCache.identity(forRegion: region) else { return names }
        return names.map { name in
            guard let choice = identity.operatorCommit(forExactText: name) else { return name }
            return choice.preferredNames.joined(separator: "/")
        }
    }
}

/// A picker or guide selection written as `station_id` plus the code and official name.
public enum RegistryStationSelection {
    public struct Written: Equatable, Sendable {
        public var stationID: String
        public var name: String
        public var code: String?

        public init(stationID: String, name: String, code: String?) {
            self.stationID = stationID
            self.name = name
            self.code = code
        }
    }

    /// Nil when the code is not exactly one company station. A shared group code stays nil.
    public static func written(stationID: String, regionCode: String) -> Written? {
        guard let identity = RegistryIdentityCache.identity(forRegion: regionCode),
              let record = identity.station(stationID) else { return nil }
        let codes = identity.codes(of: stationID)
        return Written(stationID: stationID, name: record.name, code: codes.first)
    }

    /// Nil when the code is not exactly one company station. A shared group code stays nil.
    public static func written(sourceCode: String, regionCode: String) -> Written? {
        let code = sourceCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty,
              let identity = RegistryIdentityCache.identity(forRegion: regionCode),
              let stationID = identity.stationID(forCode: code, operator: nil),
              let record = identity.station(stationID) else { return nil }
        let codes = identity.codes(of: stationID)
        return Written(stationID: stationID, name: record.name, code: codes.first ?? code)
    }

    @discardableResult
    public static func apply(sourceCode: String, regionCode: String, to stop: inout Stop) -> Bool {
        guard let written = written(sourceCode: sourceCode, regionCode: regionCode) else { return false }
        write(written, to: &stop)
        return true
    }

    @discardableResult
    public static func apply(stationID: String, regionCode: String, to stop: inout Stop) -> Bool {
        guard let written = written(stationID: stationID, regionCode: regionCode) else { return false }
        write(written, to: &stop)
        return true
    }

    /// A known station id wins. Otherwise the source code must name exactly one station.
    /// A code the registry cannot map keeps the catalog name and code and clears `station_id`.
    public static func fill(
        _ stop: inout Stop, regionCode: String, sourceCode: String, catalogName: String,
        stationID: String? = nil
    ) {
        if let stationID, apply(stationID: stationID, regionCode: regionCode, to: &stop) { return }
        if apply(sourceCode: sourceCode, regionCode: regionCode, to: &stop) { return }
        stop.stationID = nil
        stop.name = catalogName
        stop.n02StationCode = sourceCode
    }

    private static func write(_ written: Written, to stop: inout Stop) {
        stop.stationID = written.stationID
        stop.name = written.name
        if let code = written.code { stop.n02StationCode = code }
    }
}

/// Whether a region's registry can be read yet.
public enum RegistryPhase: Sendable {
    /// Decoded and ready for identity queries.
    case ready(RegistryIdentity)
    /// A bundle exists and a background decode is still running.
    case pending
    /// This region has no bundle, or the file failed to decode.
    case unavailable
}

/// Per-query results for ``RegistryIdentity/operatorIDs(matchingQuery:)``.
/// The newest query stays. Past ``limit`` entries, the oldest is dropped.
final class QueryMatchCache: @unchecked Sendable {
    static let defaultLimit = 256

    private let lock = NSLock()
    private let limit: Int
    private var stored: [String: Set<String>] = [:]
    /// Oldest query first.
    private var order: [String] = []

    init(limit: Int = defaultLimit) {
        self.limit = max(1, limit)
    }

    func matches(_ query: String, compute: () -> Set<String>) -> Set<String> {
        lock.lock()
        if let hit = stored[query] {
            touchLocked(query)
            lock.unlock()
            return hit
        }
        lock.unlock()
        let built = compute()
        lock.lock()
        if let hit = stored[query] {
            touchLocked(query)
            lock.unlock()
            return hit
        }
        stored[query] = built
        order.append(query)
        evictLocked()
        lock.unlock()
        return built
    }

    private func touchLocked(_ query: String) {
        if let index = order.firstIndex(of: query) {
            order.remove(at: index)
        }
        order.append(query)
    }

    private func evictLocked() {
        while stored.count > limit, !order.isEmpty {
            let oldest = order.removeFirst()
            stored.removeValue(forKey: oldest)
        }
    }
}

/// The app installs a per-region lookup. Tests leave it nil.
public enum RegistryIdentityLookup {
    public typealias Provider = @Sendable (String) -> RegistryIdentity?
    public typealias PhaseProvider = @Sendable (String) -> RegistryPhase

    /// A provider installed for the current task. Parallel tests each keep their own.
    public enum TestOverride: Sendable {
        case sync(Provider?)
        case phase(PhaseProvider?)
    }

    @TaskLocal static var testOverride: TestOverride?

    private static let lock = NSLock()
    nonisolated(unsafe) private static var provider: Provider?
    nonisolated(unsafe) private static var phaseProvider: PhaseProvider?
    nonisolated(unsafe) private static var generation: UInt64 = 0
    nonisolated(unsafe) private static var settled: [String: UInt64] = [:]
    nonisolated(unsafe) private static var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    /// Bumps every time the provider changes or a preload settles. The cache keys on this.
    public static var providerGeneration: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return generation
    }

    /// A synchronous provider. A nil result is unavailable, never pending.
    /// Installing one clears a phase provider.
    public static func install(_ provider: Provider?) {
        lock.lock()
        self.provider = provider
        self.phaseProvider = nil
        generation &+= 1
        let pending = waiters
        waiters.removeAll(keepingCapacity: true)
        lock.unlock()
        for list in pending.values {
            for waiter in list { waiter.resume() }
        }
    }

    /// Runs `operation` with a task-local synchronous provider. The app-wide install is unchanged.
    @_spi(Testing) public static func withTestProvider<T>(
        _ provider: Provider?, operation: () throws -> T
    ) rethrows -> T {
        try $testOverride.withValue(.sync(provider), operation: operation)
    }

    /// Runs `operation` with a task-local phase provider. The app-wide install is unchanged.
    @_spi(Testing) public static func withTestPhase<T>(
        _ provider: PhaseProvider?, operation: () throws -> T
    ) rethrows -> T {
        try $testOverride.withValue(.phase(provider), operation: operation)
    }

    /// Async overload. Child tasks inherit the override; `Task.detached` does not.
    @_spi(Testing) public static func withTestPhase<T>(
        _ provider: PhaseProvider?,
        isolation: isolated (any Actor)? = #isolation,
        operation: () async throws -> T
    ) async rethrows -> T {
        try await $testOverride.withValue(.phase(provider), operation: operation, isolation: isolation)
    }

    /// The app's background-preload provider. A nil provider is unavailable for every region.
    public static func installPhase(_ provider: PhaseProvider?) {
        lock.lock()
        self.provider = nil
        self.phaseProvider = provider
        generation &+= 1
        let pending = waiters
        waiters.removeAll(keepingCapacity: true)
        lock.unlock()
        for list in pending.values {
            for waiter in list { waiter.resume() }
        }
    }

    public static func phase(forRegion region: String) -> RegistryPhase {
        let cc = region.lowercased()
        guard !cc.isEmpty else { return .unavailable }
        if let testOverride {
            switch testOverride {
            case .sync(let provider):
                if let identity = provider?(cc) { return .ready(identity) }
                return .unavailable
            case .phase(let provider):
                return provider?(cc) ?? .unavailable
            }
        }
        lock.lock()
        let sync = provider
        let phased = phaseProvider
        lock.unlock()
        if let phased { return phased(cc) }
        if let sync {
            if let identity = sync(cc) { return .ready(identity) }
            return .unavailable
        }
        return .unavailable
    }

    public static func identity(forRegion region: String) -> RegistryIdentity? {
        if case .ready(let identity) = phase(forRegion: region) { return identity }
        return nil
    }

    /// One-shot watches. A settle for another region leaves them in place.
    private struct SettledWatch: Sendable {
        var region: String
        var handler: @Sendable (String) -> Void
    }

    nonisolated(unsafe) private static var settledWatches: [SettledWatch] = []

    /// Runs `handler` once when `region` settles. A region that is not pending runs it now.
    public static func whenSettled(region: String, _ handler: @escaping @Sendable (String) -> Void) {
        let cc = region.lowercased()
        guard !cc.isEmpty else { return }
        if !isPending(cc) {
            handler(cc)
            return
        }
        let stamp = settledStamp(cc)
        lock.lock()
        let raced = (settled[cc] ?? 0) != stamp
        if !raced {
            settledWatches.append(SettledWatch(region: cc, handler: handler))
        }
        lock.unlock()
        if raced { handler(cc) }
    }

    /// Resume waiters for one region and drop cached misses. Called when a preload finishes.
    public static func notifySettled(region: String) {
        let cc = region.lowercased()
        guard !cc.isEmpty else { return }
        lock.lock()
        generation &+= 1
        settled[cc] = generation
        let resumed = waiters.removeValue(forKey: cc) ?? []
        let watches = settledWatches
        settledWatches.removeAll { $0.region == cc }
        lock.unlock()
        for waiter in resumed { waiter.resume() }
        for watch in watches where watch.region == cc {
            watch.handler(cc)
        }
    }

    /// True when this task or the process has a lookup or phase provider installed.
    public static var lookupInstalled: Bool {
        if testOverride != nil { return true }
        lock.lock()
        defer { lock.unlock() }
        return provider != nil || phaseProvider != nil
    }

    /// Retained for source compatibility. Missing-lookup solves are tolerated under a test runner, so this is a no-op.
    @_spi(Testing) public static func permitMissingLookup() {}

    @_spi(Testing) public static var missingLookupPermitted: Bool { runningUnderTestRunner }

    /// True when the process is hosted by XCTest or swift-testing.
    static let runningUnderTestRunner: Bool = {
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil || env["XCTestBundlePath"] != nil
            || env["XCTestSessionIdentifier"] != nil || env["SWT_ENABLE_EXPERIMENTAL_CONSOLE_OUTPUT"] != nil {
            return true
        }
        if NSClassFromString("XCTestCase") != nil { return true }
        let name = ProcessInfo.processInfo.processName.lowercased()
        return name.contains("xctest") || name.contains("swiftpm-testing-helper")
            || name.hasSuffix("pm-testing-helper")
    }()

    /// True when a solve should report that no lookup is installed.
    public static func shouldNoteUninstalledLookup(installed: Bool, permitted: Bool) -> Bool {
        !installed && !permitted
    }

    static func noteUninstalledLookup(_ context: String) {
        guard shouldNoteUninstalledLookup(installed: lookupInstalled, permitted: runningUnderTestRunner) else { return }
        #if DEBUG
        assertionFailure(
            "Solving \(context) without RegistryIdentityLookup.install().")
        #endif
    }

    /// Waits until the region is ready or unavailable. A region that is already settled returns immediately.
    /// A notify for a provider this task does not see is ignored and the wait continues.
    public static func waitUntilSettled(region: String) async {
        let cc = region.lowercased()
        guard !cc.isEmpty else { return }
        while true {
            let stamp = settledStamp(cc)
            if case .pending = phase(forRegion: cc) {} else { return }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                if !enqueueWaiter(region: cc, stamp: stamp, continuation) {
                    continuation.resume()
                }
            }
        }
    }

    private static func isPending(_ region: String) -> Bool {
        if case .pending = phase(forRegion: region) { return true }
        return false
    }

    /// Synchronous so the lock stays out of an async context.
    private static func settledStamp(_ region: String) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return settled[region] ?? 0
    }

    /// Returns false when the region settled before the waiter was recorded.
    private static func enqueueWaiter(
        region: String, stamp: UInt64, _ continuation: CheckedContinuation<Void, Never>
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if (settled[region] ?? 0) != stamp { return false }
        waiters[region, default: []].append(continuation)
        return true
    }
}

/// One ``RegistryIdentity`` per region for the currently installed provider.
///
/// Maps are built in ``RegistryIdentity/init(bundle:)``. This cache keeps that
/// build off the per-row path. The lookup lock is never taken while this lock is held.
public enum RegistryIdentityCache {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var generation: UInt64 = .max
    nonisolated(unsafe) private static var identities: [String: RegistryIdentity] = [:]
    nonisolated(unsafe) private static var misses: Set<String> = []

    public static func identity(forRegion region: String) -> RegistryIdentity? {
        let cc = region.lowercased()
        guard !cc.isEmpty else { return nil }
        // A task-local provider must not read or fill the process-wide cache.
        if RegistryIdentityLookup.testOverride != nil {
            if case .ready(let built) = RegistryIdentityLookup.phase(forRegion: cc) { return built }
            return nil
        }
        let current = RegistryIdentityLookup.providerGeneration
        lock.lock()
        if generation != current {
            identities.removeAll(keepingCapacity: true)
            misses.removeAll(keepingCapacity: true)
            generation = current
        } else if let cached = identities[cc] {
            lock.unlock()
            return cached
        } else if misses.contains(cc) {
            lock.unlock()
            return nil
        }
        lock.unlock()
        switch RegistryIdentityLookup.phase(forRegion: cc) {
        case .pending:
            return nil
        case .unavailable:
            lock.lock()
            if generation == current { misses.insert(cc) }
            lock.unlock()
            return nil
        case .ready(let built):
            lock.lock()
            defer { lock.unlock() }
            guard generation == current else { return built }
            identities[cc] = built
            return built
        }
    }
}

/// Station text for a ride stop. A missing id, region, or station record is unresolved:
/// the stored name is shown and readings are not looked up by that name.
public struct RegistryStationDisplay: Equatable, Sendable {
    public var primary: String
    public var caption: String?
    public var unresolved: Bool
    public var readingCodes: [String]
    public static let unresolvedKey = "ios.identity.unresolved"

    public init(primary: String, caption: String?, unresolved: Bool, readingCodes: [String]) {
        self.primary = primary
        self.caption = caption
        self.unresolved = unresolved
        self.readingCodes = readingCodes
    }

    /// The first code whose readings row exists. Later codes are tried in order.
    public static func firstCodeWithReading(_ codes: [String], hasRow: (String) -> Bool) -> String? {
        codes.first(where: hasRow)
    }

    public static func resolve(
        storedName: String, stationID: String?, region: String?, lineID: String? = nil
    ) -> RegistryStationDisplay {
        func unresolved() -> RegistryStationDisplay {
            RegistryStationDisplay(primary: storedName, caption: nil, unresolved: true, readingCodes: [])
        }
        func pending() -> RegistryStationDisplay {
            RegistryStationDisplay(primary: storedName, caption: nil, unresolved: false, readingCodes: [])
        }
        guard let stationID, !stationID.isEmpty else { return unresolved() }
        let resolvedRegion = (region?.isEmpty == false ? region : nil) ?? SolverRegistryInput.regionCode(stationID)
        guard let resolvedRegion, !resolvedRegion.isEmpty else { return unresolved() }
        switch RegistryIdentityLookup.phase(forRegion: resolvedRegion) {
        case .pending:
            return pending()
        case .unavailable:
            return unresolved()
        case .ready(let identity):
            guard let label = identity.label(for: stationID, line: lineID, country: resolvedRegion) else {
                return unresolved()
            }
            let secondary = label.presentation.secondary
            let qualifier = label.text.qualifier
            let caption = !secondary.isEmpty ? secondary : (qualifier.isEmpty ? nil : qualifier)
            return RegistryStationDisplay(
                primary: label.presentation.label,
                caption: caption,
                unresolved: false,
                readingCodes: identity.codes(of: stationID))
        }
    }
}
