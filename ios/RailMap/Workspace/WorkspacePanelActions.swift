import RailPresentation
import SwiftUI

/// Header controls render resolved actions and caller-supplied scope menus.
/// This view neither owns a store nor decides which journey action is primary.
struct WorkspacePanelActions<Playback: View, JourneyDate: View, RegionMenu: View,
                             StatisticsDate: View, StatisticsShare: View,
                             DestinationMenu: View>: View {
    let tab: PrimaryTab
    let newJourney: () -> Void
    @ViewBuilder var playback: () -> Playback
    @ViewBuilder var journeyDate: () -> JourneyDate
    @ViewBuilder var region: () -> RegionMenu
    @ViewBuilder var statisticsDate: () -> StatisticsDate
    @ViewBuilder var statisticsShare: () -> StatisticsShare
    @ViewBuilder var destinationMenu: () -> DestinationMenu
    @Environment(AppLocalization.self) private var localization

    var body: some View {
        // New journey leads on Upcoming — the default tab and where a
        // planned trip appears once saved — and stays on Search. Same
        // handler, so both open the one new-trip flow.
        if tab == .upcoming { newJourneyButton }
        if tab == .all { playback() }
        if tab == .stats { statisticsShare() }
        // Keep date, region and utilities anchored at the trailing edge.
        // Tab-specific actions occupy the leading slot so filters do not move.
        if tab == .upcoming || tab == .all {
            journeyDate()
            region()
        }
        if tab == .stats {
            statisticsDate()
            region()
        }
        if tab == .search { newJourneyButton }
        Menu(content: destinationMenu) {
            SheetIconLabel(systemImage: "gearshape")
        }
        .accessibilityLabel(Text(localization.text(
            "nav.utilities", fallback: "Data and settings")))
        .accessibilityIdentifier("utilityMenuButton")
    }

    private var newJourneyButton: some View {
        SheetIconButton(
            systemImage: "plus",
            accessibilityLabel: Text(localization.text(
                "ios.newJourney", fallback: "New journey")),
            action: newJourney)
        .accessibilityIdentifier("newJourneyButton.\(tab.rawValue)")
    }
}
