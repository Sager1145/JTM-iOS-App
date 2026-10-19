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
    private let operatorCodes: Set<String>?

    public init(_ text: String) {
        let normalized = text.precomposedStringWithCompatibilityMapping.replacingOccurrences(of: "->", with: "→")
        let parts = normalized.components(separatedBy: "→")
        route = parts.count > 1 ? parts.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        } : []
        rawQuery = normalized
        prepared = SearchFold.PreparedQuery(normalized)
        preparedRoute = route.map(SearchFold.PreparedQuery.init)
        operatorCodes = OperatorIdentity.exactCodes(query: normalized)
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
        if route.isEmpty, let operatorCodes {
            return trip.operatorSegments.contains {
                !Set(OperatorIdentity.codes(forJoined: $0.displayName)).isDisjoint(with: operatorCodes)
            }
        }
        return matches(fields: [trip.service.canonicalName, trip.service.englishName ?? "",
                         trip.publicNumber ?? "", trip.trainNumber,
                         trip.service.canonicalName + (trip.publicNumber ?? trip.trainNumber),
                         trip.service.canonicalName + (trip.publicNumber ?? trip.trainNumber) + "号",
                         (trip.service.englishName ?? "") + (trip.publicNumber ?? trip.trainNumber)]
                + trip.lineSegments.map(\.lineName)
                + trip.operatorSegments.flatMap { OperatorIdentity.searchNames(for: $0.displayName) },
                stops: trip.passengerStops.map { $0.station.name },
                plainFields: [trip.origin?.departureTime ?? "", trip.destination?.arrivalTime ?? ""])
    }

    public func matches(_ pattern: TrainServicePatterns.Pattern) -> Bool {
        if route.isEmpty, let operatorCodes {
            return !Set(OperatorIdentity.codes(forJoined: pattern.company)).isDisjoint(with: operatorCodes)
        }
        return matches(fields: [pattern.name, pattern.label, pattern.companyLabel,
                         pattern.origin, pattern.destination] + pattern.lines
                + (Self.serviceNamesByID[pattern.serviceId] ?? [])
                + OperatorIdentity.searchNames(for: pattern.company),
                stops: pattern.stops)
    }

}
