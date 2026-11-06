import RailApplication
import RailCore
import RailPresentation
import SwiftUI

/// One entry for every source that can fill in this trip: timetable
/// matches, the full timetable, the line's service types, and ChatGPT
/// or pasted text. What was applied stays visible here, with hand entry
/// for what no source filled.
struct EditorTripDetailsSection: View, JourneyEditorLabelling {
    @Environment(AppLocalization.self) var localization
    let model: TripDraftModel

    var body: some View {
        Section {
            Button { model.showsFillDetails = true } label: {
                Label(text("fillDetails", fallback: "Fill in trip details"), systemImage: "text.badge.plus")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .accessibilityIdentifier("newTripFillDetails")
            if model.timetableFailed {
                Text(text("timetableFailed", fallback: "This timetable could not be applied."))
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            if let timetableTrain = model.timetableTrain {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.limitedExpressName.isEmpty ? timetableTrain.number : model.limitedExpressName)
                        .font(.headline)
                    Text("\(timetableTrain.origin) → \(timetableTrain.destination)")
                    Text(text("stationCount", fallback: "{count} stations",
                              ["count": .string(String(timetableTrain.stops.count))]))
                    Text(model.timetableTimes(timetableTrain))
                        .font(.caption.monospacedDigit())
                    Button(text("timetableRemove", fallback: "Remove"), action: model.removeTimetable)
                        .accessibilityIdentifier("newTripTimetableRemove")
                }
                // Keep the Remove button's own identifier reachable.
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("newTripTimetableApplied")
            }
            manualEntryRows
        } header: {
            Text(text("tripDetails", fallback: "Trip details"))
        } footer: {
            Text(text("fillDetailsNote",
                      fallback: "Timetables, the line's services, and ChatGPT or pasted text, in one list."))
        }
    }

    /// Hand entry for what no source filled: vehicle type and the two
    /// platforms that matter most. Other stops' platforms are on their rows.
    @ViewBuilder private var manualEntryRows: some View {
        let missing = model.missingDetails
        if !missing.isEmpty {
            Label(missingText(missing), systemImage: "square.and.pencil")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("newTripNeedsDetails")
        }
        Button { model.showsVehiclePicker = true } label: {
            LabeledContent(localization.text("ios.editor.vehicleType")) {
                Text(model.draft.vehicleType.flatMap { $0.isEmpty ? nil : $0 }
                     ?? text("vehicleAdd", fallback: "Add"))
                    .foregroundStyle(missing.vehicleType ? Color.accentColor : Color.primary)
            }
            .frame(minHeight: 44)
        }
        .accessibilityIdentifier("newTripVehicleType")
        HStack {
            Text(text("platforms", fallback: "Platforms"))
            Spacer()
            Text(text("departureShort", fallback: "Dep.")).font(.caption).foregroundStyle(.secondary)
            PlatformEntryBadge(platform: model.departurePlatform, identifier: "newTripDeparturePlatform")
            Text(text("arrivalShort", fallback: "Arr.")).font(.caption).foregroundStyle(.secondary)
            PlatformEntryBadge(platform: model.arrivalPlatform, identifier: "newTripArrivalPlatform")
        }
    }
}
