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
        if route.isEmpty, let identity = RegistryIdentityCache.identity(forRegion: region) {
            let wanted = identity.operatorIDs(matchingQuery: rawQuery)
            if !wanted.isEmpty {
                return trip.operatorSegments.contains { segment in
                    guard let identifier = identity.operatorID(forCatalogOrTimetableToken: segment.displayName)
                        ?? identity.operatorID(forCatalogOrTimetableToken: segment.operatorID)
                    else { return false }
                    return wanted.contains(identifier)
                }
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
        if route.isEmpty, let identity = RegistryIdentityCache.identity(forRegion: region) {
            let wanted = identity.operatorIDs(matchingQuery: rawQuery)
            if !wanted.isEmpty {
                return !Set(identity.operatorIDs(forCatalogName: pattern.company)).isDisjoint(with: wanted)
            }
        }
        return matches(fields: [pattern.name, pattern.label,
                         pattern.origin, pattern.destination] + pattern.lines
                + (Self.serviceNamesByID[pattern.serviceId] ?? []),
                stops: pattern.stops)
    }

}
