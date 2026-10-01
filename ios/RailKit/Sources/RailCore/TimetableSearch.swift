import Foundation

/// Free-text discovery is separate from the exact, timed editor match.
/// Whitespace combines terms; an arrow constrains the order of passenger calls.
public struct TimetableSearch: Sendable {
    private static let serviceNamesByID = Dictionary(uniqueKeysWithValues:
        TrainServiceBranding.services.map { ($0.id, $0.names) })
    private let terms: [String]
    private let route: [String]

    public init(_ text: String) {
        let normalized = Self.normalize(text).replacingOccurrences(of: "->", with: "→")
        let parts = normalized.components(separatedBy: "→")
        route = parts.count > 1 ? parts.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        } : []
        terms = normalized.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    public func matches(fields: [String], stops: [String]) -> Bool {
        if terms.isEmpty && route.isEmpty { return true }
        if !route.isEmpty {
            let stations = stops.map(Self.normalize)
            guard route.allSatisfy({ !$0.isEmpty }) else { return false }
            var nextIndex = 0
            for station in route {
                guard let index = stations.indices.first(where: {
                    $0 >= nextIndex && stations[$0].contains(station)
                }) else { return false }
                nextIndex = index + 1
            }
            return true
        }
        let values = (fields + stops).map(Self.normalize)
        return terms.allSatisfy { term in
            values.contains { $0.contains(term) }
        }
    }

    public func matches(_ trip: TrainTimetableDatabase.Trip) -> Bool {
        matches(fields: [trip.service.canonicalName, trip.service.englishName ?? "",
                         trip.publicNumber ?? "", trip.trainNumber,
                         trip.service.canonicalName + (trip.publicNumber ?? trip.trainNumber),
                         trip.service.canonicalName + (trip.publicNumber ?? trip.trainNumber) + "号",
                         (trip.service.englishName ?? "") + (trip.publicNumber ?? trip.trainNumber),
                         trip.origin?.departureTime ?? "", trip.destination?.arrivalTime ?? ""]
                + trip.lineSegments.map(\.lineName)
                + trip.operatorSegments.map(\.displayName),
                stops: trip.passengerStops.map { $0.station.name })
    }

    public func matches(_ pattern: TrainServicePatterns.Pattern) -> Bool {
        matches(fields: [pattern.name, pattern.label, pattern.companyLabel,
                         pattern.origin, pattern.destination] + pattern.lines
                + (Self.serviceNamesByID[pattern.serviceId] ?? []),
                stops: pattern.stops)
    }

    private static func normalize(_ value: String) -> String {
        let folded = value.precomposedStringWithCompatibilityMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        return folded.applyingTransform(.hiraganaToKatakana, reverse: false) ?? folded
    }
}
