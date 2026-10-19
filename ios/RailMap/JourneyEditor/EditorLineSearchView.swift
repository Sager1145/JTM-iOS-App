import RailCore
import RailPresentation
import SwiftUI

struct EditorLineSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppLocalization.self) private var localization
    let region: Region
    let lineNames: [String]
    let operatorNames: [String]
    let selectedLineIDs: Set<String>
    let stationCodes: [String]
    let onCommit: (_ lineIDs: [String], _ lineNames: [String], _ operatorNames: [String]) -> Void
    @State private var query = ""
    @State private var isSearching = false
    @State private var catalog: EditorCatalog?
    @State private var regionLines: [CatalogLine] = []
    @State private var operatorNameByID: [String: String] = [:]
    @State private var selectedIDs: Set<String> = []
    @State private var unresolvedNames: [String] = []
    @State private var didInitialize = false
    @State private var didCommit = false
    @State private var userEdited = false
    @State private var loadError: String?
    @State private var snapshot = SearchSnapshot()

    private struct OperatorLineGroup: Identifiable {
        var id: String
        var name: String
        var lines: [CatalogLine]
    }

    private struct SearchSnapshot {
        var selectedLines: [CatalogLine] = []
        var conflictingSelectedLines: [CatalogLine] = []
        var matchGroups: [OperatorLineGroup] = []
        var hasMatches = false
    }

    /// Publish the station constraint, selection and query result together.
    /// Rebuild on an input change, rather than during each body evaluation.
    private func refreshSnapshot() {
        guard let catalog else { snapshot = SearchSnapshot(); return }
        var resolvedStation = false
        var stationLineIDs = Set<String>()
        for code in Set(stationCodes) where !code.isEmpty {
            let key = StationKey(regionCode: region.code, sourceCode: code)
            guard catalog.station(key) != nil else { continue }
            resolvedStation = true
            stationLineIDs.formUnion(catalog.memberships(stationKey: key).map(\.lineID))
        }
        let candidates = resolvedStation
            ? regionLines.filter { stationLineIDs.contains($0.id) } : regionLines
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let prepared = SearchFold.PreparedQuery(needle)
        let identity = RegistryIdentityCache.identity(forRegion: region.code)
        let operatorIDs = identity?.operatorIDs(matchingQuery: needle) ?? []
        let matches = candidates.filter { line in
            if !operatorIDs.isEmpty, let identity {
                return line.operatorIDs.contains { packageOperator in
                    let name = operatorNameByID[packageOperator] ?? ""
                    return !Set(identity.operatorIDs(forCatalogName: name)).isDisjoint(with: operatorIDs)
                }
            }
            return needle.isEmpty || prepared.matches(fields: [line.name] + line.aliases)
        }
        let selected = regionLines.filter { selectedIDs.contains($0.id) }
        let conflicts = resolvedStation ? selected.filter { !stationLineIDs.contains($0.id) } : []
        let groups = Dictionary(grouping: matches) { $0.operatorIDs.first ?? "" }
            .map { operatorID, lines in
                OperatorLineGroup(id: operatorID,
                    name: operatorNameByID[operatorID]
                        ?? localization.countryText("field.company", fallback: "Operator"),
                    lines: lines)
            }.sorted {
                if $0.name != $1.name { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                return $0.id < $1.id
            }
        snapshot = SearchSnapshot(selectedLines: selected, conflictingSelectedLines: conflicts,
                                  matchGroups: groups, hasMatches: !matches.isEmpty)
    }

    var body: some View {
        Group {
            if let loadError {
                Text(loadError).foregroundStyle(.secondary).padding()
            } else if catalog == nil {
                ProgressView()
            } else {
                List {
                    if !snapshot.selectedLines.isEmpty || !unresolvedNames.isEmpty {
                        Section(localization.text("ios.editor.selectedLines")) {
                            ForEach(snapshot.selectedLines, id: \.id) { line in
                                lineButton(line, tagged: false)
                            }
                            ForEach(unresolvedNames, id: \.self) { name in
                                Text(name)
                                    .foregroundStyle(.secondary)
                                    .frame(minHeight: 44, alignment: .leading)
                            }
                        }
                    }
                    if !snapshot.conflictingSelectedLines.isEmpty {
                        Section {
                            ForEach(snapshot.conflictingSelectedLines, id: \.id) { line in
                                HStack(spacing: 12) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(line.name)
                                        if let operatorName = line.operatorIDs
                                            .compactMap({ operatorNameByID[$0] }).first
                                        {
                                            Text(operatorName).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        } header: {
                            Text("\(localization.text("ios.editor.station")) ↔ \(localization.text("ios.editor.lineNames"))")
                        }
                    }
                    ForEach(snapshot.matchGroups) { group in
                        Section(group.name) {
                            ForEach(group.lines, id: \.id) { line in
                                lineButton(line, tagged: true)
                            }
                        }
                    }
                    if !snapshot.hasMatches {
                        Section {
                            Text(localization.text("ios.editor.noLineMatches"))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(localization.text("ios.editor.searchLines"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, isPresented: $isSearching, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text(localization.text("ios.editor.lineSearchPrompt")))
        .task {
            let region = region
            do {
                let loaded = try await Task.detached(priority: .userInitiated) {
                    try loadCatalog(for: region)
                }.value
                guard !Task.isCancelled else { return }
                if !didInitialize {
                    let matched = CatalogLinePreferenceMapping.matching(
                        lineNames: lineNames, operatorNames: operatorNames,
                        regionCode: region.code, catalog: loaded)
                    let knownSelectedIDs = selectedLineIDs.filter {
                        loaded.line(id: $0, regionCode: region.code) != nil
                    }
                    selectedIDs = knownSelectedIDs.isEmpty ? Set(matched.lineIDs) : knownSelectedIDs
                    unresolvedNames = matched.unresolvedNames
                    didInitialize = true
                }
                operatorNameByID = Dictionary(
                    uniqueKeysWithValues: loaded.operators(in: region.code).map { ($0.id, $0.name) })
                regionLines = loaded.lines(in: region.code)
                catalog = loaded
                refreshSnapshot()
            } catch {
                guard !Task.isCancelled else { return }
                loadError = error.localizedDescription
            }
        }
        .onChange(of: query) { _, _ in refreshSnapshot() }
        .onChange(of: stationCodes) { _, _ in refreshSnapshot() }
        .onChange(of: localization.language) { _, _ in refreshSnapshot() }
        .onDisappear { commit() }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(localization.text("ios.done", fallback: "Done")) {
                    commit()
                    dismiss()
                }
                .accessibilityIdentifier("rideEditorLinesDone")
            }
        }
    }

    @ViewBuilder
    private func lineButton(_ line: CatalogLine, tagged: Bool) -> some View {
        let row = lineRow(line)
        if tagged {
            row.accessibilityIdentifier("rideEditorLine-\(line.id)")
        } else {
            row
        }
    }

    private func lineRow(_ line: CatalogLine) -> some View {
        let lineID = line.id
        let selected = selectedIDs.contains(lineID)
        let operatorName = line.operatorIDs.compactMap { operatorNameByID[$0] }.first { !$0.isEmpty }
        return Button {
            if selected { selectedIDs.remove(lineID) } else { selectedIDs.insert(lineID) }
            refreshSnapshot()
            userEdited = true
            isSearching = false
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(line.name)
                    if let operatorName {
                        Text(operatorName).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if selected { Image(systemName: "checkmark") }
            }
            .frame(minHeight: 44)
        }
        .accessibilityValue(selected ? localization.text("ios.editor.lineSelected") : "")
    }

    private func commit() {
        // Opening the list and leaving it must not drop a stored name that
        // matched more than one line. Those names stay unresolved until the
        // reader actually toggles a row.
        guard !didCommit, didInitialize, userEdited, let catalog else { return }
        didCommit = true
        let preference = CatalogLinePreferenceMapping.preferences(
            lineIDs: Array(selectedIDs), regionCode: region.code, catalog: catalog)
        var lineNames = preference.lineNames
        for name in unresolvedNames where !lineNames.contains(name) {
            lineNames.append(name)
        }
        onCommit(selectedIDs.sorted(), lineNames, preference.operatorNames)
    }
}

