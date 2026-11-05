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
/// Pass 2 (docs/ui-reorganization.md): these are now the workspace's PAGE
/// states, not tabs. Upcoming, All and Search are list modes of the one
/// Journeys tab; the tab bar shows `WorkspaceTab` below.
enum PrimaryTab: String, CaseIterable, Identifiable {
    /// What is coming. Dated today or later, soonest first.
    case upcoming
    /// What it adds up to — §5.3's Passport, by its plainer name.
    case stats
    /// Everything on record, by date.
    case all
    /// System Search, also the entry point for adding a journey.
    case search

    var id: String { rawValue }

    var headerActionCount: Int {
        switch self {
        // Journeys (any list mode): new, play, filter, utilities.
        // Stats: share, date scope, region, utilities.
        case .upcoming, .stats, .all, .search: 4
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


/// The two destinations on the tab bar (UI reorganization pass 2).
///
/// Upcoming, All and Search were three tabs over ONE journey list: Upcoming is
/// a date rule, Search is a query. They are now one Journeys destination whose
/// list mode (`PrimaryTab.upcoming` / `.all`) is a segmented control under the
/// search field, and whose `.search` mode is simply "the field has text".
/// `PrimaryTab` keeps those three values because the map scope, playback scope
/// and filters already key off them; this enum is only what the tab bar shows.
enum WorkspaceTab: String, CaseIterable, Identifiable {
    case journeys
    case stats

    var id: String { rawValue }

    var tabLocalizationKey: String {
        switch self {
        case .journeys: "ios.tab.journeys"
        case .stats: "ios.tab.stats"
        }
    }

    var tabFallbackName: String {
        switch self {
        case .journeys: "Journeys"
        case .stats: "Stats"
        }
    }

    var systemImage: String {
        switch self {
        case .journeys: "tram"
        case .stats: "chart.bar.xaxis"
        }
    }
}

extension PrimaryTab {
    /// Which tab-bar destination shows this page.
    var workspaceTab: WorkspaceTab { self == .stats ? .stats : .journeys }

    /// Upcoming, All and Search are list modes of the one Journeys tab.
    var isJourneyList: Bool { self != .stats }
}
