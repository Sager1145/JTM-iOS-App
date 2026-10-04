import RailCore
import SwiftUI

/// Station search for a new trip. Matches station, line, and operator names,
/// then groups hits under each line.
struct TripStationSearchView: View {
    @Environment(AppLocalization.self) private var localization
    @Environment(\.dismiss) private var dismiss

    let catalog: EditorCatalog
    let regionCode: String
    let companyFilter: String?
    let onSelect: (CatalogStation, CatalogLine?) -> Void

    @State private var query = ""
    @State private var onlyCompany = false
    @State private var index: TripStationIndex?
    @State private var sections: [TripStationSection] = []

    private struct SearchToken: Equatable {
        var needle: String
        var onlyCompany: Bool
        var indexed: Bool
    }

    var body: some View {
        NavigationStack {
            List {
                if let companyFilter, !companyFilter.isEmpty {
                    Toggle(isOn: $onlyCompany) {
                        Text(text(
                            "onlyCompany",
                            fallback: "Only {company}",
                            ["company": .string(companyFilter)]))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if needle.isEmpty {
                    Text(text(
                        "searchPrompt",
                        fallback: "Search by station, line or company"))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if index == nil {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(sections) { section in
                        Section {
                            ForEach(section.rows) { row in
                                stationButton(row)
                            }
                        } header: {
                            Text(section.header)
                        }
                    }
                }
            }
            .navigationTitle(text("searchTitle", fallback: "Choose a station"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text(text(
                    "searchPrompt",
                    fallback: "Search by station, line or company")))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(text("cancel", fallback: "Cancel")) { dismiss() }
                }
            }
        }
        .task { await loadIndex() }
        .task(id: searchToken) { await refreshResults() }
    }

    private var needle: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchToken: SearchToken {
        SearchToken(needle: needle, onlyCompany: onlyCompany, indexed: index != nil)
    }

    private func stationButton(_ row: TripStationRow) -> some View {
        Button {
            onSelect(row.station, row.line)
            dismiss()
        } label: {
            Text(localization.stationName(
                row.station.name,
                code: row.station.key.sourceCode,
                region: Region(rawValue: regionCode)))
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .accessibilityIdentifier("newTripStation-\(row.line.id)-\(row.station.key.sourceCode)")
    }

    private func loadIndex() async {
        let catalog = catalog
        let regionCode = regionCode
        let built = await Task.detached(priority: .userInitiated) {
            TripStationIndex.build(catalog: catalog, regionCode: regionCode)
        }.value
        guard !Task.isCancelled else { return }
        index = built
    }

    private func refreshResults() async {
        let needle = needle
        guard let index, !needle.isEmpty else {
            sections = []
            return
        }
        do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
        guard !Task.isCancelled else { return }
        let company = onlyCompany ? companyFilter : nil
        let worker = Task.detached(priority: .userInitiated) {
            TripStationIndex.filter(index, needle: needle, company: company)
        }
        let found = await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
        guard !Task.isCancelled else { return }
        sections = found
    }

    private func text(
        _ key: String,
        fallback: String,
        _ params: [String: Localization.Param]? = nil
    ) -> String {
        localization.text("ios.newTrip.\(key)", params: params, fallback: fallback)
    }
}

private struct TripStationSection: Identifiable, Sendable {
    var id: String
    var header: String
    var rows: [TripStationRow]
}

private struct TripStationRow: Identifiable, Sendable {
    var id: String
    var station: CatalogStation
    var line: CatalogLine
}

private struct TripStationLine: Sendable {
    var id: String
    var line: CatalogLine
    var name: String
    var aliases: [String]
    var operatorNames: [String]
    var operatorShortNames: [String]
    var operatorAliases: [String]
    var header: String
    var stations: [CatalogStation]
}

private struct TripStationIndex: Sendable {
    var lines: [TripStationLine]
    static let sectionCap = 60
    static let rowCap = 400

    static func build(catalog: EditorCatalog, regionCode: String) -> TripStationIndex {
        let operatorsByID = Dictionary(
            catalog.operators(in: regionCode).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first })
        var lines: [TripStationLine] = []
        for line in catalog.lines(in: regionCode) {
            let lineOperators = line.operatorIDs.compactMap { operatorsByID[$0] }
            let operatorNames = lineOperators.map(\.name).filter { !$0.isEmpty }
            let header = operatorNames.isEmpty
                ? line.name
                : operatorNames.joined(separator: " / ") + " · " + line.name
            var seen: Set<String> = []
            var stations: [CatalogStation] = []
            for member in catalog.memberships(lineID: line.id, regionCode: regionCode) {
                guard seen.insert(member.stationKey.sourceCode).inserted,
                      let station = catalog.station(member.stationKey) else { continue }
                stations.append(station)
            }
            guard !stations.isEmpty else { continue }
            lines.append(TripStationLine(
                id: line.id,
                line: line,
                name: line.name,
                aliases: line.aliases.filter { !$0.isEmpty },
                operatorNames: operatorNames,
                operatorShortNames: lineOperators.compactMap(\.shortName).filter { !$0.isEmpty },
                operatorAliases: lineOperators.flatMap(\.aliases).filter { !$0.isEmpty },
                header: header,
                stations: stations))
        }
        lines.sort { $0.header.localizedStandardCompare($1.header) == .orderedAscending }
        return TripStationIndex(lines: lines)
    }

    static func filter(_ index: TripStationIndex, needle: String, company: String?) -> [TripStationSection] {
        var sections: [TripStationSection] = []
        var rowCount = 0
        for line in index.lines {
            if Task.isCancelled { return sections }
            if let company, !line.operatorNames.contains(company) { continue }
            if sections.count == sectionCap || rowCount == rowCap { break }
            let chosen = lineMatches(line, needle: needle)
                ? line.stations
                : line.stations.filter { stationMatches($0, needle: needle) }
            guard !chosen.isEmpty else { continue }
            let room = rowCap - rowCount
            let rows = chosen.prefix(room).map { station in
                TripStationRow(id: "\(line.id)|\(station.key.sourceCode)", station: station, line: line.line)
            }
            guard !rows.isEmpty else { continue }
            sections.append(TripStationSection(id: line.id, header: line.header, rows: Array(rows)))
            rowCount += rows.count
        }
        return sections
    }

    private static func lineMatches(_ line: TripStationLine, needle: String) -> Bool {
        contains(needle, [line.name])
            || contains(needle, line.aliases)
            || contains(needle, line.operatorNames)
            || contains(needle, line.operatorShortNames)
            || contains(needle, line.operatorAliases)
    }

    private static func stationMatches(_ station: CatalogStation, needle: String) -> Bool {
        station.name.localizedStandardContains(needle)
            || contains(needle, station.aliases)
    }

    private static func contains(_ needle: String, _ values: [String]) -> Bool {
        values.contains { !$0.isEmpty && $0.localizedStandardContains(needle) }
    }
}
