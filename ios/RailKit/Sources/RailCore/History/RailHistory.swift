import Foundation

/// Canonical solver context shared by cache keys and precomputed provenance.
/// Region codes are sorted so opposite directions of a border crossing use
/// the same history identity.
public struct RailHistoryRevisionSet: Sendable, Equatable {
    public let revisions: [String: String]
    public let contentHashes: [String: String]

    public init(
        _ revisions: [String: String?],
        contentHashes: [String: String] = [:]
    ) {
        self.revisions = revisions.mapValues { $0 ?? "none" }
        self.contentHashes = contentHashes
    }

    public var canonical: String {
        let revisionIdentity = revisions.keys.sorted().map { "\($0):\(revisions[$0]!)" }
            .joined(separator: "|")
        guard !contentHashes.isEmpty else { return revisionIdentity }
        let hashIdentity = contentHashes.keys.sorted().map { "\($0):\(contentHashes[$0]!)" }
            .joined(separator: "|")
        return "\(revisionIdentity)|hashes:\(hashIdentity)"
    }
}

/// Provenance emitted with each precomputed route. A matching train record
/// alone cannot attest which dated network produced its geometry.
public struct RailPrecomputedSolverContext: Decodable, Sendable, Equatable {
    public let solverVersion: String
    public let routeCacheDigest: String
    public let rideDate: String?
    public let historyRevisions: [String: String]
    public let historyHashes: [String: String]?

    private enum CodingKeys: String, CodingKey {
        case solverVersion = "solver_version"
        case routeCacheDigest = "route_cache_digest"
        case rideDate = "ride_date"
        case historyRevisions = "history_revisions"
        case historyHashes = "history_hashes"
    }
}

public enum RailPrecomputedRouteGate {
    public static func accepts(
        _ context: RailPrecomputedSolverContext?,
        expectedDigest: String,
        solverVersion: String,
        rideDate: String?,
        revisions: RailHistoryRevisionSet,
        expectedHashes: [String: String]? = nil
    ) -> Bool {
        if let context {
            guard context.solverVersion == solverVersion
                && context.routeCacheDigest == expectedDigest
                && context.rideDate == rideDate
                && context.historyRevisions == revisions.revisions
            else { return false }
            if let expectedHashes {
                return context.historyHashes == expectedHashes
            }
            return true
        }
        // A caller supplying the current content hashes requires an attested
        // precomputed context.  Falling back to the legacy undated rule here
        // would accept bytes from a different snapshot with the same revision.
        if expectedHashes != nil { return false }
        // Legacy parts have no network attestation. Dated rides in a region
        // with history must be solved on demand instead.
        return rideDate == nil || !revisions.revisions.values.contains(where: { $0 != "none" })
    }
}

/// Service interval the ride solver reads.
///
/// `service`, when present, wins. Otherwise today's `validFrom`/`validTo`
/// (`hasLegacy` is key presence, so an empty string still counts as the
/// legacy pair). A lone infrastructure pair is that service interval.
public enum RailServiceValidity {
    public static func bounds(
        service: [String?]?, infrastructure: [String?]?,
        validFrom: String?, validTo: String?, hasLegacy: Bool
    ) -> (String?, String?) {
        if let service, service.count == 2 {
            return (service[0], service[1])
        }
        if let infrastructure, !hasLegacy, infrastructure.count == 2 {
            return (infrastructure[0], infrastructure[1])
        }
        return (validFrom, validTo)
    }
}

/// A per-region history overlay (`rail-history[-<cc>].json`), per ADR 0011.
///
/// The overlay carries retired sections and stations — features absent from
/// the current package, with their own geometry — plus `retirements` that
/// stamp current features and `identity_periods` that date old names onto
/// unchanged current geometry. Nothing is dropped from the solver graph.
public struct RailHistoryOverlay: Decodable, Sendable {
    public static let supportedSchemaVersion = "1"
    public static let kinds: Set<String> = [
        "opening", "closure", "relocation", "station_opening", "station_closure",
        "suspension", "resumption", "operator_transfer",
    ]

