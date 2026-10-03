import RailCore
import SwiftUI

/// A separate proposal surface: endpoint selection never edits the parent draft.
struct LocalJourneyFillView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppLocalization.self) private var localization
    let train: Train
    let package: CompactPackage
    let onApply: (LocalJourneyAutofill.Proposal) -> Void

    @State private var originCode: String?
    @State private var destinationCode: String?
    @State private var choices: [RailwayRouteChoices.Choice] = []
    @State private var searching = false
    @State private var searched = false
    @State private var pending: LocalJourneyAutofill.Proposal?
    @State private var catalog: LineServiceCatalog?
    @State private var catalogFailure = false
    @State private var throughPatterns: [JapanThroughServices.Pattern] = []
    @State private var operatingPatternID: String?

    init(train: Train, package: CompactPackage, onApply: @escaping (LocalJourneyAutofill.Proposal) -> Void) {
        self.train = train
        self.package = package
        self.onApply = onApply
        _originCode = State(initialValue: train.stops.first?.n02StationCode)
        _destinationCode = State(initialValue: train.stops.last?.n02StationCode)
    }

    private var input: [String?] { [originCode, destinationCode, train.trainType, operatingPatternID] }
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
                    if searched && choices.isEmpty { Text(text("empty")).foregroundStyle(.secondary) }
                    ForEach(choices) { choice in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(choice.lineNames.joined(separator: " → ")).font(.headline)
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
                    if catalogFailure {
                        Text(text("unknown")).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: { Text(text("route")) } footer: { Text(text("physical")) }
            }
            .navigationTitle(text("title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localization.text("ios.cancel")) { dismiss() }
                }
            }
            .task {
                do {
                    let loaded = try await Task.detached(priority: .utility) {
                        (try LineServiceCatalog.loadBundled(), JapanThroughServices.patterns)
                    }.value
                    guard !Task.isCancelled else { return }
                    catalog = loaded.0
                    throughPatterns = loaded.1
                } catch { catalogFailure = true }
            }
            .task(id: input) { await search() }
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
        guard let first = pattern.legs.first, let last = pattern.legs.last,
              let origin = package.lines.first(where: { $0.id == first.lineID })?.stations
                .first(where: { $0.id == first.fromStationCode }),
              let destination = package.lines.first(where: { $0.id == last.lineID })?.stations
                .first(where: { $0.id == last.toStationCode }) else { return prefix + pattern.name }
        return prefix + pattern.name + "（" + origin.name + " → " + destination.name + "）"
    }

    private func endpointRow(key: String, selection: Binding<String?>) -> some View {
        NavigationLink {
            LocalJourneyStationPicker(package: package) { code in selection.wrappedValue = code }
        } label: {
            LabeledContent(localization.editorText(key), value: stationName(selection.wrappedValue))
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
        searched = false
        guard ready, let originCode, let destinationCode else { searching = false; return }
        searching = true
        let package = package
        let type = train.trainType
        let pattern = throughPatterns.first { $0.id == operatingPatternID }
        let worker = Task.detached(priority: .userInitiated) {
            if let pattern {
                return pattern.choices(package: package, originCode: originCode, destinationCode: destinationCode)
            }
            return LocalJourneySearch.choices(package: package, originCode: originCode,
                destinationCode: destinationCode, trainType: type)
        }
        let result = await withTaskCancellationHandler {
            await worker.value
        } onCancel: { worker.cancel() }
        guard !Task.isCancelled else { return }
        choices = result
        searching = false
        searched = true
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

/// Shows the evidence's geographic scope beside each physical line.
struct LineServiceCatalogView: View {
    @Environment(AppLocalization.self) private var localization
    let package: CompactPackage
    let lineIDs: [String]
    let catalog: LineServiceCatalog
    var serviceDate: String?

    private var lines: [CompactPackage.Line] {
        let selected = Set(lineIDs)
        return package.lines.filter { selected.contains($0.id) }
    }
    private func text(_ key: String) -> String {
        LocalJourneyStrings.text(key, language: localization.language)
    }
    var body: some View {
        DisclosureGroup(text("types")) {
            ForEach(lines, id: \.id) { line in
                VStack(alignment: .leading, spacing: 5) {
                    Text(line.name).font(.subheadline.weight(.medium))
                    let kinds = catalog.serviceKinds(lineID: line.id, operatorName: line.operator)
                    if kinds.isEmpty { Text(text("unknown")).foregroundStyle(.secondary) }
                    ForEach(kinds) { kind in
                        if let url = URL(string: kind.sourceURL) {
                            Link(destination: url) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(kind.displayName)
                                    Text(scope(kind, line: line)).font(.caption)
                                    Text(kind.validFrom.map { start in
                                        start + " – " + (kind.validUntil.flatMap { Dates.addDays($0, -1) } ?? "…")
                                    } ?? (text("reviewed") + " " + kind.observedOn))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if let date = serviceDate {
                        ForEach(catalog.timetableTrips(lineID: line.id, serviceDate: date)) { trip in
                            DisclosureGroup("\(trip.trainType) \(trip.trainNumber) · \(date)") {
                                ForEach(Array(trip.stops.enumerated()), id: \.offset) { _, stop in
                                    Text(localization.stationName(stop.stationName, code: stop.stationCode)
                                        + " · " + times(stop))
                                }
                                ForEach(continuations(for: trip)) { next in
                                    Text(text("continues") + " " + next.trainNumber)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Text(text("timetableNote")).font(.caption).foregroundStyle(.secondary)
                                if let url = URL(string: trip.sourceURL) {
                                    Link(text("timetable"), destination: url)
                                }
                            }
                        }
                    }
                }
            }
            Text(text("partial")).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func continuations(for trip: LineServiceCatalog.TimetableTrip) -> [LineServiceCatalog.TimetableTrip] {
        let referenced = Set(trip.nextTrainIDs ?? [])
        return catalog.trips.filter { next in
            referenced.contains(next.id) && next.serviceDates.contains(where: trip.serviceDates.contains)
                && trip.stops.last?.stationCode == next.stops.first?.stationCode
        }
    }

    private func scope(_ kind: LineServiceCatalog.ServiceKind, line: CompactPackage.Line) -> String {
        guard let fromCode = kind.fromStationCode, let toCode = kind.toStationCode,
              let from = line.stations.first(where: { $0.id == fromCode }),
              let to = line.stations.first(where: { $0.id == toCode }) else { return text("sourceScope") }
        return localization.stationName(from.name, code: fromCode) + " → "
            + localization.stationName(to.name, code: toCode)
    }

    private func times(_ stop: LineServiceCatalog.TimetableTrip.StopTime) -> String {
        [stop.arrivalSeconds, stop.departureSeconds].compactMap { seconds in
            seconds.map { String(format: "%02d:%02d", $0 / 3600, ($0 % 3600) / 60) }
        }.joined(separator: " / ")
    }
}

private struct LocalJourneyStationPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppLocalization.self) private var localization
    let package: CompactPackage
    let onSelect: (String) -> Void
    @State private var query = ""
    @State private var rows: [Row] = []
    @State private var matches: [Row] = []

    struct Row: Identifiable, Sendable {
        var id: String { code }
        let code: String
        let name: String
        let romanizedName: String
        let lines: String
        let searchText: String
    }

    nonisolated private static func stationRows(in package: CompactPackage) -> [Row] {
        var grouped: [String: (CompactPackage.Station, [String])] = [:]
        for line in package.lines {
            let operatorName: String = line.operatorShort ?? line.operator ?? ""
            let label = [operatorName, line.name].filter { !$0.isEmpty }.joined(separator: " · ")
            for station in line.stations {
                if grouped[station.id] == nil { grouped[station.id] = (station, []) }
                if !grouped[station.id]!.1.contains(label) { grouped[station.id]!.1.append(label) }
            }
        }
        var result: [Row] = []
        for (code, value) in grouped {
            let station = value.0
            let lineLabels = value.1
            let romanizedName = station.nameRoma ?? ""
            let searchParts = [station.name, romanizedName, code] + lineLabels
            let searchText = searchParts.joined(separator: " ").folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            result.append(Row(code: code, name: station.name, romanizedName: romanizedName,
                lines: lineLabels.joined(separator: " · "), searchText: searchText))
        }
        return result.sorted { $0.name == $1.name ? $0.code < $1.code : $0.name < $1.name }
    }

    var body: some View {
        List(matches) { row in
            Button {
                onSelect(row.code)
                dismiss()
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(localization.stationName(row.name, code: row.code))
                    Text(row.lines).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .accessibilityIdentifier("localJourneyStation-\(row.code)")
        }
        .navigationTitle(LocalJourneyStrings.text("choose", language: localization.language))
        .searchable(text: $query, prompt: Text(localization.editorText("ios.editor.stationSearch")))
        .task {
            let package = package
            let prepared = await Task.detached(priority: .userInitiated) {
                Self.stationRows(in: package)
            }.value
            guard !Task.isCancelled else { return }
            rows = prepared
            matches = Array(prepared.prefix(100))
        }
        .task(id: query + "|" + String(rows.count)) {
            let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            let rows = rows
            let result = await Task.detached(priority: .userInitiated) {
                Array(rows.lazy.filter { needle.isEmpty || $0.searchText.contains(needle) }.prefix(100))
            }.value
            guard !Task.isCancelled else { return }
            matches = result
        }
    }
}

struct LocalLineServicesSection: View {
    @Environment(AppLocalization.self) private var localization
    let package: CompactPackage
    let lineIDs: [String]
    let serviceDate: String?
    @Binding var trainType: String
    @State private var catalog: LineServiceCatalog?
    @State private var failed = false

    private func text(_ key: String) -> String {
        LocalJourneyStrings.text(key, language: localization.language)
    }
    private var kinds: [LineServiceCatalog.ServiceKind] {
        guard let catalog else { return [] }
        var seen: Set<String> = []
        return lineIDs.flatMap { catalog.serviceKinds(lineID: $0, serviceDate: serviceDate) }
            .filter { seen.insert($0.trainType).inserted }
    }

    var body: some View {
        Section {
            if let catalog {
                if !kinds.isEmpty {
                    Picker(localization.countryText("field.trainType", fallback: "Train type"),
                        selection: $trainType) {
                        if !kinds.contains(where: { $0.trainType == trainType }) {
                            Text(trainType.isEmpty ? text("choose") : trainType).tag(trainType)
                        }
                        ForEach(kinds) { kind in Text(kind.displayName).tag(kind.trainType) }
                    }
                    .accessibilityIdentifier("rideEditorLineServiceType")
                }
                if !lineIDs.isEmpty {
                    LineServiceCatalogView(package: package, lineIDs: lineIDs,
                        catalog: catalog, serviceDate: serviceDate)
                }
                NavigationLink {
                    LocalLineServiceBrowser(package: package, catalog: catalog)
                } label: { Text(text("types")) }
                .accessibilityIdentifier("rideEditorLineServiceDatabase")
            } else if failed {
                Text(text("unknown")).foregroundStyle(.secondary)
            } else { ProgressView() }
        } header: { Text(text("types")) } footer: { Text(text("partial")) }
        .task {
            do {
                let loaded = try await Task.detached(priority: .utility) {
                    try LineServiceCatalog.loadBundled()
                }.value
                guard !Task.isCancelled else { return }
                catalog = loaded
            } catch { failed = true }
        }
    }
}

private struct LocalLineServiceBrowser: View {
    @Environment(AppLocalization.self) private var localization
    let package: CompactPackage
    let catalog: LineServiceCatalog
    @State private var query = ""
    private var lines: [LineServiceCatalog.LineCoverage] {
        catalog.lines.filter { line in
            query.isEmpty || ([line.lineName, line.operatorName] + line.aliases
                + line.kinds.map(\.displayName)).contains { $0.localizedStandardContains(query) }
        }
    }
    var body: some View {
        List(lines) { line in
            NavigationLink {
                List {
                    LineServiceCatalogView(package: package, lineIDs: [line.lineID], catalog: catalog)
                }
                .navigationTitle(line.lineName)
                .navigationBarTitleDisplayMode(.inline)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(line.lineName)
                    Text(line.operatorName).font(.caption).foregroundStyle(.secondary)
                    if line.kinds.isEmpty {
                        Text(LocalJourneyStrings.text("unknown", language: localization.language))
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(Array(Set(line.kinds.map(\.displayName))).sorted().joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(LocalJourneyStrings.text("types", language: localization.language))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query)
    }
}
