/// §2.2 (revised) — three primary destinations and semantic Search.
///
/// Not Journeys / Network / Passport any more. The railway network stopped
/// being a destination when the map became the root layer that all three
/// share: a "network" tab would have been a tab whose whole content is a set
/// of switches for the map already on screen behind it. Its package status and
/// diagnostics moved to Settings, where the rest of the app's plumbing lives.
///
/// What is left are the questions a journey log actually answers: what is
/// coming, what does it all add up to, and what have I got.
///
/// Pass 2 (docs/maintenance/ui-reorganization.md): these are now the workspace's PAGE
/// states, not tabs. Upcoming, All and Search are list modes of the one
/// Journeys tab; the tab bar shows `WorkspaceTab` below.
enum PrimaryTab: String, CaseIterable, Identifiable {
    /// What is coming. Dated today or later, soonest first.
    case upcoming
    /// What it adds up to — §5.3's Passport, by its plainer name.
    case stats
    /// The History tab (pass 3): everything before today, and undated
    /// records. The raw value stays `all` for the UI-test hook's old spelling.
    case all
    /// System Search, also the entry point for adding a journey.
    case search

    var id: String { rawValue }

    var headerActionCount: Int {
        switch self {
        // Mirrors `WorkspacePanelActions` (pass 3). History: play, share,
        // filter, utilities. Upcoming and Stats: share, filter, utilities.
        // A search reserves History's width.
        case .all, .search: 4
        case .upcoming, .stats: 3
        }
    }

    /// The short name shown by the system tab bar.
    ///
    /// A tab item and a page heading have different space budgets. Reusing
    /// `nav.allJourneys` and `sec.search` here made the system compress some
    /// languages but not others (for example, 「すべての行程」 versus 「統計」).
    /// These iOS-only labels keep all four languages on the same one-concept,
    /// one-line footing while the panel header continues to use the complete
    /// shared-catalog wording.
    var tabLocalizationKey: String {
        switch self {
        case .upcoming: "ios.tab.upcoming"
        case .stats: "ios.tab.stats"
        case .all: "ios.tab.all"
        case .search: "ios.tab.search"
        }
    }

    var tabFallbackName: String {
        switch self {
        case .upcoming: "Upcoming"
        case .stats: "Stats"
        case .all: "All"
        case .search: "Search"
        }
    }

    var systemImage: String {
        switch self {
        case .upcoming: "calendar"
        case .stats: "chart.bar.xaxis"
        case .all: "tram"
        case .search: "magnifyingglass"
        }
    }
}


/// What the tab bar shows (UI reorganization pass 3).
///
/// Three destinations — Upcoming (today and later), History (everything
/// before today, and undated records) and Stats — plus ``add``, which is not
/// a destination: it is the system's separate search-role button at the end
/// of the bar, used as the one Add trip entry. Selecting it opens the add
/// menu and leaves the current tab selected.
///
/// Each list has its own search field and the shared filter button. A query
/// puts the page in `PrimaryTab.search`, scoped to that list.
enum WorkspaceTab: String, CaseIterable, Identifiable {
    case upcoming
    case history
    case stats
    case add

    var id: String { rawValue }

    /// The three tabs that show a page.
    static let destinations: [WorkspaceTab] = [.upcoming, .history, .stats]

    var tabLocalizationKey: String {
        switch self {
        case .upcoming: "ios.tab.upcoming"
        case .history: "ios.tab.history"
        case .stats: "ios.tab.stats"
        case .add: "ios.tab.addTrip"
        }
    }

    var tabFallbackName: String {
        switch self {
        case .upcoming: "Upcoming"
        case .history: "History"
        case .stats: "Stats"
        case .add: "Add trip"
        }
    }

    var systemImage: String {
        switch self {
        case .upcoming: "calendar"
        case .history: "clock.arrow.circlepath"
        case .stats: "chart.bar.xaxis"
        case .add: "plus"
        }
    }
}

extension PrimaryTab {
    /// Upcoming, History (`.all`) and a search over either are journey lists.
    var isJourneyList: Bool { self != .stats }
}