    public enum ValidationError: Error, Equatable {
        case invalid(String)
    }
    public var schemaVersion: String
    public var revision: String
    public var sections: [RouteGraph.SectionFeature]
    public var stations: [Stations.Feature]
    public var retirements: [Retirement]
    public var identityPeriods: [IdentityPeriod]

    public struct Retirement: Decodable, Sendable {
        public var historyId: String
        public var match: Match
        public var validFrom: String?
        public var validTo: String?
        public var source: String?

        public struct Match: Decodable, Sendable {
            public var lineName: String
            public var `operator`: String
            /// `[minLon, minLat, maxLon, maxLat]`.
            public var bbox: [Double]
            /// Nil stamps sections and stations. Otherwise `"sections"` and/or
            /// `"stations"`. Omitted on every retirement shipped today.
            public var targets: [String]?
            public var stationName: String?

            private enum CodingKeys: String, CodingKey {
                case lineName = "line_name"
                case `operator`
                case bbox
                case targets
                case stationName = "station_name"
            }

            func allows(_ target: String) -> Bool {
                guard let targets, !targets.isEmpty else { return true }
                return targets.contains(target)
            }
        }

        public var serviceValidity: [String?]?
        public var infrastructureValidity: [String?]?

        private enum CodingKeys: String, CodingKey {
            case historyId = "history_id"
            case match
            case validFrom = "valid_from"
            case validTo = "valid_to"
            case serviceValidity = "service_validity"
            case infrastructureValidity = "infrastructure_validity"
            case source
        }
    }

    public struct IdentityPeriod: Decodable, Sendable {
        public var historyId: String
        public var match: Retirement.Match
        public var validFrom: String?
        public var validTo: String
        public var identity: Identity
        public var source: String
        public var officialEventId: String?

        public struct Identity: Decodable, Sendable {
            public var railwayClassCode: String?
            public var institutionTypeCode: String?
            public var lineName: String
            public var `operator`: String
            public var stationName: String?

            private enum CodingKeys: String, CodingKey {
                case railwayClassCode = "N02_001"
                case institutionTypeCode = "N02_002"
                case lineName = "N02_003"
                case `operator` = "N02_004"
                case stationName = "N02_005"
            }
        }

        private enum CodingKeys: String, CodingKey {
            case historyId = "history_id"
            case match
            case validFrom = "valid_from"
            case validTo = "valid_to"
            case identity = "as"
            case source
            case officialEventId = "official_event_id"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case revision
        case sections
        case stations
        case retirements
        case identityPeriods = "identity_periods"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(String.self, forKey: .schemaVersion) ?? ""
        // `revision` has no default: a missing revision cannot be folded into
        // the route cache key, so decode fails loudly rather than silently
        // using an empty string that would collide with a legitimately empty
        // revision.
        revision = try c.decode(String.self, forKey: .revision)
        sections = try c.decodeIfPresent([RouteGraph.SectionFeature].self, forKey: .sections) ?? []
        stations = try c.decodeIfPresent([Stations.Feature].self, forKey: .stations) ?? []
        retirements = try c.decodeIfPresent([Retirement].self, forKey: .retirements) ?? []
        identityPeriods = try c.decodeIfPresent([IdentityPeriod].self, forKey: .identityPeriods) ?? []
    }

    public static func load(from url: URL) throws -> RailHistoryOverlay {
        try decode(Data(contentsOf: url))
    }

    public static func decode(_ data: Data) throws -> RailHistoryOverlay {
        try validate(data)
        return try JSONDecoder().decode(RailHistoryOverlay.self, from: data)
    }

    /// Validate the source JSON before decoding. Section features keep
    /// `history_id` (see ``RouteGraph/SectionProperties``), but a malformed
    /// identifier still has to fail here — decode would otherwise turn a
    /// missing id into `nil` and look like a current-package feature.
    private static func validate(_ data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ValidationError.invalid("root")
        }
        guard root["schema_version"] as? String == supportedSchemaVersion else {
            throw ValidationError.invalid("schema_version")
        }
        guard let revision = root["revision"] as? String,
              !revision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.invalid("revision")
        }

