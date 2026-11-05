import Foundation

/// Builds indexes from app data.
public enum SearchIndexBuilder {
    /// Stations, lines and companies of one catalog region.
    /// `extraNames`: readings and other-language names keyed by station source code
    /// (`Localization.StationReadings.searchNamesByCode`).
    ///
    /// Importance: no ridership data ships, so a station's prior is the number of
    /// lines serving its registry complex (or the station itself), a line's is its
    /// package rank and length, and a company's is its line count.
    ///
    /// `aliases` (default: the bundled `search-aliases.json`) adds alternate
    /// readings, former names and English names, marked with their kind.
    public static func catalog(
        _ catalog: EditorCatalog, regionCode: String, extraNames: [String: [String]] = [:],
        aliases: SearchAliasTable = .bundled
    ) -> SearchIndex {
        SearchIndex(regionCode: regionCode, documents: documents(
            catalog, regionCode: regionCode, extraNames: extraNames, aliases: aliases))
    }

    static func documents(
        _ catalog: EditorCatalog, regionCode: String, extraNames: [String: [String]],
        aliases: SearchAliasTable = .bundled
    ) -> [SearchDocument] {
        let identity = RegistryIdentityCache.identity(forRegion: regionCode)
        let registry = identity.flatMap { $0.bundle.stations.isEmpty ? nil : $0 }
        let operators = catalog.operators(in: regionCode)
        let lines = catalog.lines(in: regionCode)
        let stations = catalog.stations(in: regionCode)
        let operatorsByID = Dictionary(operators.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var linesByOperator: [String: [String]] = [:]
        var operatorsByLine: [String: [String]] = [:]
        var stationCountByLine: [String: Int] = [:]
        for line in lines {
            operatorsByLine[line.id] = line.operatorIDs
            for op in line.operatorIDs { linesByOperator[op, default: []].append(line.id) }
            stationCountByLine[line.id] = Set(catalog.memberships(lineID: line.id, regionCode: regionCode)
                .map(\.stationKey.sourceCode)).count
        }

        var documents: [SearchDocument] = []
        documents.reserveCapacity(stations.count + lines.count + operators.count)

        for op in operators {
            var names: [SearchDocument.Name] = []
            for alias in [op.shortName].compactMap({ $0 }) + op.aliases { names.append(.init(alias, source: .alias)) }
            var brand: Set<String> = []
            for text in [op.name] + names.map(\.text) {
                let key = SearchNormalizer.canonical(text)
                if let group = SearchKeywords.brandAliases[key] { brand.formUnion(group) }
                if let stem = SearchKeywords.stripCompanySuffix(key), stem.count >= 2 {
                    names.append(.init(String(decoding: stem, as: UTF16.self), source: .alias))
                    if let group = SearchKeywords.brandAliases[stem] { brand.formUnion(group) }
                }
            }
            for alias in brand.sorted() { names.append(.init(alias, source: .alias)) }
            let lineIDs = linesByOperator[op.id] ?? []
            documents.append(SearchDocument(
                entity: .company(op.id), title: op.name, names: names,
                importance: min(1, Float(lineIDs.count) / 20), lineIDs: lineIDs, operatorIDs: [op.id]))
        }

        for line in lines {
            var names = line.aliases.map { SearchDocument.Name($0, source: .alias) }
            // Operator spellings, so an ambiguous company word ("JR") still finds its lines.
            for op in line.operatorIDs.compactMap({ operatorsByID[$0] }) {
                names.append(.init(op.name, source: .alias))
                if let short = op.shortName, !short.isEmpty { names.append(.init(short, source: .alias)) }
            }
            if let code = line.lineCode, !code.isEmpty { names.append(.init(code, source: .code)) }
            names.append(contentsOf: aliases.names(regionCode: regionCode, entity: .line(line.id)))
            let members = catalog.memberships(lineID: line.id, regionCode: regionCode)
            let lat = members.isEmpty ? nil : members.map(\.latitude).reduce(0, +) / Double(members.count)
            let lon = members.isEmpty ? nil : members.map(\.longitude).reduce(0, +) / Double(members.count)
            let rankPrior = 1 - Float(min(max(line.rank, 0), 5)) / 5
            let sizePrior = min(1, Float(stationCountByLine[line.id] ?? 0) / 40)
            documents.append(SearchDocument(
                entity: .line(line.id), title: line.name, names: names,
                importance: 0.5 * rankPrior + 0.5 * sizePrior,
                lineIDs: [line.id], operatorIDs: line.operatorIDs, latitude: lat, longitude: lon))
        }

        var stationLines: [String: [String]] = [:]
        var complexLines: [String: Set<String>] = [:]
        var registryRecords: [String: (id: String, complex: String?, record: RegistryStationRecord)] = [:]
        for station in stations {
            let code = station.key.sourceCode
            var seen: Set<String> = []
            let lineIDs = catalog.memberships(stationKey: station.key).map(\.lineID).filter { seen.insert($0).inserted }
            stationLines[code] = lineIDs
            if let registry, let id = registry.stationID(forCode: code, operator: nil),
               let record = registry.station(id) {
                registryRecords[code] = (id, record.cx.isEmpty ? nil : record.cx, record)
                if !record.cx.isEmpty { complexLines[record.cx, default: []].formUnion(lineIDs) }
            }
        }

        for station in stations {
            let code = station.key.sourceCode
            var names = station.aliases.map { SearchDocument.Name($0, source: .alias) }
            let registryEntry = registryRecords[code]
            if let entry = registryEntry, let registry {
                let record = entry.record
                names.append(.init(record.name, source: .alias))
                if let base = record.parts?.base { names.append(.init(base, source: .alias)) }
                if let bracket = record.parts?.bracket { names.append(.init(bracket, source: .alias)) }
                for code in record.codes { names.append(.init(code, source: .code)) }
                for alias in record.aka ?? [] { names.append(.init(alias, source: .alias)) }
                if let complex = registry.complex(of: entry.id) { names.append(.init(complex.name, source: .alias)) }
            }
            for name in extraNames[code] ?? [] { names.append(.init(name, source: .reading)) }
            names.append(contentsOf: aliases.names(regionCode: regionCode, entity: .station(code)))
            let lineIDs = stationLines[code] ?? []
            var ops: [String] = []
            var seenOps: Set<String> = []
            for line in lineIDs { for op in operatorsByLine[line] ?? [] where seenOps.insert(op).inserted { ops.append(op) } }
            let served = registryEntry?.complex.flatMap { complexLines[$0]?.count } ?? lineIDs.count
            documents.append(SearchDocument(
                entity: .station(code), title: station.name, names: names,
                importance: min(1, Float(max(0, served - 1)) / 8),
                lineIDs: lineIDs, operatorIDs: ops,
                stationID: registryEntry?.id, complexID: registryEntry?.complex,
                latitude: station.latitude, longitude: station.longitude))
        }
        return documents
    }

    /// A vocabulary of free terms (e.g. station names and train numbers seen in
    /// journeys) for completion and did-you-mean. Each distinct term is one
    /// `.term` document; `weights` (0…1) ranks frequent terms first.
    public static func vocabulary(
        _ terms: [String], weights: [String: Float] = [:], regionCode: String = ""
    ) -> SearchIndex {
        var seen: Set<String> = []
        let documents = terms.compactMap { term -> SearchDocument? in
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return nil }
            return SearchDocument(entity: SearchEntityID(kind: .term, id: trimmed), title: trimmed,
                                  importance: weights[trimmed] ?? 0)
        }
        return SearchIndex(regionCode: regionCode, documents: documents)
    }
}

