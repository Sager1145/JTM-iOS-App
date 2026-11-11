import Foundation

/// Free-text discovery is separate from the exact, timed editor match.
/// Whitespace combines terms; an arrow constrains the order of passenger calls.
public struct TimetableSearch: Sendable {
    private static let serviceNamesByID = Dictionary(uniqueKeysWithValues:
        TrainServiceBranding.services.map { ($0.id, $0.names) })
    private let terms: [String]
    private let route: [String]
    private let prepared: SearchFold.PreparedQuery
    private let preparedRoute: [SearchFold.PreparedQuery]
    private let rawQuery: String
    private let region: String
    /// Operator ids the whole query names. Computed once. Nil when the query is not an operator,
    /// or when the registry was not ready at init.
    private let operatorQuery: Set<String>?
    /// The query with a trailing train number ("のぞみ 23", "nozomi23号") removed, for
    /// stop patterns, which name a service but carry no train number. Nil when the
    /// query has no number. Matched by the shared search engine, so kana, katakana,
    /// romaji and full or half width all find the same service.
    private let serviceNameQuery: SearchTextQuery?

    public init(_ text: String, region: String = "jp") {
        let normalized = text.precomposedStringWithCompatibilityMapping.replacingOccurrences(of: "->", with: "→")
        let parts = normalized.components(separatedBy: "→")
        route = parts.count > 1 ? parts.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        } : []
        rawQuery = normalized
        prepared = SearchFold.PreparedQuery(normalized)
        preparedRoute = route.map(SearchFold.PreparedQuery.init)
        self.region = region
        terms = normalized.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        serviceNameQuery = route.isEmpty ? Self.withoutTrainNumber(normalized).map(SearchTextQuery.init) : nil
        if route.isEmpty, let identity = RegistryIdentityCache.identity(forRegion: region) {
            let wanted = identity.operatorIDs(matchingQuery: normalized)
            operatorQuery = wanted.isEmpty ? nil : wanted
        } else {
            operatorQuery = nil
        }
    }

    /// The name part of "<name> <number>[号]". Needs at least two characters of name.
    static func withoutTrainNumber(_ text: String) -> String? {
        var rest = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
        for suffix in ["号", "ごう"] where rest.hasSuffix(suffix) { rest = rest.dropLast(suffix.count) }
        let digits = rest.reversed().prefix(while: { $0.isASCII && $0.isNumber }).count
        guard (1...4).contains(digits) else { return nil }
        let name = rest.dropLast(digits).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.count >= 2 ? name : nil
    }

    public func matches(fields: [String], stops: [String], plainFields: [String] = []) -> Bool {
        if terms.isEmpty && route.isEmpty { return true }
        if !route.isEmpty {
            let stations = stops
            guard route.allSatisfy({ !$0.isEmpty }) else { return false }
            var nextIndex = 0
            for station in preparedRoute {
                guard let index = stations.indices.first(where: {
                    $0 >= nextIndex && station.matches(fields: [stations[$0]])
                }) else { return false }
                nextIndex = index + 1
            }
            return true
        }
        return prepared.matches(fields: fields + stops, plainFields: plainFields, rawQuery: rawQuery)
    }

    public func matches(_ trip: TrainTimetableDatabase.Trip) -> Bool {
        if let wanted = operatorQuery, let identity = RegistryIdentityCache.identity(forRegion: region) {
            return trip.operatorSegments.contains { segment in
                guard let identifier = identity.operatorID(forCatalogOrTimetableToken: segment.displayName)
                    ?? identity.operatorID(forCatalogOrTimetableToken: segment.operatorID)
                else { return false }
                return wanted.contains(identifier)
            }
        }
        return matches(fields: [trip.service.canonicalName, trip.service.englishName ?? "",
                         trip.publicNumber ?? "", trip.trainNumber,
                         trip.service.canonicalName + (trip.publicNumber ?? trip.trainNumber),
                         trip.service.canonicalName + (trip.publicNumber ?? trip.trainNumber) + "号",
                         (trip.service.englishName ?? "") + (trip.publicNumber ?? trip.trainNumber)]
                + trip.lineSegments.map(\.lineName),
                stops: trip.passengerStops.map { $0.station.name },
                plainFields: [trip.origin?.departureTime ?? "", trip.destination?.arrivalTime ?? ""])
    }

    public func matches(_ pattern: TrainServicePatterns.Pattern) -> Bool {
        if let wanted = operatorQuery, let identity = RegistryIdentityCache.identity(forRegion: region) {
            return !Set(identity.operatorIDs(forCatalogName: pattern.company)).isDisjoint(with: wanted)
        }
        let serviceNames = [pattern.name] + (Self.serviceNamesByID[pattern.serviceId] ?? [])
        if matches(fields: [pattern.name, pattern.label,
                         pattern.origin, pattern.destination] + pattern.lines + serviceNames,
                stops: pattern.stops) { return true }
        guard let nameQuery = serviceNameQuery else { return false }
        return serviceNames.contains { nameQuery.match($0, allowFuzzy: false) != nil }
    }

}