        var sectionIDs = Set<String>()
        var stationIDs = Set<String>()
        var retirementIDs = Set<String>()
        for kind in ["sections", "stations"] {
            guard let features = root[kind] as? [[String: Any]] else {
                throw ValidationError.invalid(kind)
            }
            for feature in features {
                guard let properties = feature["properties"] as? [String: Any],
                      let id = properties["history_id"] as? String,
                      !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ValidationError.invalid("\(kind).history_id")
                }
                try validateInterval(properties, field: kind)
                try validateKind(properties["kind"], field: kind)
                let canonicalID = id.trimmingCharacters(in: .whitespacesAndNewlines)
                if kind == "sections" {
                    // Multiple geometry fragments intentionally share one
                    // logical history event identifier.
                    sectionIDs.insert(canonicalID)
                } else if !stationIDs.insert(canonicalID).inserted {
                    throw ValidationError.invalid("duplicate station history_id: \(id)")
                }
            }
        }
        guard let retirements = root["retirements"] as? [[String: Any]] else {
            throw ValidationError.invalid("retirements")
        }
        for retirement in retirements {
            guard let id = retirement["history_id"] as? String,
                  !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ValidationError.invalid("retirements.history_id")
            }
            guard retirementIDs.insert(id.trimmingCharacters(in: .whitespacesAndNewlines)).inserted else {
                throw ValidationError.invalid("duplicate retirement history_id: \(id)")
            }
            try validateInterval(retirement, field: "retirements")
            try validateKind(retirement["kind"], field: "retirements")
            guard let match = retirement["match"] as? [String: Any],
                  let bbox = match["bbox"] as? [Double], bbox.count == 4,
                  bbox.allSatisfy(\.isFinite), bbox[0] <= bbox[2], bbox[1] <= bbox[3] else {
                throw ValidationError.invalid("retirements.bbox")
            }
            if let targets = match["targets"] {
                guard let names = targets as? [String], !names.isEmpty,
                      names.allSatisfy({ $0 == "sections" || $0 == "stations" }) else {
                    throw ValidationError.invalid("retirements.targets")
                }
            }
        }
        let identityPeriods = root["identity_periods"] as? [[String: Any]] ?? []
        var identityPeriodIDs = Set<String>()
        var periodsBySelector: [String: [(String?, String, String)]] = [:]
        for period in identityPeriods {
            guard let id = period["history_id"] as? String,
                  !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  identityPeriodIDs.insert(id).inserted else {
                throw ValidationError.invalid("identity_periods.history_id")
            }
            try validateInterval(period, field: "identity_periods")
            guard period["service_validity"] == nil,
                  period["infrastructure_validity"] == nil,
                  let validTo = period["valid_to"] as? String else {
                throw ValidationError.invalid("identity_periods.valid_to")
            }
            guard let match = period["match"] as? [String: Any],
                  let lineName = match["line_name"] as? String, !lineName.isEmpty,
                  let operatorName = match["operator"] as? String, !operatorName.isEmpty,
                  let bbox = match["bbox"] as? [Double], bbox.count == 4,
                  bbox.allSatisfy(\.isFinite), bbox[0] <= bbox[2], bbox[1] <= bbox[3] else {
                throw ValidationError.invalid("identity_periods.match")
            }
            let targets = match["targets"] as? [String]
            if let targets, targets.isEmpty || !targets.allSatisfy({ $0 == "sections" || $0 == "stations" }) {
                throw ValidationError.invalid("identity_periods.targets")
            }
            if let stationName = match["station_name"], !(stationName is String) {
                throw ValidationError.invalid("identity_periods.station_name")
            }
            guard let identity = period["as"] as? [String: Any],
                  let oldLine = identity["N02_003"] as? String, !oldLine.isEmpty,
                  let oldOperator = identity["N02_004"] as? String, !oldOperator.isEmpty,
                  identity["N02_001"] == nil || identity["N02_001"] is String,
                  identity["N02_002"] == nil || identity["N02_002"] is String,
                  identity["N02_005"] == nil || identity["N02_005"] is String,
                  let source = period["source"] as? String, !source.isEmpty else {
                throw ValidationError.invalid("identity_periods.as")
            }
            let selectorParts: [String] = [lineName, operatorName,
                match["station_name"] as? String ?? ""]
                + bbox.map { String($0) }
                + (targets ?? ["sections", "stations"]).sorted()
            let selector = selectorParts
                .joined(separator: "\u{1f}")
            let from = period["valid_from"] as? String
            for (otherFrom, otherTo, otherID) in periodsBySelector[selector, default: []]
            where (otherFrom == nil || validTo > otherFrom!) && (from == nil || otherTo > from!) {
                throw ValidationError.invalid("identity period overlap: \(id) / \(otherID)")
            }
            periodsBySelector[selector, default: []].append((from, validTo, id))
        }
        guard sectionIDs.isDisjoint(with: stationIDs),
              sectionIDs.isDisjoint(with: retirementIDs),
              stationIDs.isDisjoint(with: retirementIDs),
              sectionIDs.isDisjoint(with: identityPeriodIDs),
              stationIDs.isDisjoint(with: identityPeriodIDs),
              retirementIDs.isDisjoint(with: identityPeriodIDs) else {
            throw ValidationError.invalid("duplicate history_id across kinds")
        }
    }

    private static func validateKind(_ value: Any?, field: String) throws {
        if value == nil { return }
        guard let kind = value as? String, kinds.contains(kind) else {
            throw ValidationError.invalid("\(field).kind")
        }
    }

    private static func validatePair(
        _ object: [String: Any], key: String, field: String
    ) throws -> (String?, String?, Bool) {
        guard object[key] != nil else { return (nil, nil, false) }
        guard let pair = object[key] as? [Any], pair.count == 2 else {
            throw ValidationError.invalid("\(field).\(key)")
        }
        func bound(_ value: Any) throws -> String? {
            if value is NSNull { return nil }
            guard let text = value as? String, isRealISODay(text) else {
                throw ValidationError.invalid("\(field).\(key)")
            }
            return text
        }
        let from = try bound(pair[0])
        let to = try bound(pair[1])
        if let from, let to, from >= to {
            throw ValidationError.invalid("\(field).\(key)")
        }
        return (from, to, true)
    }

    private static func validateInterval(_ object: [String: Any], field: String) throws {
        for key in ["valid_from", "valid_to"] where object[key] != nil && !(object[key] is String) {
            throw ValidationError.invalid("\(field).\(key)")
        }
        let from = object["valid_from"] as? String
        let to = object["valid_to"] as? String
        for value in [from, to].compactMap({ $0 }) where !isRealISODay(value) {
            throw ValidationError.invalid("\(field).date: \(value)")
        }
        if let from, let to, from >= to {
            throw ValidationError.invalid("\(field).interval")
        }
        let service = try validatePair(object, key: "service_validity", field: field)
        let infrastructure = try validatePair(object, key: "infrastructure_validity", field: field)
        let hasDomain = (service.2 && (service.0 != nil || service.1 != nil))
            || (infrastructure.2 && (infrastructure.0 != nil || infrastructure.1 != nil))
        guard from != nil || to != nil || hasDomain else {
            throw ValidationError.invalid("\(field).interval")
        }
    }

    private static func isRealISODay(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
              bytes.enumerated().allSatisfy({ index, byte in
                  index == 4 || index == 7 || (48...57).contains(byte)
              }),
              let year = Int(value.prefix(4)),
              let month = Int(value.dropFirst(5).prefix(2)),
              let day = Int(value.suffix(2)), year > 0 else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            return false
        }
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return parts.year == year && parts.month == month && parts.day == day
    }
}

