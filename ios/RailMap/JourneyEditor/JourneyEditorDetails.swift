import RailApplication
import RailCore
import RailPresentation
import SwiftUI
import UIKit

/// The saved record's stops and the fields the route and timetable never
/// set: English name, direction, vehicle, section services, notes,
/// visibility, group, colour and identifier. Part of the one journey editor.
struct JourneyEditorDetails: View {
    @Environment(AppLocalization.self) private var localization
    @Binding var draft: Train
    let region: Region
    /// The saved stops are the route. A replanned route shows its stations
    /// in the Route section instead; its stops become editable once saved.
    let showsStops: Bool
    let suggestionTrains: [Train]
    let issues: [RideDraftIssue]
    @Binding var expanded: Bool
    /// Which part this instance draws: the editor puts the stops beside the
    /// route and the rest at the end of the form.
    var part: Part = .all

    enum Part { case all, stops, more }

    private enum OfficialEnglishName: Equatable {
        case loading
        case available(String)
        case unavailable

        var value: String? {
            if case .available(let name) = self { return name }
            return nil
        }
    }

    private struct OfficialNameQuery: Equatable {
        var number: String
        var date: String?
        var region: String
    }

    @State private var officialEnglishName: OfficialEnglishName = .loading

    var body: some View {
        if part != .more, showsStops, !draft.stops.isEmpty { stopsSection }
        if part != .stops { moreDetails }
    }

