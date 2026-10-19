import RailCore
import SwiftUI

struct StopEditorLabel: View {
    @Environment(AppLocalization.self) private var localization
    let stop: Stop
    let journeyDate: String?
    let index: Int
    var emptyTitle: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            Text(index, format: .number)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(stop.name.isEmpty ? (emptyTitle ?? localization.text("ios.editor.untitledStop")) : stop.name)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    if let arrival = stop.arrival, !arrival.isEmpty { Text(displayTime(arrival)) }
                    if let departure = stop.departure, !departure.isEmpty { Text(displayTime(departure)) }
                    if let actual = stop.actualArrival, !actual.isEmpty {
                        Text(localization.text("ios.editor.actualArrivalValue", params: [
                            "time": .string(displayTime(actual)),
                        ]))
                    }
                    if let actual = stop.actualDeparture, !actual.isEmpty {
                        Text(localization.text("ios.editor.actualDepartureValue", params: [
                            "time": .string(displayTime(actual)),
                        ]))
                    }
                    if let platform = stop.platformNumber {
                        Text(
                            localization.text(
                                "ios.detail.platformValue", params: ["number": .number(Double(platform))]))
                    }
                    if stop.stopType != "passenger_stop" {
                        Text(localization.countryText("stoptype.\(stop.stopType)", fallback: stop.stopType))
                    }
                    if !stop.rideSegment {
                        Text(localization.text("ios.detail.notRidden"))
                    }
                }
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
            Spacer()
            if stop.rideSegment {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
                    .accessibilityLabel(localization.text("ios.detail.ridden"))
            }
        }
        .frame(minHeight: 44)
    }

    private func displayTime(_ raw: String) -> String {
        guard let journeyDate,
              case .valid(_, let clock) = EditorTime.parseTime(raw),
              clock.dayOffset > 0,
              let date = Dates.addDays(journeyDate, clock.dayOffset)
        else { return raw }
        return "\(date) " + String(format: "%02d:%02d", clock.hour, clock.minute)
    }
}

struct StopEditorView: View {
    @Environment(AppLocalization.self) private var localization
    @Binding var stop: Stop
    @Binding var journeyDate: String?
    let index: Int
    /// The ride's region, so the picker offers that network's stations rather
    /// than all 14,000 across five countries — where 中央駅 and 中央站 would
    /// sit next to each other and picking the wrong one is a route that will
    /// never solve.
    let region: Region
    var allowsEndpointRoles = true
    let selectedLineIDs: Set<String>
    var onRiddenChange: () -> Void = {}

    /// `TrainValidation.stopTypes`, not a copy of it: the order is the web
    /// editor's `<select>` order and is quoted into the rejection message, so
    /// a second list here would be a second answer.
    private var types: [String] { TrainValidation.stopTypes }
    @FocusState private var stationNameFocused: Bool
    @State private var catalog: EditorCatalog?
    @State private var retiredOpenStations: [RetiredStation] = []

    private var selectedLines: [CatalogLine] {
        guard let catalog else { return [] }
        return selectedLineIDs.compactMap { catalog.line(id: $0, regionCode: region.code) }
            .sorted { lhs, rhs in
                if lhs.name != rhs.name { return lhs.name < rhs.name }
                return lhs.id < rhs.id
            }
    }

    private var hasStationLineConflict: Bool {
        guard let catalog, !selectedLineIDs.isEmpty,
              let code = stop.n02StationCode, !code.isEmpty
        else { return false }
        let key = StationKey(regionCode: region.code, sourceCode: code)
        return catalog.memberships(stationKey: key).allSatisfy { !selectedLineIDs.contains($0.lineID) }
    }

    private var stationName: Binding<String> {
        Binding(get: { stop.name }, set: { name in
            if name != stop.name { stop.n02StationCode = nil }
            stop.name = name
        })
    }

