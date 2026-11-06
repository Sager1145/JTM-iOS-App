import RailCore
import SwiftUI
import UIKit

enum StationCatalogText {
    static func subtitle(
        for station: CatalogStation, catalog: EditorCatalog, operators: [String: String]
    ) -> String {
        let memberships = catalog.memberships(stationKey: station.key)
        let labels = memberships.prefix(3).map { member -> String in
            guard let line = catalog.line(id: member.lineID, regionCode: member.regionCode) else {
                return member.lineID
            }
            if let name = line.operatorIDs.compactMap({ operators[$0] }).first(where: { !$0.isEmpty }) {
                return "\(line.name) · \(name)"
            }
            return line.name
        }
        var text = labels.joined(separator: " · ")
        if memberships.count > 3 { text += " · +\(memberships.count - 3)" }
        return text
    }

    /// Tokens in the old `line · operator` subtitle that the round-trip qualifier
    /// does not already show. Empty means that subtitle would only repeat the qualifier.
    static func detailBeyondQualifier(_ legacy: String, qualifier: String) -> String {
        legacy.components(separatedBy: " · ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { token in
                !token.isEmpty && !token.hasPrefix("+") && !qualifier.contains(token)
            }
            .joined(separator: " · ")
    }

    static func rows(catalog: EditorCatalog, regionCode: String) -> [CatalogStationRow] {
        let operators = Dictionary(
            uniqueKeysWithValues: catalog.operators(in: regionCode).map { ($0.id, $0.name) })
        return catalog.stations(in: regionCode).map { station in
            CatalogStationRow(
                station: station,
                subtitle: subtitle(for: station, catalog: catalog, operators: operators))
        }
    }
}

private struct CatalogStationLineGroup: Identifiable, Sendable {
    var line: CatalogLine
    var operatorID: String
    var operatorName: String
    var rows: [CatalogStationRow]
    var id: String { line.id }
}

private struct CatalogStationCompanyGroup: Identifiable {
    var id: String
    var name: String
    var lines: [CatalogStationLineGroup]
}

/// What the shared engine read from the picker's text, as the picker shows it.
private struct PickerHints: Equatable {
    struct Filter: Equatable, Identifiable {
        enum Kind: Equatable { case company, line }
        var kind: Kind
        /// `CatalogOperator.id` or `CatalogLine.id`.
        var id: String
        var title: String
    }

    var suggested: [Filter] = []
    var residualText: String?
    var didYouMean: String?
}