    @ViewBuilder private var moreDetails: some View {
        Section {
            Button {
                expanded.toggle()
            } label: {
                HStack {
                    Text(localization.text(
                        expanded ? "ios.newTrip.fewerDetails" : "ios.newTrip.moreDetails",
                        fallback: expanded ? "Fewer details" : "More details"))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: RailSize.touch)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("newTripMoreDetails")
            .id(EditorAnchor.details.rawValue)
        }
        if expanded {
            serviceDetailsSection
            serviceSectionsSection
            notesSection
            groupSection
            styleSection
            recordSection
        }
    }

    // MARK: - stops

    private var stopsSection: some View {
        Section {
            if draft.stops.contains(where: { $0.routeEditing?.generatedBy != nil }) {
                Label(localization.text("ios.editor.generatedStationsNote"), systemImage: "info.circle")
                    .railText(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("rideEditorAutoFilledStationsNote")
            }
            ForEach(draft.stops.indices, id: \.self) { index in
                HStack(spacing: RailSpacing.s8) {
                NavigationLink {
                    StopEditorView(
                        stop: editableStop(index), journeyDate: $draft.date,
                        index: index, region: region, selectedLineIDs: routeLineIDs)
                } label: {
                    VStack(alignment: .leading, spacing: RailSpacing.s4) {
                        StopEditorLabel(stop: draft.stops[index], journeyDate: draft.date, index: index + 1)
                        if draft.stops[index].routeEditing?.generatedBy != nil {
                            AutoFilledStationLabel()
                                .accessibilityIdentifier("rideEditorAutoFilledStop-\(index)")
                        }
                    }
                }
                .accessibilityIdentifier("rideEditorStop-\(index)")
                // Scroll anchors live on a row, not on the Section.
                .id(index == 0 ? EditorAnchor.stops.rawValue : "rideEditorStopRow-\(index)")
                // The platform is entered here, without opening the stop.
                PlatformEntryBadge(
                    platform: Binding(
                        get: { draft.stops.indices.contains(index) ? draft.stops[index].platformNumber : nil },
                        set: { if draft.stops.indices.contains(index) { draft.stops[index].platformNumber = $0 } }),
                    identifier: "rideEditorStopPlatformBadge-\(index)")
                }
                issueRows(.stop(index))
            }
        } header: {
            Text(localization.text("sec.stops", fallback: "Stops"))
        } footer: {
            Text(localization.text(
                "ios.newTrip.stopsNote",
                fallback: "To change the route, pick other stations or add a stop on the map."))
        }
    }

    private var routeLineIDs: Set<String> {
        Set((draft.routeSections ?? []).flatMap { $0.lineIDs ?? [] })
    }

    /// Editing an automatic visit promotes it to an authored visit. A changed
    /// station means the confirmed route no longer describes these stops.
    private func editableStop(_ index: Int) -> Binding<Stop> {
        Binding(get: {
            draft.stops.indices.contains(index) ? draft.stops[index] : Stop(name: "")
        }, set: { value in
            guard draft.stops.indices.contains(index) else { return }
            var updated = value
            let previous = draft.stops[index]
            let identityChanged = updated.stationID != previous.stationID && updated.stationID != nil
            let stationChanged = updated.name != previous.name
                || updated.n02StationCode != previous.n02StationCode
            if !identityChanged, stationChanged {
                if let code = updated.n02StationCode,
                   !RegistryStationSelection.apply(sourceCode: code, regionCode: region.code, to: &updated) {
                    updated.stationID = nil
                } else if updated.n02StationCode == nil {
                    updated.stationID = nil
                }
            }
            if updated != previous {
                if updated.routeEditing == nil { updated.routeEditing = Stop.RouteEditingMetadata() }
                updated.routeEditing?.generatedBy = nil
            }
            draft.stops[index] = updated
            if updated.n02StationCode != previous.n02StationCode, draft.routeConfirmation == .confirmed {
                draft.routeConfirmation = nil
            }
        })
    }

    // MARK: - details

    private var serviceDetailsSection: some View {
        Section {
            EditorTextField(
                title: localization.countryText("field.numberEn", fallback: "English name"),
                text: optionalText(\.numberEn))
                .accessibilityIdentifier("rideEditorNumberEn")
            Button {
                guard let name = officialEnglishName.value else { return }
                draft.numberEn = name
            } label: {
                VStack(alignment: .leading, spacing: RailSpacing.s4) {
                    Text(localization.text("ios.editor.useOfficialEnglishName"))
                    if let name = officialEnglishName.value {
                        Text(verbatim: name).railText(.tertiary)
                    }
                }
            }
            .disabled(officialEnglishName.value == nil)
            .accessibilityIdentifier("rideEditorUseOfficialEnglishName")
            if case .unavailable = officialEnglishName {
                Text(localization.text("ios.editor.officialEnglishNameUnavailable"))
                    .railText(.secondary)
            }
        } header: {
            Text(localization.text("ios.editor.serviceDetails"))
        }
        .task(id: OfficialNameQuery(number: draft.number, date: draft.date, region: region.code)) {
            officialEnglishName = .loading
            var train = draft
            train.region = region.code
            let result = await Task.detached(priority: .userInitiated) { () -> String? in
                guard TrainTimetableDatabase.accepts(train),
                      let database = try? TrainTimetableDatabase.bundled(country: train.region ?? "jp")
                else { return nil }
                return try? JourneyEnglishName.official(for: train, database: database)
            }.value
            guard !Task.isCancelled else { return }
            officialEnglishName = result.map(OfficialEnglishName.available) ?? .unavailable
        }
    }

    private var serviceSectionsSection: some View {
        Section {
            ForEach(JourneyServiceSections.legs(of: draft)) { leg in
                NavigationLink {
                    ServiceRangeEditorView(train: $draft, leg: leg)
                } label: {
                    ServiceSectionSummary(leg: leg, train: draft)
                }
                .accessibilityIdentifier("rideEditorServiceLeg-\(leg.id)")
            }
            NavigationLink {
                ServiceRangeEditorView(train: $draft, leg: nil)
            } label: {
                Label(localization.text("ios.editor.addSectionService"), systemImage: "plus.circle")
            }
            .disabled(draft.stops.count < 2)
            .accessibilityIdentifier("rideEditorAddServiceLeg")
        } header: {
            Text(localization.text("ios.editor.sectionServices"))
        } footer: {
            Text(localization.text("ios.editor.sectionServicesNote"))
        }
    }

    private var notesSection: some View {
        Section {
            TextField(localization.text("ios.ai.notes"), text: optionalText(\.notes), axis: .vertical)
                .lineLimit(2...5)
                .accessibilityIdentifier("rideEditorNotes")
        } header: {
            Text(localization.text("ios.ai.notes"))
        }
    }

    private var groupSection: some View {
        Section {
            JourneyGroupChoiceFields(
                selection: $draft.journeyGroup,
                groups: JourneyGroupCatalog.groups(in: suggestionTrains))
        } footer: {
            Text(localization.text("ios.journeyGroup.crossRegion"))
        }
    }

    private var styleSection: some View {
        Section {
            ColorPicker(
                localization.text("ios.editor.routeColor"),
                selection: colorBinding, supportsOpacity: false)
                .accessibilityIdentifier("rideEditorColor")
            if draft.style?.color != nil {
                Button(localization.text("ios.newTrip.resetColor", fallback: "Use the default color")) {
                    draft.style = nil
                }
                .accessibilityIdentifier("rideEditorColorReset")
            }
            issueRows(.color)
        } header: {
            Text(localization.text("ios.style", fallback: "Style"))
        }
    }

    /// The system colour picker's value, stored as the `#rrggbb` the record
    /// keeps. An unset colour shows the default one.
    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: draft.style?.color ?? TrainValidation.defaultTrainColor) ?? .accentColor },
            set: { draft.style = TrainStyle(color: Self.hex(of: $0)) })
    }

    private static func hex(of color: Color) -> String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func byte(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", byte(red), byte(green), byte(blue))
    }

    /// The identifier is created with the trip; changing it would break the
    /// links between records, so it is shown, not edited.
    private var recordSection: some View {
        Section {
            if issues.all(for: .id).contains(where: { $0.severity == .error }) {
                // Only a record whose identifier is empty or invalid (a
                // legacy or imported one) can be fixed here; Save is refused
                // until it is.
                EditorTextField(
                    title: localization.countryText("field.id", fallback: "Identifier"),
                    text: $draft.id)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("rideEditorID")
            } else {
                LabeledContent(localization.countryText("field.id", fallback: "Identifier")) {
                    Text(verbatim: draft.id)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("rideEditorID")
                }
            }
            issueRows(.id)
            issueRows(.record)
        } header: {
            Text(localization.text("ios.editor.record"))
        } footer: {
            Text(localization.text("ios.newTrip.idReadOnlyNote", fallback: "Set when the trip was created. It cannot be changed."))
        }
    }

    @ViewBuilder
    private func issueRows(_ field: RideDraftIssue.Field) -> some View {
        ForEach(issues.all(for: field)) { issue in
            RailStatusLabel(kind: issue.severity == .error ? .error : .warning,
                            text: localization.text(for: issue))
        }
    }

    private func optionalText(_ keyPath: WritableKeyPath<Train, String?>) -> Binding<String> {
        EditorBindings.optionalText($draft, keyPath)
    }
}
