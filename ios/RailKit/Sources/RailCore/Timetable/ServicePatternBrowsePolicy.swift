import Foundation

/// Selectable timetable browse rows and fallback visibility, independent of view lifecycle.
public enum ServicePatternBrowsePolicy {
    /// Passenger JR companies, by identity code.
    private static let jrIdentityCodes: Set<String> = [
        "jp.jr-hokkaido", "jp.jr-east", "jp.jr-central",
        "jp.jr-west", "jp.jr-shikoku", "jp.jr-kyushu",
        "jp.jnr",
    ]

    /// A row carries the object the editor will select. Occurrences never
    /// acquire route-pattern identity or a reverse-direction action.
    public enum Row: Identifiable, Sendable {
        case occurrence(TrainTimetableDatabase.Trip)
        case pattern(TrainServicePatterns.Pattern)

        public var id: String {
            switch self {
            case .occurrence(let trip): "occurrence:\(trip.id):\(trip.serviceDate)"
            case .pattern(let pattern): "pattern:\(pattern.id)"
            }
        }

        fileprivate var name: String {
            switch self {
            case .occurrence(let trip): trip.service.canonicalName
            case .pattern(let pattern): pattern.name
            }
        }
    }

    public struct SearchGroup: Sendable {
        public let name: String
        public let companyLabel: String
        public let rows: [Row]
    }

    public struct SearchFilters: Equatable, Sendable {
        public var region: String
        public var rideDate: String?
        public var companyFilter: String?
        public var lineFilter: String?
        public var showsAllHistory: Bool
    
        public init(region: String, rideDate: String?, companyFilter: String?, lineFilter: String?, showsAllHistory: Bool) {
            self.region = region
            self.rideDate = rideDate
            self.companyFilter = companyFilter
            self.lineFilter = lineFilter
            self.showsAllHistory = showsAllHistory
        }
    }

    public struct SearchSnapshot: Sendable {
        public let groups: [SearchGroup]
        public let incompleteTrips: [TrainTimetableDatabase.Trip]
        public let unknownPatterns: [TrainServicePatterns.Pattern]
        public let outsidePatterns: [TrainServicePatterns.Pattern]
        /// Facade or localized labels, parallel to ``companyIDs``.
        public let companyLabels: [String]
        /// Operator ids. The company filter compares these, not the labels.
        public let companyIDs: [String]
        public let lineNames: [String]
        /// `searchGeneration` this result belongs to. `-1` until the first build,
        /// so the list is loading rather than "no results" at launch and after
        /// a timetable reload bumps the generation.
        public let generation: Int
        public let filters: SearchFilters
        /// Primary groups came from the route-pattern catalog, not from a
        /// timetable occurrence.
        public let primaryRowsArePatterns: Bool

        public static let empty = SearchSnapshot(
            groups: [], incompleteTrips: [], unknownPatterns: [], outsidePatterns: [],
            companyLabels: [], companyIDs: [], lineNames: [],
            generation: -1,
            filters: SearchFilters(
                region: "", rideDate: nil, companyFilter: nil, lineFilter: nil,
                showsAllHistory: false),
            primaryRowsArePatterns: false)
    }

    /// Occurrence-database state. A hard failure is not a reason to present
    /// another catalog as that same successful query.
    public enum OccurrenceAvailability: Sendable, Equatable {
        case notRequested
        case unsupported
        case missing
        case damaged
        case queryFailed
        case ready(TrainTimetableDatabase.Coverage)

        public var isHardFailure: Bool {
            switch self {
            case .missing, .damaged, .queryFailed: true
            case .notRequested, .unsupported, .ready: false
            }
        }
    }

    public struct SearchInput: Sendable {
        public let query: String
        public let region: String
        public let rideDate: String?
        public let companyFilter: String?
        public let lineFilter: String?
        public let showsAllHistory: Bool
        public let language: String
        public let sources: TimetableKnowledgeQuery.ClassifiedSources
        public let generation: Int
    
