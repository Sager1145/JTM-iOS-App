import Foundation
@testable import RailCore

/// Mirrors an editor catalog as a task-local registry so import and completion
/// tests resolve through registry ids. A provider already installed by the test
/// is left in place.
enum CatalogRegistryFixture {
    static func rawDraft(
        text: String, catalog: EditorCatalog, regionCode: String, seed: Train,
        directory: StationNameDirectory? = nil
    ) -> JourneyCompletion.RawDraft {
        call(provider(catalog: catalog, region: regionCode, directory: directory)) {
            JourneyCompletion.rawDraft(
                text: text, catalog: catalog, regionCode: regionCode, seed: seed,
                directory: directory)
        }
    }

    static func resolvingUniqueStationNames(
        in train: Train,
        catalogs: [String: EditorCatalog],
        names: [String: StationNameDirectory] = [:]
    ) -> Train {
        call(provider(catalogs: catalogs, names: names)) {
            JourneyCompletion.resolvingUniqueStationNames(
                in: train, catalogs: catalogs, names: names)
        }
    }

    static func requestEligibility(
        train: Train,
        catalogs: [String: EditorCatalog],
        providerAvailable: Bool = true,
        requestInFlight: Bool = false
    ) -> JourneyCompletion.RequestEligibility {
        call(provider(catalogs: catalogs, names: [:])) {
            JourneyCompletion.requestEligibility(
                train: train, catalogs: catalogs,
                providerAvailable: providerAvailable, requestInFlight: requestInFlight)
        }
    }

    static func requestDenial(
        train: Train,
        catalog: EditorCatalog?,
        providerAvailable: Bool = true,
        requestInFlight: Bool = false
    ) -> EditorAIDenial? {
        guard let catalog else {
            return JourneyCompletion.requestDenial(
                train: train, catalog: catalog,
                providerAvailable: providerAvailable, requestInFlight: requestInFlight)
        }
        return call(provider(catalog: catalog, region: nil, directory: nil)) {
            JourneyCompletion.requestDenial(
                train: train, catalog: catalog,
                providerAvailable: providerAvailable, requestInFlight: requestInFlight)
        }
    }

    static func isRequestEligible(_ train: Train, catalog: EditorCatalog?) -> Bool {
        guard let catalog else {
            return JourneyCompletion.isRequestEligible(train, catalog: catalog)
        }
        return call(provider(catalog: catalog, region: nil, directory: nil)) {
            JourneyCompletion.isRequestEligible(train, catalog: catalog)
        }
    }

    private static func call<T>(
        _ provider: @escaping RegistryIdentityLookup.Provider, _ body: () throws -> T
    ) rethrows -> T {
        if RegistryIdentityLookup.testOverride != nil { return try body() }
        return try RegistryIdentityTestGate.withProvider(provider, body)
    }

    /// `region == nil` answers every country from the same catalog, matching
    /// `JourneyCompletion.regionalCatalogs`.
    private static func provider(
        catalog: EditorCatalog, region: String?, directory: StationNameDirectory?
    ) -> RegistryIdentityLookup.Provider {
        { asked in
            if let region, asked.caseInsensitiveCompare(region) != .orderedSame { return nil }
            return identity(catalog: catalog, region: asked, directory: directory)
        }
    }

    private static func provider(
        catalogs: [String: EditorCatalog], names: [String: StationNameDirectory]
    ) -> RegistryIdentityLookup.Provider {
        { asked in
            guard let catalog = catalogs.first(where: {
                $0.key.caseInsensitiveCompare(asked) == .orderedSame
            })?.value else { return nil }
            let directory = names.first(where: {
                $0.key.caseInsensitiveCompare(asked) == .orderedSame
            })?.value
            return identity(catalog: catalog, region: asked, directory: directory)
        }
    }

    static func identity(
        catalog: EditorCatalog, region: String, directory: StationNameDirectory?
    ) -> RegistryIdentity? {
        let slug = region.lowercased()
        let rows = catalog.stations(in: slug)
        guard !rows.isEmpty else { return nil }
        let operators = Dictionary(
            catalog.operators(in: slug).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first })
        var operatorRecords: [String: RegistryOperatorRecord] = [:]
        var lineParts: [String: RegistryLinePartRecord] = [:]
        for line in catalog.lines(in: slug) {
            let operatorID = "op:\(slug):\(line.id)"
            operatorRecords[operatorID] = RegistryOperatorRecord(
                names: aliasNames(line: line, operators: operators, labels: catalog.storedLineLabels(regionCode: slug)),
                label: shortLabel(line: line, operators: operators))
            lineParts[line.id] = RegistryLinePartRecord(
                packageLine: line.id, name: line.name, op: operatorID, ln: line.lineCode, rank: line.rank)
        }

