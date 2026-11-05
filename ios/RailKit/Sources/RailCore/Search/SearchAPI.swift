import Foundation

// MARK: - Shared search engine: public API
//
// One engine answers every search box in the app: the editor's station
// picker (stations, lines, companies), the line search, and the journey list.
// It is pure Foundation so `swift test` reaches all of it.
//
//     let index = SearchIndexBuilder.catalog(catalog, regionCode: "jp", extraNames: readings)
//     let response = index.query("东急 目黑线", scope: .all, context: SearchContext(regionCode: "jp"))
//
// `SearchEngine` owns lazily built per-region indexes (built once, off the
// main thread) and is what UI controllers hold. `SearchIndex.query` is the
// synchronous core; it checks `Task.isCancelled` so a stale query stops early.
// `SearchTextQuery` is the same matcher for ad-hoc fields (journeys).

/// What an entity in the index is.
public enum SearchEntityKind: UInt8, Hashable, Sendable, Codable, CaseIterable {
    case station
    case line
    case company
    /// A free vocabulary term (journey list did-you-mean). Never a catalog entity.
    case term
}

/// Which entity kinds a query may return.
public struct SearchScope: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let stations = SearchScope(rawValue: 1 << 0)
    public static let lines = SearchScope(rawValue: 1 << 1)
    public static let companies = SearchScope(rawValue: 1 << 2)
    public static let terms = SearchScope(rawValue: 1 << 3)
    public static let all: SearchScope = [.stations, .lines, .companies]

    public init(kind: SearchEntityKind) {
        switch kind {
        case .station: self = .stations
        case .line: self = .lines
        case .company: self = .companies
        case .term: self = .terms
        }
    }

    public func contains(kind: SearchEntityKind) -> Bool { contains(SearchScope(kind: kind)) }
}

/// A stable entity identity.
/// - station: the catalog source code (`StationKey.sourceCode`)
/// - line: `CatalogLine.id`
/// - company: `CatalogOperator.id`
public struct SearchEntityID: Hashable, Sendable, Codable {
    public var kind: SearchEntityKind
    public var id: String

    public init(kind: SearchEntityKind, id: String) {
        self.kind = kind
        self.id = id
    }

    public static func station(_ sourceCode: String) -> Self { .init(kind: .station, id: sourceCode) }
    public static func line(_ id: String) -> Self { .init(kind: .line, id: id) }
    public static func company(_ id: String) -> Self { .init(kind: .company, id: id) }
}

/// A latitude/longitude box, e.g. the map's visible region.
public struct SearchMapRect: Hashable, Sendable {
    public var minLatitude: Double
    public var maxLatitude: Double
    public var minLongitude: Double
    public var maxLongitude: Double

    public init(minLatitude: Double, maxLatitude: Double, minLongitude: Double, maxLongitude: Double) {
        self.minLatitude = minLatitude
        self.maxLatitude = maxLatitude
        self.minLongitude = minLongitude
        self.maxLongitude = maxLongitude
    }

    public init(centerLatitude: Double, centerLongitude: Double, latitudeDelta: Double, longitudeDelta: Double) {
        self.init(
            minLatitude: centerLatitude - latitudeDelta / 2, maxLatitude: centerLatitude + latitudeDelta / 2,
            minLongitude: centerLongitude - longitudeDelta / 2, maxLongitude: centerLongitude + longitudeDelta / 2)
    }

    public func contains(latitude: Double, longitude: Double) -> Bool {
        latitude >= minLatitude && latitude <= maxLatitude
            && longitude >= minLongitude && longitude <= maxLongitude
    }
}

/// Everything about the asker that ranking may use. All fields are optional
/// signals; an empty context ranks purely by match quality and importance.
public struct SearchContext: Hashable, Sendable {
    /// The region whose index is queried.
    public var regionCode: String
    /// Recently picked or searched entities, most recent first.
    public var recentPicks: [SearchEntityID]
    /// Recent query strings, most recent first. Shown for an empty query.
    public var recentQueries: [String]
    /// Rides per station source code (or per line id for lines).
    public var rideCounts: [SearchEntityID: Int]
    /// The map's visible area. Stations inside rank higher.
    public var visibleRegion: SearchMapRect?
    /// Hard constraints from the surrounding UI (e.g. the picker's selected
    /// lines). Applied in addition to filters parsed from the query text.
    public var lineIDs: Set<String>
    public var operatorIDs: Set<String>
    /// Maximum results returned.
    public var limit: Int

