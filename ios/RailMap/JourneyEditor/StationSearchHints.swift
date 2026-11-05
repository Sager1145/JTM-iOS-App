import Foundation
import RailCore

/// What the shared search engine read from a station query: filters it
/// applied, filters it suggests, and a correction. The picker only shows them.
///
/// Mirrors `SearchResponse.parsed` / `didYouMean` of the RailCore search
/// engine (branch claude/search-engine-0dab7a). Until that engine is merged,
/// ``StationSearchHints/none`` is all the picker receives: no parsing or
/// matching lives here.
struct StationSearchHints: Equatable {
    struct Filter: Equatable, Identifiable {
        enum Kind: Equatable { case company, line }
        var kind: Kind
        /// `CatalogOperator.id` or `CatalogLine.id`.
        var id: String
        var title: String
    }

    /// Unambiguous filters read from the text, applied as chips.
    var applied: [Filter] = []
    /// Ambiguous readings, offered as chips to tap.
    var suggested: [Filter] = []
    /// The text left once applied keywords are taken out.
    var residualText: String?
    /// A full corrected query, when the text found little or nothing.
    var didYouMean: String?

    static let none = StationSearchHints()
}

/// The seam the picker calls. Replaced by the RailCore search engine.
enum StationSearchHintSource {
    static func hints(for query: String, regionCode: String, catalog: EditorCatalog) -> StationSearchHints {
        .none
    }
}
