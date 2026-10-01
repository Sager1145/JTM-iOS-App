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
/// stamp an end date onto features still present in the current package.
/// Nothing is ever dropped from the solver graph; it is dated instead.
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

            private enum CodingKeys: String, CodingKey {
                case lineName = "line_name"
                case `operator`
                case bbox
                case targets
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

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case revision
        case sections
        case stations
        case retirements
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
        guard sectionIDs.isDisjoint(with: stationIDs),
              sectionIDs.isDisjoint(with: retirementIDs),
              stationIDs.isDisjoint(with: retirementIDs) else {
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

        public init(
            sectionsAdded: Int = 0, stationsAdded: Int = 0,
            retirementsApplied: [String: Int] = [:], unmatchedRetirements: [String] = []
        ) {
            self.sectionsAdded = sectionsAdded
            self.stationsAdded = stationsAdded
            self.retirementsApplied = retirementsApplied
            self.unmatchedRetirements = unmatchedRetirements
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
            retirementsApplied: retirementsApplied, unmatchedRetirements: unmatchedRetirements)
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
        points: [Coordinate]
    ) -> Bool {
        guard lineName == match.lineName, operatorName == match.operator, !points.isEmpty,
            match.bbox.count == 4
        else { return false }
        let minLon = match.bbox[0]
        let minLat = match.bbox[1]
        let maxLon = match.bbox[2]
        let maxLat = match.bbox[3]
        return points.allSatisfy {
            $0.lon >= minLon && $0.lon <= maxLon && $0.lat >= minLat && $0.lat <= maxLat
        }
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
