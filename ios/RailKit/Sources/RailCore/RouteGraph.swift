import Foundation

/// The routable graph, its spatial index, and the keys that decide whether
/// either has to be built.
///
/// Ported from `app/public/app-route-graph.js` §27–28. That file is two
/// things wearing one hat, and only one of them is here: the data-structure
/// half — nodes and edges from rail-section geometry, the coarse bbox index,
/// the LRU of regional subgraphs, the nearest-node lookup, and the
/// template/cache keys. Dijkstra, the institution rules and the route hints
/// live in `app-route-solver.js` and are a separate port. The seam between
/// them in the JavaScript is the `routeSolverApi` object that
/// `app-route-service.js` wires up; here it is ``Graph`` itself, plus the
/// `augment` hook on ``RouteGraphStore``.
///
/// Two properties are load-bearing far beyond their appearance.
///
/// **Coordinate parity is explicit.** In `.coordinateParity`, the key is
/// `coordKey` of the quantised pair, so vertices merge exactly when both
/// languages *spell* that pair identically. JavaScript writes an integral
/// coordinate `"139"`; Swift's `String(139.0)` is `"139.0"`. Seven node keys
/// in the shipped data — five Japanese, two Korean — have an integral half,
/// and under a naive port each of them becomes two nodes at the same place
/// with no edge between them. Everything goes through ``Grid``.
///
/// The application uses `.physicalRailway`: track identity scopes each node,
/// and only an evidenced physical junction joins independent identities
/// (`zeroLength`, `shortLink` of at most 30 m, or `osmConnector` with reviewed
/// OpenStreetMap stubs of at most 50 m). Display geometry and passenger
/// station groups do not establish connectivity.
///
/// **Order is an answer, not an accident.** Grid buckets and adjacency lists
/// are JavaScript arrays walked in insertion order; `nearbyGraphNodes` sorts
/// by distance with `Array.prototype.sort`, which is *stable*, so equal
/// distances keep grid-scan order; and the regional cache is a `Map` whose
/// insertion order chooses the eviction victim. Swift's `Dictionary` and
/// `Set` have no order and `sort` is not stable, so each of those is
/// reproduced explicitly below rather than inherited.
public enum RouteGraph {
    public enum BuildPolicy: Sendable {
        /// The original JavaScript coordinate-only graph, for explicit parity checks.
        case coordinateParity
        /// Independent track identities meet only at evidenced physical junctions.
        case physicalRailway
    }

    public struct TrackIdentity: Sendable, Hashable {
        public let operatorName: String
        public let lineName: String
        public let railwayClassCode: String
        public let level: String?
        public let trackID: String?
        public let sourceID: String?
        public let geometryDigest: String?

        public init(operatorName: String, lineName: String, railwayClassCode: String = "",
                    level: String? = nil, trackID: String? = nil,
                    sourceID: String? = nil, geometryDigest: String? = nil) {
            self.operatorName = operatorName
            self.lineName = lineName
            self.railwayClassCode = railwayClassCode
            self.level = level
            self.trackID = trackID
            self.sourceID = sourceID
            self.geometryDigest = geometryDigest
        }

        fileprivate var key: String {
            [operatorName, lineName, railwayClassCode, level ?? "", trackID ?? "", sourceID ?? "", geometryDigest ?? ""]
                .map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
        }
    }

    public struct PhysicalJunction: Sendable, Equatable {
        public struct Endpoint: Sendable, Equatable {
            public let identity: TrackIdentity
            public let coordinate: Coordinate
            public init(identity: TrackIdentity, coordinate: Coordinate) {
                self.identity = identity
                self.coordinate = coordinate
            }
        }
        public let id: String
        public let from: Endpoint
        public let to: Endpoint
        public let evidence: [String]
        public let validFrom: String?
        public let validTo: String?
        public let kind: Kind
        /// OSM way vertices, ordered from the from-end to the to-end.
        public let path: [Coordinate]?
        public let source: Source?
        /// Straight stubs from each existing endpoint to the nearest path vertex.
        public let attachMeters: AttachMeters?
        /// Set when one end is a dead-end platform rather than an N02 vertex.
        public let terminus: Terminus?
        /// Set when one end of an `osmTrack` attaches to an existing vertex of
        /// a different identity. The track stays on its own identity; only the
        /// stub is a junction hop.
        public let endJunction: EndJunction?
        /// Passenger stop this reviewed connection belongs to. Empty when the
        /// catalog row did not name one. Matching uses these, never proximity.
        public let station: String?
        public let stationCode: String?

        public enum Kind: String, Sendable, Equatable {
            case zeroLength, shortLink, osmConnector, osmTrack
        }

        public struct Source: Sendable, Equatable {
            public let provider: String
            public let license: String
            public let ways: [Int]
            public let retrieved: String
            public let cache: String
            public init(provider: String, license: String, ways: [Int], retrieved: String, cache: String) {
                self.provider = provider
                self.license = license
                self.ways = ways
                self.retrieved = retrieved
                self.cache = cache
            }
        }

        public struct AttachMeters: Sendable, Equatable {
            public let from: Double
            public let to: Double
            public init(from: Double, to: Double) {
                self.from = from
                self.to = to
            }
        }

        /// A dead-end platform. `end == .to` means the path's last point is the
        /// platform and does not attach to an existing vertex. `coordinate` is
        /// that station's N02 group coordinate, `[lon, lat]`.
        public struct Terminus: Sendable, Equatable {
            public enum End: String, Sendable, Equatable { case to }
            public let end: End
            public let station: String
            public let stationCode: String
            public let coordinate: Coordinate
            public init(end: End, station: String, stationCode: String, coordinate: Coordinate) {
                self.end = end
                self.station = station
                self.stationCode = stationCode
                self.coordinate = coordinate
            }
        }

        /// One end of an `osmTrack` attaches to an existing surveyed vertex of
        /// a different identity. `end == .to` means `to` is that foreign vertex
        /// and the path's last point is the near side of the stub.
        public struct EndJunction: Sendable, Equatable {
            public enum End: String, Sendable, Equatable { case to, from }
            public let end: End
            public let identity: TrackIdentity
            public let coordinate: Coordinate
            public init(end: End, identity: TrackIdentity, coordinate: Coordinate) {
                self.end = end
                self.identity = identity
                self.coordinate = coordinate
            }
        }

        /// Longest reviewed link between two existing surveyed vertices.
        public static let maximumReviewedLinkMeters: Double = 30
        /// Longest straight stub from an existing vertex onto a reviewed OSM path.
        public static let maximumOSMAttachMeters: Double = 50
        /// Longest reviewed `osmConnector`, stubs included.
        /// An `osmTrack` is same-identity survey geometry and has no total cap;
        /// only its attach stubs are limited to `maximumOSMAttachMeters`.
        /// A terminus end has no stub: the path's last point must instead lie
        /// within `maximumTerminusMeters` of `terminus.coordinate`.
        public static let maximumOSMTotalMeters: Double = 1_500
        public static let maximumTerminusMeters: Double = 300
        /// A longer consecutive step is a broken way chain, not one surveyed path.
        /// The registered 上野–東京 display interval's longest step is 697 m.
        public static let maximumOSMPathStepMeters: Double = 2_000

        /// True when `evidence` cites the train, not only an OpenStreetMap way.
        /// An `endJunction` stub joins two identities and needs that citation.
        public static func hasSameTrainEvidence(_ evidence: [String]) -> Bool {
            evidence.contains { item in
                let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return false }
                let lower = trimmed.lowercased()
                if lower.contains("openstreetmap.org") { return false }
                if lower.hasPrefix("way "), lower.dropFirst(4).allSatisfy(\.isNumber) { return false }
                return true
            }
        }

        /// Cross-identity continuity is only a reviewed junction: `zeroLength`
        /// at an identical surveyed vertex, a `shortLink` of at most
        /// `maximumReviewedLinkMeters` between two different existing vertices,
        /// or an `osmConnector` with a reviewed OpenStreetMap path whose stubs
        /// are at most `maximumOSMAttachMeters`. An `osmTrack` keeps its path
        /// on one identity. A terminus `osmTrack` leaves its named end as a
        /// dead-end platform. An `endJunction` leaves a stub of at most
        /// `maximumOSMAttachMeters` onto an existing vertex of a different
        /// identity; that stub is one junction hop. Neither distance nor a
        /// service/display relationship can create one; they are never inferred.
        public init(id: String, from: Endpoint, to: Endpoint, evidence: [String],
                    validFrom: String? = nil, validTo: String? = nil, kind: Kind = .zeroLength,
                    path: [Coordinate]? = nil, source: Source? = nil,
                    attachMeters: AttachMeters? = nil, terminus: Terminus? = nil,
                    endJunction: EndJunction? = nil,
                    station: String? = nil, stationCode: String? = nil) {
            self.kind = kind
            self.id = id
            self.from = from
            self.to = to
            self.evidence = evidence
            self.validFrom = validFrom
            self.validTo = validTo
            self.path = path
            self.source = source
            self.attachMeters = attachMeters
            self.terminus = terminus
            self.endJunction = endJunction
            self.station = station
            self.stationCode = stationCode
        }

        /// Node identity for the internal vertices of one `osmConnector`.
        /// The line name is the dedicated identity `osm-connector:<id>`.
        public static func osmConnectorIdentity(_ id: String) -> TrackIdentity {
            .init(operatorName: "", lineName: "osm-connector:\(id)", railwayClassCode: "")
        }

        /// Endpoint and path vertices in traversal order. Consecutive duplicates
        /// that quantise to one node are collapsed. Nil unless this is an OSM
        /// kind with at least two path vertices and two distinct ends.
        /// A terminus `osmTrack` stops on the last path vertex: that end is a
        /// dead-end platform, not an existing N02 vertex.
        func chainNodeKeys() -> [String]? {
            guard kind == .osmConnector || kind == .osmTrack, let path, path.count >= 2 else { return nil }
            let foreignTo = kind == .osmTrack && endJunction?.end == .to
            let foreignFrom = kind == .osmTrack && endJunction?.end == .from
            let deadEnd = kind == .osmTrack && terminus?.end == .to
            let pathIdentity = kind == .osmConnector
                ? Self.osmConnectorIdentity(id)
                : (foreignFrom ? to.identity : from.identity)
            var keys: [String] = []
            if !foreignFrom {
                keys.append(RouteGraph.physicalNodeKey(from.coordinate, identity: from.identity))
            }
            for point in path {
                let key = RouteGraph.physicalNodeKey(point, identity: pathIdentity)
                if keys.last != key { keys.append(key) }
            }
            if !deadEnd && !foreignTo {
                let end = RouteGraph.physicalNodeKey(to.coordinate, identity: to.identity)
                if keys.last != end { keys.append(end) }
            }
            guard let first = keys.first, let last = keys.last, first != last else { return nil }
            return keys
        }

