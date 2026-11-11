import Foundation

/// When a journey search counts as a "recent search": on Return (once the
/// debounced search has caught up with the typed text) and when the reader
/// opens a result from the search tab. Never for an empty query, a search with
/// no results, or a selection made anywhere else (playback, map taps).
public struct RecentSearchRecordGate: Sendable, Equatable {
    public struct State: Sendable, Equatable {
        public var query: String
        public var isSearchTab: Bool
        /// The completed search is the one for the text now in the field.
        public var isCurrent: Bool
        public var hasResults: Bool

        public init(query: String, isSearchTab: Bool, isCurrent: Bool, hasResults: Bool) {
            self.query = query
            self.isSearchTab = isSearchTab
            self.isCurrent = isCurrent
            self.hasResults = hasResults
        }

        var qualifies: Bool {
            isSearchTab && isCurrent && hasResults
                && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        var hasQuery: Bool {
            isSearchTab && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Return was pressed before the search for the typed text finished.
    public private(set) var pending = false

    public init() {}

    /// Return pressed. True when the query should be recorded now.
    public mutating func submit(_ state: State) -> Bool {
        if state.qualifies {
            pending = false
            return true
        }
        pending = state.hasQuery && !state.isCurrent
        return false
    }

    /// The search completed. True when a pending submit should now be recorded.
    public mutating func completed(_ state: State) -> Bool {
        guard pending else { return false }
        if state.qualifies {
            pending = false
            return true
        }
        if state.isCurrent { pending = false } // finished with nothing to record
        return false
    }

    /// The text changed: a pending submit belonged to the old text.
    public mutating func queryChanged() { pending = false }

    /// Opening a result row.
    public static func recordsOnPick(_ state: State) -> Bool { state.qualifies }
}
