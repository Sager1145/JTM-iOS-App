import RailApplication
import RailCore
import RailPresentation
import SwiftUI

/// Departure and arrival, typed or picked (`TypedDateTimeField`).
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
            if model.arrival < model.departure {
                Text(text(
                    "arrivalBeforeDeparture",
                    fallback: "Arrival is before departure."))
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text(text("time", fallback: "Time"))
        }
    }
}
