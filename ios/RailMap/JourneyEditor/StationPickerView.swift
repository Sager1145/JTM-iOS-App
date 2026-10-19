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

/// Catalog stations for one region. Empty search is a company → line → station
/// browser. Search results keep those categories instead of flattening stations
/// with the same display name into one ambiguous list.
struct StationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppLocalization.self) private var localization
    let regionCode: String
    var selectedLineIDs: Set<String> = []
    var onSelect: ((CatalogStation) -> Void)? = nil
    var rideDate: String? = nil
    var onSelectRetired: ((RetiredStation) -> Void)? = nil
    var sourceCatalog: EditorCatalog? = nil
    var sourcePackage: CompactPackage? = nil
    var companyFilter: String? = nil
    var onSelectWithLine: ((CatalogStation, CatalogLine?) -> Void)? = nil
    /// A stop keeps free text; only its suggestions use the shared picker.
    var inlineQuery: Binding<String>? = nil
    var showsSuggestions = true
    var onLoad: ((EditorCatalog?, [RetiredStation], [String: String]) -> Void)? = nil
    var accessibilityPrefix = "rideEditorStation"
    @State private var query = ""
    @State private var onlyCompany = false
    @State private var search = StationPickerSearchController()
    @State private var catalog: EditorCatalog?
    @State private var retiredByID: [String: RetiredStation] = [:]
    @State private var subtitleByCode: [String: String] = [:]
    @State private var copyByCode: [String: String] = [:]
    @State private var lineLabelByID: [String: String] = [:]
    @State private var didLoad = false
    @State private var loadError: String?

    private var queryBinding: Binding<String> { inlineQuery ?? $query }
    private var searchText: String { queryBinding.wrappedValue }
    private var loadToken: String {
        "\(regionCode)|\(selectedLineIDs.sorted().joined(separator: ","))|\(rideDate ?? "")|\(onSelectRetired != nil)"
    }
    private var companyName: String? { onlyCompany ? companyFilter : nil }

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
                    copyText: copy)
            }
            guard !rows.isEmpty,
                  let catalogLine = catalog.line(id: line.id, regionCode: regionCode) else { return nil }
            return CatalogStationLineGroup(line: catalogLine, operatorID: line.operatorID,
                                           operatorName: line.operatorName, rows: rows)
        }
    }
    private var suggestions: [CatalogStationRow] {
        guard let catalog else { return [] }
        return search.output.suggestions.compactMap { hit in
            guard case .current(let key, _) = hit.subject,
                  let station = catalog.station(key) else { return nil }
            return CatalogStationRow(
                station: station, subtitle: subtitleByCode[key.sourceCode] ?? "",
                copyText: copyByCode[key.sourceCode] ?? "")
        }
    }
    private var retiredStations: [RetiredStation] {
        search.output.retired.compactMap { hit in
            guard case .retired(let id) = hit.subject else { return nil }
            return retiredByID[id]
        }
    }
    private var packageRows: [CatalogStationRow] {
        var seen = Set<StationKey>()
        var rows = lineGroups.flatMap(\.rows).filter { seen.insert($0.station.key).inserted }
        if !isSearching {
            rows.sort {
                if $0.station.name != $1.station.name { return $0.station.name < $1.station.name }
                return $0.station.key.sourceCode < $1.station.key.sourceCode
            }
        }
        return Array(rows.prefix(100))
    }
    private var companyGroups: [CatalogStationCompanyGroup] {
        Dictionary(grouping: lineGroups, by: \.operatorID).map { operatorID, lines in
            CatalogStationCompanyGroup(id: operatorID,
                name: lines.first?.operatorName ?? localization.countryText("field.company", fallback: "Operator"),
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
        .onChange(of: searchText) { _, needle in search.apply(query: needle, companyName: companyName) }
        .onChange(of: onlyCompany) { _, _ in search.apply(query: searchText, companyName: companyName) }
        .onDisappear { search.cancel() }
    }

    @ViewBuilder private var browser: some View {
        if let loadError {
            Text(loadError).foregroundStyle(.secondary).padding()
        } else if !didLoad {
            ProgressView()
        } else {
            List {
                if let companyFilter, !companyFilter.isEmpty {
                    Toggle(isOn: $onlyCompany) {
                        Text(localization.text("ios.newTrip.onlyCompany", params: ["company": .string(companyFilter)],
                                               fallback: "Only {company}"))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if sourcePackage != nil {
                    let rows = packageRows
                    ForEach(rows) { row in stationButton(row) }
                    if rows.isEmpty {
                        Text(localization.text("ios.editor.stationUnmatched")).foregroundStyle(.secondary)
                    }
                } else if isSearching {
                    ForEach(lineGroups) { group in
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
                    if lineGroups.isEmpty && retiredStations.isEmpty {
                        Text(localization.text("ios.editor.stationUnmatched")).foregroundStyle(.secondary)
                    }
                } else if onSelectWithLine != nil {
                    Text(localization.text("ios.newTrip.searchPrompt", fallback: "Search by station, line or company"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(companyGroups) { company in
                        Section(company.name) {
                            ForEach(company.lines) { group in
                                NavigationLink {
                                    StationLinePickerView(title: group.line.name, rows: group.rows,
                                                          accessibilityPrefix: accessibilityPrefix) { station in
                                        select(station, line: group.line)
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
    }

    private func load() async {
        let regionCode = regionCode
        let lineIDs = selectedLineIDs
        let rideDate = rideDate
        let includesRetired = onSelectRetired != nil && rideDate?.isEmpty == false
        let sourceCatalog = sourceCatalog
        let sourcePackage = sourcePackage
        let loadID = search.beginLoad()
        didLoad = false
        loadError = nil
        catalog = nil
        retiredByID = [:]
        subtitleByCode = [:]
        copyByCode = [:]
        lineLabelByID = [:]
        onLoad?(nil, [], [:])
        guard let region = Region(rawValue: regionCode) else {
            loadError = EditorCatalogLoadError.missingResource(regionCode).localizedDescription
            return
        }
        let request = StationPickerSearchController.Request(
            regionCode: regionCode, rideDate: rideDate, lineIDs: lineIDs, includesRetired: includesRetired)
        do {
            let loaded = try await Task.detached(priority: .userInitiated) {
                let catalog: EditorCatalog
                if let sourceCatalog { catalog = sourceCatalog }
                else if let sourcePackage {
                    catalog = EditorCatalogBuilder.build(EditorCatalogBuilder.sources(regionCode: regionCode, package: sourcePackage))
                } else { catalog = try loadCatalog(for: region) }
                let index = catalog.stationSearchIndex(regionCode: regionCode)
                let directory = includesRetired ? RiddenRouteStore.retiredStations(region: regionCode) : []
                let output = index.search(StationSearchQuery(regionCode: regionCode, rideDate: rideDate,
                    eligibility: includesRetired ? [.current, .retired] : .current, lineIDs: lineIDs), retired: directory)
                let labels = StationLabel.lineLabels(in: catalog, regionCode: regionCode)
                var qualifiers: [String: String] = [:]
                var copies: [String: String] = [:]
                for station in catalog.stations(in: regionCode) {
                    qualifiers[station.key.sourceCode] = StationLabel.text(
                        for: station, catalog: catalog, labels: labels).qualifier
                    copies[station.key.sourceCode] = StationReferenceResolution.copyLabel(
                        for: station, catalog: catalog)
                }
                let openRetired = index.eligibleRetired(directory, rideDate: rideDate, lineIDs: lineIDs)
                return (catalog, index, directory, output, qualifiers, openRetired, labels, copies)
            }.value
            guard !Task.isCancelled, search.acceptsLoad(loadID),
                  search.install(index: loaded.1, retired: loaded.2, request: request,
                                 output: loaded.3, loadID: loadID) else { return }
            catalog = loaded.0
            retiredByID = Dictionary(loaded.2.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            subtitleByCode = loaded.4
            lineLabelByID = loaded.6
            copyByCode = loaded.7
            onLoad?(loaded.0, loaded.5, loaded.4)
            didLoad = true
            if isSearching || onlyCompany { search.apply(query: searchText, companyName: companyName) }
        } catch {
            guard !Task.isCancelled, search.acceptsLoad(loadID) else { return }
            loadError = error.localizedDescription
        }
    }

    private func stationButton(_ row: CatalogStationRow, line: CatalogLine? = nil) -> some View {
        Button { select(row.station, line: line) } label: { CatalogStationLabel(row: row) }
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
    private func select(_ station: CatalogStation, line: CatalogLine? = nil) {
        if let onSelectWithLine { onSelectWithLine(station, line) }
        else { onSelect?(station) }
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
            Text(visibleName)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
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
    let onSelect: (CatalogStation) -> Void

    var body: some View {
        List(rows) { row in
            Button { onSelect(row.station) } label: {
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

    static func full(name: String, qualifier: String) -> String {
        if qualifier.isEmpty { return name }
        if qualifier.hasPrefix("(") { return name + " " + qualifier }
        return qualifier
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

