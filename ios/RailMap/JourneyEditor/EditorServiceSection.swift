import RailApplication
import RailCore
import RailPresentation
import SwiftUI

/// The train: type, number or name, operator, and the timetable it was
/// matched to. Each value shows where it came from; an empty one offers the
/// reader's usual value on this route.
struct EditorServiceSection: View, JourneyEditorLabelling {
    @Environment(AppLocalization.self) var localization
    @Bindable var model: TripDraftModel
    /// History suggestions for this route (`historySuggestions(among:)`).
    let suggestions: [TripDraftModel.Field: String]

    var body: some View {
        Section {
            EditorCompactRow(title: text("trainType", fallback: "Train type"), source: model.filledBy[.trainType]) {
                Picker(text("trainType", fallback: "Train type"), selection: Binding(
                    get: { model.trainType },
                    set: { value in model.apply(TripDraftModel.Patch(trainType: value), source: .reader) })) {
                    ForEach(model.trainTypeOptions, id: \.self) { type in
                        Text(trainTypeLabel(type)).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .accessibilityIdentifier("newTripTrainType")
            }
            if model.trainType.isEmpty, let suggested = suggestions[.trainType] {
                EditorSuggestionChip(value: trainTypeLabel(suggested), identifier: "newTripSuggestTrainType") {
                    model.apply(TripDraftModel.Patch(trainType: suggested), source: .reader)
                }
            }
            EditorCompactRow(title: text("trainNumberShort", fallback: "Train"), source: model.filledBy[.number]) {
                EditorInlineTextField(
                    title: text("trainNumber", fallback: "Train number or name"),
                    text: model.readerBinding(.number, get: { model.trainNumber }, set: { model.trainNumber = $0 }))
                    .accessibilityIdentifier("newTripNumber")
            }
            if model.region == .jp, !model.limitedExpressName.isEmpty || model.filledBy[.serviceName] != nil {
                EditorCompactRow(title: text("serviceName", fallback: "Service name"),
                                 source: model.filledBy[.serviceName]) {
                    EditorInlineTextField(
                        title: text("serviceName", fallback: "Service name"),
                        text: model.readerBinding(.serviceName, get: { model.limitedExpressName },
                                                  set: { model.limitedExpressName = $0 }))
                        .accessibilityIdentifier("newTripServiceName")
                }
            }
            EditorCompactRow(title: text("company", fallback: "Company"), source: model.filledBy[.company]) {
                Picker(text("company", fallback: "Company"), selection: model.readerBinding(
                    .company, get: { model.companyName }, set: { model.companyName = $0 })) {
                    Text(text("anyCompany", fallback: "Any company")).tag("")
                    ForEach(model.shownCompanyOptions, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .accessibilityIdentifier("newTripCompany")
            }
            if model.companyName.isEmpty, let suggested = suggestions[.company],
               model.companyOptions.contains(suggested) {
                EditorSuggestionChip(value: suggested, identifier: "newTripSuggestCompany") {
                    model.markTouched(.company)
                    model.companyName = suggested
                }
            }
            if model.timetableFailed {
                Text(text("timetableFailed", fallback: "This timetable could not be applied."))
                    .font(.footnote) // ui-token-ok: error text
                    .foregroundStyle(.red)
            }
            if let timetableTrain = model.timetableTrain {
                timetableCard(timetableTrain)
            }
        } header: {
            Text(text("service", fallback: "Service"))
        }
    }

    private func timetableCard(_ timetableTrain: Train) -> some View {
        HStack(alignment: .center, spacing: RailSpacing.s8) {
            Image(systemName: "clock.badge.checkmark")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: RailSpacing.labelValueGap) {
                Text(model.limitedExpressName.isEmpty ? timetableTrain.number : model.limitedExpressName)
                    .font(.subheadline.weight(.semibold))
                Text("\(timetableTrain.origin) → \(timetableTrain.destination) · "
                     + text("stationCount", fallback: "{count} stations",
                            ["count": .string(String(timetableTrain.stops.count))]))
                    .railText(.tertiary)
                Text(model.timetableTimes(timetableTrain))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: RailSpacing.s4)
            Button(text("timetableRemove", fallback: "Remove"), action: model.removeTimetable)
                .buttonStyle(.borderless)
                .accessibilityIdentifier("newTripTimetableRemove")
        }
        // Keep the Remove button's own identifier reachable.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("newTripTimetableApplied")
    }
}
