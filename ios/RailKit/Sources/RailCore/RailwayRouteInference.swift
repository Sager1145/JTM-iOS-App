import Foundation

/// Reviewable paths through recorded visits. A candidate in compact-v1 does
/// not establish the train's actual route or complete network topology.
public enum RailwayRouteInference {
    public static func search(
        in train: Train, package: CompactPackage, stationAliases: [String: String] = [:],
        maximumChoices: Int = 3, maximumExpansions: Int = 50_000
    ) -> LocalJourneySearch.Result {
        let codes = train.stops.compactMap(\.n02StationCode)
        guard train.stops.count >= 2, codes.count == train.stops.count,
              codes.allSatisfy({ !$0.isEmpty }), let first = codes.first, let last = codes.last else {
            return .init(choices: [], isTruncated: false, topologyIsComplete: false, directionIsKnown: false)
        }
        func attempt(relaxLineConstraints: Bool) -> LocalJourneySearch.Result {
            // Shared station groups permit reviewable transfer candidates, not
            // certification of physical junction connectivity.
            let constrained = CompactPackage(format: package.format, version: package.version,
                country: package.country, lines: package.lines.filter { line in
                    (train.routeSections ?? []).isEmpty || (train.routeSections ?? []).contains { section in
                        if !relaxLineConstraints {
                            if let ids = section.lineIDs, !ids.isEmpty, !ids.contains(line.id) { return false }
                            if let names = section.lineNames, !names.isEmpty,
                               !names.contains(line.name), !names.contains(line.nameNorm ?? line.name) { return false }
                        }
                        if let operators = section.operatorNames, !operators.isEmpty,
                           !operators.contains(where: {
                               OperatorIdentity.sameCompany($0, line.operator ?? "")
                           }) { return false }
                        return true
                    }
                })
            let result = LocalJourneySearch.search(
                package: constrained, originCode: first, destinationCode: last,
                trainType: train.trainType, requiredStationCodes: codes, stationAliases: stationAliases,
                maximumChoices: maximumChoices, maximumExpansions: maximumExpansions)
            let choices = result.choices.filter {
                respectsSections($0, train: train, package: package, stationAliases: stationAliases,
                                 relaxLineConstraints: relaxLineConstraints)
            }
            return .init(choices: choices, isTruncated: result.isTruncated, topologyIsComplete: false,
                         directionIsKnown: true)
        }
        let constrained = attempt(relaxLineConstraints: false)
        guard constrained.choices.isEmpty else { return constrained }
        // Legal/service line labels can differ from physical package rows. A
        // match that appears only after dropping those labels is route-guide
        // material: it does not auto-complete. topologyIsComplete stays false.
        let relaxed = attempt(relaxLineConstraints: true)
        return .init(choices: relaxed.choices, isTruncated: relaxed.isTruncated,
                     topologyIsComplete: false, directionIsKnown: relaxed.directionIsKnown,
                     relaxedLineConstraints: !relaxed.choices.isEmpty)
    }

    /// Recorded stop order supplies direction. An untruncated, single package
    /// route found under the recorded line constraints can auto-complete; it
    /// remains an undoable inference, not proof of complete real-world topology.
    /// A route found only by relaxing those constraints is not a unique choice
    /// and stays on the route guide.
    public static func choice(in train: Train, package: CompactPackage, stationAliases: [String: String] = [:]) -> RailwayRouteChoices.Choice? {
        search(in: train, package: package, stationAliases: stationAliases).uniqueChoice
    }

    private static func respectsSections(
        _ choice: RailwayRouteChoices.Choice, train: Train, package: CompactPackage,
        stationAliases: [String: String], relaxLineConstraints: Bool
    ) -> Bool {
        let packageCodes = Set(package.lines.flatMap { $0.stations.map(\.id) })
        func canonical(_ code: String) -> String {
            packageCodes.contains(code) ? code : stationAliases[code] ?? code
        }
        var cursor = 0
        for section in train.routeSections ?? [] {
            func matches(_ visit: RailwayRouteChoices.Visit, code: String?, name: String?) -> Bool {
                if let code { return canonical(visit.code) == canonical(code) }
                if let name { return visit.name == name }
                return false
            }
            guard let start = (cursor..<choice.stations.count).first(where: {
                matches(choice.stations[$0], code: section.fromN02StationCode, name: section.from)
            }), let end = ((start + 1)..<choice.stations.count).first(where: {
                matches(choice.stations[$0], code: section.toN02StationCode, name: section.to)
            }) else { return false }
            let path = choice.routeSections[start..<end]
            for interval in path {
                if !relaxLineConstraints, let ids = section.lineIDs, !ids.isEmpty,
                   !(interval.lineIDs ?? []).allSatisfy(ids.contains) { return false }
                if !relaxLineConstraints, let names = section.lineNames, !names.isEmpty,
                   !(interval.lineIDs ?? []).allSatisfy({ id in
                       guard let line = package.lines.first(where: { $0.id == id }) else { return false }
                       return names.contains(line.name) || names.contains(line.nameNorm ?? line.name)
                   }) { return false }
                if let operators = section.operatorNames, !operators.isEmpty,
                   !(interval.operatorNames ?? []).allSatisfy({ actual in
                       operators.contains { OperatorIdentity.sameCompany($0, actual) }
                   }) { return false }
            }
            if !relaxLineConstraints, let expected = section.sectionCodes, !expected.isEmpty,
               path.flatMap({ $0.sectionCodes ?? [] }) != expected { return false }
            cursor = end
        }
        return true
    }
}
