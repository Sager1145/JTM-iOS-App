import RailCore
import SwiftUI

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
                                ForEach(catalog.continuations(for: trip)) { next in
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
        let prepared = SearchFold.PreparedQuery(query)
        let operatorCodes = OperatorIdentity.exactCodes(query: query)
        return catalog.lines.filter { line in
            if let operatorCodes {
                return !Set(OperatorIdentity.codes(forJoined: line.operatorName)).isDisjoint(with: operatorCodes)
            }
            return query.isEmpty || prepared.matches(fields: [line.lineName, line.operatorName] + line.aliases
                + line.kinds.map(\.displayName) + OperatorIdentity.searchNames(for: line.operatorName))
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