/// Applies a ``RailHistoryOverlay`` to a solver network, per ADR 0011.
public enum RailHistory {
    public struct ApplyReport: Sendable, Equatable {
        public var sectionsAdded: Int
        public var stationsAdded: Int
        /// `history_id` → matched feature count (sections + stations).
        public var retirementsApplied: [String: Int]
        /// `history_id`s that matched nothing — a data error the caller logs.
        public var unmatchedRetirements: [String]
        public var identityPeriodsApplied: [String: Int]
        public var unmatchedIdentityPeriods: [String]

        public init(
            sectionsAdded: Int = 0, stationsAdded: Int = 0,
            retirementsApplied: [String: Int] = [:], unmatchedRetirements: [String] = [],
            identityPeriodsApplied: [String: Int] = [:], unmatchedIdentityPeriods: [String] = []
        ) {
            self.sectionsAdded = sectionsAdded
            self.stationsAdded = stationsAdded
            self.retirementsApplied = retirementsApplied
            self.unmatchedRetirements = unmatchedRetirements
            self.identityPeriodsApplied = identityPeriodsApplied
            self.unmatchedIdentityPeriods = unmatchedIdentityPeriods
        }
    }

    /// Stamps retirements onto matching current features, then appends the
    /// overlay's own sections and stations.
    public static func apply(
        _ overlay: RailHistoryOverlay,
        sections: inout [RouteGraph.SectionFeature],
        stations: inout [Stations.Feature]
    ) -> ApplyReport {
        var retirementsApplied: [String: Int] = [:]
        var unmatchedRetirements: [String] = []

        let retirementIDs = Set(overlay.retirements.map(\.historyId))

        for retirement in overlay.retirements {
            var matched = 0

            let bounds = serviceBounds(of: retirement)
            if retirement.match.allows("sections") {
                for index in sections.indices {
                    guard matches(retirement.match, lineName: sections[index].properties.lineName,
                        operatorName: sections[index].properties.operator,
                        points: sections[index].lines.flatMap { $0 })
                    else { continue }
                    matched += 1
                    if let validFrom = bounds.0 {
                        sections[index].properties.validFrom = validFrom
                        // `valid_from` marks the current alignment that replaced a
                        // retired one. A later `valid_to`-only stamp must not
                        // collapse that back to `.current`.
                        if sections[index].properties.temporalKind == .current {
                            sections[index].properties.temporalKind = .relocatedNew
                        }
                        if sections[index].properties.historyId == nil {
                            sections[index].properties.historyId = retirement.historyId
                        }
                    }
                    if let validTo = bounds.1 {
                        sections[index].properties.validTo = validTo
                    }
                }
            }

            if retirement.match.allows("stations") {
                for index in stations.indices {
                    let feature = stations[index]
                    let lineName = Stations.stationLineName(feature)
                    let operatorName = Stations.stationOperator(feature)
                    guard
                        matches(retirement.match, lineName: lineName, operatorName: operatorName,
                            points: stationPoints(feature.geometry))
                    else { continue }
                    matched += 1
                    if let validFrom = bounds.0 {
                        stations[index].properties["valid_from"] = .string(validFrom)
                    }
                    if let validTo = bounds.1 {
                        stations[index].properties["valid_to"] = .string(validTo)
                    }
                    if let service = retirement.serviceValidity {
                        stations[index].properties["service_validity"] = pairValue(service)
                    }
                    if let infrastructure = retirement.infrastructureValidity {
                        stations[index].properties["infrastructure_validity"] = pairValue(infrastructure)
                    }
                }
            }

            retirementsApplied[retirement.historyId] = matched
            if matched == 0 {
                unmatchedRetirements.append(retirement.historyId)
            }
        }

        var identityPeriodsApplied = Dictionary(
            uniqueKeysWithValues: overlay.identityPeriods.map { ($0.historyId, 0) })
        if !overlay.identityPeriods.isEmpty {
            let currentSections = sections
            sections = currentSections.flatMap { feature in
                let periods = overlay.identityPeriods.filter {
                    $0.match.allows("sections") && matches(
                        $0.match, lineName: feature.properties.lineName,
                        operatorName: feature.properties.operator, stationName: nil,
                        points: feature.lines.flatMap { $0 })
                }
                for period in periods { identityPeriodsApplied[period.historyId, default: 0] += 1 }
                return sectionIdentityVariants(feature, periods: periods)
            }
            let currentStations = stations
            stations = currentStations.flatMap { feature in
                let periods = overlay.identityPeriods.filter {
                    $0.match.allows("stations") && matches(
                        $0.match, lineName: Stations.stationLineName(feature),
                        operatorName: Stations.stationOperator(feature),
                        stationName: Stations.stationName(feature),
                        points: stationPoints(feature.geometry))
                }
                for period in periods { identityPeriodsApplied[period.historyId, default: 0] += 1 }
                return stationIdentityVariants(feature, periods: periods)
            }
        }

        var overlaySections = overlay.sections
        for index in overlaySections.indices {
            overlaySections[index].properties.temporalKind = overlaySectionKind(
                historyId: overlaySections[index].properties.historyId,
                retirementIDs: retirementIDs)
        }
        sections.append(contentsOf: overlaySections)
        stations.append(contentsOf: overlay.stations)

        return ApplyReport(
            sectionsAdded: overlay.sections.count, stationsAdded: overlay.stations.count,
            retirementsApplied: retirementsApplied, unmatchedRetirements: unmatchedRetirements,
            identityPeriodsApplied: identityPeriodsApplied,
            unmatchedIdentityPeriods: identityPeriodsApplied.compactMap { $0.value == 0 ? $0.key : nil }.sorted())
    }