/// Catalog stations for one region. Empty search is a company → line → station
/// browser. Search results keep those categories instead of flattening stations
/// with the same display name into one ambiguous list.
struct StationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppLocalization.self) private var localization
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let regionCode: String
    var selectedLineIDs: Set<String> = []
    var onSelect: ((CatalogStation, String?) -> Void)? = nil
    var rideDate: String? = nil
    var onSelectRetired: ((RetiredStation) -> Void)? = nil
    var sourceCatalog: EditorCatalog? = nil
    var companyFilter: String? = nil
    var onSelectWithLine: ((CatalogStation, CatalogLine?, String?) -> Void)? = nil
    /// A stop keeps free text; only its suggestions use the shared picker.
    var inlineQuery: Binding<String>? = nil
    var showsSuggestions = true
    var onLoad: ((EditorCatalog?, [RetiredStation], [String: String]) -> Void)? = nil
    var accessibilityPrefix = "rideEditorStation"
    @State private var query = ""
    /// Company, then optionally one of its lines. Both narrow the results
    /// and the map; a line also lists its stations in route order.
    @State private var filterOperatorID: String?
    @State private var filterLineID: String?
    /// Operators of this region, most ridden first. Built once per load from
    /// the catalog's own operator → line index.
    @State private var filterOperators: [CatalogOperator] = []
    @State private var operatorLabels: [String: String] = [:]
    @State private var riddenByLine: [String: Int] = [:]
    @State private var lineFitRevision = 0
    /// Filter results, computed once per filter change rather than per render.
    @State private var filterLines: [CatalogLine] = []
    @State private var mapStations: [CatalogStation] = []
    @State private var mapStationsRevision = 0
    @State private var filterMapContent = TripMapContent()
    @State private var lineRows: [CatalogStationRow] = []
    @State private var hints = PickerHints()
    /// The text a reader typed before an applied filter took its keywords,
    /// restored when that chip is removed.
    @State private var textBeforeAppliedFilter: String?
    /// Text whose filters the reader removed; it is not applied again.
    @State private var declinedFilterText: String?
    /// The residual text an applied filter wrote into the field. Clearing the
    /// filter restores `textBeforeAppliedFilter` only while the field still
    /// holds exactly this.
    @State private var writtenResidual: String?
    /// The latest engine response, re-read when search is submitted.
    @State private var latestResponse: SearchResponse?
    @State private var search = StationPickerSearchController()
    @State private var catalog: EditorCatalog?
    @State private var retiredByID: [String: RetiredStation] = [:]
    @State private var subtitleByCode: [String: String] = [:]
    /// Copy text per station, filled only for rows that are actually shown.
    /// Each label scans every same-named station in the region, so computing
    /// all of them up front was quadratic and held the picker on its spinner.
    @State private var copyLabels = CopyLabelMemo()
    @State private var lineLabelByID: [String: String] = [:]
    @State private var didLoad = false
    @State private var loadError: String?
    /// Every station of the region, for tapping on the map above the list.
    @State private var allStations: [CatalogStation] = []

    private var queryBinding: Binding<String> { inlineQuery ?? $query }
    private var searchText: String { queryBinding.wrappedValue }
    private var loadToken: String {
        "\(regionCode)|\(selectedLineIDs.sorted().joined(separator: ","))|\(rideDate ?? "")|\(onSelectRetired != nil)"
    }
    /// Saved rides, to rank companies and lines by use. Optional: the picker
    /// also works where no store is in the environment.
    @Environment(ItineraryStore.self) private var itineraries: ItineraryStore?

    private var operatorNames: [String: String] {
        guard let catalog else { return [:] }
        return Dictionary(
            uniqueKeysWithValues: catalog.operators(in: regionCode).map { ($0.id, $0.name) })
    }

    private var lineGroups: [CatalogStationLineGroup] {
        guard let catalog else { return [] }
        return search.output.lines.compactMap { line in
            let rows = line.hits.compactMap { hit -> CatalogStationRow? in
                guard case .current(let key, _) = hit.subject,
                      let station = catalog.station(key) else { return nil }
                let detail = lineLabelByID[line.id] ?? ""
                let caption = detail.isEmpty
                    ? (subtitleByCode[station.key.sourceCode] ?? "")
                    : StationLabel.caption(countryCode: regionCode.uppercased(), detail: detail)
                let legacy = StationCatalogText.subtitle(
                    for: station, catalog: catalog, operators: operatorNames)
                let copy = StationReferenceResolution.copyLabel(
                    for: station, catalog: catalog, preferredLineID: line.id)
                return CatalogStationRow(
                    station: station, subtitle: caption,
                    detail: StationCatalogText.detailBeyondQualifier(legacy, qualifier: caption),
                    copyText: copy, stationID: hit.stationID,
                    match: search.matches[station.key.sourceCode])
            }
            guard !rows.isEmpty,
                  let catalogLine = catalog.line(id: line.id, regionCode: regionCode) else { return nil }
            return CatalogStationLineGroup(line: catalogLine, operatorID: line.operatorID,
                                           operatorName: line.operatorName, rows: rows)
        }
    }
    private var suggestions: [CatalogStationRow] {
        guard let catalog else { return [] }
        return search.output.suggestions.flatMap { hit -> [CatalogStationRow] in
            if hit.stationIDs.count > 1 {
                return rows(stationIDs: Set(hit.stationIDs), qualifier: hit.qualifier)
            }
            guard case .current(let key, _) = hit.subject,
                  let station = catalog.station(key) else { return [] }
            return [CatalogStationRow(
                station: station,
                subtitle: hit.qualifier ?? subtitleByCode[key.sourceCode] ?? "",
                copyText: copyLabels.label(for: station, catalog: catalog),
                stationID: hit.stationID, match: search.matches[key.sourceCode])]
        }
    }

    /// Line rows for a complex that contains more than one company station.
    /// The grouped suggestion stays one row in the index; the picker lists each id.
    private func rows(stationIDs: Set<String>, qualifier: String?) -> [CatalogStationRow] {
        guard let catalog else { return [] }
        var seen: Set<String> = []
        var rows: [CatalogStationRow] = []
        for line in search.output.lines {
            for hit in line.hits {
                guard let stationID = hit.stationID, stationIDs.contains(stationID),
                      seen.insert(stationID).inserted,
                      case .current(let key, _) = hit.subject,
                      let station = catalog.station(key) else { continue }
                rows.append(CatalogStationRow(
                    station: station,
                    subtitle: qualifier ?? subtitleByCode[key.sourceCode] ?? "",
                    copyText: copyLabels.label(for: station, catalog: catalog),
                    stationID: stationID, match: search.matches[key.sourceCode]))
            }
        }
        return rows
    }
    private var retiredStations: [RetiredStation] {
        search.output.retired.compactMap { hit in
            guard case .retired(let id) = hit.subject else { return nil }
            return retiredByID[id]
        }
    }
    private var companyGroups: [CatalogStationCompanyGroup] {
        Dictionary(grouping: lineGroups, by: \.operatorID).map { operatorID, lines in
            CatalogStationCompanyGroup(id: operatorID,
                name: lines.first.map { JourneyBranding.companyText($0.operatorName) } ?? localization.countryText("field.company", fallback: "Operator"),
                lines: lines)
        }.sorted {
            if $0.name != $1.name { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return $0.id < $1.id
        }
    }
    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Group {
            if inlineQuery != nil {
                if let loadError {
                    Text(loadError).font(.footnote).foregroundStyle(.secondary)
                } else if showsSuggestions && isSearching {
                    ForEach(suggestions) { row in stationButton(row) }
                    ForEach(retiredStations) { station in retiredStationButton(station) }
                }
            } else {
                browser
                    .navigationTitle(localization.text("ios.editor.chooseStation"))
                    .navigationBarTitleDisplayMode(.inline)
                    .searchable(text: queryBinding, placement: .navigationBarDrawer(displayMode: .always),
                                prompt: Text(localization.text("ios.editor.stationSearch")))
                    .onSubmit(of: .search) { readHints(latestResponse ?? search.output.response, submitted: true) }
                    .toolbar {
                        if onSelectWithLine != nil {
                            ToolbarItem(placement: .cancellationAction) {
                                Button(localization.text("ios.newTrip.cancel", fallback: "Cancel")) { dismiss() }
                            }
                        }
                    }
            }
        }
        .task(id: loadToken) { await load() }
        .onChange(of: searchText) { _, needle in
            search.apply(query: needle, companyName: nil)
            if needle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { hints = PickerHints() }
        }
        .onChange(of: search.output.response) { _, response in
            latestResponse = response
            readHints(response)
        }
        .onChange(of: filterOperatorID) { _, _ in refreshFilterState() }
        .onChange(of: filterLineID) { _, _ in
            lineFitRevision += 1
            refreshFilterState()
        }
        .onDisappear { search.cancel() }
    }

    @ViewBuilder private var browser: some View {
        if let loadError {
            Text(loadError).foregroundStyle(.secondary).padding()
        } else if !didLoad {
            ProgressView()
        } else {
            VStack(spacing: 0) {
                if !isSearching { mapHeader }
                filterChips
                list
            }
        }
    }

    /// The same map the journey editor uses: zoom in and tap a station.
    private var mapHeader: some View {
        TripMapView(
            regionCode: regionCode,
            stations: mapStations,
            content: filterMapContent,
            reduceMotion: reduceMotion,
            onStation: { station in
                recordPick(station)
                if let onSelectWithLine { onSelectWithLine(station, nil, nil) }
                else { onSelect?(station, nil) }
                dismiss()
            },
            onRoute: { _ in },
            onBackground: {},
            onZoomChange: { _ in },
            onRegionChange: { rect in search.setSignals(visibleRegion: rect) },
            showsAllStations: filterOperatorID != nil,
            stationsRevision: mapStationsRevision)
            .overlay(alignment: .top) {
                Text(localization.text("ios.newTrip.pickOnMap", fallback: "Tap a station on the map, or search"))
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 8)
                    .allowsHitTesting(false)
            }
            .frame(height: 220)
            .accessibilityIdentifier("stationPickerMap")
    }

    private var list: some View {
            List {
                if let line = filterLineID.flatMap({ catalog?.line(id: $0, regionCode: regionCode) }), !isSearching {
                    Section(line.name) {
                        ForEach(lineRows) { row in stationButton(row, line: line) }
                    }
                } else if isSearching {
                    ForEach(filteredLineGroups) { group in
                        Section {
                            ForEach(group.rows) { row in stationButton(row, line: group.line) }
                        } header: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.operatorName)
                                Text(group.line.name).font(.caption)
                            }
                        }
                    }
                    ForEach(retiredStations) { station in retiredStationButton(station) }
                    if filteredLineGroups.isEmpty && retiredStations.isEmpty {
                        Text(localization.text("ios.editor.stationUnmatched")).foregroundStyle(.secondary)
                    }
                } else if onSelectWithLine != nil, filterOperatorID == nil {
                    Text(localization.text("ios.newTrip.searchPrompt", fallback: "Search by station, line or company"))
                        .foregroundStyle(.secondary)
                } else {
                    if filterOperatorID != nil {
                        // The company's lines: choosing one lists its stations in order.
                        ForEach(filterLines, id: \.id) { line in
                            Button { filterLineID = line.id } label: {
                                Text(line.name).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }
                            .accessibilityIdentifier("stationPickerFilterLine-\(line.id)")
                        }
                    }
                    ForEach(filterOperatorID == nil ? companyGroups : []) { company in
                        Section(company.name) {
                            ForEach(company.lines) { group in
                                NavigationLink {
                                    StationLinePickerView(title: group.line.name, rows: group.rows,
                                                          accessibilityPrefix: accessibilityPrefix) { row in
                                        select(row, line: group.line)
                                    }
                                } label: {
                                    Text(group.line.name).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                }
                                .accessibilityIdentifier("rideEditorStationLine-\(group.line.id)")
                            }
                        }
                    }
                    if !retiredStations.isEmpty {
                        Section(localization.text("ios.editor.retiredStationsSection")) {
                            ForEach(retiredStations) { station in retiredStationButton(station) }
                        }
                    }
                }
            }
    }

    // MARK: - company and line filter

    /// Search results on the chosen company's lines, or on the chosen line.
    private var filteredLineGroups: [CatalogStationLineGroup] {
        guard let filterOperatorID else { return lineGroups }
        let lineIDs = filterLineID.map { Set([$0]) } ?? Set(filterLines.map(\.id))
        return lineGroups.filter { lineIDs.contains($0.line.id) }
    }

    private func operatorLabel(_ op: CatalogOperator) -> String {
        operatorLabels[op.id] ?? op.shortName ?? op.name
    }

    /// Recomputes what the filters show. Runs when a filter changes.
    private func refreshFilterState() {
        filterLines = computeFilterLines()
        mapStations = computeMapStations()
        mapStationsRevision += 1
        filterMapContent = computeFilterMapContent()
        lineRows = filterLineID.flatMap { catalog?.line(id: $0, regionCode: regionCode) }.map(lineStationRows) ?? []
    }

    /// The chosen company's lines, most ridden first, then by name.
    private func computeFilterLines() -> [CatalogLine] {
        guard let filterOperatorID, let catalog else { return [] }
        return catalog.lines(operatorID: filterOperatorID)
            .filter { $0.regionCode == regionCode }
            .sorted {
                let lhs = riddenByLine[$0.id] ?? 0
                let rhs = riddenByLine[$1.id] ?? 0
                if lhs != rhs { return lhs > rhs }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    /// A line's stations in route order, ready to pick without typing. A
    /// loop's closing station is listed once. The company station is resolved
    /// from the code when the stop is written, as for a map pick.
    private func lineStationRows(_ line: CatalogLine) -> [CatalogStationRow] {
        guard let catalog else { return [] }
        var seen: Set<StationKey> = []
        return catalog.memberships(lineID: line.id, regionCode: regionCode)
            .sorted { $0.sequence < $1.sequence }
            .compactMap { membership in
                guard seen.insert(membership.stationKey).inserted,
                      let station = catalog.station(membership.stationKey) else { return nil }
                return CatalogStationRow(
                    station: station, subtitle: subtitleByCode[station.key.sourceCode] ?? "",
                    copyText: copyLabels.label(for: station, catalog: catalog),
                    stationID: nil)
            }
    }

    /// Stations the map offers: the chosen line's, the company's, or all.
    private func computeMapStations() -> [CatalogStation] {
        guard let catalog, let filterOperatorID else { return allStations }
        let lineIDs = filterLineID.map { [$0] } ?? catalog.lines(operatorID: filterOperatorID).map(\.id)
        var seen: Set<StationKey> = []
        return lineIDs.flatMap { catalog.memberships(lineID: $0, regionCode: regionCode) }
            .compactMap { seen.insert($0.stationKey).inserted ? catalog.station($0.stationKey) : nil }
    }

    /// The chosen line drawn through its stations, so the camera frames it.
    private func computeFilterMapContent() -> TripMapContent {
        guard let catalog, let filterLineID else { return TripMapContent() }
        let coordinates = catalog.memberships(lineID: filterLineID, regionCode: regionCode)
            .sorted { $0.sequence < $1.sequence }
            .map { AppleMapDatum.display(Coordinate(lon: $0.longitude, lat: $0.latitude), country: regionCode).clLocation }
        guard coordinates.count >= 2 else { return TripMapContent() }
        let route = TripMapContent.Route(
            id: filterLineID,
            pieces: [.init(coordinates: coordinates, colorHex: nil, isConnector: false)],
            isSelected: false)
        return TripMapContent(routes: [route], marks: [], fitRevision: lineFitRevision)
    }

    /// Filters and corrections the shared engine read from the text. Only the
    /// response for the text now in the field counts; it names ids that exist
    /// in this picker's catalog.
    private func readHints(_ response: SearchResponse?, submitted: Bool = false) {
        // The inline field is the stop's saved name: search never rewrites it
        // and never applies filters from it.
        if inlineQuery != nil {
            if hints != PickerHints() { hints = PickerHints() }
            return
        }
        let typed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let catalog, let response, !typed.isEmpty,
              response.query.trimmingCharacters(in: .whitespacesAndNewlines) == typed else {
            hints = PickerHints()
            return
        }
        let operatorIDs = Set(catalog.operators(in: regionCode).map(\.id))
        func known(_ filters: [SearchFilter]) -> [PickerHints.Filter] {
            filters.compactMap { filter in
                switch filter.entity.kind {
                case .company:
                    guard operatorIDs.contains(filter.entity.id) else { return nil }
                    return PickerHints.Filter(kind: .company, id: filter.entity.id, title: filter.title)
                case .line:
                    guard catalog.line(id: filter.entity.id, regionCode: regionCode) != nil else { return nil }
                    return PickerHints.Filter(kind: .line, id: filter.entity.id, title: filter.title)
                default: return nil
                }
            }
        }
        var applied = known(response.parsed.applied)
        var suggested = known(response.parsed.suggested)
        if !selectedLineIDs.isEmpty {
            let selectedLines = catalog.lines(in: regionCode).filter { selectedLineIDs.contains($0.id) }
            let allowedOperators = Set(selectedLines.flatMap(\.operatorIDs))
            func allowed(_ filter: PickerHints.Filter) -> Bool {
                switch filter.kind {
                case .company: allowedOperators.contains(filter.id)
                case .line: selectedLineIDs.contains(filter.id)
                }
            }
            applied = applied.filter(allowed)
            suggested = suggested.filter(allowed)
        }
        // Only a finished token (trailing space) or a submit applies filters.
        let finishedToken = searchText.last?.isWhitespace == true
        if !(finishedToken || submitted) {
            suggested = applied + suggested
            applied = []
        }
        // A query that names a station exactly is a station search, even when
        // a company or line shares the name (横浜, 京急 etc.): offer the filter,
        // do not swap the station out for it.
        if response.results.contains(where: { $0.entity.kind == .station && $0.match.kind == .exact }) {
            suggested = applied + suggested
            applied = []
        }
        if declinedFilterText == typed {
            suggested = applied + suggested
            applied = []
        } else {
            declinedFilterText = nil
        }
        hints = PickerHints(
            suggested: suggested,
            residualText: response.parsed.residualText,
            didYouMean: response.didYouMean.map(\.text))
        guard !applied.isEmpty else { return }
        textBeforeAppliedFilter = searchText
        writtenResidual = response.parsed.residualText
        for filter in applied {
            switch filter.kind {
            case .company: filterOperatorID = filter.id
            case .line:
                if filterOperatorID == nil {
                    filterOperatorID = catalog.line(id: filter.id, regionCode: regionCode)?.operatorIDs.first
                }
                filterLineID = filter.id
            }
        }
        queryBinding.wrappedValue = response.parsed.residualText
    }

    private func apply(_ filter: PickerHints.Filter) {
        switch filter.kind {
        case .company:
            filterOperatorID = filter.id
            filterLineID = nil
        case .line:
            filterOperatorID = catalog?.line(id: filter.id, regionCode: regionCode)?.operatorIDs.first
            filterLineID = filter.id
        }
        if let residual = hints.residualText {
            textBeforeAppliedFilter = searchText
            writtenResidual = residual
            queryBinding.wrappedValue = residual
        }
        hints.suggested = []
    }

    @ViewBuilder private var hintRows: some View {
        if !hints.suggested.isEmpty || hints.didYouMean != nil {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let correction = hints.didYouMean {
                        Button {
                            queryBinding.wrappedValue = correction
                        } label: {
                            Text(localization.text("ios.newTrip.didYouMean", params: ["text": .string(correction)],
                                                   fallback: "Did you mean {text}?"))
                                .font(.subheadline)
                                .frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("stationPickerDidYouMean")
                    }
                    ForEach(hints.suggested) { filter in
                        Button { apply(filter) } label: { chip(filter.title, active: false) }
                            .accessibilityIdentifier("stationPickerSuggestedFilter-\(filter.id)")
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder private var filterChips: some View {
        hintRows
        if !filterOperators.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Menu {
                        ForEach(filterOperators, id: \.id) { op in
                            Button(operatorLabel(op)) {
                                filterOperatorID = op.id
                                filterLineID = nil
                            }
                        }
                    } label: {
                        chip(filterOperators.first { $0.id == filterOperatorID }.map(operatorLabel)
                             ?? localization.text("ios.newTrip.filterCompany", fallback: "Company"),
                             active: filterOperatorID != nil)
                    }
                    .accessibilityIdentifier("stationPickerCompanyFilter")
                    if filterOperatorID != nil, !filterLines.isEmpty {
                        Menu {
                            ForEach(filterLines, id: \.id) { line in
                                Button(line.name) { filterLineID = line.id }
                            }
                        } label: {
                            chip(filterLines.first { $0.id == filterLineID }?.name
                                 ?? localization.text("ios.newTrip.filterLine", fallback: "Line"),
                                 active: filterLineID != nil)
                        }
                        .accessibilityIdentifier("stationPickerLineFilter")
                    }
                    if filterOperatorID != nil {
                        Button {
                            filterOperatorID = nil
                            filterLineID = nil
                            // A filter the search applied gives its words back.
                            if let typed = textBeforeAppliedFilter {
                                textBeforeAppliedFilter = nil
                                // Restore only if the reader has not edited the residual since.
                                if searchText == writtenResidual {
                                    declinedFilterText = typed.trimmingCharacters(in: .whitespacesAndNewlines)
                                    queryBinding.wrappedValue = typed
                                }
                                writtenResidual = nil
                            }
                        } label: {
                            Label(localization.text("ios.newTrip.filterClear", fallback: "Clear filters"),
                                  systemImage: "xmark.circle.fill")
                                .labelStyle(.iconOnly)
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .accessibilityIdentifier("stationPickerClearFilters")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
    }

    private func chip(_ title: String, active: Bool) -> some View {
        HStack(spacing: 4) {
            Text(title).lineLimit(1)
            Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
        }
        .font(.subheadline.weight(active ? .semibold : .regular))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .foregroundStyle(active ? Color.white : Color.primary)
        .background(active ? Color.accentColor : Color(.tertiarySystemFill), in: Capsule())
        .frame(minHeight: 44)
    }

    /// Operators with lines here, ranked by how often the reader rode them.
    /// Labels come from the operator registry, the app's one display-name path.
    private func prepareFilters(catalog: EditorCatalog) {
        let operators = catalog.operators(in: regionCode).filter { !catalog.lines(operatorID: $0.id).isEmpty }
        let identity = RegistryIdentityCache.identity(forRegion: regionCode)
        var labels: [String: String] = [:]
        if let identity {
            for op in operators {
                if let id = identity.operatorIDs(forCatalogName: op.name).first,
                   let label = identity.operatorLabel(id, language: localization.language.rawValue), !label.isEmpty {
                    labels[op.id] = label
                }
            }
        }
        var byLine: [String: Int] = [:]
        for train in itineraries?.loaded?.trains ?? [] where (train.region ?? regionCode) == regionCode {
            for id in Set((train.routeSections ?? []).flatMap { $0.lineIDs ?? [] }) { byLine[id, default: 0] += 1 }
        }
        var byOperator: [String: Int] = [:]
        for op in operators {
            byOperator[op.id] = catalog.lines(operatorID: op.id).reduce(0) { $0 + (byLine[$1.id] ?? 0) }
        }
        let preferred = companyFilter
        operatorLabels = labels
        riddenByLine = byLine
        filterOperators = operators.sorted { lhs, rhs in
            // The trip's own company, when the editor has one, comes first.
            let lp = lhs.name == preferred || labels[lhs.id] == preferred
            let rp = rhs.name == preferred || labels[rhs.id] == preferred
            if lp != rp { return lp }
            let l = byOperator[lhs.id] ?? 0
            let r = byOperator[rhs.id] ?? 0
            if l != r { return l > r }
            return (labels[lhs.id] ?? lhs.name).localizedStandardCompare(labels[rhs.id] ?? rhs.name) == .orderedAscending
        }
    }

    private func load() async {
        let regionCode = regionCode
        let lineIDs = selectedLineIDs
        let rideDate = rideDate
        let includesRetired = onSelectRetired != nil && rideDate?.isEmpty == false
        let sourceCatalog = sourceCatalog
        let loadID = search.beginLoad()
        didLoad = false
        loadError = nil
        catalog = nil
        retiredByID = [:]
        subtitleByCode = [:]
        copyLabels = CopyLabelMemo()
        lineLabelByID = [:]
        hints = PickerHints()
        declinedFilterText = nil
        textBeforeAppliedFilter = nil
        writtenResidual = nil
        latestResponse = nil
        onLoad?(nil, [], [:])
        guard let region = Region(rawValue: regionCode) else {
            loadError = EditorCatalogLoadError.missingResource(regionCode).localizedDescription
            return
        }
        let readings = localization.stationSearchNames(region: region)
        let recent = StationPickerRecents.load(regionCode: regionCode)
        let rideCounts = StationPickerRecents.rideCounts(
            trains: itineraries?.loaded?.trains ?? [], regionCode: regionCode)
        search.setSignals(recentPicks: recent, rideCounts: rideCounts)
        if sourceCatalog == nil {
            SharedSearchEngine.shared.prepare(regionCode: regionCode, readings: readings)
        }
        let request = StationPickerSearchController.Request(
            regionCode: regionCode, rideDate: rideDate, lineIDs: lineIDs, includesRetired: includesRetired)
        do {
            let loaded = try await Task.detached(priority: .userInitiated) {
                let catalog = try sourceCatalog ?? loadCatalog(for: region)
                // One index per region, shared with the line search. An injected
                // catalog is not the bundled one, so it gets its own index.
                let index = sourceCatalog == nil
                    ? try await SharedSearchEngine.shared.stationIndex(regionCode: regionCode, catalog: catalog)
                    : catalog.stationSearchIndex(regionCode: regionCode, extraNames: readings)
                let directory = includesRetired ? RiddenRouteStore.retiredStations(region: regionCode) : []
                let output = index.search(StationSearchQuery(regionCode: regionCode, rideDate: rideDate,
                    eligibility: includesRetired ? [.current, .retired] : .current, lineIDs: lineIDs), retired: directory)
                let labels = StationLabel.lineLabels(in: catalog, regionCode: regionCode)
                var qualifiers: [String: String] = [:]
                for station in catalog.stations(in: regionCode) {
                    qualifiers[station.key.sourceCode] = StationLabel.text(
                        for: station, catalog: catalog, labels: labels).qualifier
                }
                let openRetired = index.eligibleRetired(directory, rideDate: rideDate, lineIDs: lineIDs)
                return (catalog, index, directory, output, qualifiers, openRetired, labels)
            }.value
            guard !Task.isCancelled, search.acceptsLoad(loadID),
                  search.install(index: loaded.1, retired: loaded.2, request: request,
                                 output: loaded.3, loadID: loadID) else { return }
            catalog = loaded.0
            allStations = loaded.0.stations(in: regionCode)
            retiredByID = Dictionary(loaded.2.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            subtitleByCode = loaded.4
            lineLabelByID = loaded.6
            onLoad?(loaded.0, loaded.5, loaded.4)
            didLoad = true
            prepareFilters(catalog: loaded.0)
            refreshFilterState()
            if isSearching { search.apply(query: searchText, companyName: nil) }
        } catch {
            guard !Task.isCancelled, search.acceptsLoad(loadID) else { return }
            loadError = error.localizedDescription
        }
    }

    private func stationButton(_ row: CatalogStationRow, line: CatalogLine? = nil) -> some View {
        Button { select(row, line: line) } label: { CatalogStationLabel(row: row) }
            .buttonStyle(RailRowPressStyle(cornerRadius: 0))
            .accessibilityIdentifier(stationIdentifier(row.station, line: line))
    }
    private func stationIdentifier(_ station: CatalogStation, line: CatalogLine?) -> String {
        if inlineQuery != nil { return "rideEditorStationSuggestion-\(station.key.sourceCode)" }
        if onSelectWithLine != nil, let line { return "newTripStation-\(line.id)-\(station.key.sourceCode)" }
        return "\(accessibilityPrefix)-\(station.key.sourceCode)"
    }
    private func retiredStationButton(_ station: RetiredStation) -> some View {
        Button {
            onSelectRetired?(station)
            if inlineQuery == nil { dismiss() }
        } label: { RetiredStationLabel(station: station, rideDate: rideDate, regionCode: regionCode) }
            .buttonStyle(RailRowPressStyle(cornerRadius: 0))
            .accessibilityIdentifier("stationPickerRetired-\(station.id)")
    }
    private func recordPick(_ station: CatalogStation) {
        let recent = StationPickerRecents.record(
            stationCode: station.key.sourceCode, regionCode: regionCode)
        search.setSignals(recentPicks: recent)
    }
    private func select(_ row: CatalogStationRow, line: CatalogLine? = nil) {
        recordPick(row.station)
        if let onSelectWithLine { onSelectWithLine(row.station, line, row.stationID) }
        else { onSelect?(row.station, row.stationID) }
        if inlineQuery == nil { dismiss() }
    }
}

struct RetiredStationLabel: View {
    @Environment(AppLocalization.self) private var localization
    let station: RetiredStation
    let rideDate: String?
    let regionCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(BracketedStationText.title(
                officialName: station.name, localizedTitle: station.name,
                regionCode: regionCode, localization: localization))
            Text(BracketedStationText.secondary(
                officialName: station.name, regionCode: regionCode,
                qualifier: "\(station.lineName) · \(station.operatorName)",
                localization: localization))
                .font(.caption).foregroundStyle(.secondary)
            Label(
                closedText, systemImage: "clock.arrow.circlepath"
            )
            .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    private var closedText: String {
        // A `certifiedCode` means this entry is an old name for a station
        // that still exists today (builder-certified same code + geometry),
        // not a closed station.
        let marker = localization.text(
            station.certifiedCode != nil ? "ios.editor.renamedStation" : "ios.editor.retiredStation")
        guard let validTo = station.period(on: rideDate)?.validTo else { return marker }
        let onKey = station.certifiedCode != nil ? "ios.editor.renamedOn" : "ios.editor.retiredOn"
        return "\(marker) · \(localization.text(onKey, params: ["date": .string(validTo)]))"
    }
}

private struct CatalogStationLabel: View {
    @Environment(AppLocalization.self) private var localization
    let row: CatalogStationRow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(highlighted(visibleName, ranges: titleHighlights))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            if let via = matchedVia {
                Text(highlighted(via.text, ranges: via.ranges))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if !caption.isEmpty {
                StationQualifierCaption(text: caption)
            }
            if !row.detail.isEmpty {
                Text(row.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .contextMenu {
            Button {
                StationQualifierCopy.copy(full)
            } label: {
                Label(localization.text("ios.editor.copyStation", fallback: "Copy"), systemImage: "doc.on.doc")
            }
            ShareLink(item: full) {
                Label(localization.text("ios.share", fallback: "Share"), systemImage: "square.and.arrow.up")
            }
        }
    }

    private var visibleName: String {
        BracketedStationText.title(
            officialName: row.station.name,
            localizedTitle: localization.stationName(
                row.station.name, code: row.station.key.sourceCode,
                region: Region(rawValue: row.station.key.regionCode)),
            regionCode: row.station.key.regionCode, localization: localization)
    }

    /// Highlight ranges when the matched spelling is the title on screen.
    private var titleHighlights: [Range<Int>] {
        guard let match = row.match, match.highlightsTitle, match.matchedText == visibleName else { return [] }
        return match.highlights
    }

    /// The spelling that matched when it is not the shown name (romaji, reading, alias, code).
    private var matchedVia: (text: String, ranges: [Range<Int>])? {
        guard let match = row.match, match.source != .name, !match.matchedText.isEmpty,
              match.matchedText != visibleName,
              match.kind != .browse, match.kind != .recent, match.kind != .frequent else { return nil }
        return (match.matchedText, match.highlights)
    }

    /// Bold the matched UTF-16 ranges of `text`.
    private func highlighted(_ text: String, ranges: [Range<Int>]) -> AttributedString {
        var result = AttributedString(text)
        let length = text.utf16.count
        for range in ranges where range.lowerBound >= 0 && range.upperBound <= length && !range.isEmpty {
            let nsRange = NSRange(location: range.lowerBound, length: range.count)
            if let target = Range<AttributedString.Index>(nsRange, in: result) {
                result[target].inlinePresentationIntent = .stronglyEmphasized
            }
        }
        return result
    }

    private var caption: String {
        BracketedStationText.secondary(
            officialName: row.station.name, regionCode: row.station.key.regionCode,
            qualifier: row.subtitle, localization: localization)
    }

    private var full: String {
        if !row.copyText.isEmpty { return row.copyText }
        return StationQualifierCopy.full(name: row.station.name, qualifier: row.subtitle)
    }

    private var spoken: String {
        StationQualifierCopy.spoken(
            name: row.station.name,
            countryCode: row.station.key.regionCode.uppercased(),
            qualifier: row.subtitle,
            localization: localization)
    }
}

private struct StationLinePickerView: View {
    let title: String
    let rows: [CatalogStationRow]
    let accessibilityPrefix: String
    let onSelect: (CatalogStationRow) -> Void

    var body: some View {
        List(rows) { row in
            Button { onSelect(row) } label: {
                CatalogStationLabel(row: row)
            }
            .buttonStyle(RailRowPressStyle(cornerRadius: 0))
            .accessibilityIdentifier("\(accessibilityPrefix)-\(row.station.key.sourceCode)")
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

@MainActor
enum StationQualifierCopy {
    static func qualifier(fromFull full: String, name: String) -> String {
        let prefix = name + " "
        guard full.hasPrefix(prefix) else { return "" }
        return String(full.dropFirst(prefix.count))
    }

    /// The catalog's copy rule, so a fallback copy never drops the station name.
    static func full(name: String, qualifier: String) -> String {
        StationLabel.copyText(officialName: name, qualifier: qualifier)
    }

    static func countryName(_ code: String, localization: AppLocalization) -> String? {
        guard let region = Region(rawValue: code.lowercased()) else { return nil }
        let value = localization.text(region.localizationKey, fallback: region.fallbackName)
        if value.isEmpty || value == region.localizationKey { return nil }
        return value
    }

    static func spoken(
        name: String, countryCode: String, qualifier: String, localization: AppLocalization
    ) -> String {
        StationLabel.accessibility(
            name: name, countryCode: countryCode,
            spokenDetail: StationLabel.spokenDetail(in: qualifier),
            countryName: countryName(countryCode, localization: localization))
    }

    static func copy(_ full: String) {
        UIPasteboard.general.string = full
    }
}

struct StationQualifierCaption: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}


/// Memoized `StationReferenceResolution.copyLabel` results for one loaded
/// catalog. A reference type so filling it while rendering does not count as
/// a state change.
@MainActor
final class CopyLabelMemo {
    private var labels: [String: String] = [:]

    func label(for station: CatalogStation, catalog: EditorCatalog) -> String {
        if let known = labels[station.key.sourceCode] { return known }
        let label = StationReferenceResolution.copyLabel(for: station, catalog: catalog)
        labels[station.key.sourceCode] = label
        return label
    }
}
