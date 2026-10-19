import RailCore
import SwiftUI

/// Browse exact timetable occurrences and route-pattern knowledge from the
/// ride editor. A selected occurrence retains its date, direction, and source;
/// route patterns keep their explicit direction choice.
struct ServicePatternPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let region: String
    @Environment(AppLocalization.self) private var localization
    @State private var rideDate: String?
    let onSelectDate: ((String?) -> Void)?
    @State private var showsDateEditor = false
    @State private var isLoadingTimetable = false
    let onSelectTrip: (TrainTimetableDatabase.Trip) -> Void
    let onSelectDraft: ((TrainTimetableDatabase.Trip) -> Void)?
    let onSelect: (TrainServicePatterns.Pattern, Bool) -> Void

    @State private var query = ""
    @State private var showsAllHistory = false
    @State private var companyFilter: String?
    @State private var lineFilter: String?
    @State private var pendingSelection: Selection?
    @State private var sources: TimetableKnowledgeQuery.ClassifiedSources?
    @State private var inspectedTrip: TrainTimetableDatabase.Trip?
    @State private var showsTrainResearch = false
    @State private var searchSnapshot = SearchSnapshot.empty
    @State private var searchGeneration = 0

    private static let japaneseOpen: Result<TrainTimetableDatabase, TrainTimetableDatabase.OpenFailure> = {
        do { return .success(try TrainTimetableDatabase.bundled()) }
        catch let error as TrainTimetableDatabase.OpenFailure { return .failure(error) }
        catch { return .failure(.damaged(String(describing: error))) }
    }()


    init(
        region: String, rideDate: String?,
        onSelectDate: ((String?) -> Void)? = nil,
        onSelectTrip: @escaping (TrainTimetableDatabase.Trip) -> Void,
        onSelectDraft: ((TrainTimetableDatabase.Trip) -> Void)? = nil,
        onSelect: @escaping (TrainServicePatterns.Pattern, Bool) -> Void
    ) {
        self.region = region
        _rideDate = State(initialValue: rideDate)
        self.onSelectDate = onSelectDate
        self.onSelectTrip = onSelectTrip
        self.onSelectDraft = onSelectDraft
        self.onSelect = onSelect
    }

    private struct Selection: Identifiable {
        let pattern: TrainServicePatterns.Pattern
        let reversed: Bool
        var id: String { "\(pattern.id):\(reversed)" }
    }

    /// Filters that decide which rows are legal to select. Query text is not
    /// one of them: a debounced query may keep the previous rows on screen.
    private typealias SearchFilters = ServicePatternBrowsePolicy.SearchFilters

    private typealias SearchSnapshot = ServicePatternBrowsePolicy.SearchSnapshot

    private struct SearchKey: Hashable {
        let query: String
        let region: String
        let rideDate: String?
        let companyFilter: String?
        let lineFilter: String?
        let showsAllHistory: Bool
        let language: String
        let generation: Int
    }

    private typealias SearchInput = ServicePatternBrowsePolicy.SearchInput

    private var searchKey: SearchKey {
        SearchKey(
            query: query, region: region, rideDate: rideDate,
            companyFilter: companyFilter, lineFilter: lineFilter,
            showsAllHistory: showsAllHistory,
            language: localization.language.rawValue, generation: searchGeneration)
    }

    private var currentFilters: SearchFilters {
        SearchFilters(
            region: region, rideDate: rideDate, companyFilter: companyFilter,
            lineFilter: lineFilter, showsAllHistory: showsAllHistory)
    }

    private var searchSnapshotMatchesGeneration: Bool {
        searchSnapshot.generation == searchGeneration
    }

    private var searchSnapshotMatchesFilters: Bool {
        searchSnapshot.filters == currentFilters
    }

    /// Timetable loading, or the snapshot on screen is not the one for this
    /// generation or these filters. The empty-results row must wait for that
    /// snapshot; otherwise the frame after `loadTimetable` says "no results".
    private var showsSearchLoading: Bool {
        isLoadingTimetable || !searchSnapshotMatchesGeneration || !searchSnapshotMatchesFilters
    }

    /// Stale rows stay visible across a query debounce. They do not stay
    /// tappable across a filter or timetable change.
    private var allowsResultSelection: Bool {
        searchSnapshotMatchesGeneration && searchSnapshotMatchesFilters && !isLoadingTimetable
    }

    private func companyChipTitle(_ identifier: String?, results: ServicePatternBrowsePolicy.SearchSnapshot) -> String {
        guard let identifier else { return pickerText("allCompanies") }
        if let index = results.companyIDs.firstIndex(of: identifier),
           results.companyLabels.indices.contains(index) {
            return results.companyLabels[index]
        }
        return identifier
    }







    var body: some View {
        let results = searchSnapshot
        NavigationStack {
            List {
                Section {
                    Button { showsDateEditor.toggle() } label: {
                        Label(localization.editorText("ios.editor.timetableBrowseDate")
                              + (rideDate.map { ": " + $0 } ?? ""), systemImage: "calendar")
                    }
                    .accessibilityIdentifier("servicePatternDateEditor")
                    if showsDateEditor {
                        EditorDateField(
                            title: localization.editorText("ios.editor.timetableBrowseDate"),
                            date: $rideDate, region: Region(rawValue: region) ?? .jp,
                            accessibilityID: "servicePatternDateInput")
                        Button(localization.editorText("ios.editor.timetableAnyDate")) { rideDate = nil }
                    }
                    Text(localization.editorText("ios.editor.timetableSearchHelp"))
                        .font(.caption).foregroundStyle(.secondary)
                    if showsSearchLoading {
                        ProgressView(localization.editorText("ios.editor.timetableSearching"))
                    }
                    if let rideDate {
                        Toggle(pickerText("showHistory"), isOn: $showsAllHistory)
                            .accessibilityIdentifier("servicePatternHistoryFilter")
                        Text(pickerText("rideDate", ["date": .string(rideDate)]))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(pickerText("dateHelp"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if region != "jp" {
                        Text(pickerText("databaseUnsupported"))
                            .font(.caption).foregroundStyle(.orange)
                    }
                    if region == "jp", let rideDate {
                        timetableStatus(date: rideDate)
                    }
                    switch sources?.patternCatalog {
                    case .missing:
                        Text(pickerText("patternCatalogMissing"))
                            .font(.caption).foregroundStyle(.orange)
                    case .damaged:
                        Text(pickerText("patternCatalogDamaged"))
                            .font(.caption).foregroundStyle(.orange)
                    case .loaded, .notApplicable, nil:
                        EmptyView()
                    }

                    HStack {
                        Menu {
                            Button(pickerText("allCompanies")) { companyFilter = nil }
                            ForEach(Array(results.companyIDs.enumerated()), id: \.element) { index, identifier in
                                Button(results.companyLabels[index]) { companyFilter = identifier }
                            }
                        } label: {
                            Label(companyChipTitle(companyFilter, results: results), systemImage: "building.2")
                        }
                        .railMenuButtonStyle()
                        .accessibilityIdentifier("servicePatternCompanyFilter")

                        Spacer()

                        Menu {
                            Button(pickerText("allLines")) { lineFilter = nil }
                            ForEach(results.lineNames, id: \.self) { line in
                                Button(line) { lineFilter = line }
                            }
                        } label: {
                            Label(lineFilter ?? pickerText("allLines"), systemImage: "arrow.triangle.swap")
                        }
                        .railMenuButtonStyle()
                        .accessibilityIdentifier("servicePatternLineFilter")
                    }
                }
                Section {
                    Button { showsTrainResearch = true } label: {
                        Label(localization.text("ios.ai.researchTitle", fallback: "Ask ChatGPT about a train"),
                              systemImage: "sparkles")
                    }
                    .accessibilityIdentifier("servicePatternChatGPTQuery")
                }
                if searchSnapshotMatchesGeneration {
                    ForEach(results.groups, id: \.name) { group in
                        let title = results.primaryRowsArePatterns
                            ? "\(pickerText("patternKind")) · \(group.name) · \(group.companyLabel)"
                            : "\(group.name) · \(group.companyLabel)"
                        Section(header: Text(title)) {
                            ForEach(group.rows) { row in
                                switch row {
                                case .occurrence(let trip):
                                    Button { select(trip) } label: { tripRow(trip) }
                                        .disabled(!allowsResultSelection)
                                case .pattern(let pattern):
                                    patternRow(pattern)
                                }
                            }
                        }
                    }
                    if !results.incompleteTrips.isEmpty {
                        Section(localization.editorText("ios.editor.timetablePublishedDraft")) {
                            ForEach(results.incompleteTrips) { trip in
                                VStack(alignment: .leading, spacing: 8) {
                                    tripRow(trip)
                                    Button(pickerText("reviewStops")) { inspectedTrip = trip }
                                        .buttonStyle(.borderless)
                                        .disabled(!allowsResultSelection)
                                        .accessibilityIdentifier("timetableDetails-\(trip.id)")
                                }
                            }
                        }
                    }
                    if !results.unknownPatterns.isEmpty {
                        Section(pickerText("legacy")) {
                            ForEach(results.unknownPatterns) { pattern in patternRow(pattern) }
                        }
                    }
                    if !results.outsidePatterns.isEmpty {
                        Section(pickerText("outside")) {
                            ForEach(results.outsidePatterns) { pattern in patternRow(pattern) }
                        }
                    }
                }
                if allowsResultSelection && sources?.availability.isHardFailure != true
                    && results.groups.isEmpty && results.incompleteTrips.isEmpty
                    && results.unknownPatterns.isEmpty && results.outsidePatterns.isEmpty
                {
                    Text(sources?.isLegalZero == true
                         ? pickerText("noServices")
                         : pickerText("noPatterns"))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("servicePatternList")
            .navigationTitle(pickerText("title"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: Text(localization.editorText("ios.editor.timetableSearchPrompt")))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(pickerText("cancel")) { dismiss() }
                }
            }
            .task(id: "\(region):\(rideDate ?? "")") { await loadTimetable() }
            .task(id: searchKey) { await updateSearchSnapshot() }
            .sheet(isPresented: $showsTrainResearch) {
                TrainResearchView(region: region, query: query, rideDate: rideDate)
            }
            .sheet(item: $inspectedTrip) { trip in
                TimetableTripDetailView(trip: trip, onUseDraft: onSelectDraft == nil ? nil : { chosen in
                    onSelectDate?(chosen.serviceDate)
                    onSelectDraft?(chosen)
                    inspectedTrip = nil
                    dismiss()
                })
            }
            .confirmationDialog(
                pickerText("outsideConfirm"),
                isPresented: Binding(get: { pendingSelection != nil },
                                     set: { if !$0 { pendingSelection = nil } }),
                titleVisibility: .visible
            ) {
                Button(pickerText("confirmApply")) {
                    guard let selection = pendingSelection else { return }
                    apply(selection)
                }
                Button(pickerText("cancel"), role: .cancel) { pendingSelection = nil }
            }
        }
    }

    private func pickerText(_ key: String, _ params: [String: Localization.Param]? = nil) -> String {
        localization.editorText("ios.editor.pattern." + key, params)
    }

    private func patternRow(_ pattern: TrainServicePatterns.Pattern) -> some View {
        HStack(spacing: 0) {
            Button { select(pattern, reversed: false) } label: { row(for: pattern) }
            Button { select(pattern, reversed: true) } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(pickerText("reverse", ["from": .string(pattern.destination), "to": .string(pattern.origin)]))
        }
        .frame(minHeight: 44)
        .disabled(!allowsResultSelection)
    }

    private func select(_ trip: TrainTimetableDatabase.Trip) {
        onSelectDate?(trip.serviceDate)
        onSelectTrip(trip)
        dismiss()
    }

    private func select(_ pattern: TrainServicePatterns.Pattern, reversed: Bool) {
        let selection = Selection(pattern: pattern, reversed: reversed)
        if let rideDate, pattern.applicability(on: rideDate) == .notApplicable {
            pendingSelection = selection
        } else {
            apply(selection)
        }
    }

    private func apply(_ selection: Selection) {
        onSelectDate?(rideDate)
        onSelect(selection.pattern, selection.reversed)
        pendingSelection = nil
        dismiss()
    }

    private func row(for pattern: TrainServicePatterns.Pattern) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(pattern.label)
                if pattern.confidence == "low" {
                    Text(pickerText("needsReview"))
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .clipShape(Capsule())
                }
                if let rideDate, let applicability = pattern.applicability(on: rideDate),
                   applicability != .applicable {
                    Text(applicability == .unknown ? pickerText("validityUnknown") : pickerText("notApplicable"))
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.2))
                        .clipShape(Capsule())
                }
                if pattern.completeness.stops != .complete
                    || pattern.completeness.lines != .complete
                    || pattern.completeness.validity != .complete
                {
                    Text(pickerText("completeness", ["stops": .string(mark(pattern.completeness.stops)), "route": .string(mark(pattern.completeness.lines)), "dates": .string(mark(pattern.completeness.validity))]))
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            Text(pickerText("stations", ["from": .string(pattern.origin), "to": .string(pattern.destination), "count": .number(Double(pattern.stops.count))]))
                .font(.caption)
                .foregroundStyle(.secondary)
            if pattern.validFrom != nil || pattern.validUntil != nil {
                Text(validityCaption(for: pattern))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !pattern.lines.isEmpty {
                Text(pickerText("via", ["lines": .string(pattern.lines.joined(separator: "・"))]))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !pattern.optionalStops.isEmpty {
                Text(pickerText("optionalStops", ["stations": .string(pattern.optionalStops.joined(separator: "、"))]))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func tripRow(_ trip: TrainTimetableDatabase.Trip) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text([trip.service.canonicalName, trip.publicNumber ?? trip.trainNumber]
                .filter { !$0.isEmpty }.joined(separator: " "))
            if let englishName = trip.service.englishName {
                Text(englishName).font(.caption).foregroundStyle(.secondary)
            }
            Text(pickerText(trip.factCompleteness["stops"] == .verified ? "stations" : "publishedStations", [
                "from": .string(trip.origin?.station.name ?? "?"),
                "to": .string(trip.destination?.station.name ?? "?"),
                "count": .number(Double(trip.passengerStops.count)),
            ]))
                .font(.caption).foregroundStyle(.secondary)
            if let departure = trip.origin?.departureTime ?? trip.origin?.arrivalTime {
                Text(pickerText("firstDeparture", ["time": .string(departure)])).font(.caption2).foregroundStyle(.secondary)
            }
            Text(trip.timetableEditionName).font(.caption2).foregroundStyle(.secondary)
            if !trip.canApplyToRouteEditor {
                let missing = [
                    "operator", "validity_calendar", "stops", "times", "route_lines", "station_refs", "provenance",
                ].compactMap { key in
                    trip.factCompleteness[key] == .verified ? nil : pickerText("fact." + key)
                }
                Text(pickerText("unverifiedFacts", ["facts": .string(missing.joined(separator: "・"))]))
                    .font(.caption2).foregroundStyle(.orange)
            } else if !trip.lineSegments.isEmpty {
                Text(pickerText("via", ["lines": .string(trip.lineSegments.map(\.lineName).joined(separator: "・"))]))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(trip.canApplyToRouteEditor
            ? "timetableTrip-\(trip.id)" : "timetableIncompleteTrip-\(trip.id)")
        .accessibilityHint(localization.editorText("ios.editor.timetableMatchNote"))
    }

    private func validityCaption(for pattern: TrainServicePatterns.Pattern) -> String {
        let from = pattern.validFrom ?? "?"
        if let until = pattern.validUntil {
            return pickerText("validUntil", ["from": .string(from), "until": .string(until)])
        }
        return "\(from)〜"
    }

    private func mark(_ level: TrainServicePatterns.Pattern.Level) -> String {
        switch level {
        case .complete: "✓"
        case .partial: "△"
        case .missing: "?"
        }
    }

    @ViewBuilder private func timetableStatus(date: String) -> some View {
        switch sources?.availability {
        case .missing:
            Text(pickerText("databaseMissing"))
                .font(.caption).foregroundStyle(.orange)
        case .damaged:
            Text(pickerText("databaseDamaged"))
                .font(.caption).foregroundStyle(.orange)
        case .queryFailed:
            Text(pickerText("databaseQueryFailed"))
                .font(.caption).foregroundStyle(.orange)
        case .unsupported:
            Text(pickerText("databaseUnsupported"))
                .font(.caption).foregroundStyle(.orange)
        case .notRequested, nil:
            EmptyView()
        case .ready:
            readyTimetableStatus(date: date)
        }
    }

    @ViewBuilder private func readyTimetableStatus(date: String) -> some View {
        if let sources, case .ready(let coverage) = sources.availability {
            let incompleteCount = sources.occurrences.filter { !$0.canApplyToRouteEditor }.count
            if coverage == .conflict {
                Text(pickerText("conflict", ["date": .string(date)]))
                    .font(.caption).foregroundStyle(.orange)
            } else if sources.isLegalZero {
                Text(pickerText("noJRServices", ["date": .string(date)]))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                if coverage == .partial || coverage == .unknown {
                    Text(pickerText("inventoryIncomplete", ["date": .string(date)]))
                        .font(.caption).foregroundStyle(.orange)
                        .accessibilityIdentifier("timetableInventoryIncomplete")
                }
                if incompleteCount > 0 {
                    Text(pickerText("routesIncomplete", ["total": .number(Double(sources.occurrences.count)), "incomplete": .number(Double(incompleteCount))]))
                        .font(.caption).foregroundStyle(.orange)
                        .accessibilityIdentifier("timetableTripsNotApplicable")
                }
                if coverage == .verified && incompleteCount == 0 && !sources.occurrences.isEmpty {
                    Text(pickerText("dailyNumbers", ["date": .string(date)]))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    @MainActor private func loadTimetable() async {
        isLoadingTimetable = true
        defer { if !Task.isCancelled { isLoadingTimetable = false } }
        sources = nil
        searchGeneration += 1
        let country = region
        let serviceDate = rideDate
        let opened = Self.japaneseOpen
        let classified = await Task.detached(priority: .userInitiated) {
            TimetableKnowledgeQuery.sources(
                country: country, serviceDate: serviceDate, database: opened)
        }.value
        guard !Task.isCancelled else { return }
        sources = classified
        searchGeneration += 1
    }

    @MainActor private func updateSearchSnapshot() async {
        let queryIsEmpty = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !queryIsEmpty {
            do { try await Task.sleep(for: .milliseconds(150)) }
            catch { return }
        }
        guard !Task.isCancelled else { return }
        guard let sources else { return }
        let input = SearchInput(
            query: query, region: region, rideDate: rideDate,
            companyFilter: companyFilter, lineFilter: lineFilter,
            showsAllHistory: showsAllHistory, language: localization.language.rawValue,
            sources: sources,
            generation: searchGeneration)
        // An empty query is the list the reader is already looking at. Hopping
        // it off the main actor leaves a frame of the previous snapshot.
        let snapshot: SearchSnapshot
        if queryIsEmpty {
            snapshot = ServicePatternBrowsePolicy.makeSearchSnapshot(input)
        } else {
            snapshot = await Task.detached(priority: .userInitiated) {
                ServicePatternBrowsePolicy.makeSearchSnapshot(input)
            }.value
        }
        guard !Task.isCancelled else { return }
        guard snapshot.generation == searchGeneration,
              snapshot.filters == currentFilters else { return }
        searchSnapshot = snapshot
    }
}