    /// Overlay sections are historical unless swapping `.old-` for `.new-` in
    /// `history_id` names a retirement in the same overlay. That pair is a
    /// relocation: the overlay feature is the old alignment.
    private static func overlaySectionKind(
        historyId: String?, retirementIDs: Set<String>
    ) -> RouteGraph.TemporalKind {
        guard let historyId else { return .historical }
        let relocated = historyId.replacingOccurrences(of: ".old-", with: ".new-")
        if relocated != historyId, retirementIDs.contains(relocated) {
            return .relocatedOld
        }
        return .historical
    }

    private static func serviceBounds(
        of retirement: RailHistoryOverlay.Retirement
    ) -> (String?, String?) {
        RailServiceValidity.bounds(
            service: retirement.serviceValidity,
            infrastructure: retirement.infrastructureValidity,
            validFrom: retirement.validFrom, validTo: retirement.validTo,
            hasLegacy: retirement.validFrom != nil || retirement.validTo != nil)
    }

    private static func pairValue(_ pair: [String?]) -> Stations.Value {
        .array(pair.map { value in
            guard let value else { return .null }
            return .string(value)
        })
    }

    /// Exact line/operator equality, and every coordinate inside `bbox`
    /// (inclusive). A feature with no coordinates never matches — there is
    /// nothing to confirm is inside the box.
    private static func matches(
        _ match: RailHistoryOverlay.Retirement.Match, lineName: String, operatorName: String,
        stationName: String? = nil,
        points: [Coordinate]
    ) -> Bool {
        guard lineName == match.lineName, operatorName == match.operator, !points.isEmpty,
            match.bbox.count == 4
        else { return false }
        if let expected = match.stationName, stationName != expected { return false }
        let minLon = match.bbox[0]
        let minLat = match.bbox[1]
        let maxLon = match.bbox[2]
        let maxLat = match.bbox[3]
        return points.allSatisfy {
            $0.lon >= minLon && $0.lon <= maxLon && $0.lat >= minLat && $0.lat <= maxLat
        }
    }

