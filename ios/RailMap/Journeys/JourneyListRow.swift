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
/// The editing boundary arrives whole rather than as one closure per command:
/// the row really does edit the store — duplicate, reorder, hide — and every
/// one of those transitions must persist the generation it produced. What IS
/// a closure is everything that belongs to the workspace rather than to the
/// record: starting a run, opening a sheet, and raising a confirmation.
struct JourneyListRow: View {
    let train: Train
    let presentation: JourneyPresentation
    let showsDate: Bool

    /// The record store and the persistence edge for commands made here.
    let editing: JourneyEditing

    let select: () -> Void
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

    /// Whether the trip is in the Upcoming list, which decides whether the
    /// menu offers "Move to past trips" or "Move to upcoming".
    let isUpcoming: Bool

    /// An upcoming trip whose time has gone by. It is never refiled on its
    /// own: the row marks it and offers the reader the three choices.
    let isOverdue: Bool

    /// File the trip under Upcoming (`true`) or past (`false`).
    let setUpcoming: (Bool) -> Void

    /// Open the journey editor. `@Sendable` for the same reason as
    /// ``confirmDelete``: the menu's copy waits for the menu's teardown.
    let edit: @MainActor @Sendable () -> Void

    @Environment(AppLocalization.self) private var localization
    @Environment(PresentationHost.self) private var presentationHost
    @State private var showsGroupAssignment = false

    var body: some View {
        VStack(alignment: .leading, spacing: RailSpacing.s8) {
            // The workspace highlights the route and presents a separate journey
            // menu. The source list retains its filters and scroll position.
            Button {
                select()
            } label: {
                JourneySummaryRow(
                    train: train,
                    presentation: presentation,
                    isSelected: editing.itineraries.selectedTrainID == train.id,
                    showsDate: showsDate,
                    isOverdue: isOverdue)
            }
            // §14.3's first line, on the control this app is tapped through more
            // than any other. `.plain` inside a `List` draws no highlight at all,
            // so selecting a journey used to give nothing back until the store
            // came round and the row's border changed — which is after the finger
            // has already lifted.
            .buttonStyle(RailRowPressStyle())
            .accessibilityIdentifier("journeyRow-\(train.id)")

            if isOverdue { overduePrompt }
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: WorkspaceMenuMetrics.listRowVerticalInset,
                                 leading: WorkspaceMenuMetrics.horizontalInset,
                                 bottom: WorkspaceMenuMetrics.listRowVerticalInset,
                                 trailing: WorkspaceMenuMetrics.horizontalInset))
        // §5.1: the row does not expose every verb. Swipe and context menu do.
        .contextMenu { contextMenuItems }
        .sheet(isPresented: $showsGroupAssignment) {
            JourneyGroupAssignmentView(
                train: train,
                groups: JourneyGroupCatalog.groups(in: editing.itineraries.store?.trains ?? []),
                editing: editing)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: confirmDelete) {
                Label(
                    localization.countryText("btn.delete", fallback: "Delete"),
                    systemImage: "trash")
            }
            Button {
                _ = editing.itineraries.toggleVisibility(train.id)
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
                    localization.text(
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
        // The leading swipe, on the pointer menu as well: a trackpad has no
        // swipe edge, and the label, icon, and closure stay the swipe's own.
        let ridden = RideLedger.hasBeenRidden(train)
        Button {
            setRidden(!ridden)
        } label: {
            Label(
                localization.text(
                    ridden ? "ios.detail.markNotRidden" : "ios.detail.confirmRidden"),
                systemImage: ridden ? "circle.dashed" : "checkmark.circle")
        }
        listMembershipButton
        if isOverdue {
            Button {
                presentationHost.afterTeardown(edit)
            } label: {
                Label(localization.text("ios.edit", fallback: "Edit"), systemImage: "pencil")
            }
        }
        Button {
            presentationHost.afterTeardown { showsGroupAssignment = true }
        } label: {
            Label(localization.text("ios.journeyGroup.title"), systemImage: "folder")
        }
        // No Play here (pass 2): playing one journey is the journey card's
        // Play, and playing the list is the Journeys header's.
        Button(action: showDetail) {
            Label(
                localization.text("ios.journeyInfo", fallback: "Journey information"),
                systemImage: "info.circle")
        }
        Button {
            _ = editing.itineraries.duplicate(train.id)
        } label: {
            Label(
                localization.countryText("btn.duplicate", fallback: "Duplicate"),
                systemImage: "plus.square.on.square")
        }
        Button {
            _ = editing.itineraries.toggleVisibility(train.id)
        } label: {
            Label(visibilityTitle, systemImage: visibilitySymbol)
        }
        Button {
            _ = editing.itineraries.move(train.id, by: -1)
        } label: {
            Label(
                localization.countryText("btn.moveUp", fallback: "Move earlier"),
                systemImage: "arrow.up")
        }
        Button {
            _ = editing.itineraries.move(train.id, by: 1)
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
            presentationHost.afterTeardown(confirmDelete)
        } label: {
            Label(
                localization.countryText("btn.delete", fallback: "Delete"),
                systemImage: "trash")
        }
    }

    /// Moving between the lists is the reader's decision, never the clock's.
    private var listMembershipButton: some View {
        Button {
            setUpcoming(!isUpcoming)
        } label: {
            Label(
                localization.text(
                    isUpcoming ? "ios.journey.moveToPast" : "ios.journey.moveToUpcoming",
                    fallback: isUpcoming ? "Move to past trips" : "Move to upcoming"),
                systemImage: isUpcoming ? "clock.arrow.circlepath" : "calendar")
        }
    }

    /// The overdue trip's inline choices: file it as past, edit it, or delete
    /// it through the workspace's usual confirmation.
    private var overduePrompt: some View {
        VStack(alignment: .leading, spacing: RailSpacing.s4) {
            RailStatusLabel(
                kind: .warning,
                text: localization.text(
                    "ios.journey.overduePrompt", fallback: "This trip's time has passed."))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: RailSpacing.s8) { overdueActions }
                VStack(alignment: .leading, spacing: RailSpacing.s4) { overdueActions }
            }
            .buttonStyle(.railSecondary)
        }
        .padding(.horizontal, RailSpacing.s4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("journeyOverdue-\(train.id)")
    }

    @ViewBuilder
    private var overdueActions: some View {
        Button {
            setUpcoming(false)
        } label: {
            Label(
                localization.text("ios.journey.moveToPast", fallback: "Move to past trips"),
                systemImage: "clock.arrow.circlepath")
        }
        .tint(.orange)
        Button(action: edit) {
            Label(localization.text("ios.edit", fallback: "Edit"), systemImage: "pencil")
        }
        Button(role: .destructive, action: confirmDelete) {
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
