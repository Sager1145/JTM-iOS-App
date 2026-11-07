import RailApplication
import RailCore
import RailPresentation
import SwiftUI

/// The fastest way in, first on the form: scan a ticket, which fills every
/// field it can at once, or find the train in a timetable. Everything they
/// fill stays editable below and is tagged with where it came from.
struct EditorQuickFillSection: View, JourneyEditorLabelling {
    @Environment(AppLocalization.self) var localization
    @Bindable var model: TripDraftModel

    var body: some View {
        Section {
            HStack(spacing: 10) {
                if model.ticketRegion != nil {
                    Button { model.showsTicketScan = true } label: {
                        Label(text("scanTicket", fallback: "Scan ticket"), systemImage: "ticket")
                            .quickFillPill(prominent: true)
                    }
                    // Borderless: a Form row with two default-style buttons
                    // fires both on any tap.
                    .buttonStyle(.borderless)
                    .disabled(model.catalog == nil)
                    .accessibilityIdentifier("newTripScanTicket")
                }
                Button { model.showsFillDetails = true } label: {
                    Label(text("findTrain", fallback: "Find train"), systemImage: "magnifyingglass")
                        .quickFillPill(prominent: false)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("newTripFillDetails")
            }
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            if let count = model.ticketFillCount {
                Label(count == 0
                      ? text("ticketFilledNone", fallback: "Nothing on the ticket could be used.")
                      : text("ticketFilled", fallback: "Filled {count} fields from the ticket. Check them below.",
                             ["count": .string(String(count))]),
                      systemImage: count == 0 ? "exclamationmark.triangle" : "checkmark.circle")
                    .font(.footnote)
                    .foregroundStyle(count == 0 ? Color.orange : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("newTripTicketFilled")
            }
        } footer: {
            Text(text("quickFillNote",
                      fallback: "A ticket or timetable fills what it knows. Fields you change are never overwritten."))
        }
        .listRowSeparator(.hidden)
    }
}

private extension View {
    /// A full-width capsule, filled for the primary action.
    func quickFillPill(prominent: Bool) -> some View {
        self
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.tint))
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(prominent ? AnyShapeStyle(.tint) : AnyShapeStyle(.tint.opacity(0.14)), in: Capsule())
            .contentShape(Capsule())
    }
}
