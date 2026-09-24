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
        /// A per-field data-completeness rating recorded on a ``Pattern``.
        public enum Level: String, Codable, Sendable {
            case complete, partial, missing
        }

        /// Per-field completeness of a pattern's data — how much of the
        /// stop list, line list, and validity window is actually known,
        /// as opposed to merely present-but-empty.
        public struct Completeness: Codable, Sendable, Hashable {
            public let stops: Level
            public let lines: Level
            public let validity: Level

            public init(stops: Level, lines: Level, validity: Level) {
                self.stops = stops
                self.lines = lines
                self.validity = validity
            }

            public static let missing = Completeness(stops: .missing, lines: .missing, validity: .missing)
        }

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
        /// Ordered N02 line names traversed by this pattern.
        public let lines: [String]
        /// ISO `YYYY-MM-DD`. Not parsed to `Date` here — comparisons and
        /// formatting are the caller's concern.
        public let validFrom: String?
        public let validTo: String?
        public let completeness: Completeness
        public let notes: String?
        /// Consecutive-stop pairs known not to solve against the route
        /// graph — recorded so route-solving tests can skip them without
        /// masking genuine regressions.
        public let unsolvableLegs: [[String]]

        private enum CodingKeys: String, CodingKey {
            case id = "patternId"
            case serviceId, name, company, label, origin, destination
            case stops, optionalStops, via, confidence, source
            case lines, validFrom, validTo, completeness, notes, unsolvableLegs
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            serviceId = try container.decode(String.self, forKey: .serviceId)
            name = try container.decode(String.self, forKey: .name)
            company = try container.decode(String.self, forKey: .company)
            label = try container.decode(String.self, forKey: .label)
            origin = try container.decode(String.self, forKey: .origin)
            destination = try container.decode(String.self, forKey: .destination)
            stops = try container.decode([String].self, forKey: .stops)
            optionalStops = try container.decode([String].self, forKey: .optionalStops)
            via = try container.decode([String].self, forKey: .via)
            confidence = try container.decodeIfPresent(String.self, forKey: .confidence)
            source = try container.decodeIfPresent(String.self, forKey: .source)
            lines = try container.decodeIfPresent([String].self, forKey: .lines) ?? []
            validFrom = try container.decodeIfPresent(String.self, forKey: .validFrom)
            validTo = try container.decodeIfPresent(String.self, forKey: .validTo)
            completeness = try container.decodeIfPresent(
                Completeness.self, forKey: .completeness) ?? .missing
            notes = try container.decodeIfPresent(String.self, forKey: .notes)
            unsolvableLegs = try container.decodeIfPresent(
                [[String]].self, forKey: .unsolvableLegs) ?? []
        }

        public init(
            id: String, serviceId: String, name: String, company: String, label: String,
            origin: String, destination: String, stops: [String], optionalStops: [String],
            via: [String], confidence: String?, source: String?, lines: [String] = [],
            validFrom: String? = nil, validTo: String? = nil,
            completeness: Completeness = .missing, notes: String? = nil,
            unsolvableLegs: [[String]] = []
        ) {
            self.id = id
            self.serviceId = serviceId
            self.name = name
            self.company = company
            self.label = label
            self.origin = origin
            self.destination = destination
            self.stops = stops
            self.optionalStops = optionalStops
            self.via = via
            self.confidence = confidence
            self.source = source
            self.lines = lines
            self.validFrom = validFrom
            self.validTo = validTo
            self.completeness = completeness
            self.notes = notes
            self.unsolvableLegs = unsolvableLegs
        }

        /// `company`, mapped through ``OperatorBranding/companyLabel(_:)`` —
        /// which already splits and rejoins on "/" — to the passenger-facing
        /// short names.
        public var companyLabel: String { OperatorBranding.companyLabel(company) }

        /// True when the pattern has no recorded end-of-service date.
        public var isCurrent: Bool { validTo == nil }
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

    /// Narrows a ``search(_:region:filter:)`` call by validity status,
    /// operator, and/or traversed line, on top of the free-text query.
    public struct Filter: Sendable, Hashable {
        public enum Status: Sendable, Hashable {
            case any, current, discontinued
        }

        /// Matches `Pattern.companyLabel` exactly.
        public var company: String?
        public var status: Status
        /// A canonical line name (see `TrainServiceBranding.canonicalLineName`)
        /// that must appear in `pattern.lines`.
        public var line: String?

        public init(company: String? = nil, status: Status = .any, line: String? = nil) {
            self.company = company
            self.status = status
            self.line = line
        }
    }

    /// Searches the catalog by every name the pattern's service is known by,
    /// plus the pattern's own name, label, origin, destination, traversed
    /// lines, stops, and passenger-facing company label — case- and
    /// width-insensitive, and hiragana/katakana-insensitive. An empty or
    /// whitespace-only query matches every pattern in `region`. `filter`
    /// further narrows results by validity status, operator, and/or line.
    /// Results are sorted with current patterns before discontinued ones;
    /// for a non-empty query, patterns whose name, label, or service names
    /// contain the query rank ahead of patterns that matched only via a
    /// stop or traversed line; ties break by name, then label.
    public static func search(_ query: String, region: String = "jp") -> [Pattern] {
        search(query, region: region, filter: Filter())
    }

    public static func search(_ query: String, region: String = "jp", filter: Filter) -> [Pattern] {
        let normalizedQuery = normalizedText(
            query.trimmingCharacters(in: .whitespacesAndNewlines))
        let servicesByID = Dictionary(
            uniqueKeysWithValues: TrainServiceBranding.services.map { ($0.id, $0) })

        var candidates = patterns.filter { pattern in
            servicesByID[pattern.serviceId]?.region == region
        }

        if let company = filter.company {
            candidates = candidates.filter { $0.companyLabel == company }
        }
        switch filter.status {
        case .any: break
        case .current: candidates = candidates.filter { $0.isCurrent }
        case .discontinued: candidates = candidates.filter { $0.isCurrent == false }
        }
        if let line = filter.line {
            let canonicalLine = TrainServiceBranding.canonicalLineName(line)
            candidates = candidates.filter { pattern in
                pattern.lines.contains { TrainServiceBranding.canonicalLineName($0) == canonicalLine }
            }
        }

        let matched: [Pattern]
        if normalizedQuery.isEmpty {
            matched = candidates
        } else {
            matched = candidates.filter { pattern in
                (haystacksByPatternID[pattern.id] ?? "").contains(normalizedQuery)
            }
        }

        if normalizedQuery.isEmpty {
            return matched.sorted {
                if $0.isCurrent != $1.isCurrent { return $0.isCurrent && !$1.isCurrent }
                if $0.name != $1.name { return $0.name < $1.name }
                return $0.label < $1.label
            }
        }

        func isPrimaryMatch(_ pattern: Pattern) -> Bool {
            (primaryHaystacksByPatternID[pattern.id] ?? "").contains(normalizedQuery)
        }

        return matched.sorted {
            if $0.isCurrent != $1.isCurrent { return $0.isCurrent && !$1.isCurrent }
            let primary0 = isPrimaryMatch($0)
            let primary1 = isPrimaryMatch($1)
            if primary0 != primary1 { return primary0 && !primary1 }
            if $0.name != $1.name { return $0.name < $1.name }
            return $0.label < $1.label
        }
    }

    /// Every distinct `companyLabel` among `region`'s patterns, sorted.
    public static func companyLabels(region: String = "jp") -> [String] {
        let servicesByID = Dictionary(
            uniqueKeysWithValues: TrainServiceBranding.services.map { ($0.id, $0) })
        let labels = patterns
            .filter { servicesByID[$0.serviceId]?.region == region }
            .map(\.companyLabel)
        return Array(Set(labels)).sorted()
    }

    /// Every distinct raw line name among `region`'s patterns, sorted.
    public static func lineNames(region: String = "jp") -> [String] {
        let servicesByID = Dictionary(
            uniqueKeysWithValues: TrainServiceBranding.services.map { ($0.id, $0) })
        let names = patterns
            .filter { servicesByID[$0.serviceId]?.region == region }
            .flatMap(\.lines)
        return Array(Set(names)).sorted()
    }

    /// Each pattern's normalised search haystack — its name, label, origin,
    /// destination, passenger-facing company label, traversed lines, stops,
    /// and every name its service is known by — joined and normalised once,
    /// rather than on every ``search(_:region:filter:)`` call.
    private static let haystacksByPatternID: [String: String] = {
        let servicesByID = Dictionary(
            uniqueKeysWithValues: TrainServiceBranding.services.map { ($0.id, $0) })
        return Dictionary(uniqueKeysWithValues: patterns.map { pattern in
            var haystacks = [pattern.name, pattern.label, pattern.origin,
                              pattern.destination, pattern.companyLabel]
            haystacks.append(contentsOf: pattern.lines)
            haystacks.append(contentsOf: pattern.stops)
            if let service = servicesByID[pattern.serviceId] {
                haystacks.append(contentsOf: service.names)
            }
            return (pattern.id, haystacks.map(normalizedText).joined(separator: " "))
        })
    }()

    /// Each pattern's "primary" search haystack — its name, label, and every
    /// name its service is known by, joined and normalised once. A query
    /// that matches here names the service or pattern directly, rather than
    /// matching only via a stop or traversed line; ``search(_:region:filter:)``
    /// ranks those matches first.
    private static let primaryHaystacksByPatternID: [String: String] = {
        let servicesByID = Dictionary(
            uniqueKeysWithValues: TrainServiceBranding.services.map { ($0.id, $0) })
        return Dictionary(uniqueKeysWithValues: patterns.map { pattern in
            var haystacks = [pattern.name, pattern.label]
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
