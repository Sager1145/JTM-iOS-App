import RailPresentation
import SwiftUI

/// Header controls render resolved actions and caller-supplied scope menus.
/// This view neither owns a store nor decides which journey action is primary.
struct WorkspacePanelActions<Playback: View, ScopeFilter: View, Share: View,
                             DestinationMenu: View>: View {
    let tab: PrimaryTab
    /// Playback belongs to History and Stats (B4), the two destinations that
    /// replay the trips in their own scope.
    let showsPlayback: Bool
    @ViewBuilder var playback: () -> Playback
    /// The tab's one scope control (region, plus its date or period).
    @ViewBuilder var scopeFilter: () -> ScopeFilter
    /// The tab's one Share entry; both open the same composer.
    @ViewBuilder var share: () -> Share
    @ViewBuilder var destinationMenu: () -> DestinationMenu
    @Environment(AppLocalization.self) private var localization

    var body: some View {
        // Pass 3: every destination has the same shape — its own action,
        // then Share, then the one scope filter, then the gear. Adding a trip
        // is the tab bar's Add trip button, not a header action.
        // History and Stats: ▶ share filter ⚙︎. Upcoming: share filter ⚙︎.
        if showsPlayback {
            playback()
        }
        share()
        scopeFilter()
        Menu(content: destinationMenu) {
            SheetIconLabel(systemImage: "gearshape")
        }
        .accessibilityLabel(Text(localization.text(
            "nav.utilities", fallback: "Data and settings")))
        .accessibilityIdentifier("utilityMenuButton")
    }
}