/// Alternate readings, former names and English names, keyed by entity, with
/// their kind and source. The bundled table is built by
/// `ios/tools/build-search-aliases.py` into RailCore's `search-aliases.json`.
public struct SearchAliasTable: Sendable {
    public struct Entry: Hashable, Sendable {
        public var alias: String
        /// Nil for a plain reading.
        public var kind: SearchAliasKind?
        public var source: String

        public init(alias: String, kind: SearchAliasKind?, source: String) {
            self.alias = alias
            self.kind = kind
            self.source = source
        }
    }

    private var byEntity: [String: [Entry]]

    public init(entries: [(regionCode: String, entity: SearchEntityID, entry: Entry)] = []) {
        var table: [String: [Entry]] = [:]
        for row in entries { table[Self.key(row.regionCode, row.entity), default: []].append(row.entry) }
        byEntity = table
    }

    private static func key(_ region: String, _ entity: SearchEntityID) -> String {
        "\(region)|\(entity.kind.rawValue)|\(entity.id)"
    }

    public func entries(regionCode: String, entity: SearchEntityID) -> [Entry] {
        byEntity[Self.key(regionCode, entity)] ?? []
    }

    func names(regionCode: String, entity: SearchEntityID) -> [SearchDocument.Name] {
        entries(regionCode: regionCode, entity: entity).map {
            SearchDocument.Name($0.alias, source: $0.kind == nil ? .reading : .alias, aliasKind: $0.kind)
        }
    }

