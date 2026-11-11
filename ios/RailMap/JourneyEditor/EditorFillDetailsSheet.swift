import RailApplication
import RailCore
import RailPresentation
import SwiftUI

/// Every source that can fill in the trip, in one sheet: timetables, the
/// line's service types, and ChatGPT or pasted text.
struct EditorFillDetailsSheet: View, JourneyEditorLabelling {
    @Environment(AppLocalization.self) var localization
    @Bindable var model: TripDraftModel
    /// The record as the editor opened it.
    let original: Train

    var body: some View {
        NavigationStack {
            Form {
                if model.region == .jp {
                    Section {
                        TextField(text("serviceName", fallback: "Service name"), text: model.readerBinding(
                            .serviceName, get: { model.limitedExpressName }, set: { model.limitedExpressName = $0 }))
                            .accessibilityIdentifier("newTripLimitedExpressName")
                        Menu(text("serviceSuggestions", fallback: "Service suggestions")) {
                            ForEach(model.serviceSuggestions, id: \.self) { name in
                                Button(name) {
                                    model.markTouched(.serviceName)
                                    model.limitedExpressName = name
                                }
                            }
                        }
                        Button { model.showsTimetablePicker = true } label: {
                            Label(text("timetableBrowse", fallback: "Browse timetables"), systemImage: "magnifyingglass")
                        }
                        .accessibilityIdentifier("newTripTimetableBrowse")
                    } header: {
                        Text(text("timetable", fallback: "Timetable"))
                    }
                    if model.origin != nil, model.destination != nil {
                        TimetableQuickMatchView(
                            train: model.timetableQuery,
                            serviceName: model.limitedExpressName) { trip in
                            model.applyTimetableTrip(trip)
                            model.showsFillDetails = false
                        }
                    }
                    if let package = model.package, !model.routeLineIDs.isEmpty {
                        LocalLineServicesSection(
                            package: package, lineIDs: model.routeLineIDs,
                            serviceDate: model.dayString(model.departure), trainType: Binding(
                                get: { model.trainType },
                                set: { model.apply(TripDraftModel.Patch(trainType: $0), source: .reader) }))
                    }
                }
                Section {
                    Button { model.showsCompletion = true } label: {
                        Label(text("completeWithText", fallback: "ChatGPT or pasted text"),
                              systemImage: "sparkles")
                            .frame(maxWidth: .infinity, minHeight: RailSize.touch, alignment: .leading)
                    }
                    .accessibilityIdentifier("rideEditorAICompletion")
                } footer: {
                    Text(text("completeWithTextNote",
                              fallback: "Review every proposed change before it is applied."))
                }
                // Whatever no source filled is entered by hand in the editor.
                let missing = model.missingDetails
                if !missing.isEmpty {
                    Section {
                        Text(missingText(missing)).railText(.secondary)
                        Button(text("enterByHand", fallback: "Enter the rest by hand")) {
                            model.showsFillDetails = false
                        }
                        .accessibilityIdentifier("newTripFillDetailsByHand")
                    }
                }
            }
            .navigationTitle(text("fillDetails", fallback: "Fill in trip details"))
            .navigationBarTitleDisplayMode(.inline)
            .railSheetClose(
                Text(localization.text("ios.close", fallback: "Close")),
                identifier: "newTripFillDetailsDone"
            ) { model.showsFillDetails = false }
            .accessibilityIdentifier("newTripFillDetailsForm")
            .navigationDestination(isPresented: $model.showsCompletion) {
                JourneyCompletionView(
                    trains: [model.currentResult(original: original) ?? model.draft],
                    context: model.limitedExpressName.isEmpty ? ""
                        : "Limited express service name: \(model.limitedExpressName)",
                    allowsRawImport: true,
                    isPushed: true,
                    onApply: { completed in
                        guard let completed = completed.first else { return }
                        model.adoptCompletedRecord(completed)
                        model.showsFillDetails = false
                    })
            }
        }
        .sheet(isPresented: $model.showsTimetablePicker) {
            ServicePatternPickerView(
                region: model.region.code,
                rideDate: model.dayString(model.departure),
                onSelectDate: { day in
                    if let day, let date = model.timetableDate(day, time: "00:00") {
                        model.setDay(date, isDeparture: true)
                    }
                },
                onSelectTrip: { model.applyTimetableTrip($0); model.showsFillDetails = false },
                onSelectDraft: { model.applyTimetableTrip($0); model.showsFillDetails = false }
            ) { pattern, reversed in
                model.applyPattern(pattern, reversed: reversed)
                model.showsFillDetails = false
            }
            .railSheet(.full)
        }
    }
}
