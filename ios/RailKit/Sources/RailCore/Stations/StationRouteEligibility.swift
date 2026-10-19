import Foundation

/// Admission to the current survey topology under the source network's time
/// model. A family with any history, dated membership or service exception
/// stays with the dated solver; compact proximity cannot classify it.
public struct StationRouteEligibility: Sendable {
    private struct Family: Sendable {
        var sourceCount = 0
        var changed = false
        var institutions: Set<String> = []
        var stations: Set<String> = []
    }
    private var families: [String: Family] = [:]
    private let knownCodes: Set<String>
    private var groups: [String: Set<String>] = [:]

    public init(network: RouteNetwork, sections: [RouteGraph.SectionFeature], stations: [Stations.Feature]) {
        knownCodes = Set(network.lines.flatMap { $0.intervals.flatMap { [$0.fromStationCode, $0.toStationCode] } })
        for section in sections {
            let p = section.properties
            let key = Self.key(p.lineName, p.operator)
            families[key, default: Family()].sourceCount += 1
            families[key, default: Family()].changed = (families[key]?.changed ?? false)
                || p.validFrom != nil || p.validTo != nil || p.historyId != nil || p.temporalKind != .current
            if !p.institutionTypeCode.isEmpty {
                families[key, default: Family()].institutions.insert(p.institutionTypeCode)
            }
        }
        for station in stations {
            let key = Self.key(Stations.stationLineName(station), Stations.stationOperator(station))
            let code = Stations.stationCode(station)
            let group = Stations.stationGroupCode(station)
            if let code {
                families[key, default: Family()].stations.insert(code)
                if let group {
                    families[key, default: Family()].stations.insert(group)
                    groups[code, default: []].insert(group)
                }
            }
            let changed = Stations.stationValidFrom(station) != nil || Stations.stationValidTo(station) != nil
                || station.properties["history_id"] != nil
            families[key, default: Family()].changed = (families[key]?.changed ?? false) || changed
            let institution = Stations.stationInstitutionTypeCode(station)
            if !institution.isEmpty { families[key, default: Family()].institutions.insert(institution) }
        }
    }

    /// Only the catalog's explicit group identity can translate a missing
    /// platform code. A same-name station elsewhere is never an alias.
    public func stationCode(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let code = StationCodeAliases.canonical(raw)
        if knownCodes.contains(code) { return code }
        let candidates = (groups[code] ?? []).filter(knownCodes.contains)
        return candidates.count == 1 ? candidates.first : nil
    }

    /// The merged source/history family must be present, unchanged, and cover
    /// every package station. Nil source bounds retain their existing meaning
    /// of unrestricted validity; no date threshold is introduced here.
    public func permits(_ line: RouteNetwork.Line, allowedInstitutionCodes: [String], hard: Bool) -> Bool {
        guard let compact = line.compactLine, compact.serviceStatus == nil,
              let op = line.operator, !op.isEmpty else { return false }
        let names = Set([compact.name, compact.nameNorm].compactMap { $0 })
        let matches = names.compactMap { families[Self.key($0, op)] }
        guard matches.contains(where: { $0.sourceCount > 0 }),
              matches.allSatisfy({ !$0.changed }) else { return false }
        let members = matches.reduce(into: Set<String>()) { $0.formUnion($1.stations) }
        guard compact.stations.allSatisfy({ members.contains($0.id) }) else { return false }
        let allowed = Set(allowedInstitutionCodes.filter { !$0.isEmpty })
        if hard && !allowed.isEmpty {
            let institutions = matches.reduce(into: Set<String>()) { $0.formUnion($1.institutions) }
            guard !institutions.isEmpty, institutions.isSubset(of: allowed) else { return false }
        }
        return true
    }

    private static func key(_ name: String, _ op: String) -> String { op + "\0" + name }
}
