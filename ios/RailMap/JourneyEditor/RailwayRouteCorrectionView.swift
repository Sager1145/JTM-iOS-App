import MapKit
import RailCore
import SwiftUI

/// Selects a span of recorded visits before searching physical route choices.
/// Occurrence identities distinguish repeated visits to the same station.
/// Present this view in the parent's sheet NavigationStack.
struct RailwayRouteCorrectionView: View {
    typealias Choice = RailwayRouteChoices.Choice

    @Environment(\.dismiss) private var dismiss
    @Environment(AppLocalization.self) private var localization

    private let train: Train
    private let package: CompactPackage
    private let excludedStationCodes: Set<String>
    private let lockedFocus: Bool
    private let onApply: (Choice, UUID, UUID) -> Void
    private let onPending: (() -> Void)?

    @State private var fromID: UUID?
    @State private var toID: UUID?
    @State private var loading = false
    @State private var searchError: String?
    @State private var foundChoices: [Choice] = []
    @State private var loadedSearch: SearchKey?
    @State private var session: Session?
    @State private var showingGuide = false
    @State private var didAutoOpen = false

    init(
        train: Train, package: CompactPackage, excludedStationCodes: Set<String> = [],
        focus: (fromVisitID: UUID, toVisitID: UUID)? = nil,
        onPending: (() -> Void)? = nil,
        onApply: @escaping (Choice, UUID, UUID) -> Void
    ) {
        let prepared = RailwayRouteEditing.preparing(train)
        self.train = prepared
        self.package = package
        self.excludedStationCodes = excludedStationCodes
        self.lockedFocus = focus != nil
        self.onPending = onPending
        self.onApply = onApply
        let mappedStops = prepared.stops.filter { $0.n02StationCode != nil }
        _fromID = State(initialValue: focus?.fromVisitID ?? mappedStops.first?.routeEditing?.visitID)
        _toID = State(initialValue: focus?.toVisitID ?? mappedStops.last?.routeEditing?.visitID)
    }

    private var rows: [Endpoint] {
        train.stops.enumerated().compactMap { index, stop in
            guard let id = stop.routeEditing?.visitID, let code = stop.n02StationCode else { return nil }
            return Endpoint(id: id, index: index, code: code, name: stop.name)
        }
    }

    private var from: Endpoint? { rows.first { $0.id == fromID } }
    private var to: Endpoint? { rows.first { $0.id == toID } }

    private var destinationRows: [Endpoint] {
        guard let from else { return [] }
        return rows.filter { $0.index > from.index }
    }

    private var search: SearchKey? {
        guard let from, let to, from.index < to.index, from.code != to.code else { return nil }
        return SearchKey(fromID: from.id, toID: to.id, origin: from.code, destination: to.code)
    }

    var body: some View {
        Form {
            if !lockedFocus {
            Section {
                Picker(localization.text("ios.editor.fromStation"), selection: $fromID) {
                    ForEach(rows.filter { $0.index < (rows.last?.index ?? 0) }) { row in
                        Text(endpointName(row)).tag(Optional(row.id))
                    }
                }
                .accessibilityIdentifier("routeCorrectionFrom")
                Picker(localization.text("ios.editor.toStation"), selection: $toID) {
                    ForEach(destinationRows) { row in
                        Text(endpointName(row)).tag(Optional(row.id))
                    }
                }
                .accessibilityIdentifier("routeCorrectionTo")
            } header: {
                Text(text("choosePortion"))
            } footer: {
                Text(text(excludedStationCodes.isEmpty ? "portionHelp" : "avoidHelp"))
            }
            }

            Section {
                if let onPending {
                    Button(text("keepPending"), action: onPending)
                        .accessibilityIdentifier("routeCorrectionPending")
                }
                if loading {
                    ProgressView(text("findingPaths"))
                } else if let searchError {
                    Text(searchError).font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("routeCorrectionSearchError")
                } else if search == nil {
                    Text(text("invalidEndpoints")).foregroundStyle(.secondary)
                } else if loadedSearch == search && foundChoices.isEmpty {
                    Text(text("emptyDetail")).foregroundStyle(.secondary)
                        .accessibilityIdentifier("routeCorrectionEmpty")
                }
                if loadedSearch == search {
                    Text(text("incompleteSearch")).font(.footnote).foregroundStyle(.secondary)
                }
                Button(text("findPaths"), systemImage: "map") { openGuide() }
                    .disabled(loading || search == nil || loadedSearch != search || foundChoices.isEmpty)
                    .accessibilityIdentifier("routeCorrectionCompare")
            }
        }
        .navigationTitle(text("title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(localization.text("ios.cancel")) { dismiss() }
                    .accessibilityIdentifier("routeCorrectionCancel")
            }
        }
        .onChange(of: fromID) { _, _ in
            guard !lockedFocus else { return }
            if !destinationRows.contains(where: { $0.id == toID }) {
                toID = destinationRows.last?.id
            }
        }
        .onChange(of: loadedSearch) { _, loaded in
            guard lockedFocus, !didAutoOpen, loaded != nil, loaded == search, !foundChoices.isEmpty else { return }
            didAutoOpen = true
            openGuide()
        }
        .task(id: search) { await loadChoices() }
        .navigationDestination(isPresented: $showingGuide) {
            if let session {
                RailwayRouteGuideView(
                    train: session.train, package: package, choices: session.choices,
                    embeddedInNavigationStack: true, onCancel: { dismiss() }, onPending: onPending,
                    fromVisitID: session.fromID, toVisitID: session.toID
                ) { choice in
                    onApply(choice, session.fromID, session.toID)
                }
            }
        }
    }