        /// Why this OSM entry cannot be added, or nil when its path, stubs
        /// and identity rule are inside the reviewed limits. Total length is
        /// capped only for `osmConnector`. `fromCoordinate` and `toCoordinate`
        /// are the existing surveyed vertices. A terminus end is measured
        /// against `terminus.coordinate` and does not require `toCoordinate`
        /// to be a vertex.
        func osmRejection(fromCoordinate: Coordinate, toCoordinate: Coordinate) -> String? {
            guard kind == .osmConnector || kind == .osmTrack else { return nil }
            let deadEnd = kind == .osmTrack && terminus?.end == .to
            if let terminus {
                guard kind == .osmTrack else { return "terminus requires osmTrack" }
                guard terminus.end == .to else { return "unsupported terminus end" }
            }
            if let endJunction {
                guard kind == .osmTrack else { return "endJunction requires osmTrack" }
                if terminus != nil { return "endJunction excludes terminus" }
                let foreign = endJunction.end == .to ? to.coordinate : from.coordinate
                if Grid.normalizeGraphCoord(endJunction.coordinate) != Grid.normalizeGraphCoord(foreign) {
                    return "endJunction coordinate mismatch"
                }
            }
            guard let path, path.count >= 2 else { return "path has fewer than 2 points" }
            guard let attachMeters else { return "missing attachMeters" }
            if attachMeters.from < 0 || (!deadEnd && attachMeters.to < 0)
                || attachMeters.from > Self.maximumOSMAttachMeters
                || (!deadEnd && attachMeters.to > Self.maximumOSMAttachMeters) {
                return "attach exceeds \(Self.maximumOSMAttachMeters) m"
            }
            let fromPoint = Grid.normalizeGraphCoord(fromCoordinate)
            let pathPoints = path.map(Grid.normalizeGraphCoord)
            for point in pathPoints {
                guard point.lon.isFinite, point.lat.isFinite,
                      (-180...180).contains(point.lon), (-90...90).contains(point.lat) else {
                    return "invalid path coordinate"
                }
            }
            let stubFrom = Geometry.distanceMeters(fromPoint, pathPoints[0])
            if stubFrom > Self.maximumOSMAttachMeters {
                return "attach exceeds \(Self.maximumOSMAttachMeters) m"
            }
            if deadEnd, let terminus {
                let station = Grid.normalizeGraphCoord(terminus.coordinate)
                let end = pathPoints[pathPoints.count - 1]
                if Geometry.distanceMeters(end, station) > Self.maximumTerminusMeters {
                    return "terminus exceeds \(Self.maximumTerminusMeters) m"
                }
                for index in pathPoints.indices.dropFirst() {
                    if Geometry.distanceMeters(pathPoints[index - 1], pathPoints[index])
                        > Self.maximumOSMPathStepMeters {
                        return "path is not continuous"
                    }
                }
            } else {
                let toPoint = Grid.normalizeGraphCoord(toCoordinate)
                let stubTo = Geometry.distanceMeters(pathPoints[pathPoints.count - 1], toPoint)
                if stubTo > Self.maximumOSMAttachMeters {
                    return "attach exceeds \(Self.maximumOSMAttachMeters) m"
                }
                if kind == .osmConnector {
                    var total = stubFrom + stubTo
                    for index in pathPoints.indices.dropFirst() {
                        total += Geometry.distanceMeters(pathPoints[index - 1], pathPoints[index])
                    }
                    if total > Self.maximumOSMTotalMeters {
                        return "total length exceeds \(Self.maximumOSMTotalMeters) m"
                    }
                }
            }
            if let endJunction {
                let ownIdentity = endJunction.end == .to ? from.identity : to.identity
                let foreignIdentity = endJunction.end == .to ? to.identity : from.identity
                if endJunction.identity != foreignIdentity || endJunction.identity == ownIdentity {
                    return "identity mismatch"
                }
                if !Self.hasSameTrainEvidence(evidence) {
                    return "missing same-train evidence"
                }
            }
            switch kind {
            case .osmConnector where from.identity == to.identity:
                return "identity mismatch"
            case .osmTrack where endJunction == nil && from.identity != to.identity:
                return "identity mismatch"
            case .osmTrack where endJunction != nil && from.identity == to.identity:
                return "identity mismatch"
            default:
                return nil
            }
        }
    }

    public struct PhysicalJunctionEdge: Sendable, Equatable {
        public let junction: PhysicalJunction
        public let institutionTypeCodes: Set<String>
    }

    public static func physicalNodeKey(_ coordinate: Coordinate, identity: TrackIdentity) -> String {
        identity.key + "@" + Grid.coordKey(coordinate)
    }


    // =====================================================================
    //  §27 — route template and cache keys
    // =====================================================================

    /// A 53-bit digest of a route key, in base 36.
    ///
    /// Both route keys enumerate every route section, so they grow with the
    /// train: a 195-stop round-island itinerary produces about 35 KB of each.
    /// The two feature properties that carry them are only ever compared for
    /// equality, so stamping the full key onto every feature multiplied 35 KB
    /// by the feature count and made one precomputed part 6.8 MB. This has
    /// identical equality semantics at constant size — and it is purely
    /// deterministic, which is what lets the browser and the offline exporter
    /// each read a part written by the other. Stamping and comparing must
    /// both go through it.
    ///
    /// The arithmetic is `Math.imul` and `>>>`, i.e. wrapping 32-bit
    /// multiplication and unsigned shifts, so it is done in `UInt32` here.
    /// The input is walked by UTF-16 code unit (`charCodeAt`), which means a
    /// character outside the BMP is *two* iterations — `String.utf16` rather
    /// than `unicodeScalars`.
    public static func keyDigest(_ key: String) -> String {
        var h1: UInt32 = 0xdead_beef
        var h2: UInt32 = 0x41c6_ce57
        for unit in key.utf16 {
            let ch = UInt32(unit)
            h1 = (h1 ^ ch) &* 2_654_435_761
            h2 = (h2 ^ ch) &* 1_597_334_677
        }
        let mixed1 = ((h1 ^ (h1 >> 16)) &* 2_246_822_507) ^ ((h2 ^ (h2 >> 13)) &* 3_266_489_909)
        let mixed2 = ((h2 ^ (h2 >> 16)) &* 2_246_822_507) ^ ((mixed1 ^ (mixed1 >> 13)) &* 3_266_489_909)
        let value = UInt64(2_097_151 & mixed2) * 4_294_967_296 + UInt64(mixed1)
        return String(value, radix: 36)
    }

    /// One leg of a train's itinerary, as the template key reads it.
    ///
    /// The fields are optional because the JavaScript tests them for
    /// *falsiness*: `section.from_n02_station_code || section.from || ""`
    /// falls through on an empty string exactly as it does on `null`.
    public struct RouteSection: Sendable, Equatable {
        public var from: String?
        public var to: String?
        public var fromStationCode: String?
        public var toStationCode: String?
        public var lineNames: [String]
        public var operatorNames: [String]
        public var lineIDs: [String]
        public var sectionCodes: [String]

        public init(
            from: String? = nil,
            to: String? = nil,
            fromStationCode: String? = nil,
            toStationCode: String? = nil,
            lineNames: [String] = [],
            operatorNames: [String] = [],
            lineIDs: [String] = [], sectionCodes: [String] = []
        ) {
            self.from = from
            self.to = to
            self.fromStationCode = fromStationCode
            self.toStationCode = toStationCode
            self.lineNames = lineNames
            self.operatorNames = operatorNames
            self.lineIDs = lineIDs
            self.sectionCodes = sectionCodes
        }
    }

    /// JavaScript's `a || b`, for the strings these keys are built from.
    private static func or(_ a: String?, _ b: String?) -> String {
        if let a, !a.isEmpty { return a }
        if let b, !b.isEmpty { return b }
        return ""
    }

    /// The identity of a train's *route*, independent of the train.
    ///
    /// `line_names` / `operator_names` are part of the key because they change
    /// the solver's constraints: without them, editing only the line names
    /// would let an earlier path for the same endpoints be reused.
    public static func templateKey(sections: [RouteSection]) -> String {
        sections.map { section in
            let from = or(section.fromStationCode, section.from)
            let to = or(section.toStationCode, section.to)
            let lines = jsSorted(section.lineNames.filter { !$0.isEmpty }).joined(separator: ",")
            let operators = jsSorted(section.operatorNames.filter { !$0.isEmpty })
                .joined(separator: ",")
            var key = "\(from)->\(to)|lines:\(lines)|operators:\(operators)"
            if !section.lineIDs.isEmpty { key += "|line_ids:" + jsSorted(section.lineIDs).joined(separator: ",") }
            if !section.sectionCodes.isEmpty { key += "|section_codes:" + section.sectionCodes.joined(separator: ",") }
            return key
        }
        .joined(separator: "|")
    }

    /// The fields of a train that a cache key is made of.
    ///
    /// Deliberately not the whole train: everything else about it — stops,
    /// times, name — changes nothing about which path the solver finds, and a
    /// key that moved when they changed would throw away a valid cache entry.
    /// `id`, `number`, `origin` and `destination` ARE included, even though
    /// they look like identity rather than routing data: `solveContext` feeds
    /// them to `RouteSolver.inferSectionRouteConstraints`, which reads them to
    /// bias specific named services (Sonic, Haruka) onto specific lines. Two
    /// trains that differ only in these fields can infer different hints, and
    /// without them here the cache would hand one train's geometry to another.
    public struct CacheKeyTrain: Sendable {
        public var id: String
        public var number: String
        public var trainType: String
        public var company: String
        public var origin: String
        public var destination: String
        public var preferredLineNames: [String]
        public var preferredOperatorNames: [String]
        public var allowedInstitutionTypeCodes: [String]?
        public var institutionFilterMode: String?

        public init(
            id: String = "",
            number: String = "",
            trainType: String = "",
            company: String = "",
            origin: String = "",
            destination: String = "",
            preferredLineNames: [String] = [],
            preferredOperatorNames: [String] = [],
            allowedInstitutionTypeCodes: [String]? = nil,
            institutionFilterMode: String? = nil
        ) {
            self.id = id
            self.number = number
            self.trainType = trainType
            self.company = company
            self.origin = origin
            self.destination = destination
            self.preferredLineNames = preferredLineNames
            self.preferredOperatorNames = preferredOperatorNames
            self.allowedInstitutionTypeCodes = allowedInstitutionTypeCodes
            self.institutionFilterMode = institutionFilterMode
        }
    }

    /// `DEFAULT_ALLOWED_INSTITUTION_TYPE_CODES`, from `app-config.js`.
    public static let defaultAllowedInstitutionTypeCodes = ["1", "2", "3", "4", "5"]

    /// `ROUTE_SOLVER_CACHE_VERSION`, from `app-config.js`. Bumping it in the
    /// web app retires every persisted route cache entry, so it is a
    /// parameter here rather than a constant this file owns. The explicit
    /// coordinate parity version stays 25; physical version 27 rejects cached
    /// paths produced by coordinate merging or passenger transfer edges.
    public static let legacyCoordinateSolverCacheVersion = "25"
    public static let routeSolverCacheVersion = "27"

    /// On-disk drawn-route cache (`RiddenRouteStore` save/read). Not part of
    /// `solveContext` or the route digest: version 22 files may have
    /// canonicalized historical geometry onto the current display network,
    /// and those files must miss. Precomputed `solver_version` stays
    /// ``routeSolverCacheVersion``. Version 25 also retires legacy branch hops
    /// projected onto a nearby trunk/branch station they do not serve. Version
    /// 26 retires precomputed paths drawn without complete-network slicing.
    /// Physical version 28 additionally retires paths with inferred connectivity.
    /// Version 29 recomputes endpoint and same-identity boundary gap proofs.
    public static let legacyCoordinateDrawnCacheVersion = "26"
    public static let routeDrawnCacheVersion = "29"

    /// The operators a `company` field names, split on `/`.
    ///
    /// Several operators separated by `/` marks a 直通 through-running
    /// service. Taiwan's names go through the branding table first, because
    /// the store spells the same company several ways.
    public static func companyParts(company: String, country: String) -> [String] {
        company.components(separatedBy: "/")
            .map { part -> String in
                let name = JSString.trim(part)
                return country == "tw"
                    ? OperatorBranding.normalizeTaiwanCompanyName(name) : name
            }
            .filter { !$0.isEmpty }
    }

    /// `COMPANY_OPERATOR_ALIASES` — the human `company` field mapped onto the
    /// N02_004 operator names the solver biases towards. Both marketing names
    /// and official names are accepted, which is why the table is one-way.
    static let companyOperatorAliases: [String: String] = [
        "JR北海道": "北海道旅客鉄道",
        "JR東日本": "東日本旅客鉄道",
        "JR东日本": "東日本旅客鉄道",
        "JR東海": "東海旅客鉄道",
        "JR西日本": "西日本旅客鉄道",
        "JR四国": "四国旅客鉄道",
        "JR四國": "四国旅客鉄道",
        "JR九州": "九州旅客鉄道",
        "東京メトロ": "東京地下鉄",
        "东京地下铁": "東京地下鉄",
        "都営地下鉄": "東京都",
        "都営": "東京都",
        "京急": "京浜急行電鉄",
        "京急電鉄": "京浜急行電鉄",
        "東急": "東急電鉄",
        "小田急": "小田急電鉄",
        "京王": "京王電鉄",
        "京成": "京成電鉄",
        "西武": "西武鉄道",
        "東武": "東武鉄道",
        "相鉄": "相模鉄道",
        "近鉄": "近畿日本鉄道",
        "阪急": "阪急電鉄",
        "阪神": "阪神電気鉄道",
        "名鉄": "名古屋鉄道",
        "西鉄": "西日本鉄道",
        "台鐵": "國營臺灣鐵路股份有限公司",
        "臺鐵": "國營臺灣鐵路股份有限公司",
        "台灣高鐵": "台灣高速鐵路股份有限公司",
        "臺灣高鐵": "台灣高速鐵路股份有限公司",
        "台北捷運": "臺北大眾捷運股份有限公司",
        "臺北捷運": "臺北大眾捷運股份有限公司",
        "新北捷運": "新北大眾捷運股份有限公司",
        "桃園捷運": "桃園大眾捷運股份有限公司",
        "台中捷運": "臺中捷運股份有限公司",
        "臺中捷運": "臺中捷運股份有限公司",
        "高雄捷運": "高雄捷運股份有限公司",
        "阿里山林鐵": "阿里山林業鐵路及文化資產管理處",
    ]

    /// Operator names derived from the `company` field, in the order the
    /// company field lists them.
    ///
    /// The order is the JavaScript's `Set` insertion order, kept because the
    /// solver reads this list as it stands; the cache key happens to sort it
    /// afterwards, but that is the caller's doing.
    ///
    /// One JavaScript behaviour is deliberately *not* reproduced: the lookup
    /// is a plain object literal, so a company literally named `constructor`
    /// or `toString` would resolve through `Object.prototype` and be replaced
    /// by a function. No shipped store contains such a value, and reproducing
    /// prototype pollution would be reproducing an accident rather than a
    /// rule.
    public static func derivedPreferredOperatorNames(company: String, country: String) -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for part in companyParts(company: company, country: country) {
            let name = companyOperatorAliases[part] ?? part
            if seen.insert(name).inserted { names.append(name) }
        }
        return names
    }

    /// N02_002 institution-type codes implied by 車輛類型 + 營運公司.
    ///
    /// An empty result means "no signal", and the caller then keeps the full
    /// default set. The JavaScript spells these as regular expressions, but
    /// every one of them is a plain alternation with no metacharacter, so
    /// substring search is exactly equivalent and avoids handing the answer to
    /// a regex engine whose Unicode tables are not V8's.
    public static func derivedInstitutionTypeCodes(
        trainType: String, company: String, country: String
    ) -> [String] {
        let type = trainType
        let text =
            "\(type) \(companyParts(company: company, country: country).joined(separator: " "))"
        // `i` in the JavaScript canonicalises by upper-casing, so this does
        // too. It matters only for the two ASCII alternatives; CJK has no
        // case.
        let upper = text.uppercased()
        let has = { (needles: [String]) in needles.contains { text.contains($0) } }

        var codes = Set<String>()
        if has(["台灣高鐵", "臺灣高鐵", "高速鐵路"]) { codes.insert("1") }
        if has(["台鐵", "臺鐵", "臺灣鐵路", "台灣鐵路"]) { codes.insert("2") }
        if has(["捷運", "林鐵", "林業鐵路"]) { codes.insert("3") }
        if has(["新幹線", "新干线"]) || upper.contains("SHINKANSEN") { codes.insert("1") }
        if (upper.contains("JR") || has(["旅客鉄道", "旅客铁道"]))
            && !(type.contains("新幹線") || type.contains("新干线"))
        {
            codes.insert("2")
        }
        if has(["都営", "東京都交通局", "市営", "公営", "市交通局"]) { codes.insert("3") }
        if has([
            "メトロ", "地下鉄", "地下铁", "私鉄", "私铁", "電鉄", "电铁", "電気鉄道", "京急", "京成",
            "東急", "小田急", "近鉄", "阪急", "阪神", "名鉄", "西鉄", "西武", "東武", "モノレール",
            "ゆりかもめ", "長野電鉄", "富士山麓", "富士急",
        ]) { codes.insert("4") }
        if has([
            "第三セクター", "三セク", "三陸鉄道", "しなの鉄道", "あいの風", "IGR", "青い森",
            "肥薩おれんじ", "道南いさりび", "IRいしかわ", "松浦鉄道", "横浜高速鉄道",
        ]) { codes.insert("5") }
        return jsSorted(codes)
    }

    /// Institution codes a train may not traverse, regardless of soft-filter
    /// fallback. Conventional JR (company is JR, and `trainType` does not
    /// name 新幹線) never uses 新幹線 track. A 新幹線 train keeps an empty
    /// exclusion so mini-shinkansen can still pay the soft penalty onto
    /// conventional track.
    public static func hardExcludedInstitutionTypeCodes(
        trainType: String, company: String, country: String
    ) -> [String] {
        if trainType.contains("新幹線") || trainType.contains("新干线")
            || trainType.uppercased().contains("SHINKANSEN")
        {
            return []
        }
        let parts = companyParts(company: company, country: country).joined(separator: " ")
        if parts.uppercased().contains("JR") || parts.contains("旅客鉄道")
            || parts.contains("旅客铁道")
        {
            return ["1"]
        }
        return []
    }

    /// The institution codes a solve is allowed — or, under the default
    /// filter mode, merely biased towards.
    ///
    /// When `route_policy` has not narrowed the codes itself (the set is
    /// still the full default), a soft narrowing is derived from
    /// 車輛類型/公司 instead. With the default `"soft"` filter mode that only
    /// biases the solver, so it can never open a gap in the drawn route.
    public static func allowedInstitutionTypeCodes(
        _ train: CacheKeyTrain, country: String
    ) -> [String] {
        let explicit = train.allowedInstitutionTypeCodes ?? []
        let codes = explicit.isEmpty ? defaultAllowedInstitutionTypeCodes : explicit
        let unique = jsSorted(orderedUnique(codes))
        let fullDefault = jsSorted(defaultAllowedInstitutionTypeCodes)
        if unique.joined(separator: ",") == fullDefault.joined(separator: ",") {
            let derived = derivedInstitutionTypeCodes(
                trainType: train.trainType, company: train.company, country: country)
            if !derived.isEmpty { return derived }
        }
        return unique
    }

    /// Everything that identifies one deterministic route solve.
    public struct SolveContext: Sendable, Equatable {
        public let templateKey: String
        public let allowedCodes: [String]
        public let policyKey: String
        public let cacheKey: String
    }

    /// The cache key of one solve.
    ///
    /// `routeSections` is a parameter rather than something derived here:
    /// `buildTrainRouteSolveContext` gets them from
    /// `getRideRouteSectionsForTrain`, which lives in `app-store-ops.js` and
    /// belongs to the train store. That is the boundary of this port on that
    /// side; the graph does not know how a train's stops become sections, only
    /// what the sections identify.
    ///
    /// The `sort()` on the policy list is the reason ``jsSorted`` exists. Its
    /// members are line and operator names in Japanese, Chinese and Korean,
    /// JavaScript's default comparator orders strings by UTF-16 code unit, and
    /// this key is a persisted format — so the ordering rule is stated rather
    /// than inherited from whatever `String` comparison the standard library
    /// happens to implement.
    public static func solveContext(
        train: CacheKeyTrain,
        routeSections: [RouteSection],
        country: String,
        cacheVersion: String = routeSolverCacheVersion,
        rideDate: String? = nil,
        historyRevision: String? = nil
    ) -> SolveContext? {
        guard !routeSections.isEmpty else { return nil }
        let templateKey = templateKey(sections: routeSections)
        let allowedCodes = allowedInstitutionTypeCodes(train, country: country)
        var policyParts = train.preferredLineNames.map { "line:\($0)" }
        policyParts += train.preferredOperatorNames.map { "operator:\($0)" }
        policyParts += derivedPreferredOperatorNames(
            company: train.company, country: country
        ).map { "operator:\($0)" }
        // Duplicates are NOT removed — a preferred operator that is also
        // derived from the company field appears twice, and does so in the
        // shipped Taiwanese store.
        policyParts.append("institution_filter:\(train.institutionFilterMode ?? "soft")")
        let policyKey = jsSorted(policyParts).joined(separator: "|")
        // Mirrors the JavaScript literally: `/^\d{4}-\d{2}-\d{2}$/` on the raw
        // string, NOT `normalizeDateString` — a slash-dated or unbalanced
        // value is "none" on both sides, so the persisted key agrees.
        let normalizedRideDate = rideDate.flatMap { Self.isPlainISODay($0) ? $0 : nil }
        var cacheKey =
            "solver:\(cacheVersion)|\(allowedCodes.joined(separator: ","))|\(policyKey)|\(templateKey)"
            + "|date:\(normalizedRideDate ?? "none")|history:\(historyRevision ?? "none")"
        let inferContext = RouteSolver.TrainContext(
            id: train.id, number: train.number, trainType: train.trainType,
            company: train.company, origin: train.origin, destination: train.destination)
        for (index, section) in routeSections.enumerated() {
            // `inferSectionRouteConstraints` only reads `from`/`to`, but takes
            // the top-level `RouteSection` (from `Train.swift`), not this
            // enum's own nested one — the two exist because the graph half of
            // the port (this file) and the solver half read different subsets
            // of a section with different optionality.
            let hintSection = RailCore.RouteSection(from: section.from, to: section.to)
            let inferred = RouteSolver.inferSectionRouteConstraints(
                section: hintSection, train: inferContext)
            guard !inferred.lineNames.isEmpty || !inferred.operatorNames.isEmpty else { continue }
            let lines = jsSorted(inferred.lineNames).joined(separator: ",")
            let operators = jsSorted(inferred.operatorNames).joined(separator: ",")
            cacheKey += "|infer:\(index):line:\(lines):operator:\(operators)"
        }
        return SolveContext(
            templateKey: templateKey, allowedCodes: allowedCodes,
            policyKey: policyKey, cacheKey: cacheKey)
    }

    /// `/^\d{4}-\d{2}-\d{2}$/` — shape only, no calendar validation.
    static func isPlainISODay(_ value: String) -> Bool {
        let scalars = Array(value.unicodeScalars)
        guard scalars.count == 10, scalars[4] == "-", scalars[7] == "-" else { return false }
        for index in [0, 1, 2, 3, 5, 6, 8, 9] where !(scalars[index].value >= 48 && scalars[index].value <= 57) {
            return false
        }
        return true
    }

    // =====================================================================
    //  §27 — graph construction
    // =====================================================================

    /// The four rail-section attributes an edge carries, after the property
    /// fallback chain has been applied.
    ///
    /// Japan's sections are raw N02 and spell them `N02_001`…`N02_004`; the
    /// other four countries' sections are derived by the build scripts and
    /// spell them out. The JavaScript resolves `N02_003 || line_name || ""`
    /// at every edge; resolving once at decode is the same answer.
    public struct SectionProperties: Sendable, Equatable {
        public var lineName: String
        public var `operator`: String
        public var institutionTypeCode: String
        public var railwayClassCode: String
        public var level: String?
        public var trackID: String?
        public var sourceID: String?

        public var trackIdentity: TrackIdentity {
            .init(operatorName: `operator`, lineName: lineName, railwayClassCode: railwayClassCode, level: level, trackID: trackID, sourceID: sourceID)
        }
        /// ADR 0011 validity bounds (`valid_from`/`valid_to`), half-open
        /// `[validFrom, validTo)`. `nil` means unbounded on that side.
        public var validFrom: String?
        public var validTo: String?
        /// Overlay `history_id`, when the feature has one. A current-package
        /// feature a retirement stamps with `valid_from` receives that
        /// retirement's id. Not dropped at decode.
        public var historyId: String?
        public var temporalKind: TemporalKind

        public init(
            lineName: String = "", operator: String = "",
            institutionTypeCode: String = "", railwayClassCode: String = "",
            validFrom: String? = nil, validTo: String? = nil,
            historyId: String? = nil, temporalKind: TemporalKind = .current,
            level: String? = nil, trackID: String? = nil, sourceID: String? = nil
        ) {
            self.lineName = lineName
            self.operator = `operator`
            self.institutionTypeCode = institutionTypeCode
            self.railwayClassCode = railwayClassCode
            self.level = level
            self.trackID = trackID
            self.sourceID = sourceID
            self.validFrom = validFrom
            self.validTo = validTo
            self.historyId = historyId
            self.temporalKind = temporalKind
        }

        var carriedHistoryIDs: [String] {
            guard let historyId else { return [] }
            let trimmed = historyId.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [] : [trimmed]
        }
    }

    /// One rail-section feature: its attributes and its raw, *un-quantised*
    /// geometry.
    ///
    /// Quantisation happens where the JavaScript does it —
    /// `iterateGeometryLines`, on the way into the graph — because that is
    /// also where `featureBBox` gets its coordinates, and a bbox measured on
    /// raw vertices is a different bbox.
    public struct SectionFeature: Sendable {
        public var properties: SectionProperties
        public var lines: [[Coordinate]]
        public var geometryType: String

        public init(
            properties: SectionProperties, lines: [[Coordinate]],
            geometryType: String = "LineString"
        ) {
            self.properties = properties
            self.lines = lines
            self.geometryType = geometryType
        }

        /// Missing operator/line identity cannot merge unrelated source
        /// features just because their vertices coincide. Explicit source or
        /// track identities remain usable; otherwise source geometry supplies
        /// an order-independent, stable fallback shared by full/regional graphs.
        public var physicalTrackIdentity: TrackIdentity {
            func present(_ value: String?) -> Bool {
                !(value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            }
            if (present(properties.operator) && present(properties.lineName))
                || present(properties.trackID) || present(properties.sourceID) {
                return properties.trackIdentity
            }
            let geometry = geometryType + "|" + lines.map { line in
                line.map { String($0.lon.bitPattern, radix: 16) + "," + String($0.lat.bitPattern, radix: 16) }
                    .joined(separator: ";")
            }.joined(separator: "/")
            // Two independent 64-bit FNV-1a streams. Never use Swift Hasher,
            // whose process randomization would change persisted node identity.
            var first: UInt64 = 14_695_981_039_346_656_037
            var second: UInt64 = 7_809_847_782_465_536_322
            for byte in geometry.utf8 {
                first = (first ^ UInt64(byte)) &* 1_099_511_628_211
                second = (second ^ UInt64(byte)) &* 1_400_294_673_668_886_211
            }
            let digest = String(first, radix: 16) + ":" + String(second, radix: 16)
                + ":" + String(geometry.utf8.count)
            return .init(operatorName: properties.operator, lineName: properties.lineName,
                         railwayClassCode: properties.railwayClassCode, level: properties.level,
                         trackID: properties.trackID, geometryDigest: digest)
        }

        /// `iterateGeometryLines` — every vertex on the 5-decimal grid.
        public var quantisedLines: [[Coordinate]] {
            lines.map { $0.map(Grid.normalizeGraphCoord) }
        }
    }

    /// Extra payload the *solver* hangs on the connector edges it adds
    /// between platforms of one station group.
    ///
    /// Nothing in graph construction ever sets this. It is declared here
    /// because `addStationTransferConnectorEdges` pushes its edges into the
    /// same adjacency lists, and the alternative to naming the seam is a
    /// later port having to edit this file.
    public struct StationConnector: Sendable, Equatable {
        public var institutionTypeCodes: [String]
        public var stationName: String
        public var groupCode: String

        public init(
            institutionTypeCodes: [String] = [], stationName: String = "",
            groupCode: String = ""
        ) {
            self.institutionTypeCodes = institutionTypeCodes
            self.stationName = stationName
            self.groupCode = groupCode
        }
    }

    /// ADR 0011: whether an edge's `[validFrom, validTo)` interval covers a
    /// ride's date.
    public enum RailValidity {
        /// - `rideDate == nil`: undated ride, valid iff there is no `validTo`
        ///   (today's behaviour, unchanged).
        /// - `rideDate` a valid ISO `YYYY-MM-DD` day: valid iff
        ///   `validFrom == nil || validFrom <= rideDate` and
        ///   `validTo == nil || rideDate < validTo`, compared as strings.
        /// - `rideDate` present but not plain `YYYY-MM-DD` shape
        ///   (``RouteGraph/isPlainISODay(_:)``, the JS regex mirror): treated
        ///   as `nil`. Shape only — "2019-13-45" counts as dated and compares
        ///   as a string, exactly like `isRailValid` in app-route-graph.js.
        /// - An empty-string bound is treated as `nil`.
        public static func isValid(validFrom: String?, validTo: String?, on rideDate: String?) -> Bool {
            if (validFrom?.isEmpty ?? true) && (validTo?.isEmpty ?? true) { return true }
            return isValid(
                validFrom: validFrom, validTo: validTo,
                onPlainDay: rideDate.flatMap { RouteGraph.isPlainISODay($0) ? $0 : nil })
        }

        /// ``isValid(validFrom:validTo:on:)`` for a caller that has already
        /// shape-checked the ride date once (Dijkstra's hot loop): `plainDay`
        /// must be `nil` or pass ``RouteGraph/isPlainISODay(_:)``.
        static func isValid(validFrom: String?, validTo: String?, onPlainDay plainDay: String?) -> Bool {
            let from = validFrom.flatMap { $0.isEmpty ? nil : $0 }
            let to = validTo.flatMap { $0.isEmpty ? nil : $0 }
            if from == nil && to == nil { return true }
            guard let date = plainDay else { return to == nil }
            if let from, from > date { return false }
            if let to, date >= to { return false }
            return true
        }
    }

    /// How a section relates to the current package. Raw values are the
    /// on-disk spellings. A solved section keeps the most specific kind among
    /// its edges: `relocatedOld`, then `relocatedNew`, then `historical`,
    /// then `current`.
    public enum TemporalKind: String, Sendable, Equatable, Codable {
        case current
        case historical
        case relocatedOld
        case relocatedNew

        var specificity: Int {
            switch self {
            case .relocatedOld: 3
            case .relocatedNew: 2
            case .historical: 1
            case .current: 0
            }
        }

        /// Display-network canonicalization redraws a hop onto track that is
        /// still in the current package. Historical and relocated geometry
        /// must keep the coordinates the solver walked.
        public static func shouldCanonicalizeDisplayNetwork(_ kind: TemporalKind) -> Bool {
            kind == .current
        }
    }

    /// Validity and provenance shared by a solved section's edges. `validFrom`
    /// is the max of present bounds and `validTo` the min — the same
    /// intersection a station-transfer connector uses. `historyIDs` is the
    /// union, sorted. An empty input is `.current`.
    struct TemporalProvenance: Sendable, Equatable {
        var historyIDs: [String]
        var validFrom: String?
        var validTo: String?
        var temporalKind: TemporalKind

        static func aggregate(
            historyIDs: [String], validFrom: [String?], validTo: [String?],
            kinds: [TemporalKind]
        ) -> TemporalProvenance {
            var seen = Set<String>()
            var unique: [String] = []
            for id in historyIDs where !id.isEmpty && seen.insert(id).inserted {
                unique.append(id)
            }
            unique.sort()
            let kind = kinds.max { $0.specificity < $1.specificity } ?? .current
            return TemporalProvenance(
                historyIDs: unique,
                validFrom: validFrom.compactMap { $0 }.max(),
                validTo: validTo.compactMap { $0 }.min(),
                temporalKind: kind)
        }

        static func aggregate(edges: [Edge]) -> TemporalProvenance {
            aggregate(
                historyIDs: edges.flatMap(\.historyIDs),
                validFrom: edges.map(\.validFrom),
                validTo: edges.map(\.validTo),
                kinds: edges.map(\.temporalKind))
        }
    }

    public struct Edge: Sendable, Equatable {
        public var to: String
        /// Source rail metres, floored at 0.01. Same-coordinate physical
        /// junctions have exactly zero length and no invented rail geometry.
        public var length: Double
        public var institutionTypeCode: String
        public var railwayClassCode: String
        public var lineName: String
        public var `operator`: String
        /// Non-nil only on the solver's station-transfer edges.
        public var connector: StationConnector?
        /// An evidenced physical junction, distinct from passenger transfers.
        public var physicalJunction: PhysicalJunctionEdge? {
            get { physicalJunctionStorage?.value }
            set { physicalJunctionStorage = newValue.map(PhysicalJunctionStorage.init) }
        }
        private var physicalJunctionStorage: PhysicalJunctionStorage?

        /// Immutable storage keeps edge copies independent when their payload is replaced.
        private final class PhysicalJunctionStorage: Sendable, Equatable {
            let value: PhysicalJunctionEdge

            init(_ value: PhysicalJunctionEdge) {
                self.value = value
            }

            static func == (lhs: PhysicalJunctionStorage, rhs: PhysicalJunctionStorage) -> Bool {
                lhs.value == rhs.value
            }
        }
        /// ADR 0011 validity bounds, carried from the section (or, for a
        /// station-transfer connector, from the station) this edge came from.
        public var validFrom: String? = nil
        public var validTo: String? = nil
        /// History-overlay identifiers this edge came from. Empty on current
        /// package track and on station-transfer connectors.
        public var historyIDs: [String] = []
        public var temporalKind: TemporalKind = .current

        init(
            to: String, length: Double, institutionTypeCode: String,
            railwayClassCode: String, lineName: String, operator: String,
            connector: StationConnector? = nil, physicalJunction: PhysicalJunctionEdge? = nil,
            validFrom: String? = nil, validTo: String? = nil,
            historyIDs: [String] = [], temporalKind: TemporalKind = .current
        ) {
            self.to = to
            self.length = length
            self.institutionTypeCode = institutionTypeCode
            self.railwayClassCode = railwayClassCode
            self.lineName = lineName
            self.operator = `operator`
            self.connector = connector
            self.physicalJunctionStorage = physicalJunction.map(PhysicalJunctionStorage.init)
            self.validFrom = validFrom
            self.validTo = validTo
            self.historyIDs = historyIDs
            self.temporalKind = temporalKind
        }
    }

    /// What is known about the railways meeting at one node. Used only for
    /// membership tests, so a `Set` is faithful — the JavaScript never
    /// iterates these in a way that reaches an answer.
    public struct NodeMeta: Sendable, Equatable {
        public var lineNames: Set<String> = []
        public var operators: Set<String> = []
        public var institutionTypeCodes: Set<String> = []
        public var railwayClassCodes: Set<String> = []
        public init() {}
    }

    /// The routable graph.
    ///
    /// A reference type on purpose. In the JavaScript this is a plain object
    /// that the LRU, the solver and the caller all hold the *same* copy of:
    /// `addStationTransferConnectorEdges` mutates it after it is cached, and
    /// the solver memoises station snaps into `stationSnapCache` on it during
    /// a solve. A value type would silently give each of those its own copy
    /// and the memo would never hit.
    ///
    /// `stationSnapCache` itself is deliberately absent: its entries are
    /// solver-shaped snap candidates, and modelling them here would be
    /// modelling the solver. Because this is a class, the solver's port can
    /// keep that memo in its own store keyed by `ObjectIdentifier` of the
    /// graph and get the same lifetime — no edit to this file required.
    public final class Graph {
        /// Node key → its quantised coordinate.
        public var nodes: [String: Coordinate] = [:] {
            didSet {
                physicalRailComponentCache = nil
                physicalJunctionEdgeCache = nil
            }
        }
        public var rejectedPhysicalJunctionIDs: [String] = []
        /// Parallel to ``rejectedPhysicalJunctionIDs``: why that entry was not added.
        public var rejectedPhysicalJunctionReasons: [String] = []
        /// Node key → its edges, **in insertion order**. Dijkstra relaxes an
        /// adjacency list in order, so this is a sequence, not a set.
        public var adjacency: [String: [Edge]] = [:] {
            didSet {
                physicalRailComponentCache = nil
                physicalJunctionEdgeCache = nil
            }
        }
        private var physicalRailComponentCache: [String: Int]?
        private var physicalJunctionEdgeCache: [(
            junction: PhysicalJunction, endpointKeys: [String]
        )]?
        /// `graphGridKey` cell → the node keys in it, in insertion order.
        /// ``nearbyNodes`` leans on that order to break distance ties.
        public var grid: [String: [String]] = [:]
        public var nodeMeta: [String: NodeMeta] = [:]
        public let cellSize: Double
        /// Set only on a regional subgraph: the quantised bbox it covers.
        public var regionBBox: BBox?

        init(cellSize: Double) { self.cellSize = cellSize }

        public var nodeCount: Int { nodes.count }

        func physicalJunctionEdges() -> [(
            junction: PhysicalJunction, endpointKeys: [String]
        )] {
            if let physicalJunctionEdgeCache { return physicalJunctionEdgeCache }
            var junctions: [String: PhysicalJunction] = [:]
            var neighbors: [String: [String: Set<String>]] = [:]
            for (from, edges) in adjacency {
                for edge in edges {
                    guard let junction = edge.physicalJunction?.junction else { continue }
                    junctions[junction.id] = junction
                    neighbors[junction.id, default: [:]][from, default: []].insert(edge.to)
                    neighbors[junction.id, default: [:]][edge.to, default: []].insert(from)
                }
            }
            let result = junctions.keys.sorted().compactMap { id -> (
                junction: PhysicalJunction, endpointKeys: [String]
            )? in
                guard let junction = junctions[id] else { return nil }
                var endpointKeys = Set<String>()
                if let chainKeys = junction.chainNodeKeys() {
                    if let first = chainKeys.first, nodes[first] != nil { endpointKeys.insert(first) }
                    if let last = chainKeys.last, nodes[last] != nil { endpointKeys.insert(last) }
                    if let endJunction = junction.endJunction {
                        let foreignKey = RouteGraph.physicalNodeKey(
                            endJunction.coordinate, identity: endJunction.identity)
                        if nodes[foreignKey] != nil { endpointKeys.insert(foreignKey) }
                    }
                } else {
                    let junctionNeighbors = neighbors[id] ?? [:]
                    endpointKeys.formUnion(junctionNeighbors.compactMap { key, adjacent in
                        adjacent.count == 1 && nodes[key] != nil ? key : nil
                    })
                    if endpointKeys.isEmpty {
                        endpointKeys.formUnion(junctionNeighbors.keys.filter { nodes[$0] != nil })
                    }
                }
                return (junction, endpointKeys.sorted())
            }
            physicalJunctionEdgeCache = result
            return result
        }

        /// Weak components of surveyed rail and approved physical junctions.
        /// These ignore direction, dates and route filters: sharing a component
        /// is only a necessary condition for Dijkstra to find a physical path.
        /// Passenger connectors never merge components. Public dictionary
        /// mutations invalidate the cache, including nested edge replacement.
        /// A cancelled build publishes nothing and can be retried later.
        func physicalRailComponents(
            isCancelled: () -> Bool = { Task.isCancelled }
        ) -> [String: Int]? {
            guard !isCancelled() else { return nil }
            if let physicalRailComponentCache { return physicalRailComponentCache }

            // Union by size and path compression avoid storing a second copy
            // of every rail adjacency merely to handle one-way source edges.
            var indices: [String: Int] = [:]
            indices.reserveCapacity(nodes.count)
            var parents: [Int] = []
            var sizes: [Int] = []
            parents.reserveCapacity(nodes.count)
            sizes.reserveCapacity(nodes.count)
            func index(_ key: String) -> Int {
                if let existing = indices[key] { return existing }
                let next = parents.count
                indices[key] = next
                parents.append(next)
                sizes.append(1)
                return next
            }
            func root(_ index: Int) -> Int {
                var current = index
                while parents[current] != current {
                    parents[current] = parents[parents[current]]
                    current = parents[current]
                }
                return current
            }
            var work = 0
            func cancelled() -> Bool {
                work += 1
                return work & 255 == 0 && isCancelled()
            }
            for key in nodes.keys {
                if cancelled() { return nil }
                _ = index(key)
            }
            for (from, edges) in adjacency {
                if cancelled() { return nil }
                let fromIndex = index(from)
                for edge in edges {
                    if cancelled() { return nil }
                    guard edge.connector == nil else { continue }
                    var first = root(fromIndex)
                    var second = root(index(edge.to))
                    guard first != second else { continue }
                    if sizes[first] < sizes[second] { swap(&first, &second) }
                    parents[second] = first
                    sizes[first] += sizes[second]
                }
            }
            var components: [String: Int] = [:]
            components.reserveCapacity(indices.count)
            for (key, value) in indices {
                if cancelled() { return nil }
                components[key] = root(value)
            }
            guard !isCancelled() else { return nil }
            physicalRailComponentCache = components
            return components
        }
    }

    /// The cell size of a graph's own node grid. Not the same grid as the
    /// rail-section index (``railIndexCellDeg``), which is ten times coarser
    /// and indexes features rather than nodes.
    public static let graphCellSize = 0.01

    /// Nodes and edges from rail-section features, and nothing else.
    ///
    /// The Python pipeline's rule, kept: the routable graph is built ONLY
    /// from RailroadSection geometry. An N02 Station LineString is a snap
    /// candidate, never a train-runnable edge.
    public static func build(from features: [SectionFeature], policy: BuildPolicy = .physicalRailway,
                             junctions: [PhysicalJunction] = []) -> Graph {
        build(compiled: CompiledSections(features: features, policy: policy),
              featureIndices: features.indices, junctions: junctions)
    }

    final class CompiledSections {
        struct FeatureRecord {
            let properties: SectionProperties
            let historyIDs: [String]
            let meta: NodeMeta
            let lineRanges: [Range<Int>]
        }
        let features: [SectionFeature]
        let policy: BuildPolicy
        var records: [FeatureRecord?]
        var vertexID: [Int32] = []
        var vertexKey: [String] = []
        var vertexCoord: [Coordinate] = []
        var vertexCell: [String] = []
        private var ids: [String: Int32] = [:]
        private var keyOfID: [String] = []
        var idCount: Int { keyOfID.count }
        init(features: [SectionFeature], policy: BuildPolicy) {
            self.features = features
            self.policy = policy
            self.records = Array(repeating: nil, count: features.count)
        }

        @inline(__always) func ensure(_ f: Int) {
            if records[f] == nil { compile(f) }
        }

        private func compile(_ f: Int) {
            let feature = features[f]
            let properties = feature.properties
            var meta = NodeMeta()
            if !properties.lineName.isEmpty { meta.lineNames.insert(properties.lineName) }
            if !properties.operator.isEmpty { meta.operators.insert(properties.operator) }
            if !properties.institutionTypeCode.isEmpty { meta.institutionTypeCodes.insert(properties.institutionTypeCode) }
            if !properties.railwayClassCode.isEmpty { meta.railwayClassCodes.insert(properties.railwayClassCode) }
            let prefix = policy == .coordinateParity ? "" : feature.physicalTrackIdentity.key + "@"
            var ranges: [Range<Int>] = []
            for line in feature.quantisedLines {
                guard line.count >= 2 else { continue }
                let start = vertexID.count
                for coord in line {
                    let normalized = Grid.normalizeGraphCoord(coord)
                    let key = policy == .coordinateParity ? Grid.coordKey(normalized)
                        : prefix + Grid.coordKey(normalized)
                    if let existing = ids[key] {
                        let stored = keyOfID[Int(existing)]
                        vertexID.append(existing)
                        vertexKey.append(stored.utf8.elementsEqual(key.utf8) ? stored : key)
                    } else {
                        let id = Int32(keyOfID.count)
                        ids[key] = id
                        keyOfID.append(key)
                        vertexID.append(id)
                        vertexKey.append(key)
                    }
                    vertexCoord.append(normalized)
                    vertexCell.append(graphGridKey(normalized, cellSize: graphCellSize))
                }
                ranges.append(start..<vertexID.count)
            }
            records[f] = FeatureRecord(properties: properties, historyIDs: properties.carriedHistoryIDs,
                                       meta: meta, lineRanges: ranges)
        }
    }

    static func build<S: Sequence>(compiled c: CompiledSections, featureIndices: S,
                                   junctions: [PhysicalJunction], plans: [JunctionPlan]? = nil) -> Graph where S.Element == Int {
        let graph = Graph(cellSize: graphCellSize)
        for f in featureIndices { c.ensure(f) }
        var localOf = [Int32](repeating: -1, count: c.idCount)
        var creator: [Int] = []
        var adjacency: [[Edge]] = []
        var meta: [NodeMeta] = []
        var metaStamp: [Int] = []
        var position = 0
        for f in featureIndices {
            position += 1
            let rec = c.records[f]!
            let properties = rec.properties
            let historyIDs = rec.historyIDs
            for range in rec.lineRanges {
                for v in range {
                    let g = Int(c.vertexID[v])
                    if localOf[g] < 0 {
                        localOf[g] = Int32(creator.count)
                        creator.append(v)
                        adjacency.append([])
                        meta.append(NodeMeta())
                        metaStamp.append(0)
                    }
                }
                func record(_ l: Int) {
                    if metaStamp[l] == position { return }
                    if metaStamp[l] == 0 {
                        meta[l] = rec.meta
                    } else {
                        if !properties.lineName.isEmpty { meta[l].lineNames.insert(properties.lineName) }
                        if !properties.operator.isEmpty { meta[l].operators.insert(properties.operator) }
                        if !properties.institutionTypeCode.isEmpty { meta[l].institutionTypeCodes.insert(properties.institutionTypeCode) }
                        if !properties.railwayClassCode.isEmpty { meta[l].railwayClassCodes.insert(properties.railwayClassCode) }
                    }
                    metaStamp[l] = position
                }
                var v = range.lowerBound
                while v + 1 < range.upperBound {
                    let a = Int(localOf[Int(c.vertexID[v])])
                    let b = Int(localOf[Int(c.vertexID[v + 1])])
                    if a != b {
                        record(a)
                        record(b)
                        let length = Geometry.distanceMeters(c.vertexCoord[creator[a]], c.vertexCoord[creator[b]])
                        let edge = Edge(
                            to: c.vertexKey[v + 1],
                            length: max(length, 0.01),
                            institutionTypeCode: properties.institutionTypeCode,
                            railwayClassCode: properties.railwayClassCode,
                            lineName: properties.lineName,
                            operator: properties.operator,
                            connector: nil,
                            validFrom: properties.validFrom,
                            validTo: properties.validTo,
                            historyIDs: historyIDs,
                            temporalKind: properties.temporalKind)
                        adjacency[a].append(edge)
                        var reverse = edge
                        reverse.to = c.vertexKey[v]
                        adjacency[b].append(reverse)
                    }
                    v += 1
                }
            }
        }
        // Global-to-local lookup and stamps are needed only while recording edges.
        localOf.removeAll(keepingCapacity: false)
        metaStamp.removeAll(keepingCapacity: false)
        let n = creator.count
        var nodes = [String: Coordinate](minimumCapacity: n)
        var finalAdjacency = [String: [Edge]](minimumCapacity: n)
        var nodeMeta = [String: NodeMeta](minimumCapacity: n)
        for l in 0..<n {
            let v = creator[l]
            let key = c.vertexKey[v]
            nodes[key] = c.vertexCoord[v]
            finalAdjacency[key] = adjacency[l]
            nodeMeta[key] = meta[l]
            graph.grid[c.vertexCell[v], default: []].append(key)
            // The final values now own these buffers; dropping staging owners
            // avoids a second owner when junction augmentation mutates them.
            adjacency[l] = []
            meta[l] = NodeMeta()
        }
        creator.removeAll(keepingCapacity: false)
        adjacency.removeAll(keepingCapacity: false)
        meta.removeAll(keepingCapacity: false)
        // Assign once: nodes/adjacency observers only invalidate empty caches.
        graph.nodes = nodes
        graph.adjacency = finalAdjacency
        graph.nodeMeta = nodeMeta
        // Release local dictionary owners before mutable junction augmentation.
        nodes = [:]
        finalAdjacency = [:]
        nodeMeta = [:]
        if c.policy == .physicalRailway {
            addPhysicalJunctions(to: graph, junctions: junctions, plans: plans)
        }
        return graph
    }

    struct JunctionPlan {
        let fromKey: String
        let toKey: String
        let deadEnd: Bool
        let staticReason: String?
        let chainKeys: [String]?
        let foreignKey: String?
        init(_ junction: PhysicalJunction) {
            fromKey = physicalNodeKey(junction.from.coordinate, identity: junction.from.identity)
            toKey = physicalNodeKey(junction.to.coordinate, identity: junction.to.identity)
            deadEnd = junction.kind == .osmTrack && junction.terminus?.end == .to
            let validBounds = [junction.validFrom, junction.validTo].compactMap { $0 }
                .allSatisfy(isPlainISODay)
            let orderedBounds = junction.validFrom == nil || junction.validTo == nil
                || junction.validFrom! < junction.validTo!
            if junction.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                staticReason = "empty id"
            } else if junction.evidence.isEmpty
                        || !junction.evidence.allSatisfy({
                            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        }) {
                staticReason = "missing evidence"
            } else if !validBounds || !orderedBounds {
                staticReason = "invalid dates"
            } else {
                staticReason = nil
            }
            chainKeys = junction.chainNodeKeys()
            foreignKey = junction.endJunction.map { physicalNodeKey($0.coordinate, identity: $0.identity) }
        }
    }

    static func addPhysicalJunctions(to graph: Graph, junctions: [PhysicalJunction], plans: [JunctionPlan]? = nil) {
        let plans = plans ?? junctions.map(JunctionPlan.init)
        let policy = BuildPolicy.physicalRailway
        func ensureNode(_ coord: Coordinate, _ identity: TrackIdentity,
                        identityPrefix: String? = nil) -> String {
            // Quantised twice, exactly as the JavaScript does: once by
            // `iterateGeometryLines` on the way in, once here by
            // `normalizeGraphCoord`, and `coordKey` quantises a third time.
            // Idempotent in practice, but "in practice" is not a reason to
            // drop a step from a function that decides node identity.
            let normalized = Grid.normalizeGraphCoord(coord)
            // `identityPrefix` is `identity.key + "@"`, computed once per
            // feature: spelling the identity out per vertex was a quarter of
            // every build.
            let key = policy == .coordinateParity ? Grid.coordKey(normalized)
                : identityPrefix.map { $0 + Grid.coordKey(normalized) }
                    ?? physicalNodeKey(normalized, identity: identity)
            if graph.nodes[key] == nil {
                graph.nodes[key] = normalized
                graph.adjacency[key] = []
                graph.nodeMeta[key] = NodeMeta()
                graph.grid[graphGridKey(normalized, cellSize: graph.cellSize), default: []]
                    .append(key)
            }
            return key
        }
        if policy == .physicalRailway {
            // Surveyed rail-section and history vertices only. Junction and OSM
            // rows add nodes later; acceptance must not see those, or a later
            // row could treat an earlier path vertex as an existing endpoint.
            let surveyedNodes = graph.nodes
            var acceptedIDs: Set<String> = []
            func reject(_ junction: PhysicalJunction, _ reason: String) {
                graph.rejectedPhysicalJunctionIDs.append(junction.id)
                graph.rejectedPhysicalJunctionReasons.append("\(junction.id): \(reason)")
            }
            for (junction, plan) in zip(junctions, plans) {
                if let staticReason = plan.staticReason {
                    reject(junction, staticReason)
                    continue
                }
                let fromKey = plan.fromKey
                let toKey = plan.toKey
                let deadEnd = plan.deadEnd
                guard surveyedNodes[fromKey] != nil, deadEnd || surveyedNodes[toKey] != nil else {
                    reject(junction, "endpoint is not an existing vertex")
                    continue
                }
                let fromNode = surveyedNodes[fromKey]
                let toNode = surveyedNodes[toKey]
                let linkMeters = Geometry.distanceMeters(
                    fromNode ?? junction.from.coordinate, toNode ?? junction.to.coordinate)
                let geometryReason: String? = {
                    switch junction.kind {
                    case .zeroLength:
                        return junction.from.coordinate == junction.to.coordinate
                            ? nil : "zeroLength endpoints differ"
                    case .shortLink:
                        return junction.from.coordinate != junction.to.coordinate
                            && linkMeters <= PhysicalJunction.maximumReviewedLinkMeters
                            ? nil : "shortLink exceeds \(PhysicalJunction.maximumReviewedLinkMeters) m"
                    case .osmConnector:
                        if junction.terminus != nil { return "terminus requires osmTrack" }
                        guard let fromNode, let toNode else { return nil }
                        return junction.osmRejection(fromCoordinate: fromNode, toCoordinate: toNode)
                    case .osmTrack:
                        if deadEnd {
                            guard let fromNode else { return nil }
                            return junction.osmRejection(
                                fromCoordinate: fromNode, toCoordinate: junction.to.coordinate)
                        }
                        if junction.terminus != nil { return "unsupported terminus end" }
                        guard let fromNode, let toNode else { return nil }
                        return junction.osmRejection(fromCoordinate: fromNode, toCoordinate: toNode)
                    }
                }()
                let reason: String?
                if fromNode == nil || (!deadEnd && toNode == nil) {
                    reason = "endpoint is not an existing vertex"
                } else if !deadEnd && fromKey == toKey {
                    reason = "endpoints are the same vertex"
                } else if deadEnd && plan.chainKeys == nil {
                    reason = "path has fewer than 2 points"
                } else if let geometryReason {
                    reason = geometryReason
                } else if !acceptedIDs.insert(junction.id).inserted {
                    reason = "duplicate id"
                } else {
                    reason = nil
                }
                if let reason {
                    reject(junction, reason)
                    continue
                }
                let institutions = (graph.nodeMeta[fromKey]?.institutionTypeCodes ?? [])
                    .union(graph.nodeMeta[toKey]?.institutionTypeCodes ?? [])
                if junction.kind == .osmConnector || junction.kind == .osmTrack {
                    let pathIdentity: TrackIdentity
                    if junction.kind == .osmConnector {
                        pathIdentity = PhysicalJunction.osmConnectorIdentity(junction.id)
                    } else if junction.endJunction?.end == .from {
                        pathIdentity = junction.to.identity
                    } else {
                        pathIdentity = junction.from.identity
                    }
                    for point in junction.path ?? [] {
                        _ = ensureNode(point, pathIdentity)
                    }
                    let keys: [String]
                    if deadEnd || junction.endJunction != nil {
                        guard let chained = plan.chainKeys else {
                            reject(junction, "path has fewer than 2 points")
                            continue
                        }
                        keys = chained
                    } else {
                        keys = plan.chainKeys ?? [fromKey, toKey]
                    }
                    let junctionEdge: PhysicalJunctionEdge? = junction.kind == .osmConnector
                        ? .init(junction: junction, institutionTypeCodes: institutions) : nil
                    for (start, end) in zip(keys, keys.dropFirst()) where start != end {
                        let meters = Geometry.distanceMeters(graph.nodes[start]!, graph.nodes[end]!)
                        var edge = Edge(
                            to: end, length: max(meters, 0.01), institutionTypeCode: "",
                            railwayClassCode: junction.kind == .osmTrack ? pathIdentity.railwayClassCode : "",
                            lineName: junction.kind == .osmTrack ? pathIdentity.lineName : "",
                            operator: junction.kind == .osmTrack ? pathIdentity.operatorName : "",
                            connector: nil, physicalJunction: junctionEdge,
                            validFrom: junction.validFrom, validTo: junction.validTo)
                        graph.adjacency[start, default: []].append(edge)
                        edge.to = start
                        graph.adjacency[end, default: []].append(edge)
                    }
                    if junction.kind == .osmTrack, let endJunction = junction.endJunction,
                       let ownKey = endJunction.end == .to ? keys.last : keys.first {
                        let foreignKey = plan.foreignKey ?? physicalNodeKey(
                            endJunction.coordinate, identity: endJunction.identity)
                        guard let ownNode = graph.nodes[ownKey], let foreignNode = graph.nodes[foreignKey],
                              ownKey != foreignKey else {
                            reject(junction, "endpoint is not an existing vertex")
                            continue
                        }
                        let meters = Geometry.distanceMeters(ownNode, foreignNode)
                        guard meters <= PhysicalJunction.maximumOSMAttachMeters else {
                            reject(junction, "attach exceeds \(PhysicalJunction.maximumOSMAttachMeters) m")
                            continue
                        }
                        let stub = PhysicalJunctionEdge(
                            junction: junction, institutionTypeCodes: institutions)
                        var stubEdge = Edge(
                            to: foreignKey, length: max(meters, 0.01), institutionTypeCode: "",
                            railwayClassCode: "", lineName: "", operator: "",
                            connector: nil, physicalJunction: stub,
                            validFrom: junction.validFrom, validTo: junction.validTo)
                        graph.adjacency[ownKey, default: []].append(stubEdge)
                        stubEdge.to = ownKey
                        graph.adjacency[foreignKey, default: []].append(stubEdge)
                    }
                    if junction.kind == .osmTrack {
                        for key in keys {
                            guard graph.nodeMeta[key] != nil else { continue }
                            if !pathIdentity.lineName.isEmpty {
                                graph.nodeMeta[key]!.lineNames.insert(pathIdentity.lineName)
                            }
                            if !pathIdentity.operatorName.isEmpty {
                                graph.nodeMeta[key]!.operators.insert(pathIdentity.operatorName)
                            }
                            if !pathIdentity.railwayClassCode.isEmpty {
                                graph.nodeMeta[key]!.railwayClassCodes.insert(pathIdentity.railwayClassCode)
                            }
                        }
                    }
                    continue
                }
                var edge = Edge(to: toKey, length: junction.kind == .shortLink ? max(linkMeters, 0.01) : 0,
                                institutionTypeCode: "", railwayClassCode: "",
                                lineName: "", operator: "", connector: nil,
                                physicalJunction: .init(junction: junction, institutionTypeCodes: institutions),
                                validFrom: junction.validFrom, validTo: junction.validTo)
                graph.adjacency[fromKey, default: []].append(edge)
                edge.to = fromKey
                graph.adjacency[toKey, default: []].append(edge)
            }
        }
    }

    /// `graphGridKey` — which cell of the graph's node grid a coordinate is
    /// in. Declared in `app-route-solver.js`, but it is graph construction's
    /// only primitive that lives over there, and the graph cannot be built
    /// without it.
    static func graphGridKey(_ coord: Coordinate, cellSize: Double) -> String {
        let normalized = Grid.normalizeGraphCoord(coord)
        return JSNumber.string((normalized.lon / cellSize).rounded(.down)) + ","
            + JSNumber.string((normalized.lat / cellSize).rounded(.down))
    }

    /// The nodes AT a normalized coordinate, in the order `nearbyNodes`
    /// with radius 0 lists its zero-distance hits. An exact match can only be
    /// in the coordinate's own cell, so this reads one bucket and measures
    /// nothing — the path certifier asks it once per recorded vertex.
    public static func exactNodeKeys(_ normalized: Coordinate, in graph: Graph) -> [String] {
        graph.grid[graphGridKey(normalized, cellSize: graph.cellSize)]?
            .filter { graph.nodes[$0] == normalized } ?? []
    }

    /// The nodes near a coordinate, nearest first — the station snap's
    /// candidate list.
    ///
    /// `radiusDeg` sizes the block of cells scanned; it does **not** filter
    /// the results, so a returned node can be further away than the radius,
    /// and with `cellRadius` floored at 1 even a radius of zero scans a 3×3
    /// block. Both are relied on: a platform whose nearest rail is 400 m away
    /// still finds it.
    ///
    /// The sort is by distance and `Array.prototype.sort` is stable, so equal
    /// distances keep the order the scan found them in — which is the cell
    /// order (dx outer, dy inner) and, within a cell, the bucket's insertion
    /// order. Swift's `sort` is not stable, so the original index is carried
    /// as an explicit tiebreaker.
    public static func nearbyNodes(
        _ coord: Coordinate, in graph: Graph, radiusDeg: Double = 0.0015, limit: Int = 30
    ) -> [(key: String, distance: Double)] {
        let normalized = Grid.normalizeGraphCoord(coord)
        let baseX = (normalized.lon / graph.cellSize).rounded(.down)
        let baseY = (normalized.lat / graph.cellSize).rounded(.down)
        let cellRadius = Int(max(1, (radiusDeg / graph.cellSize).rounded(.up)))

        var found: [(key: String, distance: Double, order: Int)] = []
        var seen = Set<String>()
        for dx in -cellRadius...cellRadius {
            for dy in -cellRadius...cellRadius {
                let cell =
                    JSNumber.string(baseX + Double(dx)) + ","
                    + JSNumber.string(baseY + Double(dy))
                guard let bucket = graph.grid[cell] else { continue }
                for key in bucket {
                    guard seen.insert(key).inserted else { continue }
                    let distance = Geometry.distanceMeters(normalized, graph.nodes[key]!)
                    found.append((key, distance, found.count))
                }
            }
        }
        found.sort { $0.distance == $1.distance ? $0.order < $1.order : $0.distance < $1.distance }
        // `Array.prototype.slice(0, limit)`, negative limit and all.
        let end = limit < 0 ? max(0, found.count + limit) : min(limit, found.count)
        return found[0..<end].map { ($0.key, $0.distance) }
    }

    /// `intersects` — do these two sets share a member? Exported to the
    /// solver, which uses it for the hint and institution filters.
    public static func intersects(_ a: Set<String>?, _ b: Set<String>?) -> Bool {
        guard let a, let b else { return false }
        for value in a where b.contains(value) { return true }
        return false
    }

    // =====================================================================
    //  §28 — bounding boxes, the rail-section index and regional subgraphs
    // =====================================================================

    /// `[minX, minY, maxX, maxY]` — longitude first, matching every bbox the
    /// JavaScript passes around.
    public struct BBox: Sendable, Equatable {
        public var minX: Double
        public var minY: Double
        public var maxX: Double
        public var maxY: Double

        public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
            self.minX = minX
            self.minY = minY
            self.maxX = maxX
            self.maxY = maxY
        }

        public init?(array: [Double]) {
            guard array.count == 4 else { return nil }
            self.init(minX: array[0], minY: array[1], maxX: array[2], maxY: array[3])
        }

        public var array: [Double] { [minX, minY, maxX, maxY] }
    }

    public static func bboxIntersects(_ a: BBox, _ b: BBox) -> Bool {
        !(a.maxX < b.minX || a.minX > b.maxX || a.maxY < b.minY || a.minY > b.maxY)
    }

    /// The bbox of one feature's **quantised** geometry.
    ///
    /// Quantised because `iterateGeometryLines` is what the JavaScript walks
    /// here, and the index this feeds is compared against query boxes derived
    /// from the same grid. Returns nil for a feature with no vertices.
    public static func featureBBox(_ feature: SectionFeature) -> BBox? {
        var minX = Double.infinity
        var minY = Double.infinity
        var maxX = -Double.infinity
        var maxY = -Double.infinity
        for line in feature.quantisedLines {
            for point in line {
                if point.lon < minX { minX = point.lon }
                if point.lon > maxX { maxX = point.lon }
                if point.lat < minY { minY = point.lat }
                if point.lat > maxY { maxY = point.lat }
            }
        }
        return minX == .infinity ? nil : BBox(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }

    /// Expand a bbox by a metric margin, longitude scaled by latitude.
    ///
    /// The `max(0.2, cos …)` floor stops the longitude margin exploding near
    /// the poles; none of the five countries goes anywhere near it, but the
    /// clamp is part of the answer and is kept.
    public static func padBBoxMeters(_ bbox: BBox, meters: Double) -> BBox {
        let latPad = meters / 111_320
        let midLat = (bbox.minY + bbox.maxY) / 2
        let lonPad = meters / (111_320 * max(0.2, cos(midLat * .pi / 180)))
        return BBox(
            minX: bbox.minX - lonPad, minY: bbox.minY - latPad,
            maxX: bbox.maxX + lonPad, maxY: bbox.maxY + latPad)
    }

    public static func bboxDiagonalMeters(_ bbox: BBox) -> Double {
        Geometry.distanceMeters(
            Coordinate(lon: bbox.minX, lat: bbox.minY),
            Coordinate(lon: bbox.maxX, lat: bbox.maxY))
    }

    /// `REGION_QUANT_DEG` — regional bboxes are snapped outward to this grid
    /// so that nearby route sections share one subgraph instead of each
    /// building its own.
    public static let regionQuantDeg = 0.25

    public static func quantizeBBoxOutward(_ bbox: BBox) -> BBox {
        BBox(
            minX: (bbox.minX / regionQuantDeg).rounded(.down) * regionQuantDeg,
            minY: (bbox.minY / regionQuantDeg).rounded(.down) * regionQuantDeg,
            maxX: (bbox.maxX / regionQuantDeg).rounded(.up) * regionQuantDeg,
            maxY: (bbox.maxY / regionQuantDeg).rounded(.up) * regionQuantDeg)
    }

    /// The LRU key of a quantised region: `qbbox.map(v => v.toFixed(2))`.
    static func regionKey(_ qbbox: BBox) -> String {
        qbbox.array.map(fixed2).joined(separator: ",")
    }

    /// `Number.prototype.toFixed(2)` over the only values this key sees.
    ///
    /// Two places where the obvious `String(format: "%.2f", value)` is wrong.
    /// ECMAScript takes the sign off with `x < 0`, which is **false** for
    /// negative zero, so JavaScript writes `"0.00"` where `%.2f` writes
    /// `"-0.00"` — and negative zero is reachable, because `Math.ceil` of
    /// anything in `(-0.25, 0]` is `-0`. (Not reachable with these five
    /// countries' coordinates, all of which are 113–145°E and 22–45°N, but
    /// the rule is the rule.) The other is rounding: `toFixed` rounds a tie
    /// away from zero and `%.2f` rounds it to even. That one cannot bite
    /// here, because every input is an integer times 0.25 and 0.25 is a power
    /// of two, so the value is exact and no tie exists.
    static func fixed2(_ value: Double) -> String {
        let negative = value < 0
        let text = String(format: "%.2f", negative ? -value : value)
        return negative ? "-" + text : text
    }

    /// Something with a display point — a station feature, as far as the
    /// regional builder is concerned. A protocol rather than a concrete
    /// station type because the station model belongs to the solver's port,
    /// and all this needs is where the thing is.
    public protocol DisplayLocatable {
        var displayCoordinate: Coordinate? { get }
    }

    /// Stations inside a bbox, in the order they appear in the dataset.
    ///
    /// Note the bounds are inclusive on all four sides, and that the
    /// coordinate used is the display point — **not** quantised, unlike the
    /// rail-section bboxes this is called beside.
    public static func stationsInBBox<T: DisplayLocatable>(_ stations: [T], _ bbox: BBox) -> [T] {
        stations.filter { station in
            guard let c = station.displayCoordinate else { return false }
            return c.lon >= bbox.minX && c.lon <= bbox.maxX && c.lat >= bbox.minY
                && c.lat <= bbox.maxY
        }
    }

    /// True if any vertex of a solved feature lies within `marginDeg` of the
    /// region edge — the signal that the true optimum might leave the region,
    /// so the search should widen or fall back to the full graph. This is what
    /// makes an on-demand regional result provably equal to the all-Japan one.
    ///
    /// It iterates by geometry type rather than assuming a LineString: the
    /// solver emits only LineStrings today, but comparing a nested coordinate
    /// array against a number is always false, so a MultiLineString would
    /// silently pass the check and a truncated path would be accepted.
    public static func pathTouchesRegionEdge(
        lines: [[Coordinate]], regionBBox: BBox?, marginDeg: Double
    ) -> Bool {
        guard let regionBBox else { return false }
        for line in lines {
            for c in line {
                if c.lon <= regionBBox.minX + marginDeg || c.lon >= regionBBox.maxX - marginDeg
                    || c.lat <= regionBBox.minY + marginDeg
                    || c.lat >= regionBBox.maxY - marginDeg
                {
                    return true
                }
            }
        }
        return false
    }

    /// `RAIL_INDEX_CELL_DEG` — the rail-section index's cell size.
    public static let railIndexCellDeg = 0.1

    /// `REGIONAL_GRAPH_NODE_BUDGET` — the steady-state cap on total resident
    /// regional-graph nodes.
    ///
    /// It was 140,000, which is smaller than a single cross-Japan region
    /// (50k–72k nodes), so a multi-region load evicted a region and then
    /// rebuilt the identical one two or three times in one pass. The
    /// full-Japan graph is ~377k nodes and is already a tolerated fallback, so
    /// holding four or five regions is well inside that envelope.
    public static let regionalGraphNodeBudget = 300_000

    /// `REGIONAL_GRAPH_LOAD_NODE_BUDGET` — while a progressive load or one
    /// interactive solve is building regions back to back, eviction is
    /// suspended up to this larger transient, so a region built for an early
    /// train is still resident when a later train needs it.
    public static let regionalGraphLoadNodeBudget = 600_000
}

