import Foundation

/// Passenger-facing label derived from one company station and one line part.
public struct RegistryStationLabel: Equatable, Sendable {
    /// Large name and status secondary, from ``StationLabel/presented``.
    public var presentation: StationLabel.Presentation
    /// Country caption built from ``presentation.label`` and the chosen line.
    public var text: StationLabel.Text
    /// Line part used for the caption. Nil when the station lists none.
    public var lineID: String?

    public init(presentation: StationLabel.Presentation, text: StationLabel.Text, lineID: String?) {
        self.presentation = presentation
        self.text = text
        self.lineID = lineID
    }
}

/// Read-only identity queries over one ``RegistryBundle``.
///
/// Schema 1 files decode with empty reverse maps, so station, complex, and
/// label queries miss. ``stationID(forCode:operator:)`` still answers from the
/// forward code tables. The value is pure: it does not read the clock or disk.
public struct RegistryIdentity: Equatable, Sendable {
    public var bundle: RegistryBundle

    public init(bundle: RegistryBundle) {
        self.bundle = bundle
    }

    public func station(_ identifier: String) -> RegistryStationRecord? {
        bundle.stations[identifier]
    }

    public func codes(of stationID: String) -> [String] {
        bundle.stations[stationID]?.codes ?? []
    }

    public func complex(of stationID: String) -> RegistryComplexRecord? {
        guard let complexID = bundle.stations[stationID]?.cx else { return nil }
        return bundle.complexes[complexID]
    }

    public func stations(in complexID: String) -> [String] {
        bundle.complexes[complexID]?.stations ?? []
    }

    public func `operator`(for identifier: String) -> RegistryOperatorRecord? {
        bundle.operatorRecords[identifier]
    }

    /// The operator whose stored identity code equals `code`. Nil unless exactly one does.
    public func operatorID(forIdentityCode code: String) -> String? {
        var found: String?
        for (identifier, record) in bundle.operatorRecords {
            guard let identity = record.identity, sameCodeUnits(identity, code) else { continue }
            if found != nil { return nil }
            found = identifier
        }
        return found
    }

    /// Same fail-closed rule ``RegistryIdentityUpgrade`` used before this facade.
    ///
    /// Canonicalize the code, then a direct `stationCodes` hit wins. A group
    /// code with one station is that station. Several stations narrow to one
    /// only when `operator` owns exactly one of them. Anything else is nil.
    public func stationID(forCode rawCode: String, operator operatorID: String?) -> String? {
        let code = StationCodeAliases.canonical(rawCode)
        if let direct = bundle.stationCodes[code] {
            return direct
        }
        guard let candidates = bundle.groupCodes[code] else { return nil }
        if candidates.count == 1 { return candidates[0] }
        guard let operatorID else { return nil }
        let narrowed = candidates.filter { candidate in
            guard let owner = bundle.stationOperator[candidate] else { return false }
            return sameCodeUnits(owner, operatorID)
        }
        return narrowed.count == 1 ? narrowed[0] : nil
    }

    /// Nil when the bundle has no station record (including every schema 1 file).
    ///
    /// `line` is used only when it serves the station. Otherwise the best line
    /// by rank, then name, then id. A line name that appears once in the country
    /// is shown bare; a repeated name is qualified with the operator's short label.
    public func label(for stationID: String, line requested: String? = nil, country: String) -> RegistryStationLabel? {
        guard let station = bundle.stations[stationID] else { return nil }
        let countryCode = country.uppercased()
        let lineID = chosenLineID(station: station, requested: requested)
        let detail = lineID.flatMap { lineLabel(for: $0) }
        let qualifier = StationLabel.caption(countryCode: countryCode, detail: detail)
        let presentation = StationLabel.presented(
            officialName: station.name,
            qualifier: qualifier,
            parts: station.parts,
            statusWord: nil)
        let text = detail.map {
            StationLabel.make(name: presentation.label, countryCode: countryCode, detail: $0)
        } ?? StationLabel.countryOnly(name: presentation.label, countryCode: countryCode)
        return RegistryStationLabel(presentation: presentation, text: text, lineID: lineID)
    }

    private func chosenLineID(station: RegistryStationRecord, requested: String?) -> String? {
        if let requested, station.lines.contains(requested), bundle.lineParts[requested] != nil {
            return requested
        }
        let choices = station.lines.compactMap { identifier -> StationLabel.LineChoice? in
            guard let part = bundle.lineParts[identifier] else { return nil }
            return StationLabel.LineChoice(id: identifier, label: part.name, rank: part.rank, name: part.name)
        }
        return StationLabel.orderedLines(choices, contextLineIDs: []).first?.id
    }

    private func lineLabel(for lineID: String) -> String? {
        guard let part = bundle.lineParts[lineID] else { return nil }
        let copies = bundle.lineParts.values.filter { sameCodeUnits($0.name, part.name) }.count
        return StationLabel.lineLabel(
            name: part.name,
            operatorName: brandingSource(for: part.op),
            uniqueInCountry: copies <= 1)
    }

    /// A package name whose ``OperatorBranding/companyLabel(_:)`` equals the stored
    /// short label. Prefer one that the short label actually changes, so a
    /// UTF-16-first spelling such as "JR East" is not the only string offered.
    private func brandingSource(for operatorID: String) -> String? {
        guard let record = bundle.operatorRecords[operatorID] else { return nil }
        let stored = record.label
        guard !stored.isEmpty else { return record.names.first }
        if let changing = record.names.first(where: { name in
            let short = OperatorBranding.companyLabel(name)
            return sameCodeUnits(short, stored) && !sameCodeUnits(short, name)
        }) {
            return changing
        }
        if let exact = record.names.first(where: { sameCodeUnits(OperatorBranding.companyLabel($0), stored) }) {
            return exact
        }
        return stored
    }
}

/// The app installs a per-region lookup. Tests leave it nil.
public enum RegistryIdentityLookup {
    public typealias Provider = @Sendable (String) -> RegistryIdentity?

    private static let lock = NSLock()
    nonisolated(unsafe) private static var provider: Provider?

    public static func install(_ provider: Provider?) {
        lock.lock()
        self.provider = provider
        lock.unlock()
    }

    public static func identity(forRegion region: String) -> RegistryIdentity? {
        let cc = region.lowercased()
        guard !cc.isEmpty else { return nil }
        lock.lock()
        let current = provider
        lock.unlock()
        return current?(cc)
    }
}
