import RailPresentation
import SwiftUI

/// Header controls render resolved actions and caller-supplied scope menus.
/// This view neither owns a store nor decides which journey action is primary.
struct WorkspacePanelActions<Playback: View, JourneyFilter: View, RegionMenu: View,
                             StatisticsDate: View, StatisticsShare: View,
                             DestinationMenu: View>: View {
    let tab: PrimaryTab
    let newJourney: () -> Void
    @ViewBuilder var playback: () -> Playback
    @ViewBuilder var journeyFilter: () -> JourneyFilter
    @ViewBuilder var region: () -> RegionMenu
    @ViewBuilder var statisticsDate: () -> StatisticsDate
    @ViewBuilder var statisticsShare: () -> StatisticsShare
    @ViewBuilder var destinationMenu: () -> DestinationMenu
    @Environment(AppLocalization.self) private var localization

    var body: some View {
        // Pass 2: one header per destination, the same four slots in every
        // list mode so nothing moves while the reader types or switches
        // Upcoming / All. New journey and playback each have exactly this
        // one header entry (plus ⌘N, the empty state and the journey card's
        // own Play for a single journey).
        if tab.isJourneyList {
            newJourneyButton
            playback()
            journeyFilter()
        } else {
            statisticsShare()
            statisticsDate()
            region()
        }
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
        .accessibilityIdentifier("newJourneyButton")
    }
}
