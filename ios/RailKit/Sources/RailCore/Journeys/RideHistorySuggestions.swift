import Foundation

/// Suggestions drawn from rides already in the store: when the draft repeats a
/// route or a line, the service class, operator, vehicle, livery and set the
/// user recorded before are likely again. Always medium confidence upstream.
public enum RideHistorySuggestions {
    public enum Match: Sendable, Equatable {
        case sameRoute, sameLine
    }

    public struct Suggestion: Sendable, Equatable {
        public let field: TripInference.Field
        public let value: String
        /// How many matching rides carried this value.
        public let count: Int
        public let match: Match

        public init(field: TripInference.Field, value: String, count: Int, match: Match) {
            self.field = field
            self.value = value
            self.count = count
            self.match = match
        }
    }

    /// For each of train type, company, vehicle type, livery and set number,
    /// the most frequent value among rides with the same origin and
    /// destination; when none of those rides has the field, among rides whose
    /// route sections name `line`. Ties go to the earliest ride in `trains`.
    public static func suggestions(
        from trains: [Train], origin: String?, destination: String?, line: String? = nil
    ) -> [Suggestion] {
        func clean(_ text: String?) -> String? {
            guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
            else { return nil }
            return text
        }
        let from = clean(origin), to = clean(destination), lineName = clean(line)
        let sameRoute: [Train] = (from != nil && to != nil)
            ? trains.filter { $0.origin == from && $0.destination == to } : []
        let sameLine: [Train] = lineName.map { name in
            trains.filter { train in
                (train.routeSections ?? []).contains { ($0.lineNames ?? []).contains(name) }
            }
        } ?? []

        let extractors: [(TripInference.Field, (Train) -> String?)] = [
            (.trainType, { clean($0.trainType) }),
            (.company, { clean($0.company) }),
            (.vehicleType, { clean($0.vehicleType) }),
            (.livery, { clean($0.rollingStock?.livery) }),
            (.setNumber, { clean($0.rollingStock?.setNumber) }),
        ]
        func best(_ pool: [Train], _ value: (Train) -> String?) -> (String, Int)? {
            var counts: [String: Int] = [:]
            var order: [String] = []
            for train in pool {
                guard let item = value(train) else { continue }
                if counts[item] == nil { order.append(item) }
                counts[item, default: 0] += 1
            }
            var winner: (String, Int)?
            for item in order {
                let count = counts[item] ?? 0
                if winner == nil || count > (winner?.1 ?? 0) { winner = (item, count) }
            }
            return winner
        }
        var out: [Suggestion] = []
        for (field, value) in extractors {
            if let (item, count) = best(sameRoute, value) {
                out.append(Suggestion(field: field, value: item, count: count, match: .sameRoute))
            } else if let (item, count) = best(sameLine, value) {
                out.append(Suggestion(field: field, value: item, count: count, match: .sameLine))
            }
        }
        return out
    }
}