    private static func sectionIdentityVariants(
        _ feature: RouteGraph.SectionFeature, periods: [RailHistoryOverlay.IdentityPeriod]
    ) -> [RouteGraph.SectionFeature] {
        partition(
            baseFrom: feature.properties.validFrom, baseTo: feature.properties.validTo,
            periods: periods
        ) { from, to, period in
            var copy = feature
            copy.properties.validFrom = from
            copy.properties.validTo = to
            if let period {
                if let code = period.identity.railwayClassCode {
                    copy.properties.railwayClassCode = code
                }
                if let code = period.identity.institutionTypeCode {
                    copy.properties.institutionTypeCode = code
                }
                copy.properties.lineName = period.identity.lineName
                copy.properties.operator = period.identity.operator
                copy.properties.historyId = period.historyId
                copy.properties.temporalKind = .historical
            }
            return copy
        }
    }

    private static func stationIdentityVariants(
        _ feature: Stations.Feature, periods: [RailHistoryOverlay.IdentityPeriod]
    ) -> [Stations.Feature] {
        let base = Stations.stationServiceBounds(feature)
        return partition(baseFrom: base.0, baseTo: base.1, periods: periods) { from, to, period in
            var copy = feature
            copy.properties["service_validity"] = pairValue([from, to])
            copy.properties.removeValue(forKey: "infrastructure_validity")
            if let period {
                if let code = period.identity.railwayClassCode {
                    copy.properties["N02_001"] = .string(code)
                    copy.properties["railway_class_code"] = .string(code)
                }
                if let code = period.identity.institutionTypeCode {
                    copy.properties["N02_002"] = .string(code)
                    copy.properties["institution_type_code"] = .string(code)
                }
                copy.properties["line_name"] = .string(period.identity.lineName)
                copy.properties["N02_003"] = .string(period.identity.lineName)
                copy.properties["operator"] = .string(period.identity.operator)
                copy.properties["N02_004"] = .string(period.identity.operator)
                if let stationName = period.identity.stationName {
                    copy.properties["station_name"] = .string(stationName)
                    copy.properties["N02_005"] = .string(stationName)
                }
                copy.properties["history_id"] = .string(period.historyId)
            }
            return copy
        }
    }

