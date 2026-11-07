import RailApplication
import RailCore
import RailPresentation
import SwiftUI

/// Departure and arrival, typed or picked (`TypedDateTimeField`), and
/// whether the ride is done. Ridden follows the time (`TripListRules`) until
/// the reader sets it.
struct EditorTimeSection: View, JourneyEditorLabelling {
    @Environment(AppLocalization.self) var localization
    let model: TripDraftModel

    var body: some View {
        Section {
            TypedDateTimeField(
                title: text("departure", fallback: "Departure"),
                value: model.timetableTimeSelection(isDeparture: true),
                identifier: "newTripDeparture")
            TypedDateTimeField(
                title: text("arrival", fallback: "Arrival"),
                value: model.timetableTimeSelection(isDeparture: false),
                identifier: "newTripArrival")
            if let source = timeSource {
                HStack(spacing: 6) {
                    FillSourceBadge(source: source)
                    Text(text("timeFilled", fallback: "Check the time; changing it keeps your value."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("newTripTimeSource")
            }
            if model.arrival < model.departure {
                Text(text(
                    "arrivalBeforeDeparture",
                    fallback: "Arrival is before departure."))
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Toggle(text("ridden", fallback: "I have ridden this journey"), isOn: Binding(
                get: { model.isRidden }, set: { model.riddenOverride = $0 }))
                .accessibilityIdentifier("newTripRidden")
        } header: {
            Text(text("time", fallback: "Time"))
        }
    }

    /// The source of a clock or day the reader has not set themselves.
    private var timeSource: TripDraftModel.FillSource? {
        model.filledBy[.departure] ?? model.filledBy[.arrival] ?? model.filledBy[.date]
    }
}
