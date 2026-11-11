import Foundation

/// What a suggestion chip under a search field is.
public enum SearchChipKind: Sendable, Hashable {
    case didYouMean
    case completion
    case recent
    case frequent

    /// The kind whose label ("Did you mean", "Recent") leads a chip row. A
    /// completion chip has no label of its own, so it never decides the lead.
    public static func lead(of kinds: [SearchChipKind]) -> SearchChipKind? {
        kinds.first { $0 != .completion }
    }
}
