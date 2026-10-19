import RailCore
import RailPresentation
import SwiftUI

struct ServiceRangeEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppLocalization.self) private var localization
    @Binding var train: Train
    let leg: JourneyServiceSections.Leg?
    @State private var fromIndex: Int
    @State private var toIndex: Int
    @State private var linesText: String
    @State private var operatorsText: String
    @State private var number: String
    @State private var name: String
    @State private var usesRecordedRange: Bool

    init(train: Binding<Train>, leg: JourneyServiceSections.Leg?) {
        _train = train
        self.leg = leg
        let sections = StoreOperations.rideRouteSections(for: train.wrappedValue)
        let initialRange: (from: Int, to: Int)
        if let leg {
            initialRange = Self.clampedRange(
                from: leg.fromStopIndex, to: leg.toStopIndex, stopCount: train.wrappedValue.stops.count)
        } else if let firstUnfilled = sections.firstIndex(where: {
            RouteSectionServiceInfo(section: $0).isEmpty
        }), let endpoints = Self.stopRange(for: sections[firstUnfilled], in: train.wrappedValue) {
            initialRange = Self.clampedRange(
                from: endpoints.from, to: endpoints.to, stopCount: train.wrappedValue.stops.count)
        } else {
            initialRange = Self.clampedRange(
                from: 0, to: train.wrappedValue.stops.count - 1,
                stopCount: train.wrappedValue.stops.count)
        }
        _fromIndex = State(initialValue: initialRange.from)
        _toIndex = State(initialValue: initialRange.to)
        _linesText = State(initialValue: (leg?.info.lineNames ?? []).joined(separator: ", "))
        _operatorsText = State(initialValue: (leg?.info.operatorNames ?? []).joined(separator: ", "))
        _number = State(initialValue: leg?.info.number ?? "")
        _name = State(initialValue: leg?.info.name ?? "")
        _usesRecordedRange = State(initialValue: leg == nil)
    }

    private var stopChoices: [Int] { Array(train.stops.indices) }
    private var lines: [String] { names(in: linesText) }
    private var operators: [String] { names(in: operatorsText) }
    private var fromSelection: Binding<Int> {
        Binding(get: { fromIndex }, set: { newValue in
            fromIndex = newValue
            if toIndex <= newValue { toIndex = newValue + 1 }
        })
    }
    private var selectedStationCodes: [String] {
        if !usesRecordedRange, let leg {
            return [leg.fromStationCode, leg.toStationCode].compactMap { $0 }
        }
        guard let first = train.stops.indices.first, let last = train.stops.indices.last else { return [] }
        let lo = min(max(min(fromIndex, toIndex), first), last)
        let hi = min(max(max(fromIndex, toIndex), first), last)
        return Array(train.stops[lo...hi]).compactMap(\.n02StationCode)
    }

    var body: some View {
        Form {
            Section(localization.text("ios.editor.endpoints")) {
                if !usesRecordedRange, let leg {
                    LabeledContent(localization.text("ios.editor.fromStation"),
                        value: localization.sectionEndpoint(name: leg.from, code: leg.fromStationCode, in: train, stopIndex: leg.fromStopIndex))
                    LabeledContent(localization.text("ios.editor.toStation"),
                        value: localization.sectionEndpoint(name: leg.to, code: leg.toStationCode, in: train, stopIndex: leg.toStopIndex))
                    Button { usesRecordedRange = true } label: {
                        Label(localization.text("ios.editor.endpoints"), systemImage: "pencil")
                    }
                    .accessibilityIdentifier("rideEditorChangeServiceRange")
                } else {
                    Picker(localization.text("ios.editor.fromStation"), selection: fromSelection) {
                        ForEach(stopChoices.dropLast(), id: \.self) { index in
                            Text(station(at: index)).tag(index)
                        }
                    }
                    .accessibilityIdentifier("rideEditorServiceFrom")
                    Picker(localization.text("ios.editor.toStation"), selection: $toIndex) {
                        ForEach(stopChoices.filter { $0 > fromIndex }, id: \.self) { index in
                            Text(station(at: index)).tag(index)
                        }
                    }
                    .accessibilityIdentifier("rideEditorServiceTo")
                }
            }
            Section {
                NavigationLink {
                    EditorLineSearchView(
                        region: Region.resolved(train), lineNames: lines, operatorNames: operators,
                        selectedLineIDs: [],
                        stationCodes: selectedStationCodes
                    ) { _, names, operatorNames in
                        linesText = names.joined(separator: ", ")
                        operatorsText = operatorNames.joined(separator: ", ")
                    }
                } label: {
                    LabeledContent(localization.text("ios.editor.searchLines"),
                                   value: lines.joined(separator: " · "))
                }
                EditorTextField(title: localization.text("ios.editor.lineNames"),
                                text: $linesText,
                                prompt: localization.text("ios.editor.onePerComma"))
                EditorTextField(title: localization.text("ios.editor.operatorNames"),
                                text: $operatorsText,
                                prompt: localization.text("ios.editor.onePerComma"))
                EditorTextField(title: localization.countryText("field.number", fallback: "Train number"),
                                text: $number,
                                prompt: localization.text("ios.editor.sectionNumberUnknown"))
                    .accessibilityIdentifier("rideEditorSectionNumber")
                EditorTextField(title: localization.text("ios.editor.displayName"), text: $name)
            } header: {
                Text(localization.text("ios.editor.sectionService"))
            } footer: {
                Text(localization.text("ios.editor.sectionServicesNote"))
            }
            if leg != nil {
                Section {
                    Button(localization.text("ios.editor.clearSectionService"), role: .destructive) {
                        apply(RouteSectionServiceInfo())
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(localization.text("ios.editor.sectionService"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(localization.text("ios.editor.applySectionService")) {
                    apply(
                        RouteSectionServiceInfo(lineNames: lines, operatorNames: operators,
                                                number: number, name: name))
                    dismiss()
                }
                .accessibilityIdentifier("rideEditorApplyServiceLeg")
            }
        }
    }

    private func apply(_ info: RouteSectionServiceInfo) {
        if !usesRecordedRange, let leg {
            train = RouteSectionServiceEditing.applying(info, to: train,
                fromSectionIndex: leg.fromSectionIndex, toSectionIndex: leg.toSectionIndex)
        } else {
            train = RouteSectionServiceEditing.applying(info, to: train,
                fromStopIndex: fromIndex, toStopIndex: toIndex)
        }
    }

    private func station(at index: Int) -> String {
        let stop = train.stops[index]
        let name = localization.stationName(stop.name, in: train, code: stop.n02StationCode)
        let mark = stop.stationID?.isEmpty != false
            ? " " + localization.text(RegistryStationDisplay.unresolvedKey) : ""
        return "\(index + 1). \(name)\(mark)"
    }

    private static func clampedRange(from: Int, to: Int, stopCount: Int) -> (from: Int, to: Int) {
        guard stopCount > 1 else { return (0, 0) }
        let last = stopCount - 1
        let lo = min(max(min(from, to), 0), last - 1)
        let hi = min(max(max(from, to), lo + 1), last)
        return (lo, hi)
    }

    private static func stopRange(for section: RouteSection, in train: Train) -> (from: Int, to: Int)? {
        func matches(_ stop: Stop, code: String?, name: String?) -> Bool {
            if let code, !code.isEmpty, let stopCode = stop.n02StationCode, !stopCode.isEmpty {
                return StationCodeAliases.canonical(code) == StationCodeAliases.canonical(stopCode)
            }
            guard let name, !name.isEmpty else { return false }
            return stop.name == name
        }
        for from in train.stops.indices where matches(
            train.stops[from], code: section.fromN02StationCode, name: section.from
        ) {
            guard from < train.stops.index(before: train.stops.endIndex) else { continue }
            if let to = train.stops.indices[(from + 1)...].first(where: {
                matches(train.stops[$0], code: section.toN02StationCode, name: section.to)
            }) {
                return (from, to)
            }
        }
        return nil
    }

    private func names(in text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ",，、"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}