        public init(query: String, region: String, rideDate: String?, companyFilter: String?, lineFilter: String?, showsAllHistory: Bool, language: String, sources: TimetableKnowledgeQuery.ClassifiedSources, generation: Int) {
            self.query = query
            self.region = region
            self.rideDate = rideDate
            self.companyFilter = companyFilter
            self.lineFilter = lineFilter
            self.showsAllHistory = showsAllHistory
            self.language = language
            self.sources = sources
            self.generation = generation
        }
    }

    public static func makeSearchSnapshot(_ input: SearchInput) -> SearchSnapshot {
        let search = TimetableSearch(input.query, region: input.region)
        let sources = input.sources
        let patternMatches = sources.patterns.filter { pattern in
            matchesFilters(companies: [pattern.company], lines: pattern.lines, input: input)
                && search.matches(pattern)
        }.sorted {
            if let day = input.rideDate, $0.isValid(on: day) != $1.isValid(on: day) {
                return $0.isValid(on: day)
            }
            if $0.isCurrent != $1.isCurrent { return $0.isCurrent && !$1.isCurrent }
            if $0.name != $1.name { return $0.name < $1.name }
            return $0.label < $1.label
        }
        var completeMatches: [TrainTimetableDatabase.Trip] = []
        var incompleteMatches: [TrainTimetableDatabase.Trip] = []
        var hasIncompleteOccurrences = false
        for trip in sources.occurrences {
            let canApply = trip.canApplyToRouteEditor
            hasIncompleteOccurrences = hasIncompleteOccurrences || !canApply
            guard matchesFilters(companies: trip.operatorSegments.map(\.displayName),
                                 lines: trip.lineSegments.map(\.lineName), input: input),
                  search.matches(trip) else { continue }
            if canApply { completeMatches.append(trip) }
            else { incompleteMatches.append(trip) }
        }
        let primaryRowsArePatterns = input.region != "jp" || input.rideDate == nil
        let knownMatches: [Row]
        let incompleteTrips: [TrainTimetableDatabase.Trip]
        if primaryRowsArePatterns {
            knownMatches = patternMatches.map(Row.pattern)
            incompleteTrips = []
        } else if sources.availability.isHardFailure {
            knownMatches = []
            incompleteTrips = []
        } else {
            knownMatches = completeMatches.map(Row.occurrence)
            incompleteTrips = incompleteMatches
        }
        let researchIncomplete: Bool = {
            switch sources.availability {
            case .ready(.partial), .ready(.unknown), .ready(.conflict): true
            default: false
            }
        }()
        let shouldShowLegacyFallback = researchIncomplete || hasIncompleteOccurrences
        let unknownPatterns: [TrainServicePatterns.Pattern]
        if sources.availability.isHardFailure {
            unknownPatterns = []
        } else if input.region == "jp", let rideDate = input.rideDate {
            unknownPatterns = patternMatches.filter { pattern in
                pattern.applicability(on: rideDate) != .notApplicable
                    && (shouldShowLegacyFallback || !isJROrNationalRailway(pattern, region: input.region))
            }
        } else {
            unknownPatterns = []
        }
        let outsidePatterns: [TrainServicePatterns.Pattern]
        if let rideDate = input.rideDate, input.showsAllHistory {
            outsidePatterns = patternMatches.filter {
                $0.applicability(on: rideDate) == .notApplicable
            }
        } else {
            outsidePatterns = []
        }
        let companyNames = sources.patterns.map(\.company)
            + sources.occurrences.flatMap { $0.operatorSegments.map(\.displayName) }
        let identity = RegistryIdentityCache.identity(forRegion: input.region)
        var chips: [String: String] = [:]
        if let identity {
            for name in companyNames {
                for identifier in identity.operatorIDs(forCatalogName: name) {
                    chips[identifier] = companyDisplayName(
                        identifier, language: input.language, identity: identity)
                }
            }
        }
        let companyIDs = chips.keys.sorted {
            (chips[$0] ?? $0).localizedStandardCompare(chips[$1] ?? $1) == .orderedAscending
        }
        let companyLabels = companyIDs.map { chips[$0] ?? $0 }
        let lineNames = Array(Set(
            sources.patterns.flatMap(\.lines)
                + sources.occurrences.flatMap { $0.lineSegments.map(\.lineName) }
        )).sorted()
        var order: [String] = []
        var byName: [String: [Row]] = [:]
        for row in knownMatches {
            if byName[row.name] == nil { order.append(row.name) }
            byName[row.name, default: []].append(row)
        }
        let groups = order.map { name in
            SearchGroup(name: name,
                        companyLabel: byName[name]?.first.map { brandedCompany($0, region: input.region) } ?? "",
                        rows: byName[name] ?? [])
        }
        return SearchSnapshot(
            groups: groups, incompleteTrips: incompleteTrips,
            unknownPatterns: unknownPatterns, outsidePatterns: outsidePatterns,
            companyLabels: companyLabels, companyIDs: companyIDs, lineNames: lineNames,
            generation: input.generation,
            filters: SearchFilters(
                region: input.region, rideDate: input.rideDate,
                companyFilter: input.companyFilter, lineFilter: input.lineFilter,
                showsAllHistory: input.showsAllHistory),
            primaryRowsArePatterns: primaryRowsArePatterns)
    }