    private func loadChoices() async {
        foundChoices = []
        loadedSearch = nil
        searchError = nil
        guard let search else { loading = false; return }
        loading = true
        let package = package
        let trainType = train.trainType
        let serviceDate = Dates.normalizeDateString(train.date)
        let excluded = excludedStationCodes
        let required = train.stops[(from?.index ?? 0)...(to?.index ?? 0)]
            .filter { $0.routeEditing?.generatedBy == nil || $0.n02StationCode == search.origin || $0.n02StationCode == search.destination }
            .compactMap(\.n02StationCode)
            // A Delete action requests omission of this station. Keep the
            // original visit in the draft so the resulting plan still requires
            // explicit approval before removing its authored details.
            .filter { !excluded.contains($0) }
        // Shared station groups yield reviewable candidates, not certified junctions.
        let worker = Task.detached(priority: .userInitiated) {
            let aliases = try loadJourneyStationAliases(
                for: required + Array(excluded) + [search.origin, search.destination], package: package)
            let packageCodes = Set(package.lines.flatMap { $0.stations.map(\.id) })
            func canonical(_ code: String) -> String {
                packageCodes.contains(code) ? code : aliases[code] ?? code
            }
            let protectedCodes = Set((required + [search.origin, search.destination]).map(canonical))
            let canonicalExcluded = Set(excluded.map(canonical)).subtracting(protectedCodes)
            // A ride is one train; transfer chains must not crowd out a plain
            // line within the three-choice cap. Retain the existing fallback.
            var memo: [String: Bool] = [:]
            func allows(_ from: CompactPackage.Line, _ to: CompactPackage.Line, _ code: String) -> Bool {
                let key = from.id + "\u{1F}" + to.id + "\u{1F}" + code
                if let known = memo[key] { return known }
                let value = TripConnectivity.allows(from: from, to: to, atStationCode: code, on: serviceDate)
                memo[key] = value
                return value
            }
            let preferred = LocalJourneySearch.search(
                package: package, originCode: search.origin, destinationCode: search.destination,
                trainType: trainType, excludingStationCodes: canonicalExcluded,
                requiredStationCodes: required, stationAliases: aliases, continuation: allows)
            var choices = preferred.choices
            if choices.isEmpty {
                choices = LocalJourneySearch.search(
                    package: package, originCode: search.origin, destinationCode: search.destination,
                    trainType: trainType, excludingStationCodes: canonicalExcluded,
                    requiredStationCodes: required, stationAliases: aliases).choices
            }
            let originKey = canonical(search.origin)
            let destinationKey = canonical(search.destination)
            let sharedNames = Set(package.lines.filter { line in
                line.stations.contains { canonical($0.id) == originKey }
            }.map(\.name)).intersection(package.lines.filter { line in
                line.stations.contains { canonical($0.id) == destinationKey }
            }.map(\.name))
            // One pooled search returns only the shortest shared name. Between
            // 東京 and 品川 that is already the capped 総武線 choice, so the
            // plain 東海道線 row stays hidden. Search each name on its own rows.
            // CompactPackage has no public narrow constructor; row membership
            // is that bound, under the same continuation.
            var namedChoices: [Choice] = []
            var seen = Set(choices.map(\.id))
            for name in sharedNames.sorted() {
                let namedIDs = Set(package.lines.filter { $0.name == name }.map(\.id))
                guard !namedIDs.isEmpty else { continue }
                let direct = LocalJourneySearch.search(
                    package: package, originCode: search.origin, destinationCode: search.destination,
                    trainType: trainType, excludingStationCodes: canonicalExcluded,
                    requiredStationCodes: required, stationAliases: aliases,
                    maximumChoices: 1,
                    continuation: { from, to, code in
                        namedIDs.contains(from.id) && namedIDs.contains(to.id) && allows(from, to, code)
                    }, originLineIDs: namedIDs, destinationLineIDs: namedIDs)
                if let choice = direct.choices.first, seen.insert(choice.id).inserted {
                    namedChoices.append(choice)
                }
            }
            return namedChoices + choices
        }
        let result: [Choice]
        do {
            result = try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: { worker.cancel() }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, self.search == search else { return }
            loading = false
            searchError = error.localizedDescription
            return
        }
        guard !Task.isCancelled, self.search == search else { return }
        foundChoices = result
        loadedSearch = search
        loading = false
    }

    private func openGuide() {
        guard let from, let to, let search, loadedSearch == search, !foundChoices.isEmpty else { return }
        var segment = train
        segment.stops = Array(train.stops[from.index...to.index])
        segment.origin = segment.stops[0].name
        segment.destination = segment.stops[segment.stops.count - 1].name
        if let sections = train.routeSections, sections.count == train.stops.count - 1 {
            segment.routeSections = Array(sections[from.index..<to.index])
        } else {
            // The core planner can reconstruct absent adjacent sections safely.
            segment.routeSections = nil
        }
        session = Session(train: segment, choices: foundChoices, fromID: from.id, toID: to.id)
        showingGuide = true
    }

    private func endpointName(_ endpoint: Endpoint) -> String {
        text("occurrence", [
            "number": .number(Double(endpoint.index + 1)),
            "station": .string(localization.stationName(endpoint.name, code: endpoint.code)),
        ])
    }

    private func text(_ key: String, _ params: [String: Localization.Param]? = nil) -> String {
        localization.text("ios.routeGuide." + key, params: params)
    }

    private struct Endpoint: Identifiable {
        let id: UUID
        let index: Int
        let code: String
        let name: String
    }

    private struct SearchKey: Hashable, Sendable {
        let fromID: UUID
        let toID: UUID
        let origin: String
        let destination: String
    }

    private struct Session {
        let train: Train
        let choices: [Choice]
        let fromID: UUID
        let toID: UUID
    }
}

