import Foundation

/// Immutable compact index over one region's documents. Build it once
/// (off the main thread); query it from any thread.
public final class SearchIndex: Sendable {
    public let regionCode: String

    public init(regionCode: String, documents: [SearchDocument]) {
        self.regionCode = regionCode
    }

    /// Number of documents.
    public var count: Int { 0 }

    /// Approximate resident bytes of the index (keys, names, postings).
    public var memoryFootprint: Int { 0 }

    /// The document for an entity, when indexed.
    public func document(for entity: SearchEntityID) -> SearchDocument? { nil }

    /// Parse filters, match, rank. Empty text returns suggestions.
    public func query(_ text: String, scope: SearchScope = .all, context: SearchContext) -> SearchResponse {
        SearchResponse(query: text)
    }
}

/// Builds indexes from app data.
public enum SearchIndexBuilder {
    /// Stations, lines and companies of one catalog region.
    /// `extraNames`: readings and other-language names keyed by station source code
    /// (`Localization.StationReadings.searchNamesByCode`).
    public static func catalog(
        _ catalog: EditorCatalog, regionCode: String, extraNames: [String: [String]] = [:]
    ) -> SearchIndex {
        SearchIndex(regionCode: regionCode, documents: [])
    }

    /// A vocabulary of free terms (e.g. station names and train numbers seen in
    /// journeys) for completion and did-you-mean. Each term is its own document.
    public static func vocabulary(_ terms: [String], regionCode: String = "") -> SearchIndex {
        SearchIndex(regionCode: regionCode, documents: [])
    }
}

/// The engine's matcher for ad-hoc fields (journey records). Prepare once per
/// query, then test fields. Same normalization, romaji and typo rules as the index.
public struct SearchTextQuery: Sendable {
    public let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Best match of the whole query against one field.
    /// `allowFuzzy` enables typo matching (off for ids and dates).
    public func match(_ field: String, source: SearchMatchSource = .name, allowFuzzy: Bool = true) -> SearchMatch? {
        nil
    }

    /// Every whitespace token matches at least one field (or the whole query matches one).
    public func matchesAll(fields: [String], allowFuzzy: Bool = true) -> Bool {
        false
    }
}