    private static func matchesFilters(companies: [String], lines: [String], input: SearchInput) -> Bool {
        if let companyFilter = input.companyFilter {
            guard let identity = RegistryIdentityCache.identity(forRegion: input.region) else { return false }
            let got = Set(companies.flatMap { identity.operatorIDs(forCatalogName: $0) })
            if !got.contains(companyFilter) { return false }
        }
        if let lineFilter = input.lineFilter {
            let line = TrainServiceBranding.canonicalLineName(lineFilter)
            guard lines.contains(where: {
                TrainServiceBranding.canonicalLineName($0) == line
            }) else { return false }
        }
        return true
    }

    /// Localized name from the operator's identity code. The facade label is the fallback.
    private static func companyDisplayName(
        _ identifier: String, language: String, identity: RegistryIdentity
    ) -> String {
        if let code = identity.operator(for: identifier)?.identity,
           let translated = OperatorIdentity.displayName(code: code, language: language) {
            return translated
        }
        return identity.operatorLabel(identifier) ?? identifier
    }

    private static func isJROrNationalRailway(
        _ pattern: TrainServicePatterns.Pattern, region: String
    ) -> Bool {
        let parts = pattern.company.components(separatedBy: CharacterSet(charactersIn: "/／"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return false }
        guard let identity = RegistryIdentityCache.identity(forRegion: region) else { return false }
        return parts.contains { part in
            let identifiers = identity.operatorIDs(forCatalogName: part)
            guard !identifiers.isEmpty else { return false }
            return identifiers.contains { identifier in
                guard let code = identity.operator(for: identifier)?.identity else { return false }
                return jrIdentityCodes.contains(code)
            }
        }
    }

    /// Facade label for each part that converts. A part that does not convert stays as written.
    private static func catalogLabels(_ name: String, region: String) -> [String] {
        let parts = name.components(separatedBy: "/").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        guard let identity = RegistryIdentityCache.identity(forRegion: region) else { return parts }
        return parts.map { part in
            if let identifier = identity.operatorID(forExactName: part),
               let label = identity.operatorLabel(identifier) {
                return label
            }
            return part
        }
    }

    private static func brandedCompany(_ row: Row, region: String) -> String {
        switch row {
        case .occurrence(let trip):
            var seen: Set<String> = []
            let names = trip.operatorSegments.map(\.displayName).filter { seen.insert($0).inserted }
            return names.flatMap { catalogLabels($0, region: region) }.joined(separator: " / ")
        case .pattern(let pattern):
            let labels = catalogLabels(pattern.company, region: region)
            return labels.isEmpty ? pattern.company : labels.joined(separator: " / ")
        }
    }
}
