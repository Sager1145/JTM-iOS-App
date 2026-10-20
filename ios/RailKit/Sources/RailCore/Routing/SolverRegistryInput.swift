import Foundation

/// Where a solve reads company-station and operator identity.
///
/// The physical graph still walks source codes. These helpers only decide
/// which codes and package operator names are handed to that walk. A missing
/// lookup is the same outcome as a preload still in flight: editor features
/// report identity unavailable. Section-walk helpers may still translate a
/// stored source code. An installed lookup never falls back to a name or to
/// another company in the same complex.
public enum SolverRegistryInput {
    public static func regionCode(_ identifier: String?) -> String? {
        guard let identifier else { return nil }
        let parts = identifier.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "st" || parts[0] == "op" else { return nil }
        let region = String(parts[1])
        return region.isEmpty ? nil : region
    }

    public enum Availability: Sendable {
        case ready(RegistryIdentity)
        case pending
        case unavailable
    }

    public static func availability(region: String) -> Availability {
        switch RegistryIdentityLookup.phase(forRegion: region) {
        case .ready(let identity): return .ready(identity)
        case .pending: return .pending
        case .unavailable: return .unavailable
        }
    }

    public static func installedIdentity(region: String) -> RegistryIdentity? {
        if case .ready(let identity) = availability(region: region) { return identity }
        return nil
    }

    /// Waits for a pending preload, then returns the ready identity. Absent stays nil.
    public static func awaitReady(region: String) async -> RegistryIdentity? {
        await RegistryIdentityLookup.waitUntilSettled(region: region)
        return installedIdentity(region: region)
    }

    public static func recordedOperatorIDs(operatorID: String?, operatorIDs: [String]) -> [String] {
        var ids: [String] = []
        if let operatorID, !operatorID.isEmpty { ids.append(operatorID) }
        for identifier in operatorIDs where !identifier.isEmpty && !ids.contains(identifier) {
            ids.append(identifier)
        }
        return ids
    }