// =========================================================================
//  The module-level mutable state of app-route-graph.js §28
// =========================================================================

extension RouteGraph {

    public enum GraphCachePolicy: Sendable {
        /// Historical cache behavior, retained for parity/export callers.
        case standard
        /// Keep at most one graph across full, regional and corridor caches.
        /// Larger graphs remain available to the caller but are never retained.
        case bounded(maximumNodes: Int)
    }

    /// The rail-section dataset, its spatial index, the memoised full-network
    /// graph and the LRU of regional subgraphs.
    ///
    /// In the JavaScript these are four module-level `let`s plus
    /// `invalidateRouteGraphIndexes()`, which the country switch calls to drop
    /// all of them at once. Making them one object is the only liberty taken:
    /// the alternative in Swift is global mutable state, and the country
    /// switch's rule — never leave two countries' networks loaded, because
    /// they share station names and a stop resolved against the wrong network
    /// looks like a route rather than an error — is far easier to keep when
    /// dropping a country means dropping an object.
    public final class RouteGraphStore {

        public let sections: [SectionFeature]
        private let cachePolicy: GraphCachePolicy
        public let policy: BuildPolicy
        public let junctions: [PhysicalJunction]

        /// The solver's `addStationTransferConnectorEdges`, if it has been
        /// ported. Called with the freshly built graph and the region it
        /// covers, exactly where `getRegionalRouteGraph` and
        /// `getRuntimeRouteGraph` call it. Left nil, the store builds the pure
        /// rail graph and nothing else — which is what an offline exporter
        /// with no station dataset wants, and what the parity fixture records.
        public var augment: ((Graph, BBox?) -> Void)?

