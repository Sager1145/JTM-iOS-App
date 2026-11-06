import RailApplication
import RailCore
import RailPresentation
import SwiftUI

/// Train type, number and operator.
struct EditorServiceSection: View, JourneyEditorLabelling {
    @Environment(AppLocalization.self) var localization
    @Bindable var model: TripDraftModel

    var body: some View {
        Section {
            Picker(text("trainType", fallback: "Train type"), selection: Binding(
                get: { model.trainType },
                set: { value in model.apply(TripDraftModel.Patch(trainType: value), source: .reader) })) {
                ForEach(model.trainTypeOptions, id: \.self) { type in
                    Text(trainTypeLabel(type)).tag(type)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("newTripTrainType")
            TextField(text("trainNumber", fallback: "Train number or name"), text: $model.trainNumber)
                .accessibilityIdentifier("newTripNumber")
            Picker(text("company", fallback: "Company"), selection: $model.companyName) {
                Text(text("anyCompany", fallback: "Any company")).tag("")
                ForEach(model.shownCompanyOptions, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("newTripCompany")
        } header: {
            Text(text("service", fallback: "Service"))
        }
    }
}