    /// Package names on `edge.operator`. A stored spelling converts to an
    /// operator id, then back to that record's names. Anything that does not
    /// convert is dropped.
    public static func packageOperatorNames(
        operatorIDs: [String], storedNames: [String], identity: RegistryIdentity
    ) -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        func add(_ name: String) {
            let trimmed = JSString.trim(name)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return }
            names.append(trimmed)
        }
        var identifiers: [String] = []
        var seenIDs = Set<String>()
        func addID(_ identifier: String) {
            guard identity.operator(for: identifier) != nil, seenIDs.insert(identifier).inserted else { return }
            identifiers.append(identifier)
        }
        for identifier in operatorIDs { addID(identifier) }
        for stored in storedNames {
            let trimmed = JSString.trim(stored)
            guard !trimmed.isEmpty else { continue }
            if identity.operator(for: trimmed) != nil {
                addID(trimmed)
            } else if let identifier = identity.operatorID(forExactName: trimmed) {
                addID(identifier)
            }
        }
        for identifier in identifiers {
            for name in identity.operator(for: identifier)?.names ?? [] { add(name) }
        }
        return names
    }

    /// Features whose own source code is one of `codes`. A group-key hit for
    /// another company's code is not a sibling.
    public static func featureIndices(owning codes: [String], in stations: Stations.Index) -> [Int] {
        let wanted = Set(codes.map {
            StationCodeAliases.canonical($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }.filter { !$0.isEmpty })
        guard !wanted.isEmpty else { return [] }
        var seen = Set<Int>()
        var indices: [Int] = []
        for code in wanted {
            for index in stations.featureIndices(matchingTrimmedCodeOrGroup: code) {
                guard seen.insert(index).inserted else { continue }
                let featureCode = Stations.stationCode(stations.features[index]).map {
                    StationCodeAliases.canonical($0.trimmingCharacters(in: .whitespacesAndNewlines))
                } ?? ""
                guard wanted.contains(featureCode) else { continue }
                indices.append(index)
            }
        }
        return indices.sorted()
    }

    /// Nil when no lookup is installed. Empty when the id cannot be solved.
    public static func endpointIndices(
        stationID: String?, region: String, stations: Stations.Index
    ) -> [Int]? {
        guard let identity = installedIdentity(region: region) else { return nil }
        guard let stationID, !stationID.isEmpty else { return [] }
        let codes = identity.codes(of: stationID)
        guard !codes.isEmpty else { return [] }
        return featureIndices(owning: codes, in: stations)
    }

    public static func solveInputCodes(stops: [Stop], region: String) -> [String] {
        switch availability(region: region) {
        case .pending, .unavailable:
            return []
        case .ready(let identity):
            return solveInputCodes(stops, identity: identity)
        }
    }

    private static func solveInputCodes(_ stops: [Stop], identity: RegistryIdentity) -> [String] {
        var result: [String] = []
        var seen = Set<String>()
        for stop in stops {
            guard let identifier = stop.stationID, !identifier.isEmpty else { continue }
            for code in identity.codes(of: identifier) where seen.insert(code).inserted {
                result.append(code)
            }
        }
        return result
    }

    public static func solvableEndpointCount(stops: [Stop], region: String) -> Int {
        switch availability(region: region) {
        case .pending, .unavailable:
            return 0
        case .ready(let identity):
            return solvableEndpointCount(stops, identity: identity)
        }
    }

    private static func solvableEndpointCount(_ stops: [Stop], identity: RegistryIdentity) -> Int {
        return stops.reduce(into: 0) { count, stop in
            if let identifier = stop.stationID, !identity.codes(of: identifier).isEmpty { count += 1 }
        }
    }

    /// Section-walk code. No lookup: `eligibility.stationCode`. Lookup: a code
    /// in `codes(of:)`, or nil when the id is missing.
    public static func graphStationCode(
        stationID: String?, rawCode: String?, region: String,
        eligibility: StationRouteEligibility?
    ) -> String? {
        switch availability(region: region) {
        case .pending:
            return nil
        case .unavailable:
            guard RegistryIdentityLookup.lookupInstalled else {
                return eligibility?.stationCode(rawCode)
            }
            return nil
        case .ready(let identity):
            return graphStationCode(
                stationID: stationID, rawCode: rawCode, identity: identity, eligibility: eligibility)
        }
    }

    private static func graphStationCode(
        stationID: String?, rawCode: String?, identity: RegistryIdentity,
        eligibility: StationRouteEligibility?
    ) -> String? {
        guard let stationID, !stationID.isEmpty else { return nil }
        let owned = identity.codes(of: stationID)
        guard !owned.isEmpty else { return nil }
        let ownedSet = Set(owned.map { StationCodeAliases.canonical($0) })
        if let eligibility {
            for code in owned {
                guard let translated = eligibility.stationCode(code) else { continue }
                let canonical = StationCodeAliases.canonical(translated)
                if ownedSet.contains(canonical) || owned.contains(translated) { return translated }
            }
            return nil
        }
        return owned.first { ownedSet.contains(StationCodeAliases.canonical($0)) }
    }

    /// Hint path keeps a raw code when eligibility cannot translate it and no
    /// lookup is installed. An installed lookup does not.
    public static func hintedGraphStationCode(
        stationID: String?, rawCode: String?, region: String,
        eligibility: StationRouteEligibility?
    ) -> String? {
        switch availability(region: region) {
        case .pending:
            return nil
        case .unavailable:
            guard RegistryIdentityLookup.lookupInstalled else {
                guard let eligibility else { return rawCode }
                return eligibility.stationCode(rawCode) ?? rawCode
            }
            return nil
        case .ready:
            break
        }
        return graphStationCode(
            stationID: stationID, rawCode: rawCode, region: region, eligibility: eligibility)
    }

    public static func persistedHopCode(
        persisted: String?, sectionCode: String?, stationID: String?, region: String
    ) -> String? {
        func nonempty(_ value: String?) -> String? {
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        guard let stationID, !stationID.isEmpty else {
            return nonempty(persisted) ?? nonempty(sectionCode)
        }
        guard let identity = installedIdentity(region: region) else { return nil }
        let owned = identity.codes(of: stationID)
        guard !owned.isEmpty else { return nil }
        let ownedSet = Set(owned.map { StationCodeAliases.canonical($0) })
        if let persisted, ownedSet.contains(StationCodeAliases.canonical(persisted)) { return persisted }
        if let sectionCode, ownedSet.contains(StationCodeAliases.canonical(sectionCode)) {
            return sectionCode
        }
        return owned.first
    }

    public static func anchorStationID(
        code: String, region: String, operatorID: String?
    ) -> String? {
        installedIdentity(region: region)?.stationID(forCode: code, operator: operatorID)
    }

    public static func sameStation(_ left: String, _ right: String) -> Bool {
        if left == right { return true }
        guard let region = regionCode(left),
              let identity = installedIdentity(region: region) else { return false }
        let leftCodes = Set(identity.codes(of: left))
        guard !leftCodes.isEmpty else { return false }
        return !leftCodes.isDisjoint(with: identity.codes(of: right))
    }

    /// An absent declaration is not a disagreement. Equal names are not agreement.
    public static func markerAgrees(declared: String?, stop: Stop, region: String) -> Bool {
        guard let declared, !declared.isEmpty else { return true }
        if let identifier = stop.stationID, declared == identifier { return true }
        if let code = stop.n02StationCode, !code.isEmpty, declared == code { return true }
        if let identifier = stop.stationID,
           let identity = installedIdentity(region: region) {
            let wanted = StationCodeAliases.canonical(declared)
            if identity.codes(of: identifier).contains(where: {
                StationCodeAliases.canonical($0) == wanted
            }) {
                return true
            }
        }
        return false
    }

    /// Editors that change a section endpoint drop the cached station id.
    /// The next upgrade derives it again from the new code.
    public static func renameEndpoint(_ section: inout RouteSection, from: Bool, name: String?) {
        if from {
            if name != section.from {
                section.fromN02StationCode = nil
                section.fromStationID = nil
            }
            section.from = name
        } else {
            if name != section.to {
                section.toN02StationCode = nil
                section.toStationID = nil
            }
            section.to = name
        }
    }

    public static func assignEndpoint(
        _ section: inout RouteSection, from: Bool, name: String?, code: String?,
        regionCode: String? = nil, stationID: String? = nil
    ) {
        var resolvedName = name
        var resolvedCode = code
        var resolvedID: String?
        if let regionCode {
            if let stationID,
               let written = RegistryStationSelection.written(stationID: stationID, regionCode: regionCode) {
                resolvedID = written.stationID
                resolvedName = written.name
                resolvedCode = written.code ?? code
            } else if let code,
                      let written = RegistryStationSelection.written(sourceCode: code, regionCode: regionCode) {
                resolvedID = written.stationID
                resolvedName = written.name
                resolvedCode = written.code ?? code
            }
        }
        if from {
            section.from = resolvedName
            section.fromN02StationCode = resolvedCode
            section.fromStationID = resolvedID
        } else {
            section.to = resolvedName
            section.toN02StationCode = resolvedCode
            section.toStationID = resolvedID
        }
    }
}
