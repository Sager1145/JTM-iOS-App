import RailPresentation
import SwiftUI

/// Header controls render resolved actions and caller-supplied scope menus.
/// This view neither owns a store nor decides which journey action is primary.
struct WorkspacePanelActions<Playback: View, JourneyDate: View, RegionMenu: View,
                             StatisticsDate: View, StatisticsShare: View,
                             DestinationMenu: View>: View {
    let tab: PrimaryTab
    let showsList: Bool
    let compactJourney: JourneyPresentation?
    let performPrimary: (JourneyPresentation.PrimaryAction) -> Void
    let backToList: () -> Void
    let newJourney: () -> Void
    @ViewBuilder var playback: () -> Playback
    @ViewBuilder var journeyDate: () -> JourneyDate
    @ViewBuilder var region: () -> RegionMenu
    @ViewBuilder var statisticsDate: () -> StatisticsDate
    @ViewBuilder var statisticsShare: () -> StatisticsShare
    @ViewBuilder var destinationMenu: () -> DestinationMenu
    @Environment(AppLocalization.self) private var localization

    var body: some View {
        if let compactJourney {
            if let primary = compactJourney.primaryAction {
                let appearance = primary.appearance(localization)
                SheetIconButton(
                    systemImage: appearance.systemImage,
                    accessibilityLabel: Text(appearance.label),
                    action: { performPrimary(primary) })
            }
            SheetIconButton(
                systemImage: "xmark",
                accessibilityLabel: Text(localization.journeyText(
                    "ios.journey.backToList", fallback: "Back to the list")),
                action: backToList)
        }
        // A selected journey owns its transport in the card, so the list's
        // transport is mounted only while the list is on top.
        if tab == .all, showsList { playback() }
        if tab == .upcoming || (tab == .all && showsList) {
            journeyDate()
            region()
        }
        if tab == .stats {
            statisticsDate()
            region()
            statisticsShare()
        }
        if tab == .search {
            SheetIconButton(
                systemImage: "plus",
                accessibilityLabel: Text(localization.text(
                    "ios.newJourney", fallback: "New journey")),
                action: newJourney)
        }
        Menu(content: destinationMenu) {
            SheetIconLabel(systemImage: "gearshape")
        }
        .accessibilityLabel(Text(localization.text(
            "nav.utilities", fallback: "Data and settings")))
        .accessibilityIdentifier("utilityMenuButton")
    }
}
