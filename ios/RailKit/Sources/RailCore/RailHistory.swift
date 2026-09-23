import Foundation

/// A per-region history overlay (`rail-history[-<cc>].json`), per ADR 0011.
///
/// The overlay carries retired sections and stations — features absent from
/// the current package, with their own geometry — plus `retirements` that
/// stamp an end date onto features still present in the current package.
/// Nothing is ever dropped from the solver graph; it is dated instead.
public struct RailHistoryOverlay: Decodable, Sendable {
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

            private enum CodingKeys: String, CodingKey {
                case lineName = "line_name"
                case `operator`
                case bbox
            }
        }

        private enum CodingKeys: String, CodingKey {
            case historyId = "history_id"
            case match
            case validFrom = "valid_from"
            case validTo = "valid_to"
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
        try JSONDecoder().decode(RailHistoryOverlay.self, from: data)
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

        for retirement in overlay.retirements {
            var matched = 0

            for index in sections.indices {
                guard matches(retirement.match, lineName: sections[index].properties.lineName,
                    operatorName: sections[index].properties.operator,
                    points: sections[index].lines.flatMap { $0 })
                else { continue }
                matched += 1
                if let validFrom = retirement.validFrom {
                    sections[index].properties.validFrom = validFrom
                }
                if let validTo = retirement.validTo {
                    sections[index].properties.validTo = validTo
                }
            }

            for index in stations.indices {
                let feature = stations[index]
                let lineName = Stations.stationLineName(feature)
                let operatorName = Stations.stationOperator(feature)
                guard
                    matches(retirement.match, lineName: lineName, operatorName: operatorName,
                        points: stationPoints(feature.geometry))
                else { continue }
                matched += 1
                if let validFrom = retirement.validFrom {
                    stations[index].properties["valid_from"] = .string(validFrom)
                }
                if let validTo = retirement.validTo {
                    stations[index].properties["valid_to"] = .string(validTo)
                }
            }

            retirementsApplied[retirement.historyId] = matched
            if matched == 0 {
                unmatchedRetirements.append(retirement.historyId)
            }
        }

        sections.append(contentsOf: overlay.sections)
        stations.append(contentsOf: overlay.stations)

        return ApplyReport(
            sectionsAdded: overlay.sections.count, stationsAdded: overlay.stations.count,
            retirementsApplied: retirementsApplied, unmatchedRetirements: unmatchedRetirements)
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
