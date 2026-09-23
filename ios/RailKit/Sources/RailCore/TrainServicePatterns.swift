import Foundation

/// The bundled catalog of named limited-express stop patterns — a companion
/// to ``TrainServiceBranding``, which identifies a service by name, and
/// ``Train``, which this can pre-fill with a complete stop list.
public enum TrainServicePatterns {

    /// One route variant of a named service: an origin/destination pair and
    /// the stops between them. A service with multiple route variants —
    /// サンライズ出雲 and サンライズ瀬戸 share the サンライズ name but run to
    /// different destinations — is recorded as separate patterns, one per
    /// `serviceId`.
    public struct Pattern: Codable, Sendable, Identifiable, Hashable {
        public let id: String
        public let serviceId: String
        public let name: String
        /// Legal operator names, "/"-joined (§3.4-style shape) — raw, not yet
        /// mapped to passenger-facing labels. See ``companyLabel``.
        public let company: String
        public let label: String
        public let origin: String
        public let destination: String
        public let stops: [String]
        public let optionalStops: [String]
        public let via: [String]
        public let confidence: String?
        public let source: String?

        private enum CodingKeys: String, CodingKey {
            case id = "patternId"
            case serviceId, name, company, label, origin, destination
            case stops, optionalStops, via, confidence, source
        }

        /// `company`, mapped through ``OperatorBranding/companyLabel(_:)`` —
        /// which already splits and rejoins on "/" — to the passenger-facing
        /// short names.
        public var companyLabel: String { OperatorBranding.companyLabel(company) }
    }

    /// The bundled pattern catalog. A missing or malformed resource is a
    /// packaging error and fails at first use rather than silently disabling
    /// pattern lookup.
    public static let patterns: [Pattern] = {
        guard let url = Bundle.module.url(
            forResource: "train-service-patterns", withExtension: "json")
        else {
            fatalError("RailCore is missing train-service-patterns.json")
        }
        do {
            return try JSONDecoder().decode([Pattern].self, from: Data(contentsOf: url))
        } catch {
            fatalError("RailCore could not decode train-service-patterns.json: \(error)")
        }
    }()

    /// Every pattern that belongs to a given service, in catalog order.
    public static func patterns(for serviceId: String) -> [Pattern] {
        patterns.filter { $0.serviceId == serviceId }
    }

    /// The branding-catalog service a pattern belongs to, if any.
    public static func service(for pattern: Pattern) -> TrainServiceBranding.Service? {
        TrainServiceBranding.services.first { $0.id == pattern.serviceId }
    }

    /// Searches the catalog by every name the pattern's service is known by,
    /// plus the pattern's own name, label, origin, destination, and
    /// passenger-facing company label — case- and width-insensitive, and
    /// hiragana/katakana-insensitive. An empty or whitespace-only query
    /// matches every pattern in `region`. Results are sorted by name, then
    /// label.
    public static func search(_ query: String, region: String = "jp") -> [Pattern] {
        let normalizedQuery = normalizedText(
            query.trimmingCharacters(in: .whitespacesAndNewlines))
        let servicesByID = Dictionary(
            uniqueKeysWithValues: TrainServiceBranding.services.map { ($0.id, $0) })

        let candidates = patterns.filter { pattern in
            servicesByID[pattern.serviceId]?.region == region
        }

        let matched: [Pattern]
        if normalizedQuery.isEmpty {
            matched = candidates
        } else {
            matched = candidates.filter { pattern in
                (haystacksByPatternID[pattern.id] ?? "").contains(normalizedQuery)
            }
        }

        return matched.sorted {
            $0.name != $1.name ? $0.name < $1.name : $0.label < $1.label
        }
    }

    /// Each pattern's normalised search haystack — its name, label, origin,
    /// destination, passenger-facing company label, and every name its
    /// service is known by — joined and normalised once, rather than on
    /// every ``search(_:region:)`` call.
    private static let haystacksByPatternID: [String: String] = {
        let servicesByID = Dictionary(
            uniqueKeysWithValues: TrainServiceBranding.services.map { ($0.id, $0) })
        return Dictionary(uniqueKeysWithValues: patterns.map { pattern in
            var haystacks = [pattern.name, pattern.label, pattern.origin,
                              pattern.destination, pattern.companyLabel]
            if let service = servicesByID[pattern.serviceId] {
                haystacks.append(contentsOf: service.names)
            }
            return (pattern.id, haystacks.map(normalizedText).joined(separator: " "))
        })
    }()

    /// Every pattern's `name`, precomputed once — used by ``apply(_:to:reversed:ridden:)``
    /// to recognize a train number written by an earlier `apply` call, so a
    /// second application (re-picking a different pattern) overwrites it
    /// rather than treating it as user-entered.
    private static let allPatternNames: Set<String> = Set(patterns.map(\.name))

    /// Every pattern's `companyLabel`, precomputed once — see ``allPatternNames``.
    private static let allPatternCompanyLabels: Set<String> = Set(patterns.map(\.companyLabel))

    /// A copy of `train` pre-filled from `pattern`: the stop list becomes
    /// `pattern.stops` in order — reversed (destination to origin) when
    /// `reversed` is true — with the first stop "origin", the last
    /// "destination", every stop in between "passenger_stop", and every
    /// stop's `rideSegment` set to `ridden`. `optionalStops` (一部停車) is not
    /// added here — those stations exist so the caller can offer them for
    /// the user to insert.
    ///
    /// Origin, destination, `routeSections` and `routePolicy` are always
    /// overwritten — any hard line constraints from a previous route are
    /// stale once the stop list changes, the same as the editor's
    /// region-reset path. Number, train type and company are overwritten
    /// only when empty or when they still hold a value a previous `apply`
    /// call wrote (so a second pick replaces the first, but a user's own
    /// edit survives).
    public static func apply(
        _ pattern: Pattern, to train: Train, reversed: Bool = false, ridden: Bool = true
    ) -> Train {
        var result = train

        let orderedStops = reversed ? pattern.stops.reversed().map { $0 } : pattern.stops
        result.stops = orderedStops.enumerated().map { index, name in
            let stopType: String
            if index == 0 {
                stopType = "origin"
            } else if index == orderedStops.count - 1 {
                stopType = "destination"
            } else {
                stopType = "passenger_stop"
            }
            return Stop(name: name, stopType: stopType, rideSegment: ridden)
        }
        result.origin = reversed ? pattern.destination : pattern.origin
        result.destination = reversed ? pattern.origin : pattern.destination
        result.routeSections = nil
        result.routePolicy = nil

        let trimmedNumber = result.number.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedNumber.isEmpty || allPatternNames.contains(trimmedNumber) {
            result.number = pattern.name
        }
        let trimmedTrainType = (result.trainType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTrainType.isEmpty || trimmedTrainType == "特急" || trimmedTrainType == "寝台特急" {
            result.trainType =
                pattern.name.contains("サンライズ") || pattern.name.contains("瑞風")
                ? "寝台特急" : "特急"
        }
        let trimmedCompany = (result.company ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedCompany.isEmpty || allPatternCompanyLabels.contains(trimmedCompany) {
            result.company = pattern.companyLabel
        }
        if result.region == nil {
            result.region = "jp"
        }

        return result
    }

    private static func normalizedText(_ value: String) -> String {
        let folded = value.precomposedStringWithCompatibilityMapping.lowercased()
        return folded.applyingTransform(.hiraganaToKatakana, reverse: false) ?? folded
    }
}
