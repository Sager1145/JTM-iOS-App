import Foundation

/// Reviewable paths through recorded visits. A candidate in compact-v1 does
/// not establish the train's actual route or complete network topology.
public enum RailwayRouteInference {
    public static func search(
        in train: Train, package: CompactPackage,
        maximumChoices: Int = 3, maximumExpansions: Int = 50_000
    ) -> LocalJourneySearch.Result {
        let codes = train.stops.compactMap(\.n02StationCode)
        guard train.stops.count >= 2, codes.count == train.stops.count,
              codes.allSatisfy({ !$0.isEmpty }), let first = codes.first, let last = codes.last else {
            return .init(choices: [], isTruncated: false, topologyIsComplete: false)
        }
        // With no verified cross-row junctions, each proposal remains in one
        // row. Apply hard source constraints before the bounded candidate cap.
        let constrained = CompactPackage(format: package.format, version: package.version,
            country: package.country, lines: package.lines.filter { line in
                (train.routeSections ?? []).allSatisfy { section in
                    if let ids = section.lineIDs, !ids.isEmpty, !ids.contains(line.id) { return false }
                    if let names = section.lineNames, !names.isEmpty,
                       !names.contains(line.name), !names.contains(line.nameNorm ?? line.name) { return false }
                    if let operators = section.operatorNames, !operators.isEmpty,
                       !operators.contains(where: {
                           OperatorBranding.companyLabel($0) == OperatorBranding.companyLabel(line.operator)
                       }) { return false }
                    return true
                }
            })
        let result = LocalJourneySearch.search(
            package: constrained, originCode: first, destinationCode: last,
            trainType: train.trainType, requiredStationCodes: codes,
            maximumChoices: maximumChoices, maximumExpansions: maximumExpansions)
        let choices = result.choices.filter { respectsSections($0, train: train) }
        return .init(choices: choices, isTruncated: result.isTruncated,
                     topologyIsComplete: result.topologyIsComplete)
    }

    /// Automatic completion requires demonstrated uniqueness and complete
    /// topology coverage. Current compact packages do not assert that coverage.
    public static func choice(in train: Train, package: CompactPackage) -> RailwayRouteChoices.Choice? {
        search(in: train, package: package).uniqueChoice
    }

    private static func respectsSections(_ choice: RailwayRouteChoices.Choice, train: Train) -> Bool {
        var cursor = 0
        for section in train.routeSections ?? [] {
            func matches(_ visit: RailwayRouteChoices.Visit, code: String?, name: String?) -> Bool {
                if let code { return visit.code == code }
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
                if let ids = section.lineIDs, !ids.isEmpty,
                   !(interval.lineIDs ?? []).allSatisfy(ids.contains) { return false }
                if let operators = section.operatorNames, !operators.isEmpty,
                   !(interval.operatorNames ?? []).allSatisfy({ actual in
                       operators.contains { OperatorBranding.companyLabel($0) == OperatorBranding.companyLabel(actual) }
                   }) { return false }
            }
            if let expected = section.sectionCodes, !expected.isEmpty,
               path.flatMap({ $0.sectionCodes ?? [] }) != expected { return false }
            cursor = end
        }
        return true
    }
}