    public init(
        regionCode: String,
        recentPicks: [SearchEntityID] = [],
        recentQueries: [String] = [],
        rideCounts: [SearchEntityID: Int] = [:],
        visibleRegion: SearchMapRect? = nil,
        lineIDs: Set<String> = [],
        operatorIDs: Set<String> = [],
        limit: Int = 40
    ) {
        self.regionCode = regionCode
        self.recentPicks = recentPicks
        self.recentQueries = recentQueries
        self.rideCounts = rideCounts
        self.visibleRegion = visibleRegion
        self.lineIDs = lineIDs
        self.operatorIDs = operatorIDs
        self.limit = limit
    }
}

/// How a result matched, best first.
public enum SearchMatchKind: UInt8, Hashable, Sendable, Comparable {
    /// The whole normalized field equals the query.
    case exact
    /// The field starts with the query.
    case prefix
    /// The query occurs inside the field (or every query token does).
    case substring
    /// Within a bounded edit distance (typo).
    case fuzzy
    /// Empty query: recently picked.
    case recent
    /// Empty query: frequently ridden.
    case frequent
    /// Listed because a parsed filter selected it (e.g. stations of a line).
    case browse

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Which spelling of the entity matched.
public enum SearchMatchSource: UInt8, Hashable, Sendable {
    /// The display name.
    case name
    /// Another catalog name or alias (short name, brand, other language).
    case alias
    /// A reading (kana) or translated name supplied by `extraNames`.
    case reading
    /// The romanized form (Hepburn/loose romaji), from kana or Latin text.
    case romaji
    /// A station or line code (`JY01`, `MO`).
    case code
}

/// What kind of alias a matched spelling is, when it is not just another
/// spelling of the same reading. Shown as the match reason, e.g.
/// "Yamate → 山手線 (alternate reading)".
public enum SearchAliasKind: UInt8, Hashable, Sendable, Codable {
    /// The same characters read differently (山手 Yamate / Yamanote).
    case alternateReading = 1
    /// A name the station or line had before (梅田 → 大阪梅田).
    case formerName = 2
    /// A common English name or abbreviation.
    case englishName = 3
    /// The operator's official English name.
    case officialEnglish = 4
}

/// Why and where a result matched, for highlighting and "matched romaji" hints.
public struct SearchMatch: Hashable, Sendable {
    public var kind: SearchMatchKind
    public var source: SearchMatchSource
    /// The spelling that matched (may differ from the title, e.g. "Shinjuku").
    public var matchedText: String
    /// Highlight ranges in `matchedText`, as UTF-16 offsets (`NSRange`-compatible).
    public var highlights: [Range<Int>]
    /// Edit distance for `.fuzzy`; 0 otherwise.
    public var editDistance: Int
    /// Set when the matched spelling is an alias table entry (alternate reading,
    /// former name, English name). Nil for the entity's own names and readings.
    public var alias: SearchAliasKind?

    public init(
        kind: SearchMatchKind, source: SearchMatchSource, matchedText: String,
        highlights: [Range<Int>] = [], editDistance: Int = 0, alias: SearchAliasKind? = nil
    ) {
        self.kind = kind
        self.source = source
        self.matchedText = matchedText
        self.highlights = highlights
        self.editDistance = editDistance
        self.alias = alias
    }

    /// `true` when the title itself carries the highlights.
    public var highlightsTitle: Bool { source == .name }
}

/// One ranked hit.
public struct SearchResult: Hashable, Sendable, Identifiable {
    public var entity: SearchEntityID
    /// Display name (catalog name).
    public var title: String
    public var match: SearchMatch
    /// Higher is better. Only comparable within one response.
    public var score: Double
    /// Lines serving a station / the line itself.
    public var lineIDs: [String]
    /// Operators of the entity.
    public var operatorIDs: [String]
    /// Registry company station and complex, when known (stations only).
    public var stationID: String?
    public var complexID: String?
    public var latitude: Double?
    public var longitude: Double?

    public var id: SearchEntityID { entity }