        private var bboxes: [BBox?]?
        private var spatialIndex: [String: [Int]]?
        private var fullGraphCache: Graph?
        /// Region key → graph, plus the key order that makes it an LRU. A
        /// JavaScript `Map` is both; a Swift `Dictionary` is neither.
        private var regionalGraphs: [String: Graph] = [:]
        private var regionalOrder: [String] = []
        private var residentNodes = 0
        private var corridorGraphs: [(indices: [Int], graph: Graph)] = []
        private var junctionCellSets: [(points: [Coordinate], cells: Set<String>)]?
        private var compiledSections: CompiledSections?
        private var junctionPlanCache: [JunctionPlan]?

        private func compiled() -> CompiledSections {
            if let compiledSections { return compiledSections }
            let made = CompiledSections(features: sections, policy: policy)
            compiledSections = made
            return made
        }

        private func junctionPlans() -> [JunctionPlan] {
            if let junctionPlanCache { return junctionPlanCache }
            let made = junctions.map(JunctionPlan.init)
            junctionPlanCache = made
            return made
        }

        private func build(featureIndices: [Int]) -> Graph {
            let plans: [JunctionPlan]?
            if case .physicalRailway = policy {
                plans = junctionPlans()
            } else {
                plans = nil
            }
            let graph = RouteGraph.build(compiled: compiled(), featureIndices: featureIndices,
                                         junctions: junctions, plans: plans)
            // The compiler memo also grows as requests widen. Do not retain a
            // country-sized vertex table beside an oversized uncached graph.
            // Release it before station augmentation and solving allocate work.
            if case .bounded(let maximumNodes) = cachePolicy,
               let compiledSections, compiledSections.idCount > maximumNodes {
                self.compiledSections = nil
            }
            return graph
        }