        var bracketed = directory?.bracketedNames ?? [:]
        var baseCounts = directory?.baseNameCounts ?? [:]
        if directory == nil {
            for row in rows {
                if let parts = inferredParts(row.name) { bracketed[row.name] = parts }
            }
            var counts: [String: Int] = [:]
            for record in bracketed.values { counts[record.base, default: 0] += 1 }
            baseCounts = counts
        }

        var stationCodes: [String: String] = [:]
        var stations: [String: RegistryStationRecord] = [:]
        var stationOperator: [String: String] = [:]
        for (offset, row) in rows.sorted(by: { $0.key.sourceCode < $1.key.sourceCode }).enumerated() {
            let stationID = "st:\(slug):\(offset + 1)"
            let lineIDs = catalog.memberships(stationKey: row.key).map(\.lineID)
            let uniqueLines = Array(Set(lineIDs)).sorted()
            let operatorID = uniqueLines.first.flatMap { lineParts[$0]?.op } ?? "op:\(slug):none"
            let parts = directory?.parts(forOfficialName: row.name) ?? bracketed[row.name]
            let aliases = row.aliases.filter { $0 != row.name }
            stations[stationID] = RegistryStationRecord(
                cx: "cx:\(slug):\(offset + 1)", group: row.key.sourceCode, codes: [row.key.sourceCode],
                op: operatorID, name: row.name, parts: parts, lines: uniqueLines,
                aka: aliases.isEmpty ? nil : aliases)
            stationCodes[row.key.sourceCode] = stationID
            stationOperator[stationID] = operatorID
        }
        return RegistryIdentity(bundle: RegistryBundle(
            region: slug, run: 1, stationCodes: stationCodes, operators: [:],
            operatorRecords: operatorRecords, stationOperator: stationOperator,
            stations: stations, lineParts: lineParts,
            bracketedNames: bracketed, baseNameCounts: baseCounts))
    }

    private static func aliasNames(
        line: CatalogLine, operators: [String: CatalogOperator], labels: [String: String]
    ) -> [String] {
        var names: [String] = []
        for operatorID in line.operatorIDs {
            guard let company = operators[operatorID] else { continue }
            names.append(company.name)
            names.append(contentsOf: company.aliases)
            if let short = company.shortName { names.append(short) }
            let branded = OperatorBranding.companyLabel(company.name)
            if !branded.isEmpty {
                names.append(branded)
                names.append(branded + line.name)
                names.append(branded + " " + line.name)
            }
            names.append(StationLabel.qualifiedLineName(line.name, operatorName: company.name))
        }
        names.append(line.name)
        names.append(contentsOf: line.aliases)
        if let code = line.lineCode, !code.isEmpty { names.append(code) }
        if let label = labels[line.id] { names.append(label) }
        let numbered = names
        for name in numbered {
            if let stripped = StationReferenceResolution.withoutLeadingLineNumber(name) {
                names.append(stripped)
            }
        }
        var seen: Set<String> = []
        return names.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private static func shortLabel(line: CatalogLine, operators: [String: CatalogOperator]) -> String {
        guard let company = line.operatorIDs.compactMap({ operators[$0] }).first else { return "" }
        return OperatorBranding.companyLabel(company.name)
    }

    private static func inferredParts(_ name: String) -> StationNameRecord? {
        let pairs: [(Character, Character)] = [("（", "）"), ("(", ")")]
        for (open, close) in pairs {
            guard let start = name.firstIndex(of: open),
                  let end = name.lastIndex(of: close), start < end else { continue }
            let base = String(name[..<start])
            let bracket = String(name[name.index(after: start)..<end])
            let tail = name[name.index(after: end)...]
            guard !base.isEmpty, !bracket.isEmpty, tail.isEmpty else { continue }
            return StationNameRecord(
                base: base, bracket: bracket, kind: .subname, position: .suffix)
        }
        return nil
    }
}