    public var count: Int { byEntity.values.reduce(0) { $0 + $1.count } }

    /// The table shipped in RailCore's resources (empty if missing or unreadable).
    public static let bundled: SearchAliasTable = {
        guard let url = Bundle.module.url(forResource: "search-aliases", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return SearchAliasTable() }
        return (try? decode(data)) ?? SearchAliasTable()
    }()

    static func decode(_ data: Data) throws -> SearchAliasTable {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sources = json["sources"] as? [String],
              let rows = json["entries"] as? [[Any]] else { return SearchAliasTable() }
        let kinds: [String: SearchAliasKind] = [
            "alternateReading": .alternateReading, "formerName": .formerName,
            "englishName": .englishName, "officialEnglish": .officialEnglish,
        ]
        var entries: [(regionCode: String, entity: SearchEntityID, entry: Entry)] = []
        for row in rows {
            guard row.count >= 6, let region = row[0] as? String, let entity = row[1] as? String,
                  let key = row[2] as? String, let alias = row[3] as? String, let kind = row[4] as? String,
                  let sourceIndex = row[5] as? Int, sources.indices.contains(sourceIndex) else { continue }
            let id: SearchEntityID = entity == "line" ? .line(key) : .station(key)
            entries.append((region, id, Entry(alias: alias, kind: kinds[kind], source: sources[sourceIndex])))
        }
        return SearchAliasTable(entries: entries)
    }
}

/// The engine's matcher for ad-hoc fields (journey records). Prepare once per
/// query, then test fields. Same normalization, romaji and typo rules as the
/// index, plus the cross-language synonym groups (地铁/Metro/지하철 …).
public struct SearchTextQuery: Sendable {
    public let text: String
    private let whole: [[UInt16]]
    private let wholeLoose: [UInt16]
    private let tokens: [[[UInt16]]]
    private let tokenLoose: [[UInt16]]

    public init(_ text: String) {
        self.text = text
        let canonical = SearchNormalizer.canonical(text)
        whole = canonical.isEmpty ? [] : Self.alternatives(canonical)
        wholeLoose = SearchNormalizer.loose(fromCanonical: canonical) ?? []
        let parts = Self.splitTokens(text)
        if parts.count > 1 {
            tokens = parts.map { Self.alternatives($0) }
            tokenLoose = parts.map { SearchNormalizer.loose(fromCanonical: $0) ?? [] }
        } else {
            tokens = []
            tokenLoose = []
        }
    }

    public var isEmpty: Bool { whole.isEmpty }

    /// Whitespace tokens, further split at script changes ("JR西日本" → jr, 西日本).
    static func splitTokens(_ text: String) -> [[UInt16]] {
        var out: [[UInt16]] = []
        for word in text.split(whereSeparator: { $0.isWhitespace || $0 == "\u{3000}" }) {
            let key = SearchNormalizer.canonical(String(word))
            var current: [UInt16] = []
            var previous = 0
            for unit in key {
                let script = SearchNormalizer.isLatinOrDigit(unit) ? 1 : (SearchNormalizer.isJamo(unit) ? 3 : 2)
                if previous != 0, script != previous, !current.isEmpty { out.append(current); current = [] }
                current.append(unit)
                previous = script
            }
            if !current.isEmpty { out.append(current) }
        }
        return out
    }