        var retainedCompiledNodeCount: Int { compiledSections?.idCount ?? 0 }

        public init(sections: [SectionFeature], policy: BuildPolicy = .physicalRailway,
                    junctions: [PhysicalJunction] = [],
                    augment: ((Graph, BBox?) -> Void)? = nil,
                    cachePolicy: GraphCachePolicy = .standard) {
            if case .bounded(let maximumNodes) = cachePolicy {
                precondition(maximumNodes > 0, "Graph cache node budget must be positive")
            }
            self.cachePolicy = cachePolicy
            self.sections = sections
            self.policy = policy
            self.junctions = junctions
            self.augment = augment
        }

        /// Release cached graph ownership before allocating its replacement.
        /// Active callers retain their own graph; eviction cannot truncate it.
        private func prepareForGraphBuild() {
            guard case .bounded = cachePolicy else { return }
            fullGraphCache = nil
            regionalGraphs.removeAll()
            regionalOrder.removeAll()
            residentNodes = 0
            corridorGraphs.removeAll()
        }

        private func mayRetain(_ graph: Graph) -> Bool {
            switch cachePolicy {
            case .standard: true
            case .bounded(let maximumNodes): graph.nodeCount <= maximumNodes
            }
        }

        /// Includes every graph category, not only regional LRU entries.
        public var retainedGraphNodeCount: Int {
            (fullGraphCache?.nodeCount ?? 0) + residentNodes
                + corridorGraphs.reduce(0) { $0 + $1.graph.nodeCount }
        }