    var body: some View {
        Form {
            Section(localization.text("ios.editor.station")) {
                if stop.routeEditing?.generatedBy != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        AutoFilledStationLabel()
                        Text(localization.text("ios.editor.generatedStationsNote"))
                            .font(.footnote).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityIdentifier("stopEditorAutoFilledNote")
                }
                EditorField(title: localization.text("ios.editor.stationName")) {
                    TextField(localization.text("ios.editor.stationSearch"), text: stationName)
                        .focused($stationNameFocused)
                        .autocorrectionDisabled()
                }
                .accessibilityIdentifier("rideEditorStopName")
                StationPickerView(
                    regionCode: region.code, selectedLineIDs: selectedLineIDs,
                    onSelect: { station in
                        stop.name = station.name
                        stop.n02StationCode = station.key.sourceCode
                        stationNameFocused = false
                    },
                    rideDate: journeyDate,
                    onSelectRetired: { station in
                        stop.name = station.name
                        stop.n02StationCode = station.certifiedCode
                        stationNameFocused = false
                    },
                    inlineQuery: stationName, showsSuggestions: stationNameFocused,
                    onLoad: { loaded, retired in
                        catalog = loaded
                        retiredOpenStations = retired
                    })
                if stop.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(localization.text("ios.editor.stationGuide"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if stop.n02StationCode?.isEmpty != false {
                    if let matchedRetired = retiredOpenStations.first(where: { $0.name == stop.name }) {
                        Label(
                            localization.text(
                                matchedRetired.certifiedCode != nil
                                    ? "ios.editor.renamedStationNote" : "ios.editor.retiredStationNote"),
                            systemImage: "clock.arrow.circlepath")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(localization.text("ios.editor.stationUnmatched"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if hasStationLineConflict {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(localization.text("ios.editor.station")): \(stop.name)")
                            Text("\(localization.text("ios.editor.lineNames")): \(selectedLines.map(\.name).joined(separator: " · "))")
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("rideEditorStationLineConflict")
                }
                NavigationLink {
                    StationPickerView(
                        regionCode: region.code, selectedLineIDs: selectedLineIDs,
                        onSelect: { station in
                            stop.name = station.name
                            stop.n02StationCode = station.key.sourceCode
                        },
                        rideDate: journeyDate,
                        onSelectRetired: { station in
                            stop.name = station.name
                            stop.n02StationCode = station.certifiedCode
                        })
                    .environment(localization)
                } label: {
                    Label(
                        localization.text("ios.editor.chooseStation"),
                        systemImage: "tram.circle")
                }
                EditorTextField(
                    title: localization.text("ios.editor.platformNumber"),
                    text: platformText,
                    prompt: localization.text("ios.editor.platformOptional")
                )
                .accessibilityIdentifier("rideEditorStopPlatform")
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                if let platform = stop.platformNumber, platform < 0 {
                    Label(
                        localization.text("ios.editor.platformRule"),
                        systemImage: "exclamationmark.circle.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section {
                EditorDateField(
                    title: localization.text("ios.editor.date"),
                    date: Binding(
                        get: { journeyDate },
                        set: { journeyDate = $0 }),
                    region: region,
                    accessibilityID: "rideEditorStopJourneyDate")
            } header: {
                Text(localization.text("ios.editor.date"))
            } footer: {
                Text(localization.text("ios.editor.sharedJourneyDateNote"))
            }

            Section {
                if stop.stopType == "pass_through" {
                    EditorTimeField(
                        title: localization.text("ios.editor.passTime"),
                        time: $stop.departure,
                        serviceDate: journeyDate,
                        accessibilityID: "rideEditorStopDeparture")
                    if let arrival = stop.arrival, arrival.isEmpty == false {
                        EditorTimeField(
                            title: localization.countryText("popup.arrival", fallback: "Arrival"),
                            time: $stop.arrival,
                            serviceDate: journeyDate)
                    }
                } else {
                    EditorTimeField(
                        title: localization.countryText("popup.arrival", fallback: "Arrival"),
                        time: $stop.arrival,
                        serviceDate: journeyDate,
                        accessibilityID: "rideEditorStopArrival")
                    EditorTimeField(
                        title: localization.countryText("popup.departure", fallback: "Departure"),
                        time: $stop.departure,
                        serviceDate: journeyDate,
                        accessibilityID: "rideEditorStopDeparture")
                }
            } header: {
                Text(localization.text("ios.editor.times"))
            } footer: {
                // The stored clock keeps its service-day offset (for example,
                // 25:10); the picker and preview show its civil date.
                Text(localization.text("ios.editor.crossDayHint"))
            }
            Section {
                EditorTimeField(title: localization.text("ios.editor.actualArrival"),
                                time: $stop.actualArrival,
                                serviceDate: journeyDate,
                                accessibilityID: "rideEditorStopActualArrival")
                if let status = StopTimingStatus.localizedLabel(
                    scheduled: stop.arrival, actual: stop.actualArrival,
                    localization: localization) {
                    Text(status).foregroundStyle(.secondary)
                }
                EditorTimeField(title: localization.text("ios.editor.actualDeparture"),
                                time: $stop.actualDeparture,
                                serviceDate: journeyDate,
                                accessibilityID: "rideEditorStopActualDeparture")
                if let status = StopTimingStatus.localizedLabel(
                    scheduled: stop.departure, actual: stop.actualDeparture,
                    localization: localization) {
                    Text(status).foregroundStyle(.secondary)
                }
            } header: {
                Text(localization.text("ios.editor.actualTimes"))
            } footer: {
                Text(localization.text("ios.editor.actualTimesNote"))
            }

            Section {
                Picker(
                    localization.countryText("popup.stopType", fallback: "Stop type"),
                    selection: $stop.stopType
                ) {
                    ForEach(allowsEndpointRoles ? types : types.filter {
                        !["origin", "destination"].contains($0) || $0 == stop.stopType
                    }, id: \.self) {
                        Text(localization.countryText("stoptype.\($0)", fallback: $0)).tag($0)
                    }
                }
                .disabled(!allowsEndpointRoles && ["origin", "destination"].contains(stop.stopType))
                Toggle(
                    localization.countryText("popup.rideSegment", fallback: "Ridden segment"),
                    isOn: Binding(get: { stop.rideSegment }, set: { value in
                        onRiddenChange()
                        stop.rideSegment = value
                    }))
                    .accessibilityIdentifier("rideEditorStopRidden")
            } footer: {
                Text(localization.text("ios.editor.rideSegmentNote"))
            }
        }
        .navigationTitle(
            stop.name.isEmpty
                ? localization.text("ios.editor.stopIndex", params: ["index": .number(Double(index + 1))])
                : stop.name
        )
        .navigationBarTitleDisplayMode(.inline)
    }

    private func optionalText(_ keyPath: WritableKeyPath<Stop, String?>) -> Binding<String> {
        EditorBindings.optionalText($stop, keyPath)
    }

    private var platformText: Binding<String> {
        Binding(
            get: { stop.platformNumber.map(String.init) ?? "" },
            set: {
                let value = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                stop.platformNumber = value.isEmpty ? nil : Int(value)
            }
        )
    }
}