    private static func alternatives(_ key: [UInt16]) -> [[UInt16]] {
        var result: [[UInt16]] = [key]
        for group in SearchKeywords.synonyms {
            for word in group where !word.isEmpty && key.count >= word.count {
                guard let range = Self.range(of: word, in: key) else { continue }
                for other in group where other != word {
                    var replaced = key
                    replaced.replaceSubrange(range, with: other)
                    if !result.contains(replaced) { result.append(replaced) }
                }
            }
        }
        return result
    }

    private static func range(of needle: [UInt16], in key: [UInt16]) -> Range<Int>? {
        guard needle.count <= key.count else { return nil }
        for start in 0...(key.count - needle.count) where key[start..<(start + needle.count)].elementsEqual(needle) {
            return start..<(start + needle.count)
        }
        return nil
    }

    /// Best match of the whole query against one field.
    /// `allowFuzzy` enables typo matching (off for ids, numbers and dates).
    public func match(_ field: String, source: SearchMatchSource = .name, allowFuzzy: Bool = true) -> SearchMatch? {
        guard !whole.isEmpty, !field.isEmpty else { return nil }
        let key = SearchNormalizer.cachedCanonical(field)
        guard !key.isEmpty else { return nil }
        let rows = UnsafeMutablePointer<Int32>.allocate(capacity: SearchMatching.rowCapacity)
        defer { rows.deallocate() }
        var best: (SearchMatching.Hit, Bool)?
        func consider(_ q: [UInt16], _ k: [UInt16], loose: Bool) {
            q.withUnsafeBufferPointer { qb in
                k.withUnsafeBufferPointer { kb in
                    let budget = allowFuzzy ? SearchMatching.budget(qb, loose: loose) : 0
                    guard let hit = SearchMatching.compare(
                        qb, qMask: SearchMatching.mask(q), kb, keyMask: SearchMatching.mask(k), budget: budget, rows: rows)
                    else { return }
                    if best == nil || (hit.kind, hit.distance) < (best!.0.kind, best!.0.distance) { best = (hit, loose) }
                }
            }
        }
        for alternative in whole { consider(alternative, key, loose: false) }
        if !wholeLoose.isEmpty, best?.0.kind != .exact, let looseKey = SearchNormalizer.cachedLoose(field) {
            consider(wholeLoose, looseKey, loose: true)
        }
        guard let (hit, loose) = best else { return nil }
        let record = SearchIndex.KeyRecord(
            mask: 0, start: 0, doc: 0, name: 0,
            length: UInt16(min(Int(UInt16.max), loose ? (SearchNormalizer.cachedLoose(field)?.count ?? 0) : key.count)),
            flags: (loose ? SearchMatchSource.romaji : source).rawValue | (loose ? 8 : 0))
        return SearchMatch(
            kind: hit.kind, source: loose ? .romaji : source, matchedText: field,
            highlights: SearchQueryRunner.highlights(
                field, record: record, hit: hit, queryLength: loose ? wholeLoose.count : whole[0].count),
            editDistance: hit.distance)
    }

    /// The whole query matches one field, or every token is contained in some
    /// field. `fuzzyFields` are the fields typos may match (names, not numbers).
    public func matchesAll(fields: [String], fuzzyFields: [String] = []) -> Bool {
        guard !whole.isEmpty else { return false }
        for field in fields where match(field, allowFuzzy: false) != nil { return true }
        for field in fuzzyFields where match(field, allowFuzzy: true) != nil { return true }
        guard !tokens.isEmpty else { return false }
        let keys = (fields + fuzzyFields).map { SearchNormalizer.cachedCanonical($0) }
        let looseKeys = (fields + fuzzyFields).map { SearchNormalizer.cachedLoose($0) ?? [] }
        for (index, alternatives) in tokens.enumerated() {
            let hit = alternatives.contains { token in keys.contains { Self.range(of: token, in: $0) != nil } }
                || (!tokenLoose[index].isEmpty && looseKeys.contains { Self.range(of: tokenLoose[index], in: $0) != nil })
            if !hit { return false }
        }
        return true
    }
}
