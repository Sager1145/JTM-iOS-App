import Foundation

/// Owns admission of package proposals and the origin of materialized intervals.
/// Package uniqueness permits an undoable inference; it never proves complete
/// topology. Existing saved codes without an origin remain passenger choices.
public enum RecordedRouteAdmission {
    public enum Outcome: Equatable, Sendable {
        case apply(RailwayRouteChoices.Choice)
        case guide([RailwayRouteChoices.Choice])
        case corridorPreference(RailwayRouteChoices.Choice)
        case none

        public var automaticChoice: RailwayRouteChoices.Choice? {
            switch self {
            case .apply(let choice): Self.materialized(choice, origin: .packageInference)
            case .corridorPreference(let choice): Self.materialized(choice, origin: .corridorPreference)
            case .guide, .none: nil
            }
        }
        private static func materialized(_ choice: RailwayRouteChoices.Choice,
                                         origin: SectionCodesOrigin) -> RailwayRouteChoices.Choice {
            var result = choice
            result.routeSections = choice.routeSections.map { section in
                var section = section
                section.sectionCodesOrigin = origin
                return section
            }
            return result
        }
        public var choices: [RailwayRouteChoices.Choice] {
            switch self {
            case .apply(let choice), .corridorPreference(let choice): [choice]
            case .guide(let choices): choices
            case .none: []
            }
        }
    }

    /// Persisted only for machine-materialized interval preferences. Absence
    /// is deliberately authored, including records saved before this field.
    public enum SectionCodesOrigin: String, Codable, Hashable, Sendable {
        case corridorPreference
        case packageInference
    }

    public static func outcome(for result: LocalJourneySearch.Result) -> Outcome {
        guard !result.choices.isEmpty else { return .none }
        if result.allowsAutomaticMaterialization, result.directionIsKnown,
           result.isUniqueWithinPackage, !result.relaxedLineConstraints,
           let choice = result.choices.first { return .apply(choice) }
        return .guide(result.choices)
    }

    /// The one automatic pending decision. A raw package search does not grant it:
    /// direction, authored codes, and a relaxed label match stay on the guide.
    public static func uniqueChoice(for result: LocalJourneySearch.Result) -> RailwayRouteChoices.Choice? {
        outcome(for: result).automaticChoice
    }

    /// Sparse Tokyo conventional journeys receive the corridor preference.
    /// Explicit choices, other families, and pending confirmation are unchanged.
    public static func applyingCorridorPreference(
        to train: Train, package: CompactPackage? = nil
    ) -> Train {
        TokyoConventionalRouteInference.applying(to: train, package: package)
    }

    public static func admission(in train: Train, package: CompactPackage,
                                 stationAliases: [String: String] = [:],
                                 maximumChoices: Int = 3, maximumExpansions: Int = 50_000) -> Outcome {
        if let choice = TokyoConventionalRouteInference.choice(in: train, package: package) {
            return .corridorPreference(choice)
        }
        return outcome(for: search(in: train, package: package, stationAliases: stationAliases,
                                   maximumChoices: maximumChoices, maximumExpansions: maximumExpansions))
    }

    enum MaterializedOrigin {
        case authored, database, inferred, corridorPreference
        var permitsFallback: Bool { self == .inferred || self == .corridorPreference }
    }

    static func materializedOrigin(section: RouteSection, recorded: RouteSection?,
                                   database: Bool, stationInferred: Bool) -> MaterializedOrigin {
        if database { return .database }
        switch section.sectionCodesOrigin {
        case .corridorPreference: return .corridorPreference
        case .packageInference: return .inferred
        case nil: break
        }
        if recorded?.sectionCodes?.isEmpty == false { return .authored }
        if stationInferred || (section.sectionCodes?.isEmpty == false && recorded != nil) {
            return .inferred
        }
        return .authored
    }

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
            // Search surveyed row intervals. Cross-row physical permission
            // cannot come from station groups or service display labels.
            let constrained = CompactPackage(format: package.format, version: package.version,
                country: package.country, lines: package.lines.filter { line in
                    (train.routeSections ?? []).isEmpty || (train.routeSections ?? []).contains { section in
                        if !relaxLineConstraints {
                            if let ids = section.lineIDs, !ids.isEmpty, !ids.contains(line.id) { return false }
                            if let names = section.lineNames, !names.isEmpty,
                               !names.contains(line.name), !names.contains(line.nameNorm ?? line.name) { return false }
                        }
                        if let operators = section.operatorNames, !operators.isEmpty,
                           !operatorsAgree(operators, line.operator ?? "", region: package.country) { return false }
                        return true
                    }
                })
            let result = LocalJourneySearch.search(
                package: constrained, originCode: first, destinationCode: last,
                trainType: train.trainType, requiredStationCodes: codes, stationAliases: stationAliases,
                maximumChoices: maximumChoices, maximumExpansions: maximumExpansions,
                operatorID: train.operatorID)
            let choices = result.choices.filter {
                respectsSections($0, train: train, package: package, stationAliases: stationAliases,
                                 relaxLineConstraints: relaxLineConstraints)
            }
            var admitted = LocalJourneySearch.Result(choices: choices, isTruncated: result.isTruncated,
                topologyIsComplete: false, directionIsKnown: true)
            admitted.allowsAutomaticMaterialization = !(train.routeSections ?? []).contains {
                $0.sectionCodes?.isEmpty == false && $0.sectionCodesOrigin == nil
            }
            return admitted
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

    private static func respectsSections(
        _ choice: RailwayRouteChoices.Choice, train: Train, package: CompactPackage,
        stationAliases: [String: String], relaxLineConstraints: Bool
    ) -> Bool {
        let identity = RegistryIdentityCache.identity(forRegion: package.country)
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
                       operatorsAgree(operators, actual, identity: identity)
                   }) { return false }
            }
            if !relaxLineConstraints, let expected = section.sectionCodes, !expected.isEmpty,
               path.flatMap({ $0.sectionCodes ?? [] }) != expected { return false }
            cursor = end
        }
        return true
    }

    private static func operatorsAgree(_ required: [String], _ actual: String, region: String) -> Bool {
        operatorsAgree(required, actual, identity: RegistryIdentityCache.identity(forRegion: region))
    }

    /// True when the line may stay. Missing registry, or either side failing to
    /// convert, is unknown and does not reject the line. Disjoint converted sets reject.
    private static func operatorsAgree(
        _ required: [String], _ actual: String, identity: RegistryIdentity?
    ) -> Bool {
        guard let identity else { return true }
        let wanted = Set(required.flatMap { identity.operatorIDs(forCatalogName: $0) })
        let actualIDs = Set(identity.operatorIDs(forCatalogName: actual))
        if wanted.isEmpty || actualIDs.isEmpty { return true }
        return !actualIDs.isDisjoint(with: wanted)
    }
}
