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
        /// A fixed station identity in the shipped JP station directory.
        /// `name` is a display snapshot; `sourceCode` is the identity.
        public struct StationRef: Codable, Sendable, Hashable {
            public let name: String
            public let sourceCode: String

            public init(name: String, sourceCode: String) {
                self.name = name
                self.sourceCode = sourceCode
            }

            public var stationKey: StationKey {
                StationKey(regionCode: "jp", sourceCode: sourceCode)
            }
        }

        /// A per-field data-completeness rating recorded on a ``Pattern``.
        public enum Level: String, Codable, Sendable {
            case complete, partial, missing
        }

        /// Whether the available validity evidence establishes that this
        /// pattern applies on a particular day.
        public enum Applicability: Sendable, Hashable {
            case applicable
            case notApplicable
            case unknown
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
        public let stopRefs: [StationRef]
        public let optionalStopRefs: [StationRef]
        public var stops: [String] { stopRefs.map(\.name) }
        public var optionalStops: [String] { optionalStopRefs.map(\.name) }
        public let via: [String]
        public let confidence: String?
        public let source: String?
        /// Ordered N02 line names traversed by this pattern.
        public let lines: [String]
        /// Strict Gregorian `YYYY-MM-DD`, validated when the pattern is created.
        public let validFrom: String?
        /// Exclusive end date, matching the dated rail network's [from, until) interval.
        public let validUntil: String?
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
            case lines, validFrom, validUntil, completeness, notes, unsolvableLegs
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
            stopRefs = try container.decode([StationRef].self, forKey: .stops)
            optionalStopRefs = try container.decode([StationRef].self, forKey: .optionalStops)
            via = try container.decode([String].self, forKey: .via)
            confidence = try container.decodeIfPresent(String.self, forKey: .confidence)
            source = try container.decodeIfPresent(String.self, forKey: .source)
            lines = try container.decodeIfPresent([String].self, forKey: .lines) ?? []
            let decodedValidFrom = try container.decodeIfPresent(String.self, forKey: .validFrom)
            let decodedValidUntil = try container.decodeIfPresent(String.self, forKey: .validUntil)
            try Self.validateValidityInterval(
                validFrom: decodedValidFrom,
                validUntil: decodedValidUntil,
                codingPath: decoder.codingPath)
            validFrom = decodedValidFrom
            validUntil = decodedValidUntil
            completeness = try container.decodeIfPresent(
                Completeness.self, forKey: .completeness) ?? .missing
            notes = try container.decodeIfPresent(String.self, forKey: .notes)
            unsolvableLegs = try container.decodeIfPresent(
                [[String]].self, forKey: .unsolvableLegs) ?? []
        }

        public init(
            id: String, serviceId: String, name: String, company: String, label: String,
            origin: String, destination: String, stopRefs: [StationRef], optionalStopRefs: [StationRef],
            via: [String], confidence: String?, source: String?, lines: [String] = [],
            validFrom: String? = nil, validUntil: String? = nil,
            completeness: Completeness = .missing, notes: String? = nil,
            unsolvableLegs: [[String]] = []
        ) {
            precondition(
                Self.hasValidValidityInterval(validFrom: validFrom, validUntil: validUntil),
                "Pattern validity must use a nonempty Gregorian [validFrom, validUntil) interval")
            self.id = id
            self.serviceId = serviceId
            self.name = name
            self.company = company
            self.label = label
            self.origin = origin
            self.destination = destination
            self.stopRefs = stopRefs
            self.optionalStopRefs = optionalStopRefs
            self.via = via
            self.confidence = confidence
            self.source = source
            self.lines = lines
            self.validFrom = validFrom
            self.validUntil = validUntil
            self.completeness = completeness
            self.notes = notes
            self.unsolvableLegs = unsolvableLegs
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(serviceId, forKey: .serviceId)
            try container.encode(name, forKey: .name)
            try container.encode(company, forKey: .company)
            try container.encode(label, forKey: .label)
            try container.encode(origin, forKey: .origin)
            try container.encode(destination, forKey: .destination)
            try container.encode(stopRefs, forKey: .stops)
            try container.encode(optionalStopRefs, forKey: .optionalStops)
            try container.encode(via, forKey: .via)
            try container.encodeIfPresent(confidence, forKey: .confidence)
            try container.encodeIfPresent(source, forKey: .source)
            try container.encode(lines, forKey: .lines)
            try container.encodeIfPresent(validFrom, forKey: .validFrom)
            try container.encodeIfPresent(validUntil, forKey: .validUntil)
            try container.encode(completeness, forKey: .completeness)
            try container.encodeIfPresent(notes, forKey: .notes)
            try container.encode(unsolvableLegs, forKey: .unsolvableLegs)
        }

        /// `company`, mapped through ``OperatorBranding/companyLabel(_:)`` —
        /// which already splits and rejoins on "/" — to the passenger-facing
        /// short names.
        public var companyLabel: String { OperatorBranding.companyLabel(company) }

        /// Classifies a strict Gregorian `YYYY-MM-DD` using the evidence in
        /// this pattern. A known bound can exclude a day even when validity
        /// evidence is incomplete; only complete evidence can confirm one.
        /// Returns `nil` when `day` is malformed or is not a real Gregorian date.
        public func applicability(on day: String) -> Applicability? {
            guard let day = GregorianDay(day),
                  Self.hasValidValidityInterval(validFrom: validFrom, validUntil: validUntil)
            else { return nil }

            if let validFrom = validFrom.flatMap(GregorianDay.init), day < validFrom {
                return .notApplicable
            }
            if let validUntil = validUntil.flatMap(GregorianDay.init), day >= validUntil {
                return .notApplicable
            }
            return completeness.validity == .complete ? .applicable : .unknown
        }

        /// Compatibility facade for callers that require a definite answer.
        /// Invalid input and incomplete evidence both fail closed.
        public func isValid(on day: String) -> Bool {
            applicability(on: day) == .applicable
        }

        /// Whether a pattern's recorded interval covers today. Unknown validity
        /// is not presented as a confirmed current service.
        public var isCurrent: Bool {
            isCurrent(at: Date())
        }

        /// Whether a pattern covers the calendar day containing `instant` in
        /// Japan. Inject an instant in tests to avoid dependence on wall-clock time.
        public func isCurrent(at instant: Date) -> Bool {
            isValid(on: Self.japanOperationalDay(at: instant))
        }

        /// A recorded exclusive end date that has already passed.
        public var isDiscontinued: Bool {
            isDiscontinued(at: Date())
        }

        /// Whether the recorded exclusive end is at or before the calendar day
        /// containing `instant` in Japan.
        public func isDiscontinued(at instant: Date) -> Bool {
            guard let validUntil = validUntil.flatMap(GregorianDay.init),
                  let day = GregorianDay(Self.japanOperationalDay(at: instant))
            else { return false }
            return validUntil <= day
        }

        /// The Gregorian calendar day at `instant` in Japan Standard Time.
        public static func japanOperationalDay(at instant: Date) -> String {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
            let parts = calendar.dateComponents([.year, .month, .day], from: instant)
            guard let year = parts.year, let month = parts.month, let day = parts.day else { return "" }
            return String(format: "%04d-%02d-%02d", year, month, day)
        }

        private static func hasValidValidityInterval(
            validFrom: String?, validUntil: String?
        ) -> Bool {
            let from: GregorianDay?
            if let validFrom {
                guard let parsed = GregorianDay(validFrom) else { return false }
                from = parsed
            } else {
                from = nil
            }

            let until: GregorianDay?
            if let validUntil {
                guard let parsed = GregorianDay(validUntil) else { return false }
                until = parsed
            } else {
                until = nil
            }

            if let from, let until { return from < until }
            return true
        }

        private static func validateValidityInterval(
            validFrom: String?, validUntil: String?, codingPath: [any CodingKey]
        ) throws {
            guard hasValidValidityInterval(validFrom: validFrom, validUntil: validUntil) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: codingPath,
                    debugDescription: "validFrom/validUntil must be real Gregorian YYYY-MM-DD dates forming a nonempty [from, until) interval"))
            }
        }

        private struct GregorianDay: Comparable {
            let rawValue: String

            init?(_ rawValue: String) {
                let bytes = Array(rawValue.utf8)
                guard bytes.count == 10,
                      bytes[4] == 45, bytes[7] == 45,
                      bytes.enumerated().allSatisfy({ index, byte in
                          index == 4 || index == 7 || (48...57).contains(byte)
                      })
                else { return nil }

                func number(_ range: Range<Int>) -> Int {
                    range.reduce(0) { $0 * 10 + Int(bytes[$1] - 48) }
                }
                let year = number(0..<4)
                let month = number(5..<7)
                let day = number(8..<10)
                guard year > 0, (1...12).contains(month) else { return nil }
                let leapYear = year.isMultiple(of: 400)
                    || (year.isMultiple(of: 4) && year.isMultiple(of: 100) == false)
                let daysInMonth = [
                    31, leapYear ? 29 : 28, 31, 30, 31, 30,
                    31, 31, 30, 31, 30, 31,
                ][month - 1]
                guard (1...daysInMonth).contains(day) else { return nil }
                self.rawValue = rawValue
            }

            static func < (lhs: GregorianDay, rhs: GregorianDay) -> Bool {
                lhs.rawValue < rhs.rawValue
            }
        }
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
            case any, onDate, current, discontinued
        }

        /// Matches the stable operator identity, including joined companies.
        public var company: String?
        public var status: Status
        /// ISO calendar date used by `onDate` and date-aware ordering.
        public var rideDate: String?
        /// A canonical line name (see `TrainServiceBranding.canonicalLineName`)
        /// that must appear in `pattern.lines`.
        public var line: String?

        public init(
            company: String? = nil, status: Status = .any,
            line: String? = nil, rideDate: String? = nil
        ) {
            self.company = company
            self.status = status
            self.line = line
            self.rideDate = rideDate
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
        let prepared = SearchFold.PreparedQuery(query)
        let operatorCodes = OperatorIdentity.exactCodes(query: query)
        let normalizedQuery = normalizedText(
            query.trimmingCharacters(in: .whitespacesAndNewlines))
        let servicesByID = Dictionary(
            uniqueKeysWithValues: TrainServiceBranding.services.map { ($0.id, $0) })

        var candidates = patterns.filter { pattern in
            servicesByID[pattern.serviceId]?.region == region
        }

        filterCandidates(&candidates, using: filter)

        let matched: [Pattern]
        if normalizedQuery.isEmpty {
            matched = candidates
        } else {
            matched = candidates.filter { pattern in
                if let operatorCodes {
                    return !Set(OperatorIdentity.codes(forJoined: pattern.company)).isDisjoint(with: operatorCodes)
                }
                return prepared.matches(fields: haystacksByPatternID[pattern.id] ?? [])
            }
        }

        return sortedSearchMatches(matched, queryIsEmpty: normalizedQuery.isEmpty,
            prepared: prepared, rideDate: filter.rideDate)
    }

    private static func filterCandidates(_ candidates: inout [Pattern], using filter: Filter) {
        if let company = filter.company {
            candidates = candidates.filter { OperatorIdentity.sameCompany($0.company, company) }
        }
        switch filter.status {
        case .any: break
        case .onDate:
            if let day = filter.rideDate {
                candidates = candidates.filter { $0.isValid(on: day) }
            }
        case .current: candidates = candidates.filter { $0.isCurrent }
        case .discontinued: candidates = candidates.filter { $0.isDiscontinued }
        }
        if let line = filter.line {
            let canonicalLine = TrainServiceBranding.canonicalLineName(line)
            candidates = candidates.filter { pattern in
                pattern.lines.contains { TrainServiceBranding.canonicalLineName($0) == canonicalLine }
            }
        }
    }

    private static func sortedSearchMatches(
        _ matched: [Pattern], queryIsEmpty: Bool, prepared: SearchFold.PreparedQuery, rideDate: String?
    ) -> [Pattern] {
        if queryIsEmpty {
            return matched.sorted {
                if let day = rideDate, $0.isValid(on: day) != $1.isValid(on: day) {
                    return $0.isValid(on: day)
                }
                if $0.isCurrent != $1.isCurrent { return $0.isCurrent && !$1.isCurrent }
                if $0.name != $1.name { return $0.name < $1.name }
                return $0.label < $1.label
            }
        }

        func isPrimaryMatch(_ pattern: Pattern) -> Bool {
            prepared.matches(fields: primaryHaystacksByPatternID[pattern.id] ?? [])
        }

        return matched.sorted {
            if let day = rideDate, $0.isValid(on: day) != $1.isValid(on: day) {
                return $0.isValid(on: day)
            }
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

    /// Search fields include multilingual operator and family names. Keep the
    /// fields separate so query tokens can match across languages and fields.
    private static let haystacksByPatternID: [String: [String]] = {
        let servicesByID = Dictionary(
            uniqueKeysWithValues: TrainServiceBranding.services.map { ($0.id, $0) })
        return Dictionary(uniqueKeysWithValues: patterns.map { pattern in
            var haystacks = [pattern.name, pattern.label, pattern.origin,
                              pattern.destination, pattern.companyLabel]
            haystacks.append(contentsOf: OperatorIdentity.searchNames(for: pattern.company))
            haystacks.append(contentsOf: pattern.lines)
            haystacks.append(contentsOf: pattern.stops)
            if let service = servicesByID[pattern.serviceId] {
                haystacks.append(contentsOf: service.names)
            }
            return (pattern.id, haystacks)
        })
    }()

    /// Each pattern's "primary" search haystack — its name, label, and every
    /// name its service is known by. A query
    /// that matches here names the service or pattern directly, rather than
    /// matching only via a stop or traversed line; ``search(_:region:filter:)``
    /// ranks those matches first.
    private static let primaryHaystacksByPatternID: [String: [String]] = {
        let servicesByID = Dictionary(
            uniqueKeysWithValues: TrainServiceBranding.services.map { ($0.id, $0) })
        return Dictionary(uniqueKeysWithValues: patterns.map { pattern in
            var haystacks = [pattern.name, pattern.label]
            if let service = servicesByID[pattern.serviceId] {
                haystacks.append(contentsOf: service.names)
            }
            return (pattern.id, haystacks)
        })
    }()

    /// Every pattern's `name`, precomputed once — used by ``apply(_:to:reversed:ridden:)``
    /// to recognize a train number written by an earlier `apply` call, so a
    /// second application (re-picking a different pattern) overwrites it
    /// rather than treating it as user-entered.
    private static let allPatternNames: Set<String> = Set(patterns.map(\.name))

    /// Every pattern's `companyLabel`, precomputed once — see ``allPatternNames``.
    private static let allPatternCompanyLabels: Set<String> = Set(patterns.map(\.companyLabel))

    /// N02 spellings of each pattern's lines. A preferred-line list that
    /// equals one of these was written by an earlier `apply`, so the next
    /// apply may replace it. Any other non-empty list is the user's.
    private static let patternPreferredLineLists: Set<[String]> = Set(
        patterns.map { canonicalPreferredLineNames($0.lines) })

    private static func canonicalPreferredLineNames(_ lines: [String]) -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for line in lines {
            let name = TrainServiceBranding.canonicalLineName(line)
            if !name.isEmpty, seen.insert(name).inserted { names.append(name) }
        }
        return names
    }

    /// A copy of `train` pre-filled from `pattern`: the stop list becomes
    /// `pattern.stops` in order — reversed (destination to origin) when
    /// `reversed` is true — with the first stop "origin", the last
    /// "destination", every stop in between "passenger_stop", and every
    /// stop's `rideSegment` set to `ridden`. `optionalStops` (一部停車) is not
    /// added here — those stations exist so the caller can offer them for
    /// the user to insert.
    ///
    /// Origin, destination and `routeSections` are always overwritten — any
    /// hard line constraints from a previous route are stale once the stop
    /// list changes, the same as the editor's region-reset path. `routePolicy`
    /// keeps user-edited fields. Its preferred lines become the pattern's
    /// lines in N02 spelling (a trailing 本線 folds to 線) unless the train
    /// already carries a preferred-line list that no pattern would have
    /// written. Number, train type and company are overwritten only when
    /// empty or when they still hold a value a previous `apply` call wrote
    /// (so a second pick replaces the first, but a user's own edit survives).
    public static func apply(
        _ pattern: Pattern, to train: Train, reversed: Bool = false, ridden: Bool = true
    ) -> Train {
        var result = train

        let orderedStops = reversed ? Array(pattern.stopRefs.reversed()) : pattern.stopRefs
        result.stops = orderedStops.enumerated().map { index, station in
            let stopType: String
            if index == 0 {
                stopType = "origin"
            } else if index == orderedStops.count - 1 {
                stopType = "destination"
            } else {
                stopType = "passenger_stop"
            }
            return Stop(
                name: station.name, n02StationCode: station.sourceCode,
                stopType: stopType, rideSegment: ridden)
        }
        result.origin = reversed ? pattern.destination : pattern.origin
        result.destination = reversed ? pattern.origin : pattern.destination
        applyRoutePolicy(pattern, to: &result)
        applyServiceMetadata(pattern, to: &result)
        return result
    }

    private static func applyRoutePolicy(_ pattern: Pattern, to result: inout Train) {
        let previousPolicy = result.routePolicy
        let mappedLines = canonicalPreferredLineNames(pattern.lines)
        let previousLines = previousPolicy?.preferredLineNames ?? []
        let keepUserLines = !previousLines.isEmpty
            && !patternPreferredLineLists.contains(previousLines)
        let preferredLines = keepUserLines ? previousLines : mappedLines
        result.routeSections = nil
        if previousPolicy == nil && preferredLines.isEmpty {
            result.routePolicy = nil
        } else {
            result.routePolicy = RoutePolicy(
                mode: "single_primary_route",
                jrOnly: previousPolicy?.jrOnly ?? false,
                allowAlternatives: false,
                allowBrowserStraightLineFallback: false,
                allowedInstitutionTypeCodes: previousPolicy?.allowedInstitutionTypeCodes,
                preferredLineNames: preferredLines.isEmpty ? nil : preferredLines,
                preferredOperatorNames: previousPolicy?.preferredOperatorNames,
                institutionFilterMode: previousPolicy?.institutionFilterMode)
        }
    }

    private static func applyServiceMetadata(_ pattern: Pattern, to result: inout Train) {
        let trimmedNumber = result.number.trimmingCharacters(in: .whitespacesAndNewlines)
        if pattern.id.hasPrefix("timetable:")
            || trimmedNumber.isEmpty || allPatternNames.contains(trimmedNumber)
        {
            result.number = pattern.name
        }
        let trimmedTrainType = (result.trainType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTrainType.isEmpty || ["特急", "寝台特急", "新幹線"].contains(trimmedTrainType) {
            // Route metadata distinguishes shared historical service names such as はくたか.
            // Mini-shinkansen retain conventional-track access through the default soft filter.
            if pattern.lines.contains(where: { $0.contains("新幹線") }) {
                result.trainType = "新幹線"
            } else {
                result.trainType =
                    pattern.name.contains("サンライズ") || pattern.name.contains("瑞風")
                    ? "寝台特急" : "特急"
            }
        }
        let trimmedCompany = (result.company ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if pattern.id.hasPrefix("timetable:")
            || trimmedCompany.isEmpty || allPatternCompanyLabels.contains(trimmedCompany)
        {
            result.company = pattern.companyLabel
        }
        if result.region == nil {
            result.region = "jp"
        }
    }

    private static func normalizedText(_ value: String) -> String {
        let folded = value.precomposedStringWithCompatibilityMapping.lowercased()
        return folded.applyingTransform(.hiraganaToKatakana, reverse: false) ?? folded
    }
}