        /// Drops every memo. The country switch's single call.
        public func invalidate() {
            spatialIndex = nil
            bboxes = nil
            fullGraphCache = nil
            regionalGraphs.removeAll()
            regionalOrder.removeAll()
            residentNodes = 0
            corridorGraphs.removeAll()
            junctionCellSets = nil
            compiledSections = nil
            junctionPlanCache = nil
        }

        private func cell(_ coordinate: Coordinate) -> String {
            JSNumber.string((coordinate.lon / railIndexCellDeg).rounded(.down)) + ","
                + JSNumber.string((coordinate.lat / railIndexCellDeg).rounded(.down))
        }

        private func cachedJunctionCellSets() -> [(points: [Coordinate], cells: Set<String>)] {
            if let junctionCellSets { return junctionCellSets }
            let computed = junctions.map { junction in
                let points = [junction.from.coordinate, junction.to.coordinate] + (junction.path ?? [])
                return (points, Set(points.map(cell)))
            }
            junctionCellSets = computed
            return computed
        }

        /// Cached per-feature bboxes — the JavaScript stashes these on the
        /// feature object itself as `__railBbox`.
        private func featureBBoxes() -> [BBox?] {
            if let bboxes { return bboxes }
            let computed = sections.map { RouteGraph.featureBBox($0) }
            bboxes = computed
            return computed
        }

