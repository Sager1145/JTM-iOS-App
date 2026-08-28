import RailCore
import RailPresentation
import SwiftUI

/// One journey in a list, with everything the reader can do to it from there.
///
/// ## Why this is a view type and not a `some View` on the workspace
///
/// It was a 78-line builder on `RailWorkspaceView`, and being a builder rather
/// than a type cost twice.
///
/// **It had no identity.** A builder's output is part of the parent's body, so
/// the row's whole modifier chain — two `swipeActions`, a `contextMenu`, a
/// button style — was rebuilt for all 200 rows whenever anything on that view
/// changed, including the sheet's drag offset and the search field's text. As a
/// `View` with `Equatable` inputs, SwiftUI can see that a row whose journey and
/// selection did not move does not need rebuilding.
///
/// **It could not be read.** `RailWorkspaceView` is one struct with 35 `some
/// View` members; the row is the control this app is tapped through more than
/// any other, and finding it meant scrolling past the statistics panel.
///
/// The store arrives whole rather than as six closures because the row really
/// does edit it — duplicate, reorder, hide — and six one-line closures naming
/// six store methods is the same coupling with more to read. What IS a closure
/// is everything that belongs to the workspace rather than to the record:
/// starting a run, opening a sheet, raising a confirmation, the save feedback.
struct JourneyListRow: View {
    let train: Train
    let presentation: JourneyPresentation
    let showsDate: Bool

    /// The record store, edited in place by the menu and the swipes.
    let itineraries: ItineraryStore

    /// Write the reader's own store back after an edit made here.
    let persist: () -> Void

    let play: () -> Void
    let showDetail: () -> Void

    /// Say whether this journey was ridden. The workspace owns it because it
    /// also owns the save feedback that follows.
    let setRidden: (Bool) -> Void

    /// Raise the delete confirmation. The workspace owns the dialog.
    ///
    /// `@MainActor @Sendable` because the menu's copy of it is handed to
    /// ``PresentationHost/afterTeardown(_:)``, which resumes it on the main
    /// actor after an `await` — a plain `() -> Void` cannot cross that.
    let confirmDelete: @MainActor @Sendable () -> Void

    @Environment(AppLocalization.self) private var localization

    var body: some View {
        // A Button rather than a `NavigationLink`: selecting a journey changes
        // which resident layer is on top, and §8.1 wants that reflected in the
        // list AND on the map at once rather than pushing a screen over both.
        Button {
            itineraries.selectedTrainID = train.id
        } label: {
            JourneySummaryRow(
                train: train,
                presentation: presentation,
                isSelected: itineraries.selectedTrainID == train.id,
                showsDate: showsDate)
        }
        // §14.3's first line, on the control this app is tapped through more
        // than any other. `.plain` inside a `List` draws no highlight at all,
        // so selecting a journey used to give nothing back until the store
        // came round and the row's border changed — which is after the finger
        // has already lifted.
        .buttonStyle(RailRowPressStyle())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12))
        // §5.1: the row does not expose every verb. Swipe and context menu do.
        .contextMenu { contextMenuItems }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: confirmDelete) {
                Label(
                    localization.countryText("btn.delete", fallback: "Delete"),
                    systemImage: "trash")
            }
            Button {
                itineraries.toggleVisibility(train.id)
                persist()
            } label: {
                Label(visibilityTitle, systemImage: visibilitySymbol)
            }
            // §6.2's allowed roles do not include indigo, and this action is
            // not a state colour anyway: showing or hiding a journey on the map
            // is the tint role — 可点击、选中 — so it takes the app's accent.
            .tint(.accentColor)
        }
        // §5.3: the passport counts what the reader says they rode, so the
        // saying has to be somewhere they already are. The leading edge,
        // because the trailing one is where destructive lives and a confirm is
        // the opposite of that — and because this is the swipe a reader makes
        // repeatedly after a trip, down a list of the journeys they just took.
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            let ridden = RideLedger.hasBeenRidden(train)
            Button {
                setRidden(!ridden)
            } label: {
                Label(
                    localization.editorText(
                        ridden ? "ios.detail.markNotRidden" : "ios.detail.confirmRidden"),
                    systemImage: ridden ? "circle.dashed" : "checkmark.circle")
            }
            // Green for the confirm, which §6.2 allows as the success role;
            // the accent for taking it back, because that is not a failure —
            // it is the same tint role the visibility swipe takes.
            .tint(ridden ? .accentColor : .green)
        }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        Button(action: play) {
            Label(
                localization.countryText("btn.play", fallback: "Play journey"),
                systemImage: "play.fill")
        }
        Button(action: showDetail) {
            Label(
                localization.text("ios.journeyInfo", fallback: "Journey information"),
                systemImage: "info.circle")
        }
        Button {
            itineraries.duplicate(train.id)
            persist()
        } label: {
            Label(
                localization.countryText("btn.duplicate", fallback: "Duplicate"),
                systemImage: "plus.square.on.square")
        }
        Button {
            itineraries.toggleVisibility(train.id)
            persist()
        } label: {
            Label(visibilityTitle, systemImage: visibilitySymbol)
        }
        Button {
            itineraries.move(train.id, by: -1)
            persist()
        } label: {
            Label(
                localization.countryText("btn.moveUp", fallback: "Move earlier"),
                systemImage: "arrow.up")
        }
        Button {
            itineraries.move(train.id, by: 1)
            persist()
        } label: {
            Label(
                localization.countryText("btn.moveDown", fallback: "Move later"),
                systemImage: "arrow.down")
        }
        Divider()
        Button(role: .destructive) {
            // The swipe's delete needs no wait — nothing is being dismissed.
            // A menu's does: this callback runs while UIKit is still tearing
            // the menu down, and the confirmation would be dropped.
            PresentationHost.afterTeardown(confirmDelete)
        } label: {
            Label(
                localization.countryText("btn.delete", fallback: "Delete"),
                systemImage: "trash")
        }
    }

    private var visibilityTitle: String {
        train.visible == false
            ? localization.text("ios.showOnMap", fallback: "Show on map")
            : localization.journeyText("ios.journey.hideFromMap", fallback: "Hide from map")
    }

    private var visibilitySymbol: String {
        train.visible == false ? "eye" : "eye.slash"
    }
}
