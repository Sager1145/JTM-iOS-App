import RailCore
import SwiftUI

/// A separate proposal surface: endpoint selection never edits the parent draft.
struct LocalJourneyFillView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppLocalization.self) private var localization
    let train: Train
    let package: CompactPackage
    let onApply: (LocalJourneyAutofill.Proposal) -> Void
    let onPending: ((Train) -> Void)?

    @State private var originCode: String?
    @State private var destinationCode: String?
    @State private var choices: [RailwayRouteChoices.Choice] = []
    @State private var selectedChoiceID: String?
    @State private var requiredStationCodes: [String] = []
    @State private var pendingTrain: Train?
    @State private var searching = false
    @State private var searched = false
    @State private var searchError: String?
    @State private var geometry: RailwayGuideGeometry?
    @State private var pending: LocalJourneyAutofill.Proposal?
    @State private var catalog: LineServiceCatalog?
    @State private var catalogFailure = false
    @State private var throughPatterns: [JapanThroughServices.Pattern] = []
    @State private var operatingPatternID: String?

    init(train: Train, package: CompactPackage, onPending: ((Train) -> Void)? = nil, onApply: @escaping (LocalJourneyAutofill.Proposal) -> Void) {
        self.train = train
        self.package = package
        self.onApply = onApply
        self.onPending = onPending
        _requiredStationCodes = State(initialValue: train.stops.dropFirst().dropLast()
            .filter { $0.routeEditing?.generatedBy == nil }.compactMap(\.n02StationCode))
        _originCode = State(initialValue: train.stops.first?.n02StationCode)
        _destinationCode = State(initialValue: train.stops.last?.n02StationCode)
    }

    private var input: [String?] { [originCode, destinationCode, train.trainType, operatingPatternID] + requiredStationCodes.map(Optional.some) }
    private var allowsOperatingPatterns: Bool {
        let type = (train.trainType ?? "local").lowercased()
        return !["highspeed", "high speed", "high-speed", "shinkansen", "新幹線", "新干线", "高速"]
            .contains { type.contains($0) }
    }
    private var ready: Bool {
        originCode != nil && destinationCode != nil && originCode != destinationCode
    }
    private func text(_ key: String) -> String {
        LocalJourneyStrings.text(key, language: localization.language)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    endpointRow(key: "ios.editor.fromStation", selection: $originCode)
                    endpointRow(key: "ios.editor.toStation", selection: $destinationCode)
                } footer: { Text(text("note")) }
                Section {
                    ForEach(Array(requiredStationCodes.enumerated()), id: \.offset) { index, code in
                        HStack {
                            Text(stationName(code))
                            Spacer()
                            Button(role: .destructive) { requiredStationCodes.remove(at: index) } label: {
                                Image(systemName: "minus.circle")
                            }
                            .accessibilityLabel(localization.text("ios.remove", fallback: "Remove") + " " + stationName(code))
                        }
                    }
                    NavigationLink {
                        StationPickerView(
                            regionCode: package.country.lowercased(),
                            onSelect: { station, _ in
                                let code = station.key.sourceCode
                                if !requiredStationCodes.contains(code) { requiredStationCodes.append(code) }
                            },
                            sourcePackage: package, accessibilityPrefix: "localJourneyStation")
                    } label: {
                        Label(localization.text("ios.routeGuide.addVia"), systemImage: "plus")
                    }
                } header: { Text(localization.text("ios.routeGuide.via")) }
                if package.country.lowercased() == "jp", allowsOperatingPatterns, !throughPatterns.isEmpty {
                    Section {
                        Picker(text("services"), selection: $operatingPatternID) {
                            Text(text("anyService")).tag(Optional<String>.none)
                            ForEach(throughPatterns) { pattern in
                                Text(patternLabel(pattern)).tag(Optional(pattern.id))
                            }
                        }
                        .accessibilityIdentifier("localJourneyOperatingService")
                        if let pattern = throughPatterns.first(where: { $0.id == operatingPatternID }) {
                            ForEach(pattern.sourceURLs, id: \.self) { source in
                                if let url = URL(string: source) {
                                    Link(pattern.name, destination: url).font(.caption)
                                }
                            }
                        }
                    }
                }
                Section {
                    if searching { ProgressView(text("searching")) }
                    if let searchError {
                        Text(searchError).font(.footnote).foregroundStyle(.secondary)
                            .accessibilityIdentifier("localJourneySearchError")
                    }
                    if searched && choices.isEmpty {
                        Text(text("empty")).foregroundStyle(.secondary)
                            .accessibilityIdentifier("localJourneySearchEmpty")
                    }
                    if searched {
                        Text(localization.text("ios.routeGuide.incompleteSearch"))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if !choices.isEmpty, let geometry {
                        RailwayGuideMap(choices: choices,
                            geometry: geometry,
                            selectedID: selectedChoiceID,
                            geometryWarning: localization.text("ios.routeGuide.geometryUnavailable"),
                            onSelect: { selectedChoiceID = $0 })
                    }
                    ForEach(choices) { choice in
                        VStack(alignment: .leading, spacing: 8) {
                            Button { selectedChoiceID = choice.id } label: {
                                Label(choice.lineNames.joined(separator: " → "),
                                      systemImage: selectedChoiceID == choice.id ? "checkmark.circle.fill" : "circle")
                                    .font(.headline)
                            }
                            .accessibilityAddTraits(selectedChoiceID == choice.id ? .isSelected : [])
                            Text(choice.operatorNames.joined(separator: " / "))
                                .font(.caption).foregroundStyle(.secondary)
                            DisclosureGroup {
                                ForEach(Array(choice.stations.enumerated()), id: \.offset) { _, visit in
                                    Text(localization.stationName(visit.name, code: visit.code))
                                }
                            } label: {
                                Text(choice.stations.count.formatted(.number.locale(localization.locale))
                                    + " · " + text("route"))
                            }
                            Button(text("apply")) { propose(choice) }
                                .buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("localJourneyApply-\(choice.id)")
                            if let catalog {
                                LineServiceCatalogView(package: package, lineIDs: choice.lineIDs,
                                    catalog: catalog, serviceDate: train.date)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    if onPending != nil {
                        Button(localization.text("ios.routeGuide.keepPending")) { proposePending() }
                            .disabled(!ready)
                            .accessibilityIdentifier("localJourneyKeepPending")
                        Text(localization.text("ios.routeGuide.pendingNote"))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if catalogFailure {
                        Text(text("unknown")).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: { Text(text("route")) } footer: { Text(text("physical")) }
            }
            .accessibilityIdentifier("localJourneyProposalForm")
            .navigationTitle(text("title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localization.text("ios.cancel")) { dismiss() }
                }
            }
            .task {
                do {
                    let serviceDate = Dates.normalizeDateString(train.date)
                    let loaded = try await Task.detached(priority: .utility) {
                        let catalog = try JapanThroughServices.loadBundled()
                        return (try LineServiceCatalog.loadBundled(),
                                JapanThroughServices.patterns(on: serviceDate, patterns: catalog.patterns))
                    }.value
                    guard !Task.isCancelled else { return }
                    catalog = loaded.0
                    throughPatterns = loaded.1
                } catch is CancellationError {
                    return
                } catch { catalogFailure = true }
            }
            .task(id: input) { await search() }
            .confirmationDialog(text("replace"), isPresented: Binding(
                get: { pendingTrain != nil }, set: { if !$0 { pendingTrain = nil } }),
                titleVisibility: .visible) {
                Button(localization.text("ios.routeGuide.keepPending"), role: .destructive) {
                    if let pendingTrain { onPending?(pendingTrain); dismiss() }
                    pendingTrain = nil
                }
                Button(localization.text("ios.cancel"), role: .cancel) { pendingTrain = nil }
            }
            .confirmationDialog(text("replace"), isPresented: Binding(
                get: { pending != nil }, set: { if !$0 { pending = nil } }),
                titleVisibility: .visible, presenting: pending) { proposal in
                Button(text("apply"), role: .destructive) { apply(proposal) }
                Button(localization.text("ios.cancel"), role: .cancel) { pending = nil }
            } message: { proposal in
                Text(proposal.conflictingStops.map(\.name).joined(separator: " · "))
            }
        }
    }

    private func patternLabel(_ pattern: JapanThroughServices.Pattern) -> String {
        let prefix = pattern.id == "JK" ? "JK · " : (pattern.id.hasPrefix("JS-") ? "JS · " : "")
        let legs = pattern.legs(on: Dates.normalizeDateString(train.date))
        guard let first = legs.first, let last = legs.last,
              let origin = package.lines.first(where: { $0.id == first.lineID })?.stations
                .first(where: { $0.id == first.fromStationCode }),
              let destination = package.lines.first(where: { $0.id == last.lineID })?.stations
                .first(where: { $0.id == last.toStationCode }) else { return prefix + pattern.name }
        return prefix + pattern.name + "（" + origin.name + " → " + destination.name + "）"
    }

    private func endpointRow(key: String, selection: Binding<String?>) -> some View {
        NavigationLink {
            StationPickerView(
                regionCode: package.country.lowercased(),
                onSelect: { station, _ in selection.wrappedValue = station.key.sourceCode },
                sourcePackage: package, accessibilityPrefix: "localJourneyStation")
        } label: {
            LabeledContent(localization.text(key), value: stationName(selection.wrappedValue))
        }
        .accessibilityIdentifier(key == "ios.editor.fromStation" ? "localJourneyOrigin" : "localJourneyDestination")
    }

    private func stationName(_ code: String?) -> String {
        guard let code, let station = package.lines.lazy.flatMap(\.stations).first(where: { $0.id == code })
        else { return text("choose") }
        return localization.stationName(station.name, code: code)
    }

    private func search() async {
        choices = []
        selectedChoiceID = nil
        searched = false
        searchError = nil
        geometry = nil
        guard ready, let originCode, let destinationCode else { searching = false; return }
        searching = true
        let package = package
        let type = train.trainType
        let serviceDate = Dates.normalizeDateString(train.date)
        let required = [originCode] + requiredStationCodes + [destinationCode]
        let operatorID = train.operatorID
        // Service labels are display metadata, never additional graph edges.
        let worker = Task.detached(priority: .userInitiated) {
            let aliases = try loadJourneyStationAliases(for: required, package: package)
            // Physical fill never retries with passenger-transfer permissions.
            var memo: [String: Bool] = [:]
            func allows(_ from: CompactPackage.Line, _ to: CompactPackage.Line, _ code: String) -> Bool {
                let key = from.id + "\u{1F}" + to.id + "\u{1F}" + code
                if let known = memo[key] { return known }
                let value = TripConnectivity.allows(from: from, to: to, atStationCode: code, on: serviceDate)
                memo[key] = value
                return value
            }
            return LocalJourneySearch.search(package: package, originCode: originCode,
                destinationCode: destinationCode, trainType: type, requiredStationCodes: required,
                stationAliases: aliases, continuation: allows, operatorID: operatorID)
        }
        let result: LocalJourneySearch.Result
        do {
            result = try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: { worker.cancel() }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            searching = false
            searchError = error.localizedDescription
            return
        }
        guard !Task.isCancelled else { return }
        choices = result.choices
        geometry = RailwayGuideGeometry(package: package, choices: result.choices)
        searching = false
        searched = true
    }

    private func proposePending() {
        guard let originCode, let destinationCode else { return }
        var value = train
        let sameEndpoints = train.stops.first?.n02StationCode == originCode
            && train.stops.last?.n02StationCode == destinationCode
            && train.stops.dropFirst().dropLast().filter { $0.routeEditing?.generatedBy == nil }
                .compactMap(\.n02StationCode) == requiredStationCodes
        if !sameEndpoints {
            let codes = [originCode] + requiredStationCodes + [destinationCode]
            var cursor = 0
            value.stops = codes.enumerated().map { index, code in
                if let matched = train.stops.indices.dropFirst(cursor).first(where: { train.stops[$0].n02StationCode == code }) {
                    var recorded = train.stops[matched]
                    cursor = matched + 1
                    if index == 0 { recorded.stopType = "origin" }
                    else if index == codes.count - 1 { recorded.stopType = "destination" }
                    else if ["origin", "destination"].contains(recorded.stopType) { recorded.stopType = "pass_through" }
                    return recorded
                }
                let name = package.lines.lazy.flatMap(\.stations).first { $0.id == code }?.name ?? code
                var stop = Stop(name: name, n02StationCode: code,
                    stopType: index == 0 ? "origin" : (index == codes.count - 1 ? "destination" : "pass_through"))
                RegistryStationSelection.fill(
                    &stop, regionCode: package.country.lowercased(), sourceCode: code,
                    catalogName: name)
                stop.stopType = index == 0 ? "origin" : (index == codes.count - 1 ? "destination" : "pass_through")
                return stop
            }
            value.routeSections = nil
            value.origin = value.stops.first?.name ?? ""
            value.destination = value.stops.last?.name ?? ""
        }
        value.routeConfirmation = .pending
        if let pattern = throughPatterns.first(where: { $0.id == operatingPatternID }) {
            if value.routeSections?.isEmpty != false {
                value.routeSections = [RouteSection(from: value.origin, to: value.destination,
                    fromN02StationCode: originCode, toN02StationCode: destinationCode, name: pattern.name)]
            } else {
                for index in value.routeSections!.indices { value.routeSections?[index].name = pattern.name }
            }
        }
        if value.number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            value.number = value.origin + " → " + value.destination
        }
        if !sameEndpoints && !train.stops.isEmpty { pendingTrain = value }
        else { onPending?(value); dismiss() }
    }

    private func propose(_ choice: RailwayRouteChoices.Choice) {
        var labeled = choice
        if let pattern = throughPatterns.first(where: { $0.id == operatingPatternID }) {
            for index in labeled.routeSections.indices { labeled.routeSections[index].name = pattern.name }
        }
        guard let proposal = LocalJourneyAutofill.proposal(train: train, choice: labeled) else { return }
        if proposal.requiresConfirmation { pending = proposal } else { apply(proposal) }
    }
    private func apply(_ proposal: LocalJourneyAutofill.Proposal) {
        onApply(proposal)
        dismiss()
    }
}