        /// A coarse grid over feature bboxes: cheap (bboxes and indices only),
        /// built once, so a regional build never scans all 22k features.
        ///
        /// Feature identity is the index in the shipped file, because that is
        /// the only identity a feature has. The JavaScript de-duplicates by
        /// object identity, which is the same thing.
        public func railSectionSpatialIndex() -> [String: [Int]] {
            if let spatialIndex { return spatialIndex }
            var grid: [String: [Int]] = [:]
            let boxes = featureBBoxes()
            for (index, bbox) in boxes.enumerated() {
                guard let bbox else { continue }
                let x0 = (bbox.minX / railIndexCellDeg).rounded(.down)
                let x1 = (bbox.maxX / railIndexCellDeg).rounded(.down)
                let y0 = (bbox.minY / railIndexCellDeg).rounded(.down)
                let y1 = (bbox.maxY / railIndexCellDeg).rounded(.down)
                var x = x0
                while x <= x1 {
                    var y = y0
                    while y <= y1 {
                        grid[JSNumber.string(x) + "," + JSNumber.string(y), default: []]
                            .append(index)
                        y += 1
                    }
                    x += 1
                }
            }
            spatialIndex = grid
            return grid
        }

        /// The indices of every feature whose bbox meets `bbox`.
        ///
        /// The ORDER is part of the answer. Cells are scanned x outer, y
        /// inner, and a feature is emitted the first time it is seen — so the
        /// graph built from this list gets its adjacency lists in this order,
        /// and Dijkstra relaxes them in it.
        public func featureIndicesInBBox(_ bbox: BBox) -> [Int] {
            let grid = railSectionSpatialIndex()
            let boxes = featureBBoxes()
            let x0 = (bbox.minX / railIndexCellDeg).rounded(.down)
            let x1 = (bbox.maxX / railIndexCellDeg).rounded(.down)
            let y0 = (bbox.minY / railIndexCellDeg).rounded(.down)
            let y1 = (bbox.maxY / railIndexCellDeg).rounded(.down)
            var seen = Set<Int>()
            var out: [Int] = []
            var x = x0
            while x <= x1 {
                var y = y0
                while y <= y1 {
                    if let bucket = grid[JSNumber.string(x) + "," + JSNumber.string(y)] {
                        for index in bucket {
                            guard seen.insert(index).inserted else { continue }
                            if let fb = boxes[index], RouteGraph.bboxIntersects(fb, bbox) {
                                out.append(index)
                            }
                        }
                    }
                    y += 1
                }
                x += 1
            }
            return out
        }

        public func featuresInBBox(_ bbox: BBox) -> [SectionFeature] {
            featureIndicesInBBox(bbox).map { sections[$0] }
        }

        /// The full-network graph — ~377k nodes for Japan.
        ///
        /// Kept as the guaranteed-correct fallback for on-demand solving:
        /// built lazily and memoised only if a regional subgraph proves
        /// insufficient, never eagerly at startup.
        public func fullGraph() -> Graph {
            if let fullGraphCache { return fullGraphCache }
            prepareForGraphBuild()
            let graph = build(featureIndices: Array(sections.indices))
            augment?(graph, nil)
            if mayRetain(graph) { fullGraphCache = graph }
            return graph
        }