    private static func partition<T>(
        baseFrom: String?, baseTo: String?, periods: [RailHistoryOverlay.IdentityPeriod],
        make: (String?, String?, RailHistoryOverlay.IdentityPeriod?) -> T
    ) -> [T] {
        guard !periods.isEmpty else { return [make(baseFrom, baseTo, nil)] }
        func later(_ a: String?, _ b: String?) -> String? {
            if let a, let b { return max(a, b) }
            return a ?? b
        }
        func earlier(_ a: String?, _ b: String?) -> String? {
            guard let a else { return b }
            guard let b else { return a }
            return min(a, b)
        }
        func nonempty(_ from: String?, _ to: String?) -> Bool {
            guard let from, let to else { return true }
            return from < to
        }
        var result: [T] = []
        var cursor = baseFrom
        for period in periods.sorted(by: { ($0.validFrom ?? "") < ($1.validFrom ?? "") }) {
            let periodFrom = later(baseFrom, period.validFrom)
            let periodTo = earlier(baseTo, period.validTo)
            guard nonempty(periodFrom, periodTo) else { continue }
            let gapTo = earlier(baseTo, periodFrom)
            if cursor != gapTo, nonempty(cursor, gapTo) { result.append(make(cursor, gapTo, nil)) }
            result.append(make(periodFrom, periodTo, period))
            cursor = later(cursor, period.validTo)
        }
        if cursor != baseTo, nonempty(cursor, baseTo) { result.append(make(cursor, baseTo, nil)) }
        return result
    }

    /// `Stations.Feature.geometry` is a `Point` or `LineString`, stored as an
    /// untyped ``Stations/Value`` tree — flattens either shape into points.
    private static func stationPoints(_ geometry: Stations.Geometry?) -> [Coordinate] {
        guard let coordinates = geometry?.coordinates else { return [] }
        return flatten(coordinates)
    }

    /// A `Value.array` of exactly two numbers is one coordinate pair; any
    /// other array recurses into its elements. Handles `Point` (one pair) and
    /// `LineString` (an array of pairs) alike without needing the geometry's
    /// `type` to disambiguate.
    private static func flatten(_ value: Stations.Value) -> [Coordinate] {
        guard case .array(let items) = value else { return [] }
        if items.count == 2, case .number(let lon) = items[0], case .number(let lat) = items[1] {
            return [Coordinate(lon: lon, lat: lat)]
        }
        return items.flatMap(flatten)
    }
}