    public init(
        entity: SearchEntityID, title: String, match: SearchMatch, score: Double,
        lineIDs: [String] = [], operatorIDs: [String] = [], stationID: String? = nil,
        complexID: String? = nil, latitude: Double? = nil, longitude: Double? = nil
    ) {
        self.entity = entity
        self.title = title
        self.match = match
        self.score = score
        self.lineIDs = lineIDs
        self.operatorIDs = operatorIDs
        self.stationID = stationID
        self.complexID = complexID
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// A structured filter recognized in the query text ("东急" → company 東急電鉄).
public struct SearchFilter: Hashable, Sendable, Identifiable {
    /// `.company` or `.line` (a station filter is expressed as `typeHint`).
    public var entity: SearchEntityID
    /// Display name of the entity.
    public var title: String
    /// The query text this filter was read from.
    public var sourceText: String

    public var id: SearchEntityID { entity }

    public init(entity: SearchEntityID, title: String, sourceText: String) {
        self.entity = entity
        self.title = title
        self.sourceText = sourceText
    }
}

/// The query after keyword parsing.
public struct SearchParsedQuery: Hashable, Sendable {
    /// Unambiguous filters, applied to the results.
    public var applied: [SearchFilter]
    /// Candidates for an ambiguous keyword ("山手線" → JR East or Kobe). Not applied;
    /// the UI may offer them as chips. Selecting one = re-query with `residualText`
    /// and the chip's id as the context constraint. Context ids within one set
    /// are alternatives (OR), so in an already restricted picker intersect with
    /// the restriction rather than adding to it.
    public var suggested: [SearchFilter]
    /// Type keyword seen (駅/站/역/Station → `.stations`, 線/Line → `.lines`,
    /// 鉄道/Railway → `.companies`). Nil when none.
    public var typeHint: SearchScope?
    /// The text left after filters and type keywords were removed. This is
    /// what was matched against entity names.
    public var residualText: String

    public init(
        applied: [SearchFilter] = [], suggested: [SearchFilter] = [],
        typeHint: SearchScope? = nil, residualText: String = ""
    ) {
        self.applied = applied
        self.suggested = suggested
        self.typeHint = typeHint
        self.residualText = residualText
    }
}

/// "Did you mean …?" for a query with no or few good results.
public struct SearchCorrection: Hashable, Sendable {
    /// The whole corrected query text, ready to put in the search field.
    public var text: String
    /// The entity the correction names, when it is one.
    public var entity: SearchEntityID?

    public init(text: String, entity: SearchEntityID? = nil) {
        self.text = text
        self.entity = entity
    }
}

/// Everything one query returns.
public struct SearchResponse: Hashable, Sendable {
    public var query: String
    public var parsed: SearchParsedQuery
    /// Ranked: exact > prefix > substring > fuzzy, then relevance. For an empty
    /// query these are suggestions (recent, frequent) with `.recent`/`.frequent`.
    public var results: [SearchResult]
    /// Set when there were no or few non-fuzzy results and a close spelling exists.
    public var didYouMean: SearchCorrection?
    /// Recent query strings for an empty query (from `SearchContext.recentQueries`).
    public var recentQueries: [String]

    public init(
        query: String = "", parsed: SearchParsedQuery = SearchParsedQuery(), results: [SearchResult] = [],
        didYouMean: SearchCorrection? = nil, recentQueries: [String] = []
    ) {
        self.query = query
        self.parsed = parsed
        self.results = results
        self.didYouMean = didYouMean
        self.recentQueries = recentQueries
    }

    public var isEmptyQuery: Bool { query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// One searchable entity, the input to `SearchIndex`. Names are matched; the
/// rest is carried to results and used for ranking and filters.
public struct SearchDocument: Sendable {
    public struct Name: Sendable, Hashable {
        public var text: String
        public var source: SearchMatchSource
        /// Alias table kind, when this spelling came from one.
        public var aliasKind: SearchAliasKind?
        public init(_ text: String, source: SearchMatchSource, aliasKind: SearchAliasKind? = nil) {
            self.text = text
            self.source = source
            self.aliasKind = aliasKind
        }
    }

    public var entity: SearchEntityID
    public var title: String
    /// Every spelling. The title is matched as `.name` automatically.
    public var names: [Name]
    /// 0…1 prior (e.g. lines served, ridership). Higher ranks first among equals.
    public var importance: Float
    public var lineIDs: [String]
    public var operatorIDs: [String]
    public var stationID: String?
    public var complexID: String?
    public var latitude: Double?
    public var longitude: Double?

    public init(
        entity: SearchEntityID, title: String, names: [Name] = [], importance: Float = 0,
        lineIDs: [String] = [], operatorIDs: [String] = [], stationID: String? = nil,
        complexID: String? = nil, latitude: Double? = nil, longitude: Double? = nil
    ) {
        self.entity = entity
        self.title = title
        self.names = names
        self.importance = importance
        self.lineIDs = lineIDs
        self.operatorIDs = operatorIDs
        self.stationID = stationID
        self.complexID = complexID
        self.latitude = latitude
        self.longitude = longitude
    }
}