        /// Evict least-recently-used regional graphs until the resident node
        /// count is at or below `target` — always keeping at least one, so the
        /// in-flight solve still has its graph.
        public func trimRegionalGraphCache(target: Int) {
            while residentNodes > target && regionalGraphs.count > 1 {
                let oldestKey = regionalOrder.removeFirst()
                if let oldest = regionalGraphs.removeValue(forKey: oldestKey) {
                    residentNodes -= oldest.nodeCount
                }
            }
        }

        /// Build, or reuse from the LRU, the regional subgraph covering a
        /// bbox.
        ///
        /// A subgraph built from EVERY rail feature inside a bbox is
        /// structurally identical to the full graph restricted to that bbox,
        /// so Dijkstra returns the same optimal path as long as that path
        /// stays inside — which the caller checks with
        /// ``pathTouchesRegionEdge`` and widens or falls back to the full
        /// graph when it does not.
        public func regionalGraph(
            for bbox: BBox, importInProgress: Bool = false, routeSolveInProgress: Bool = false
        ) -> Graph {
            let qbbox = RouteGraph.quantizeBBoxOutward(bbox)
            let key = RouteGraph.regionKey(qbbox)
            if let cached = regionalGraphs[key] {
                // The LRU touch: delete then re-insert moves the key to the
                // young end. Reproducing it is the whole reason this cache
                // carries its own key order.
                if let position = regionalOrder.firstIndex(of: key) {
                    regionalOrder.remove(at: position)
                }
                regionalOrder.append(key)
                return cached
            }
            prepareForGraphBuild()
            let graph = build(featureIndices: featureIndicesInBBox(qbbox))
            augment?(graph, qbbox)
            graph.regionBBox = qbbox
            guard mayRetain(graph) else { return graph }
            regionalGraphs[key] = graph
            regionalOrder.append(key)
            residentNodes += graph.nodeCount
            trimRegionalGraphCache(
                target: importInProgress || routeSolveInProgress
                    ? RouteGraph.regionalGraphLoadNodeBudget
                    : RouteGraph.regionalGraphNodeBudget)
            return graph
        }

        /// The indices of every feature whose bbox meets the `meters` box
        /// around at least one of `coordinates`, ascending.
        ///
        /// A long ride's own bbox covers whole regions it never touches; this
        /// keeps only the track along the path.
        public func featureIndicesNear(_ coordinates: [Coordinate], meters: Double) -> [Int] {
            let grid = railSectionSpatialIndex()
            let boxes = featureBBoxes()
            var found = Set<Int>()
            for coordinate in coordinates {
                let box = RouteGraph.padBBoxMeters(
                    BBox(minX: coordinate.lon, minY: coordinate.lat,
                         maxX: coordinate.lon, maxY: coordinate.lat), meters: meters)
                let x0 = (box.minX / railIndexCellDeg).rounded(.down)
                let x1 = (box.maxX / railIndexCellDeg).rounded(.down)
                let y0 = (box.minY / railIndexCellDeg).rounded(.down)
                let y1 = (box.maxY / railIndexCellDeg).rounded(.down)
                var x = x0
                while x <= x1 {
                    var y = y0
                    while y <= y1 {
                        let cell = JSNumber.string(x) + "," + JSNumber.string(y)
                        y += 1
                        guard let bucket = grid[cell] else { continue }
                        for index in bucket where !found.contains(index) {
                            if let fb = boxes[index], RouteGraph.bboxIntersects(fb, box) {
                                found.insert(index)
                            }
                        }
                    }
                    x += 1
                }
            }
            return found.sorted()
        }

        /// A graph of the track within `meters` of `coordinates` — enough to
        /// certify a recorded path and its boundaries, which only ever walk
        /// along the path or a bounded approach from one of its vertices.
        /// Memoised by feature set, so the repeated proofs of one ride reuse it.
        public func corridorGraph(for coordinates: [Coordinate], meters: Double) -> Graph {
            // A reviewed junction is added only when its anchor vertex is in
            // the graph, and an osmTrack's path can reach the ride while its
            // anchor sits farther than `meters` away. Any junction touching
            // the corridor brings its own endpoints, so the proof never
            // depends on how far the graph happens to extend.
            var points = coordinates
            var cells = Set(coordinates.map(cell))
            var pending = cachedJunctionCellSets()
            var grew = true
            while grew {
                grew = false
                pending.removeAll { junction in
                    guard !junction.cells.isDisjoint(with: cells) else { return false }
                    points += junction.points
                    cells.formUnion(junction.cells)
                    grew = true
                    return true
                }
            }
            // In the order a bbox scan over the same path would emit them
            // (`featureIndicesInBBox`: cells x outer, y inner, first sighting
            // wins, bucket order within a cell). Adjacency order follows
            // feature order, and the certifier breaks ties between co-located
            // identities by it — so the corridor answers as the bbox did.
            var indices = featureIndicesNear(points, meters: meters)
            if let first = coordinates.first {
                var box = BBox(minX: first.lon, minY: first.lat, maxX: first.lon, maxY: first.lat)
                for c in coordinates {
                    box.minX = Swift.min(box.minX, c.lon); box.minY = Swift.min(box.minY, c.lat)
                    box.maxX = Swift.max(box.maxX, c.lon); box.maxY = Swift.max(box.maxY, c.lat)
                }
                let query = RouteGraph.quantizeBBoxOutward(RouteGraph.padBBoxMeters(box, meters: meters))
                let x0 = (query.minX / railIndexCellDeg).rounded(.down)
                let y0 = (query.minY / railIndexCellDeg).rounded(.down)
                let boxes = featureBBoxes()
                func scanOrder(_ index: Int) -> (Double, Double, Int) {
                    guard let fb = boxes[index] else { return (x0, y0, index) }
                    return (Swift.max((fb.minX / railIndexCellDeg).rounded(.down), x0),
                            Swift.max((fb.minY / railIndexCellDeg).rounded(.down), y0), index)
                }
                indices.sort { scanOrder($0) < scanOrder($1) }
            }
            if let cached = corridorGraphs.first(where: { $0.indices == indices }) {
                return cached.graph
            }
            prepareForGraphBuild()
            let graph = build(featureIndices: indices)
            if let augment, !coordinates.isEmpty {
                let bbox = RouteGraph.padBBoxMeters(BBox(
                    minX: coordinates.map(\.lon).min()!, minY: coordinates.map(\.lat).min()!,
                    maxX: coordinates.map(\.lon).max()!, maxY: coordinates.map(\.lat).max()!),
                    meters: meters)
                augment(graph, bbox)
            }
            guard mayRetain(graph) else { return graph }
            corridorGraphs.append((indices, graph))
            if corridorGraphs.count > 32 { corridorGraphs.removeFirst() }
            return graph
        }

        /// The LRU's keys, oldest first — the order eviction follows.
        public var regionCacheKeys: [String] { regionalOrder }
        public var residentNodeCount: Int { residentNodes }
    }
}

// =========================================================================
//  JavaScript ordering and string rules these keys depend on
// =========================================================================

extension RouteGraph {

    /// `Array.prototype.sort()` with no comparator: strings ordered by UTF-16
    /// code unit.
    ///
    /// Not the same as Swift's `<` on `String`, which orders by Unicode
    /// canonical equivalence. Every list sorted here ends up inside a
    /// persisted cache key and most of them hold Japanese, Chinese or Korean
    /// names, so the rule is stated rather than inherited.
    static func jsSorted<S: Sequence>(_ values: S) -> [String] where S.Element == String {
        // a < b  ⟺  not (b <= a)
        values.sorted { !JSNumber.stringLessOrEqual($1, $0) }
    }

    /// `[...new Set(values)]` — first occurrence wins, insertion order kept.
    static func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

}

extension Coordinate: RouteGraph.DisplayLocatable {
    public var displayCoordinate: Coordinate? { self }
}

// =========================================================================
//  Reading the shipped rail-section datasets
// =========================================================================

extension RouteGraph {

    /// `app/data/rail-sections*.json` — the solver's own routable geometry,
    /// one feature per stretch of track.
    ///
    /// This is a *different* dataset from the compact display packages that
    /// ``CompactPackage`` reads. Japan's is raw N02 (`N02_001`…`N02_004`,
    /// 21,933 features); the other four are derived by
    /// `scripts/railway/rebuild-solver-sections.py` from the display package
    /// and spell their properties out. Both spellings are accepted here
    /// because the JavaScript accepts both, at every edge.
    public struct SectionFeatureCollection: Decodable {
        public let features: [SectionFeature]

        public static func load(contentsOf url: URL) throws -> SectionFeatureCollection {
            try JSONDecoder().decode(SectionFeatureCollection.self, from: Data(contentsOf: url))
        }
    }
}

extension RouteGraph.SectionFeature: Decodable {
    private enum CodingKeys: String, CodingKey { case properties, geometry }

    private struct Properties: Decodable {
        let lineName: String?
        let `operator`: String?
        let institutionTypeCode: String?
        let railwayClassCode: String?
        let validFrom: String?
        let validTo: String?
        let historyId: String?
        let level: String?
        let trackID: String?
        let sourceID: String?

        private enum CodingKeys: String, CodingKey {
            case n02_001 = "N02_001"
            case n02_002 = "N02_002"
            case n02_003 = "N02_003"
            case n02_004 = "N02_004"
            case line_name, `operator`, institution_type_code, railway_class_code
            case valid_from, valid_to, history_id
            case service_validity, infrastructure_validity
            case level, track_id, source_id
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // JavaScript's `a || b`: an empty string is falsy, so it falls
            // through to the next spelling just as a missing key does.
            func orFallback(_ primary: CodingKeys, _ secondary: CodingKeys) throws -> String? {
                let value = try c.decodeIfPresent(String.self, forKey: primary)
                if let value, !value.isEmpty { return value }
                return try c.decodeIfPresent(String.self, forKey: secondary)
            }
            func identityValue(_ key: CodingKeys) throws -> String? {
                guard c.contains(key), !(try c.decodeNil(forKey: key)) else { return nil }
                if let text = try? c.decode(String.self, forKey: key) { return text }
                return JSNumber.string(try c.decode(Double.self, forKey: key))
            }
            level = try identityValue(.level)
            trackID = try identityValue(.track_id)
            sourceID = try identityValue(.source_id)
            railwayClassCode = try orFallback(.n02_001, .railway_class_code)
            institutionTypeCode = try orFallback(.n02_002, .institution_type_code)
            lineName = try orFallback(.n02_003, .line_name)
            `operator` = try orFallback(.n02_004, .operator)
            let legacyFrom = try c.decodeIfPresent(String.self, forKey: .valid_from)
            let legacyTo = try c.decodeIfPresent(String.self, forKey: .valid_to)
            let service = try c.decodeIfPresent([String?].self, forKey: .service_validity)
            let infrastructure = try c.decodeIfPresent([String?].self, forKey: .infrastructure_validity)
            let resolved = RailServiceValidity.bounds(
                service: service, infrastructure: infrastructure,
                validFrom: legacyFrom, validTo: legacyTo,
                hasLegacy: c.contains(.valid_from) || c.contains(.valid_to))
            validFrom = resolved.0
            validTo = resolved.1
            let rawHistoryID = try c.decodeIfPresent(String.self, forKey: .history_id)
            let trimmedHistoryID = rawHistoryID?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            historyId = (trimmedHistoryID?.isEmpty == false) ? trimmedHistoryID : nil
        }
    }

    private struct Geometry: Decodable {
        let type: String
        let lines: [[Coordinate]]

        private enum CodingKeys: String, CodingKey { case type, coordinates }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            type = try c.decode(String.self, forKey: .type)
            // `iterateGeometryLines` handles exactly these three and returns
            // nothing for anything else.
            switch type {
            case "LineString":
                lines = [try c.decode([[Double]].self, forKey: .coordinates)
                    .compactMap(Coordinate.init(pair:))]
            case "MultiLineString":
                lines = try c.decode([[[Double]]].self, forKey: .coordinates)
                    .map { $0.compactMap(Coordinate.init(pair:)) }
            case "Point":
                lines = [[Coordinate(pair: try c.decode([Double].self, forKey: .coordinates))]
                    .compactMap { $0 }]
            default:
                lines = []
            }
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let properties = try c.decodeIfPresent(Properties.self, forKey: .properties)
        // The `||` fallback chain, resolved once: an empty string is falsy in
        // JavaScript, so it falls through to the next spelling just as a
        // missing key does.
        func nonEmpty(_ value: String?) -> String { (value?.isEmpty == false) ? value! : "" }
        let geometry = try c.decodeIfPresent(Geometry.self, forKey: .geometry)
        self.init(
            properties: RouteGraph.SectionProperties(
                lineName: nonEmpty(properties?.lineName),
                operator: nonEmpty(properties?.operator),
                institutionTypeCode: nonEmpty(properties?.institutionTypeCode),
                railwayClassCode: nonEmpty(properties?.railwayClassCode),
                validFrom: properties?.validFrom,
                validTo: properties?.validTo,
                historyId: properties?.historyId, level: properties?.level, trackID: properties?.trackID, sourceID: properties?.sourceID),
            lines: geometry?.lines ?? [], geometryType: geometry?.type ?? "")
    }
}
