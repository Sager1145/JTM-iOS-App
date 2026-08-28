import RailCore
import RailPresentation
import SwiftUI

/// The ambiguous-tap chooser: every ride under one finger, as a sheet.
///
/// A tap that lands on several rides asks instead of choosing — see
/// `ContentView.selectFromMap`, and `handleDeckRouteChoices` in the web app
/// before it. What it asked WITH was a `confirmationDialog`, and the format
/// cost the question two things:
///
///   - **A dialog button is one line.** The web app's `uiChoose` gives each
///     candidate a label (date・number・type), a sublabel (origin →
///     destination) and the ride's own colour. A system action sheet renders
///     one line per button and drops the rest, so those were folded into a
///     single string and the type, the operator and the colour fell out of
///     it. The colour is the worst of the three to lose: it is the one field
///     on the list the reader can also see on the map, under the finger they
///     have just put down.
///   - **The dialog covers what it is about.** On iOS 26 it arrives as a
///     bubble anchored over the map — the same fault the station callout had,
///     and the reason `StationCardView` exists: a surface that hides the
///     thing it is asking about, at a size that cannot grow with the reader's
///     text size or scroll when six rides share a corridor.
///
/// So the ambiguous tap on a LINE is now answered the way the ambiguous tap
/// on a STATION already was: a bottom sheet, at the same stops, with the same
/// close button, leaving the map visible above it. Nothing about which rides
/// are offered or in what order has changed — that is `RideTapResolver`, and
/// it is unit-tested there.
///
/// The rows are the journeys list's own ``JourneySummaryRow``, which is what
/// makes the colour, the date, the service metadata and the endpoints come
/// back: the reader is picking between records, and this is what a record
/// looks like everywhere else in the app.
struct RideChooserView: View {
    @Environment(AppLocalization.self) private var localization
    @Environment(\.dismiss) private var dismiss

    /// The rides under the tap, in `RideTapResolver`'s order — the nearest
    /// stroke first, and stable where two rides are coincident.
    var trains: [Train]
    /// Whether each row leads with its date.
    ///
    /// The same rule the folded dialog label used: scoped to one day, every
    /// candidate carries the same date and the badge is a prefix that says
    /// nothing about which of them is which.
    var showsDate: Bool
    /// Resolved by the workspace, exactly as the journeys list resolves it —
    /// a row must not re-derive "is it hidden, did the route fail" from the
    /// train (§3.3, §11.2).
    var presentation: (Train) -> JourneyPresentation
    /// Picking is the answer. The caller closes this sheet and selects.
    var onPick: (Train) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(trains, id: \.id) { train in
                    row(train)
                }
            }
            // The journeys list's own container: `JourneySummaryRow` draws its
            // own card, and a grouped list would put that card inside a second
            // one.
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            // The heading says what the list is; the web app's sentence
            // (`choose.overlap` — "several routes overlap here, choose a
            // train") is not repeated below it. A bar takes a heading, and a
            // sentence printed under one is the same fact twice, in the space
            // the first ride could have occupied.
            .navigationTitle(
                localization.text("ios.chooseOverlapTitle", fallback: "Overlapping lines"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SheetCloseButton(
                        accessibilityLabel: Text(
                            localization.text("ios.close", fallback: "Close")),
                        action: { dismiss() })
                }
            }
        }
        // The station card's stops, and for the same reason: the answer is
        // short, the map it is about must stay visible above it, and `.large`
        // is still reachable for the tap that found six rides in one corridor.
        .presentationDetents([.medium, .large])
        // §9.5.6's no-Pull-Bar rule, next to `.resizes` — without that a sheet
        // with no grabber and a scrolling list inside it cannot be dragged
        // between its stops at all.
        .presentationDragIndicator(.hidden)
        .presentationContentInteraction(.resizes)
    }

    private func row(_ train: Train) -> some View {
        Button {
            onPick(train)
        } label: {
            JourneySummaryRow(
                train: train,
                presentation: presentation(train),
                // Nothing here is the selection yet — that is what the reader
                // is being asked. Marking the currently selected ride would
                // answer the question in the question.
                isSelected: false,
                showsDate: showsDate)
        }
        // §14.3, and the same row as the journeys list — so the same feedback.
        .buttonStyle(RailRowPressStyle())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12))
    }
}
