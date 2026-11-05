import RailApplication
import RailCore
import RailPresentation
import SwiftUI

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
        if showsStops, !draft.stops.isEmpty { stopsSection }
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
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("newTripMoreDetails")
        }
        if expanded {
            serviceDetailsSection
            serviceSectionsSection
            statusSection
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
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("rideEditorAutoFilledStationsNote")
            }
            ForEach(draft.stops.indices, id: \.self) { index in
                NavigationLink {
                    StopEditorView(
                        stop: editableStop(index), journeyDate: $draft.date,
                        index: index, region: region, selectedLineIDs: routeLineIDs)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        StopEditorLabel(stop: draft.stops[index], journeyDate: draft.date, index: index + 1)
                        if draft.stops[index].routeEditing?.generatedBy != nil {
                            AutoFilledStationLabel()
                                .accessibilityIdentifier("rideEditorAutoFilledStop-\(index)")
                        }
                    }
                }
                .accessibilityIdentifier("rideEditorStop-\(index)")
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
                VStack(alignment: .leading, spacing: 4) {
                    Text(localization.text("ios.editor.useOfficialEnglishName"))
                    if let name = officialEnglishName.value {
                        Text(verbatim: name).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(officialEnglishName.value == nil)
            .accessibilityIdentifier("rideEditorUseOfficialEnglishName")
            if case .unavailable = officialEnglishName {
                Text(localization.text("ios.editor.officialEnglishNameUnavailable"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            EditorTextField(
                title: localization.countryText("field.direction", fallback: "Direction"),
                text: optionalText(\.direction))
                .accessibilityIdentifier("rideEditorDirection")
            EditorTextField(
                title: localization.text("ios.editor.vehicleType"),
                text: optionalText(\.vehicleType))
                .accessibilityIdentifier("rideEditorVehicleType")
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
            TextField(localization.text("ios.ai.notes"), text: optionalText(\.notes), axis: .vertical)
                .lineLimit(2...5)
                .accessibilityIdentifier("rideEditorNotes")
        } header: {
            Text(localization.text("ios.editor.sectionServices"))
        } footer: {
            Text(localization.text("ios.editor.sectionServicesNote"))
        }
    }

    private var statusSection: some View {
        Section {
            if RideLedger.confirmation(of: draft) == .partly {
                Text(localization.text(
                    "ios.editor.riddenPartlyNote",
                    params: ["n": .number(Double(RideLedger.riddenSegmentCount(draft.stops)))]))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Toggle(localization.text("ios.showOnMap", fallback: "Show on map"), isOn: Binding(
                get: { draft.visible != false }, set: { draft.visible = $0 }))
                .accessibilityIdentifier("rideEditorVisible")
        } footer: {
            Text(localization.text("ios.editor.visibilityNote"))
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
            HStack {
                EditorTextField(
                    title: localization.text("ios.editor.routeColor"),
                    text: Binding(
                        get: { draft.style?.color ?? "" },
                        set: { draft.style = TrainStyle(color: $0.isEmpty ? nil : $0) }),
                    prompt: "#RRGGBB")
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                RouteLogoSquare.shape(side: 22)
                    .fill(Color(hex: draft.style?.color) ?? .accentColor)
                    .frame(width: 22, height: 22)
                    .overlay(RouteLogoSquare.shape(side: 22).strokeBorder(.separator, lineWidth: 0.5))
                    .accessibilityHidden(true)
            }
            issueRows(.color)
        } header: {
            Text(localization.text("ios.style", fallback: "Style"))
        }
    }

    private var recordSection: some View {
        Section {
            EditorTextField(
                title: localization.countryText("field.id", fallback: "Identifier"),
                text: $draft.id)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("rideEditorID")
            issueRows(.id)
            issueRows(.record)
        } header: {
            Text(localization.text("ios.editor.record"))
        } footer: {
            Text(localization.text("ios.editor.recordNote"))
        }
    }

    @ViewBuilder
    private func issueRows(_ field: RideDraftIssue.Field) -> some View {
        ForEach(issues.all(for: field)) { issue in
            Label(localization.text(for: issue),
                  systemImage: issue.severity == .error ? "exclamationmark.circle.fill" : "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(issue.severity == .error ? Color.red : Color.orange)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
        }
    }

    private func optionalText(_ keyPath: WritableKeyPath<Train, String?>) -> Binding<String> {
        EditorBindings.optionalText($draft, keyPath)
    }
}
