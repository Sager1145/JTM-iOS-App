import Foundation

/// The deterministic routing kernel from `app-route-solver.js` §29.
///
/// This file deliberately stops at graph-node paths. Station resolution,
/// endpoint completion and whole-train section assembly are separate layers;
/// keeping this kernel pure lets the JavaScript and Swift implementations run
/// over exactly the same graph and compare every chosen node and cost.
public enum RouteSolver {
    /// Passenger transfers describe walking between platforms, not track a
    /// train can traverse. Physical rail is the default for every solver entry.
    public enum TraversalPolicy: Sendable, Equatable {
        case physicalRail
        case passengerTransfers

        public func permits(_ edge: RouteGraph.Edge) -> Bool {
            self == .passengerTransfers || edge.connector == nil
        }
    }

    public static let stationSnapCostFactor = 4.0
    public static let nonPreferredInstitutionLengthFactor = 180.0
    public static let nonPreferredInstitutionEdgePenalty = 5_000.0
    public static let nonPreferredOperatorLengthFactor = 6.0
    public static let nonPreferredLineLengthFactor = 8.0
    public static let stationSnapMaxDistanceMeters = 500.0
    public static let nonPreferredStationSnapPenalty = 20_000.0
    public static let nonPreferredOperatorStationSnapPenalty = 12_000.0
    public static let nonPreferredLineStationSnapPenalty = 15_000.0
    /// Endpoint plausibility guard. When a section names a station without an
    /// N02 code, every same-name station in the country is an endpoint
    /// candidate. A strict attempt can then drop the nearby station's graph
    /// node on institution grounds and reach a same-name station in another
    /// region instead (糸魚川→泊 snapping to 泊 on 山陰線); the detour guard
    /// cannot see that because the straight line is just as long as the path.
    /// A result whose endpoint station is more than
    /// `endpointAmbiguityDistanceFactor` times as far as another same-name
    /// candidate is rejected so a laxer attempt (or the final fallback) can
    /// find the near one. Only applied beyond
    /// `endpointAmbiguityMinStraightMeters`, only to endpoints the section
    /// names without an N02 code, never to a from-station pinned by the
    /// continuity anchor, and a rejected result is still returned as a last
    /// resort when no attempt (including the fallback) finds anything else,
    /// so a section that solved before this guard existed never becomes nil.
    public static let endpointAmbiguityMinStraightMeters = 20_000.0
    public static let endpointAmbiguityDistanceFactor = 2.0

    public struct TrainPolicy: Sendable, Equatable {
        public var institutionFilterMode: String
        /// ADR 0011: the ride's date, `YYYY-MM-DD`, or `nil` for an undated
        /// ride. Governs which rail-history edges `dijkstra` may use.
        public var rideDate: String?
        /// Institution codes rejected even when the filter mode is soft and
        /// the soft fallback restores the default allowed set. Conventional
        /// JR sets this to `["1"]`.
        public var hardExcludedInstitutionTypeCodes: [String]

        public init(
            institutionFilterMode: String = "soft", rideDate: String? = nil,
            hardExcludedInstitutionTypeCodes: [String] = []
        ) {
            self.institutionFilterMode = institutionFilterMode
            self.rideDate = rideDate
            self.hardExcludedInstitutionTypeCodes = hardExcludedInstitutionTypeCodes
        }
    }

    public struct TrainContext: Sendable, Equatable {
        public var id: String
        public var number: String
        public var trainType: String
        public var company: String
        public var origin: String
        public var destination: String
        public var preferredLineNames: [String]
        public var preferredOperatorNames: [String]
        public var allowedInstitutionTypeCodes: [String]?
        public var institutionFilterMode: String
        /// ADR 0011: the ride's ISO day, used to keep retired railway out of
        /// the graph for rides after its abolition. `nil` = undated ride.
        public var rideDate: String?

        public init(
            id: String = "", number: String = "", trainType: String = "",
            company: String = "", origin: String = "", destination: String = "",
            preferredLineNames: [String] = [], preferredOperatorNames: [String] = [],
            allowedInstitutionTypeCodes: [String]? = nil,
            institutionFilterMode: String = "soft",
            rideDate: String? = nil
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
            self.rideDate = rideDate
        }

        public var policy: TrainPolicy {
            .init(
                institutionFilterMode: institutionFilterMode, rideDate: rideDate,
                hardExcludedInstitutionTypeCodes: RouteGraph.hardExcludedInstitutionTypeCodes(
                    trainType: trainType, company: company, country: "jp"))
        }
    }

    public struct SegmentHints: Sendable, Equatable {
        public var preferredLines: Set<String>
        public var preferredOperators: Set<String>
        public var requiredLines: Set<String>
        public var requiredOperators: Set<String>
        public var requirePreferredInstitution: Bool
        public var explicitRequiredLines: Set<String>
        public var explicitRequiredOperators: Set<String>
        public var commonLines: Set<String>
        public var commonOperators: Set<String>
        public var allCommonLines: Set<String>
        public var allCommonOperators: Set<String>
        public var preferredInstitutionCommonLines: Set<String>
        public var preferredInstitutionCommonOperators: Set<String>
        public var fromLines: Set<String>
        public var toLines: Set<String>
        public var fromOperators: Set<String>
        public var toOperators: Set<String>
        public var fromPreferredLines: Set<String>
        public var toPreferredLines: Set<String>
        public var fromPreferredOperators: Set<String>
        public var toPreferredOperators: Set<String>
        public var solveMode: String
        /// Package geometry forbidden for this section's station order. Kept
        /// in hints so every solve attempt retains it without mutating graphs.
        /// Only edges whose operator and line name are in
        /// `directionExcludedFamilies` are dropped for landing on one of these.
        public var directionExcludedCoordinates: Set<Coordinate> = []
        /// NUL-separated `operator` and line name of the direction-restricted
        /// package line family. Empty when nothing is excluded.
        public var directionExcludedFamilies: Set<String> = []

        public init(
            preferredLines: Set<String> = [],
            preferredOperators: Set<String> = [],
            requiredLines: Set<String> = [],
            requiredOperators: Set<String> = [],
            requirePreferredInstitution: Bool = false,
            explicitRequiredLines: Set<String> = [],
            explicitRequiredOperators: Set<String> = [],
            commonLines: Set<String> = [], commonOperators: Set<String> = [],
            allCommonLines: Set<String> = [], allCommonOperators: Set<String> = [],
            preferredInstitutionCommonLines: Set<String> = [],
            preferredInstitutionCommonOperators: Set<String> = [],
            fromLines: Set<String> = [], toLines: Set<String> = [],
            fromOperators: Set<String> = [], toOperators: Set<String> = [],
            fromPreferredLines: Set<String> = [], toPreferredLines: Set<String> = [],
            fromPreferredOperators: Set<String> = [], toPreferredOperators: Set<String> = [],
            solveMode: String = "base"
        ) {
            self.preferredLines = preferredLines
            self.preferredOperators = preferredOperators
            self.requiredLines = requiredLines
            self.requiredOperators = requiredOperators
            self.requirePreferredInstitution = requirePreferredInstitution
            self.explicitRequiredLines = explicitRequiredLines
            self.explicitRequiredOperators = explicitRequiredOperators
            self.commonLines = commonLines
            self.commonOperators = commonOperators
            self.allCommonLines = allCommonLines
            self.allCommonOperators = allCommonOperators
            self.preferredInstitutionCommonLines = preferredInstitutionCommonLines
            self.preferredInstitutionCommonOperators = preferredInstitutionCommonOperators
            self.fromLines = fromLines
            self.toLines = toLines
            self.fromOperators = fromOperators
            self.toOperators = toOperators
            self.fromPreferredLines = fromPreferredLines
            self.toPreferredLines = toPreferredLines
            self.fromPreferredOperators = fromPreferredOperators
            self.toPreferredOperators = toPreferredOperators
            self.solveMode = solveMode
        }
    }

    public struct Candidate: Sendable, Equatable {
        public var key: String
        public var distance: Double

        public init(key: String, distance: Double) {
            self.key = key
            self.distance = distance
        }
    }

    /// One station geometry snapped to one routable graph node.
    public struct StationNodeCandidate: Sendable, Equatable {
        public var key: String
        public var distance: Double
        public var score: Double
        public var hasPreferredInstitution: Bool
        public var stationIndex: Int

        public init(
            key: String, distance: Double, score: Double,
            hasPreferredInstitution: Bool, stationIndex: Int
        ) {
            self.key = key
            self.distance = distance
            self.score = score
            self.hasPreferredInstitution = hasPreferredInstitution
            self.stationIndex = stationIndex
        }
    }

    public struct SolvedTarget: Sendable, Equatable {
        public var targetKey: String
        public var sourceKey: String
        public var cost: Double
        public var pathKeys: [String]
        /// The edge actually relaxed onto each node of `pathKeys`, so parallel-edge
        /// consumers (`usedInstitutionTypeCodes`, `routeLineMismatchPenalty`) score
        /// the path Dijkstra chose rather than the first adjacency entry between
        /// the same pair of nodes. `edges[i]` is the edge from `pathKeys[i]` to
        /// `pathKeys[i + 1]`.
        public var edges: [RouteGraph.Edge]

        public init(
            targetKey: String, sourceKey: String, cost: Double, pathKeys: [String],
            edges: [RouteGraph.Edge] = []
        ) {
            self.targetKey = targetKey
            self.sourceKey = sourceKey
            self.cost = cost
            self.pathKeys = pathKeys
            self.edges = edges
        }
    }

    public static func edgeHasPreferredInstitution(
        _ edge: RouteGraph.Edge, allowedCodes: [String]
    ) -> Bool {
        edgeHasPreferredInstitution(edge, allowed: Set(allowedCodes.filter { !$0.isEmpty }))
    }

    private static func edgeHasPreferredInstitution(
        _ edge: RouteGraph.Edge, allowed: Set<String>
    ) -> Bool {
        if allowed.isEmpty { return true }
        if let junction = edge.physicalJunction {
            return junction.institutionTypeCodes.allSatisfy { $0.isEmpty || allowed.contains($0) }
        }
        if let connector = edge.connector {
            if connector.institutionTypeCodes.isEmpty { return true }
            return connector.institutionTypeCodes.allSatisfy {
                $0.isEmpty || allowed.contains($0)
            }
        }
        if edge.institutionTypeCode.isEmpty { return true }
        return allowed.contains(edge.institutionTypeCode)
    }

    public static func stationMatchesPreferredInstitution(
        _ feature: Stations.Feature, allowedCodes: [String]
    ) -> Bool {
        stationMatchesPreferredInstitution(
            feature, preferred: Set(allowedCodes.filter { !$0.isEmpty }))
    }

    private static func stationMatchesPreferredInstitution(
        _ feature: Stations.Feature, preferred: Set<String>
    ) -> Bool {
        if preferred.isEmpty { return true }
        let code = Stations.stationInstitutionTypeCode(feature)
        return code.isEmpty || preferred.contains(code)
    }

    public static func filterStationsByPreferredInstitution(
        _ indices: [Int], in index: Stations.Index, allowedCodes: [String]
    ) -> [Int] {
        let preferred = Set(allowedCodes.filter { !$0.isEmpty })
        return indices.filter {
            stationMatchesPreferredInstitution(index.features[$0], preferred: preferred)
        }
    }

    public static func filterStationCandidatesNear(
        _ indices: [Int], referenceIndices: [Int], in index: Stations.Index,
        maxDistanceMeters: Double = 1_800
    ) -> [Int] {
        guard !indices.isEmpty, !referenceIndices.isEmpty else { return [] }
        return indices.filter { candidateIndex in
            guard let candidate = coordinate(Stations.displayCoordinate(
                index.features[candidateIndex])) else { return false }
            return referenceIndices.contains { referenceIndex in
                guard let reference = coordinate(Stations.displayCoordinate(
                    index.features[referenceIndex])) else { return false }
                return Geometry.distanceMeters(candidate, reference) <= maxDistanceMeters
            }
        }
    }

    /// Route-specific endpoint expansion. Source station codes identify one
    /// platform/line; a long-distance section may need a nearby same-name
    /// platform on the section's actual line, so that candidate is added while
    /// the exact-code station remains the fallback.
    /// ADR 0011: drop endpoint station candidates not valid on the ride date,
    /// with the same half-open rule as rail edges (`app-route-graph.js`'s
    /// `filterStationCandidatesByRideDate`). Order is preserved.
    public static func filterStationCandidatesByRideDate(
        _ candidates: [Int], in index: Stations.Index, rideDate: String?
    ) -> [Int] {
        candidates.filter { i in
            let feature = index.features[i]
            return RouteGraph.RailValidity.isValid(
                validFrom: Stations.stationValidFrom(feature),
                validTo: Stations.stationValidTo(feature), on: rideDate)
        }
    }

    public static func resolveRouteEndpointStationCandidates(
        _ endpoint: Stations.Query,
        in index: Stations.Index,
        allowedCodes: [String],
        sectionLineNames: [String],
        sectionOperatorNames: [String] = [],
        rideDate: String? = nil
    ) -> [Int] {
        var candidates = index.candidateIndices(for: endpoint)
        let name: String
        let code: String?
        switch endpoint {
        case .name(let value):
            name = value
            code = nil
        case .stop(let stop):
            name = Stations.stopName(stop)
            code = Stations.stopStationCode(stop)
        }
        // A fixed code is the stable station identity across a rename. The
        // ordinary station index still checks the written name first so a
        // genuinely wrong name/code pair can fall back to its name pool. Keep
        // that safeguard, but when this written name is known inside the code
        // pool and its variants are all inactive on the ride date, use the
        // date-valid same-code predecessor/successor variants instead.
        if let code, !code.isEmpty, let rideDate,
           RouteGraph.isPlainISODay(rideDate), !name.isEmpty
        {
            let codePool = index.candidateIndices(
                for: .stop(.init(n02StationCode: code)))
            let normalizedName = Stations.normalizeStationName(name)
            let writtenNameKnown = codePool.contains { candidate in
                sameCodeUnits(
                    Stations.normalizeStationName(
                        Stations.stationName(index.features[candidate])),
                    normalizedName)
            }
            let hasValidResolvedCandidate = candidates.contains { candidate in
                let feature = index.features[candidate]
                return RouteGraph.RailValidity.isValid(
                    validFrom: Stations.stationValidFrom(feature),
                    validTo: Stations.stationValidTo(feature), on: rideDate)
            }
            if writtenNameKnown, !hasValidResolvedCandidate {
                let validCodeIdentity = codePool.filter { candidate in
                    let feature = index.features[candidate]
                    return RouteGraph.RailValidity.isValid(
                        validFrom: Stations.stationValidFrom(feature),
                        validTo: Stations.stationValidTo(feature), on: rideDate)
                }
                if !validCodeIdentity.isEmpty {
                    candidates = dedupeStationIndices(
                        candidates + validCodeIdentity, in: index)
                }
            }
        }
        // A dated old name can remain current at a different operator (梅田
        // on Osaka Metro after 阪急/阪神 renamed their terminals). If this
        // section explicitly pins the retired line/operator membership, that
        // namesake is not a substitute. Keep the full candidate pool whenever
        // the pinned membership is valid so shared physical stations retain
        // the existing cross-platform behavior. Fixed codes also retain their
        // existing stable-identity resolution.
        if (code ?? "").isEmpty, let rideDate,
           RouteGraph.isPlainISODay(rideDate)
        {
            let lines = Set(sectionLineNames.filter { !$0.isEmpty })
            let operators = Set(sectionOperatorNames.filter { !$0.isEmpty })
            if !lines.isEmpty, !operators.isEmpty {
                let explicitMemberships = index.exactNameCandidateIndices(for: name).filter {
                    let feature = index.features[$0]
                    return lines.contains(Stations.stationLineName(feature))
                        && operators.contains(Stations.stationOperator(feature))
                }
                if !explicitMemberships.isEmpty,
                   !explicitMemberships.contains(where: { candidate in
                       let feature = index.features[candidate]
                       return RouteGraph.RailValidity.isValid(
                           validFrom: Stations.stationValidFrom(feature),
                           validTo: Stations.stationValidTo(feature), on: rideDate)
                   })
                {
                    return []
                }
            }
        }
        guard !name.isEmpty, let code, !code.isEmpty, !candidates.isEmpty else {
            return candidates
        }

        let sameNameStop = Stations.Stop(name: name)
        let sameNameCandidates = index.candidateIndices(for: .stop(sameNameStop))
        let sameNamePreferred = filterStationsByPreferredInstitution(
            sameNameCandidates, in: index, allowedCodes: allowedCodes)
        let nearby = filterStationCandidatesNear(
            sameNamePreferred, referenceIndices: candidates, in: index)
        let sectionLines = Set(sectionLineNames)
        let additions = sectionLines.isEmpty ? nearby : nearby.filter {
            sectionLines.contains(Stations.stationLineName(index.features[$0]))
        }
        if !additions.isEmpty {
            return dedupeStationIndices(candidates + additions, in: index)
        }
        // A fixed code anchors the physical station even when its operator
        // does not match the preferred institution. Expanding nationwide here
        // can send a cross-company service to a distant same-name JR station
        // (for example 高田 in Niigata to 高田 in Nara).
        return candidates
    }

    /// Every graph-node candidate for one physical station record, scored by
    /// the exact station/line/operator/institution preference formula used by
    /// the browser solver.
    public static func stationCandidateGraphNodes(
        stationIndex: Int,
        stations: Stations.Index,
        graph: RouteGraph.Graph,
        hints: SegmentHints = SegmentHints(),
        allowedCodes: [String] = RouteGraph.defaultAllowedInstitutionTypeCodes,
        hardExcludedInstitutionTypeCodes: [String] = []
    ) -> [StationNodeCandidate] {
        stationCandidateGraphNodes(
            stationIndex: stationIndex, stations: stations, graph: graph,
            hints: hints, preferredCodes: Set(allowedCodes.filter { !$0.isEmpty }),
            excludedCodes: Set(hardExcludedInstitutionTypeCodes.filter { !$0.isEmpty }))
    }

    private static func stationCandidateGraphNodes(
        stationIndex: Int,
        stations: Stations.Index,
        graph: RouteGraph.Graph,
        hints: SegmentHints,
        preferredCodes: Set<String>,
        excludedCodes: Set<String>
    ) -> [StationNodeCandidate] {
        let feature = stations.features[stationIndex]
        let sourceCoordinates = stationGeometryCoordinates(feature)
        let stationLine = Stations.stationLineName(feature)
        let stationOperator = Stations.stationOperator(feature)
        var byKey: [String: (candidate: StationNodeCandidate, order: Int)] = [:]
        var nextOrder = 0

        for source in sourceCoordinates {
            for nearest in RouteGraph.nearbyNodes(source, in: graph, radiusDeg: 0.006, limit: 160) {
                guard nearest.distance <= stationSnapMaxDistanceMeters,
                      let meta = graph.nodeMeta[nearest.key] else { continue }
                if nodeIsExcludedInstitution(meta.institutionTypeCodes, excluded: excludedCodes) {
                    continue
                }
                let preferredInstitution = graphNodeHasPreferredInstitution(
                    meta, preferred: preferredCodes)
                if hints.requirePreferredInstitution && !preferredInstitution { continue }
                if !hints.requiredLines.isEmpty
                    && !RouteGraph.intersects(hints.requiredLines, meta.lineNames) { continue }
                if !hints.requiredOperators.isEmpty
                    && !RouteGraph.intersects(hints.requiredOperators, meta.operators) { continue }

                var score = nearest.distance
                if !stationLine.isEmpty && meta.lineNames.contains(stationLine) { score -= 40 }
                if !stationOperator.isEmpty && meta.operators.contains(stationOperator) { score -= 15 }
                if RouteGraph.intersects(hints.preferredLines, meta.lineNames) {
                    score -= 25
                } else if !hints.preferredLines.isEmpty {
                    score += nonPreferredLineStationSnapPenalty
                }
                if RouteGraph.intersects(hints.preferredOperators, meta.operators) {
                    score -= 10
                } else if !hints.preferredOperators.isEmpty {
                    score += nonPreferredOperatorStationSnapPenalty
                }
                if !preferredInstitution { score += nonPreferredStationSnapPenalty }

                let candidate = StationNodeCandidate(
                    key: nearest.key, distance: nearest.distance, score: score,
                    hasPreferredInstitution: preferredInstitution,
                    stationIndex: stationIndex)
                if let previous = byKey[nearest.key] {
                    if score < previous.candidate.score
                        || (score == previous.candidate.score
                            && nearest.distance < previous.candidate.distance)
                    {
                        byKey[nearest.key] = (candidate, previous.order)
                    }
                } else {
                    byKey[nearest.key] = (candidate, nextOrder)
                    nextOrder += 1
                }
            }
        }

        return byKey.values.sorted {
            if $0.candidate.score != $1.candidate.score {
                return $0.candidate.score < $1.candidate.score
            }
            if $0.candidate.distance != $1.candidate.distance {
                return $0.candidate.distance < $1.candidate.distance
            }
            return $0.order < $1.order
        }.prefix(16).map(\.candidate)
    }

    public static func collectStationCandidateGraphNodes(
        stationIndices: [Int],
        stations: Stations.Index,
        graph: RouteGraph.Graph,
        hints: SegmentHints,
        allowedCodes: [String],
        hardExcludedInstitutionTypeCodes: [String] = []
    ) -> [StationNodeCandidate] {
        let preferredCodes = Set(allowedCodes.filter { !$0.isEmpty })
        let excludedCodes = Set(hardExcludedInstitutionTypeCodes.filter { !$0.isEmpty })
        var byKey: [String: (candidate: StationNodeCandidate, order: Int)] = [:]
        var nextOrder = 0
        for stationIndex in stationIndices {
            for candidate in stationCandidateGraphNodes(
                stationIndex: stationIndex, stations: stations, graph: graph,
                hints: hints, preferredCodes: preferredCodes, excludedCodes: excludedCodes)
            {
                if let previous = byKey[candidate.key] {
                    if candidate.score < previous.candidate.score
                        || (candidate.score == previous.candidate.score
                            && candidate.distance < previous.candidate.distance)
                    {
                        byKey[candidate.key] = (candidate, previous.order)
                    }
                } else {
                    byKey[candidate.key] = (candidate, nextOrder)
                    nextOrder += 1
                }
            }
        }
        return byKey.values.sorted {
            if $0.candidate.score != $1.candidate.score {
                return $0.candidate.score < $1.candidate.score
            }
            if $0.candidate.distance != $1.candidate.distance {
                return $0.candidate.distance < $1.candidate.distance
            }
            return $0.order < $1.order
        }.map(\.candidate)
    }

    /// The top 12 snaps. A mini-shinkansen endpoint lives on conventional
    /// track, and the institution penalty can push that platform out of the
    /// twelve. When none of the twelve is on a preferred line, keep the four
    /// best preferred-line platforms as well.
    private static func cappedStationCandidates(
        _ candidates: [StationNodeCandidate], hints: SegmentHints, graph: RouteGraph.Graph
    ) -> [StationNodeCandidate] {
        let ranked = Array(candidates.prefix(12))
        guard !hints.preferredLines.isEmpty else { return ranked }
        func matches(_ candidate: StationNodeCandidate) -> Bool {
            RouteGraph.intersects(hints.preferredLines, graph.nodeMeta[candidate.key]?.lineNames ?? [])
        }
        guard !ranked.contains(where: matches) else { return ranked }
        return ranked + candidates.filter(matches).prefix(4)
    }

    /// Adds the short, penalised platform-transfer edges that join physical
    /// platforms belonging to one station group. These are graph edges, not
    /// drawable railway geometry, and the institution list on each connector
    /// is what prevents a hard-filtered JR route from hopping onto a nearby
    /// subway/private platform.
    public static func addStationTransferConnectorEdges(
        graph: RouteGraph.Graph, stations: [Stations.Feature],
        permitsNode: ((Stations.Feature, Coordinate) -> Bool)? = nil
    ) {
        struct PlatformMembership {
            let featureID: String
            let stationName: String
            let groupCode: String?
            let lineName: String
            let operatorName: String
            let institutionTypeCode: String
            let validFrom: String?
            let validTo: String?
        }
        /// Graph snap bookkeeping around one platform membership. Closer snaps
        /// replace the list; equal distance keeps a distinct validity.
        struct Info {
            var key: String
            var distance: Double
            var order: Int
            var membership: PlatformMembership
        }
        struct GroupKey: Hashable { var units: [UInt16] }

        func featureID(_ feature: Stations.Feature) -> String {
            for key in ["id", "history_id"] {
                if case .string(let text)? = feature.properties[key], !text.isEmpty {
                    return text
                }
            }
            if let code = Stations.stationCode(feature), !code.isEmpty { return code }
            return ""
        }
        var groups: [GroupKey: [String: [Info]]] = [:]
        var groupOrder: [GroupKey] = []

        func key(for feature: Stations.Feature) -> GroupKey {
            if let code = Stations.stationGroupCode(feature), !code.isEmpty {
                return GroupKey(units: Array("group:\(code)".utf16))
            }
            let display = coordinate(Stations.displayCoordinate(feature))
                ?? Coordinate(lon: 0, lat: 0)
            let lon = JSNumber.round(display.lon * 10) / 10
            let lat = JSNumber.round(display.lat * 10) / 10
            let text = "name:\(Stations.stationName(feature) ?? "")@"
                + "\(JSNumber.string(lon)),\(JSNumber.string(lat))"
            return GroupKey(units: Array(text.utf16))
        }

        for feature in stations {
            if Task.isCancelled { return }
            let groupKey = key(for: feature)
            if groups[groupKey] == nil {
                groups[groupKey] = [:]
                groupOrder.append(groupKey)
            }
            let sources = stationGeometryCoordinates(feature)
            for source in sources {
                for nearest in RouteGraph.nearbyNodes(
                    source, in: graph, radiusDeg: 0.0035, limit: 30)
                where nearest.distance <= 520 {
                    if let permitsNode, let point = graph.nodes[nearest.key],
                       !permitsNode(feature, point) { continue }
                    let nextOrder = groups[groupKey]!.count
                    let info = Info(
                        key: nearest.key, distance: nearest.distance, order: nextOrder,
                        membership: PlatformMembership(
                            featureID: featureID(feature),
                            stationName: Stations.stationName(feature) ?? "",
                            groupCode: Stations.stationGroupCode(feature),
                            lineName: Stations.stationLineName(feature),
                            operatorName: Stations.stationOperator(feature),
                            institutionTypeCode: Stations.stationInstitutionTypeCode(feature),
                            validFrom: Stations.stationValidFrom(feature),
                            validTo: Stations.stationValidTo(feature)))
                    if let existing = groups[groupKey]![nearest.key], let closest = existing.first {
                        var kept = info
                        kept.order = closest.order
                        if nearest.distance < closest.distance {
                            groups[groupKey]![nearest.key] = [kept]
                        } else if nearest.distance == closest.distance,
                                  !existing.contains(where: {
                                      $0.membership.validFrom == info.membership.validFrom
                                          && $0.membership.validTo == info.membership.validTo
                                  }) {
                            // Co-located station records may represent different eras.
                            // Keep each membership instead of letting input order decide
                            // whether this platform is current or retired.
                            groups[groupKey]![nearest.key]!.append(kept)
                        }
                    } else {
                        groups[groupKey]![nearest.key] = [info]
                    }
                }
            }
        }

        struct ConnectorKey: Hashable {
            let pair: String
            let validFrom: String?
            let validTo: String?
        }
        var edgeKeys = Set<ConnectorKey>()
        var railReachability: [String: Set<String>] = [:]
        func alreadyJoined(_ a: Info, _ b: Info, coordinate: Coordinate) -> Bool {
            guard !a.membership.lineName.isEmpty,
                  a.membership.lineName == b.membership.lineName,
                  a.membership.operatorName == b.membership.operatorName,
                  a.membership.validFrom == nil, a.membership.validTo == nil,
                  b.membership.validFrom == nil, b.membership.validTo == nil else { return false }
            let cacheKey = a.key + "|" + a.membership.lineName + "|" + a.membership.operatorName
            if let reachable = railReachability[cacheKey] { return reachable.contains(b.key) }
            var reachable: Set<String> = [a.key]
            var pending = [a.key]
            while let node = pending.popLast() {
                for edge in graph.adjacency[node] ?? [] {
                    guard edge.connector == nil, edge.validFrom == nil, edge.validTo == nil,
                          edge.lineName == a.membership.lineName,
                          edge.operator == a.membership.operatorName,
                          let point = graph.nodes[edge.to],
                          Geometry.distanceMeters(coordinate, point) <= 900,
                          reachable.insert(edge.to).inserted else { continue }
                    pending.append(edge.to)
                }
            }
            railReachability[cacheKey] = reachable
            return reachable.contains(b.key)
        }
        for groupKey in groupOrder {
            if Task.isCancelled { return }
            // This reachability is local to one station; retaining every
            // platform's neighborhood would grow with the whole country.
            railReachability.removeAll(keepingCapacity: true)
            let nodes = (groups[groupKey]?.values ?? Dictionary<String, [Info]>().values)
                .sorted {
                    let a = $0[0], b = $1[0]
                    return a.distance == b.distance ? a.order < b.order : a.distance < b.distance
                }.prefix(24)
            guard nodes.count >= 2 else { continue }
            let values = Array(nodes)
            for i in 0..<(values.count - 1) {
                for j in (i + 1)..<values.count {
                    for a in values[i] {
                        for b in values[j] {
                            if a.key == b.key { continue }
                            let pairKey = jsSorted([a.key, b.key]).joined(separator: "|")
                            guard let aCoordinate = graph.nodes[a.key],
                                  let bCoordinate = graph.nodes[b.key] else { continue }
                            let gap = Geometry.distanceMeters(aCoordinate, bCoordinate)
                            if gap > 900 { continue }
                            // Preserve the surveyed junction path when these
                            // same-line nodes already meet in the station area.
                            if alreadyJoined(a, b, coordinate: aCoordinate) { continue }
                            var codes: [String] = []
                            for code in [a.membership.institutionTypeCode, b.membership.institutionTypeCode]
                            where !code.isEmpty && !codes.contains(code) { codes.append(code) }
                            let connector = RouteGraph.StationConnector(
                                institutionTypeCodes: codes,
                                stationName: a.membership.stationName,
                                groupCode: a.membership.groupCode ?? "")
                            // ADR 0011: a transfer is valid only while both ends'
                            // stations are, so the edge carries the intersection.
                            // lineName and operatorName stay on the membership;
                            // the connector edge does not copy them yet.
                            let validFrom = [a.membership.validFrom, b.membership.validFrom].compactMap { $0 }.max()
                            let validTo = [a.membership.validTo, b.membership.validTo].compactMap { $0 }.min()
                            if let validFrom, let validTo, validFrom >= validTo { continue }
                            let edgeKey = ConnectorKey(
                                pair: pairKey, validFrom: validFrom, validTo: validTo)
                            guard edgeKeys.insert(edgeKey).inserted else { continue }
                            let edge = RouteGraph.Edge(
                                to: b.key, length: max(gap + 180, 0.01),
                                institutionTypeCode: "", railwayClassCode: "",
                                lineName: "", operator: "", connector: connector,
                                validFrom: validFrom, validTo: validTo)
                            graph.adjacency[a.key, default: []].append(edge)
                            var reverse = edge
                            reverse.to = a.key
                            graph.adjacency[b.key, default: []].append(reverse)
                        }
                    }
                }
            }
        }
    }

    public static func inferSectionRouteConstraints(
        section: RouteSection, train: TrainContext
    ) -> (lineNames: Set<String>, operatorNames: Set<String>) {
        let text = [
            train.id, train.number, train.trainType, train.company,
            train.origin, train.destination,
        ].map(normalizeRouteHintText).joined(separator: " ")
        var lines = Set<String>()
        var operators = Set<String>()

        // JR Kyushu Sonic: N02 often gives 大分 as 久大線 and 小倉 as 鹿児島線,
        // while the actual limited express runs on 日豊線 between 大分/別府/中津/小倉.
        // West of 小倉 the train runs on 鹿児島線, so only require 日豊線 when BOTH
        // endpoints are on the 日豊線 corridor east of 小倉 (e.g. 黒崎→小倉 must not
        // be forced onto 日豊線).
        if (text.contains("ソニック") || asciiCaseInsensitiveContains(text, "sonic"))
            && sectionHasAnyEndpoint(section, names: Self.sonicNippoCorridorStations)
            && sectionEndpointNames(section).allSatisfy({
                Self.sonicNippoCorridorStations.contains($0)
            })
        {
            lines.insert("日豊線")
            operators.insert("九州旅客鉄道")
        }
        // Haruka keeps its JR West operator preference, but no longer pins a
        // line per section: required lines skip every fallback attempt, so a
        // leg continuing from the previous leg's track (関西空港線 at 日根野,
        // the うめきた platform at 大阪) could not reach the pinned row.
        // Physical junctions now decide which rows a train can cross.
        if text.contains("はるか") || asciiCaseInsensitiveContains(text, "haruka") {
            operators.insert("西日本旅客鉄道")
        }
        return (lines, operators)
    }

    public static func buildSegmentRouteHints(
        section: RouteSection,
        fromStationIndices: [Int],
        toStationIndices: [Int],
        stations: Stations.Index,
        train: TrainContext,
        country: String
    ) -> SegmentHints {
        let cacheTrain = RouteGraph.CacheKeyTrain(
            trainType: train.trainType,
            company: train.company,
            preferredLineNames: train.preferredLineNames,
            preferredOperatorNames: train.preferredOperatorNames,
            allowedInstitutionTypeCodes: train.allowedInstitutionTypeCodes,
            institutionFilterMode: train.institutionFilterMode)
        let allowedCodes = RouteGraph.allowedInstitutionTypeCodes(cacheTrain, country: country)
        var preferredLines = Set(train.preferredLineNames.filter { !$0.isEmpty })
        var preferredOperators = Set(train.preferredOperatorNames.filter { !$0.isEmpty })
        preferredOperators.formUnion(RouteGraph.derivedPreferredOperatorNames(
            company: train.company, country: country))

        let inferred = inferSectionRouteConstraints(section: section, train: train)
        var explicitLines = Set((section.lineNames ?? []).filter { !$0.isEmpty })
        explicitLines.formUnion(inferred.lineNames)
        var explicitOperators = Set((section.operatorNames ?? []).filter { !$0.isEmpty })
        explicitOperators.formUnion(inferred.operatorNames)
        preferredLines.formUnion(explicitLines)
        preferredOperators.formUnion(explicitOperators)
        // A service's preferred lines stay preferred. A same-name platform on
        // another line (神戸線 beside 宝塚線) must not join that set, or the
        // soft penalty never distinguishes them. With no service list, the
        // common endpoint lines are still the preference.

        let fromPreferred = preferredStationPool(
            fromStationIndices, stations: stations, allowedCodes: allowedCodes)
        let toPreferred = preferredStationPool(
            toStationIndices, stations: stations, allowedCodes: allowedCodes)
        let fromLines = stationSet(fromStationIndices, stations: stations, getter: Stations.stationLineName)
        let toLines = stationSet(toStationIndices, stations: stations, getter: Stations.stationLineName)
        let fromOperators = stationSet(fromStationIndices, stations: stations, getter: Stations.stationOperator)
        let toOperators = stationSet(toStationIndices, stations: stations, getter: Stations.stationOperator)
        let fromPreferredLines = stationSet(fromPreferred, stations: stations, getter: Stations.stationLineName)
        let toPreferredLines = stationSet(toPreferred, stations: stations, getter: Stations.stationLineName)
        let fromPreferredOperators = stationSet(fromPreferred, stations: stations, getter: Stations.stationOperator)
        let toPreferredOperators = stationSet(toPreferred, stations: stations, getter: Stations.stationOperator)

        let allCommonLines = fromLines.intersection(toLines)
        let allCommonOperators = fromOperators.intersection(toOperators)
        let preferredCommonLines = fromPreferredLines.intersection(toPreferredLines)
        let preferredCommonOperators = fromPreferredOperators.intersection(toPreferredOperators)
        let commonLines = preferredCommonLines.isEmpty ? allCommonLines : preferredCommonLines
        let commonOperators = preferredCommonOperators.isEmpty
            ? allCommonOperators : preferredCommonOperators
        let serviceLines = Set(train.preferredLineNames.filter { !$0.isEmpty })
        if serviceLines.isEmpty {
            preferredLines.formUnion(commonLines)
        } else {
            let foldedService = Set(serviceLines.map(displayRowGraphLineName))
            for line in commonLines where foldedService.contains(displayRowGraphLineName(line)) {
                preferredLines.insert(line)
            }
        }
        preferredOperators.formUnion(commonOperators)
        if preferredLines.isEmpty {
            // A section spanning two lines must not penalize its destination
            // line simply because the origin was considered first. Infer
            // both unambiguous endpoint memberships before routing so the
            // same physical corridor is preferred in either direction.
            if fromPreferredLines.count == 1 {
                preferredLines.formUnion(fromPreferredLines)
            }
            if toPreferredLines.count == 1 {
                preferredLines.formUnion(toPreferredLines)
            }
        }
        if preferredOperators.isEmpty,
           fromPreferredOperators.count == 1, toPreferredOperators.count == 1,
           fromPreferredOperators.first == toPreferredOperators.first,
           let common = fromPreferredOperators.first
        {
            preferredOperators.insert(common)
        }

        return SegmentHints(
            preferredLines: preferredLines,
            preferredOperators: preferredOperators,
            requiredLines: explicitLines,
            requiredOperators: explicitOperators,
            explicitRequiredLines: explicitLines,
            explicitRequiredOperators: explicitOperators,
            commonLines: commonLines,
            commonOperators: commonOperators,
            allCommonLines: allCommonLines,
            allCommonOperators: allCommonOperators,
            preferredInstitutionCommonLines: preferredCommonLines,
            preferredInstitutionCommonOperators: preferredCommonOperators,
            fromLines: fromLines, toLines: toLines,
            fromOperators: fromOperators, toOperators: toOperators,
            fromPreferredLines: fromPreferredLines, toPreferredLines: toPreferredLines,
            fromPreferredOperators: fromPreferredOperators,
            toPreferredOperators: toPreferredOperators)
    }

    public static func buildSegmentRouteSolveAttempts(
        _ base: SegmentHints
    ) -> [SegmentHints] {
        var attempts: [SegmentHints] = []
        var keys = Set<String>()

        func push(
            lines: Set<String>? = nil, operators: Set<String>? = nil,
            preferredLines: Set<String>? = nil,
            preferredOperators: Set<String>? = nil,
            home: Bool, mode: String
        ) {
            var attempt = base
            if let lines { attempt.requiredLines = lines }
            if let operators { attempt.requiredOperators = operators }
            if let preferredLines { attempt.preferredLines = preferredLines }
            if let preferredOperators { attempt.preferredOperators = preferredOperators }
            attempt.requirePreferredInstitution = home
            attempt.solveMode = mode
            let key = [
                mode, home ? "home" : "soft",
                jsSorted(attempt.requiredLines).joined(separator: ","),
                jsSorted(attempt.requiredOperators).joined(separator: ","),
            ].joined(separator: "|")
            if keys.insert(key).inserted { attempts.append(attempt) }
        }

        let explicitLines = base.explicitRequiredLines
        let explicitOperators = base.explicitRequiredOperators
        if !explicitLines.isEmpty {
            push(lines: explicitLines, operators: explicitOperators, home: true,
                 mode: "explicit_section_route_required_home_institution")
            push(lines: explicitLines, operators: explicitOperators, home: false,
                 mode: "explicit_section_route_required_soft_institution")
            return attempts
        }
        if !explicitOperators.isEmpty {
            if !base.commonLines.isEmpty {
                push(lines: base.commonLines, operators: explicitOperators, home: true,
                     mode: "operator_pinned_common_line_required_home_institution")
                push(lines: base.commonLines, operators: explicitOperators, home: false,
                     mode: "operator_pinned_common_line_required_soft_institution")
            }
            push(lines: [], operators: explicitOperators, home: true,
                 mode: "explicit_operator_required_home_institution")
            push(lines: [], operators: explicitOperators, home: false,
                 mode: "explicit_operator_required_soft_institution")
            return attempts
        }
        if !base.commonLines.isEmpty, !base.commonOperators.isEmpty {
            push(lines: base.commonLines, operators: base.commonOperators, home: true,
                 mode: "common_line_and_operator_required_home_institution")
        }
        if !base.commonLines.isEmpty {
            push(lines: base.commonLines, operators: [], home: true,
                 mode: "common_line_required_home_institution")
        }
        if !base.commonOperators.isEmpty {
            push(lines: [], operators: base.commonOperators, home: true,
                 mode: "common_operator_required_home_institution")
        }
        push(home: true, mode: "home_institution_soft_line_operator_hints")
        if !base.commonLines.isEmpty {
            push(lines: base.commonLines, operators: [], home: false,
                 mode: "common_line_required_other_operator_fallback")
        }
        push(home: false, mode: (base.commonLines.isEmpty && base.commonOperators.isEmpty)
             ? "no_common_line_soft_fallback" : "soft_fallback_after_home_attempts")
        push(lines: [], operators: [], preferredLines: [], preferredOperators: [], home: true,
             mode: "institution_only_unbiased_fallback")
        return attempts
    }

    public struct SolvedSection: Sendable, Equatable {
        public var segmentIndex: Int
        /// The section endpoint's fixed station identity when its dated record
        /// is available. Route solving may internally snap through a nearby
        /// same-name platform on the actual line, but that implementation
        /// detail must not replace the station code stored by the journey.
        public var fromStationIndex: Int
        public var toStationIndex: Int
        public var coordinates: [Coordinate]
        public var rawPathKeys: [String]
        public var hints: SegmentHints
        public var allowedInstitutionTypeCodes: [String]
        public var usedInstitutionTypeCodes: [String]
        public var snapFrom: Double
        public var snapTo: Double
        public var physicalLength: Double
        public var rawPhysicalLength: Double
        public var cost: Double
        /// Which entry of `buildSegmentRouteSolveAttempts()` produced this
        /// path — mirrors JS `solve_attempt_index`. `solveSectionOnDemand`
        /// only trusts an early regional result when this is 0 (the
        /// strictest attempt); see its comment.
        public var attemptIndex: Int
        public var historyIDs: [String] = []
        public var validFrom: String? = nil
        public var validTo: String? = nil
        public var temporalKind: RouteGraph.TemporalKind = .current
    }

    /// The only cross-identity continuation admitted before a section's own
    /// line hints: reviewed, service-valid physical junctions. That is a
    /// zero-length junction at an identical vertex, a reviewed short link of
    /// at most 30 m, or an `osmConnector` whose reviewed OpenStreetMap path
    /// has stubs of at most 50 m. The connector's whole chain is one hop, and
    /// its length is not an approach bound. A coordinate match or a passenger
    /// connector cannot establish this path.
    public static func physicalContinuationPath(
        from key: String, to target: String, graph: RouteGraph.Graph,
        rideDate: String?
    ) -> [String]? {
        guard graph.nodes[key] != nil, graph.nodes[target] != nil else { return nil }
        if key == target { return [key] }
        var previous: [String: String] = [:]
        var osmHops: [String: [String]] = [:]
        var visited: Set<String> = [key]
        var pending = [key]
        var offset = 0
        while offset < pending.count {
            guard !Task.isCancelled else { return nil }
            let current = pending[offset]
            offset += 1
            if current == target {
                var hops = [target]
                while let parent = previous[hops.last!] { hops.append(parent) }
                hops.reverse()
                var expanded = [hops[0]]
                for index in hops.indices.dropFirst() {
                    let node = hops[index]
                    if let via = osmHops[node], via.first == hops[index - 1], via.last == node {
                        expanded.append(contentsOf: via.dropFirst())
                    } else {
                        expanded.append(node)
                    }
                }
                return expanded
            }
            for edge in graph.adjacency[current] ?? [] {
                guard edge.connector == nil,
                      let boundary = edge.physicalJunction?.junction,
                      !boundary.evidence.isEmpty,
                      junctionGeometryIsValid(boundary, edge: edge, current: current, graph: graph),
                      RouteGraph.RailValidity.isValid(
                        validFrom: edge.validFrom, validTo: edge.validTo, on: rideDate) else { continue }
                if boundary.kind == .osmConnector {
                    guard let hop = osmConnectorHop(
                        from: current, junction: boundary, graph: graph, rideDate: rideDate),
                          visited.insert(hop.destination).inserted else { continue }
                    previous[hop.destination] = current
                    osmHops[hop.destination] = hop.keys
                    pending.append(hop.destination)
                    continue
                }
                guard visited.insert(edge.to).inserted else { continue }
                if boundary.kind == .osmTrack, boundary.endJunction != nil {
                    previous[edge.to] = current
                    pending.append(edge.to)
                    continue
                }
                let from = RouteGraph.physicalNodeKey(boundary.from.coordinate, identity: boundary.from.identity)
                let to = RouteGraph.physicalNodeKey(boundary.to.coordinate, identity: boundary.to.identity)
                guard (current == from && edge.to == to) || (current == to && edge.to == from) else { continue }
                previous[edge.to] = current
                pending.append(edge.to)
            }
        }
        return nil
    }

    /// Zero-length junctions need identical vertices and length 0; a reviewed
    /// short link needs distinct vertices within the 30 m bound and its real
    /// length. An OSM connector is the whole reviewed chain, not one stub.
    /// The link length counts toward no approach bound.
    private static func junctionGeometryIsValid(
        _ junction: RouteGraph.PhysicalJunction, edge: RouteGraph.Edge,
        current: String, graph: RouteGraph.Graph
    ) -> Bool {
        guard let a = graph.nodes[current], let b = graph.nodes[edge.to] else { return false }
        switch junction.kind {
        case .zeroLength:
            return edge.length == 0 && junction.from.coordinate == junction.to.coordinate && a == b
        case .shortLink:
            return a != b && edge.length > 0
                && Geometry.distanceMeters(a, b) <= RouteGraph.PhysicalJunction.maximumReviewedLinkMeters
        case .osmConnector:
            guard edge.length > 0, a != b,
                  let from = graph.nodes[RouteGraph.physicalNodeKey(
                    junction.from.coordinate, identity: junction.from.identity)],
                  let to = graph.nodes[RouteGraph.physicalNodeKey(
                    junction.to.coordinate, identity: junction.to.identity)] else { return false }
            return junction.osmRejection(fromCoordinate: from, toCoordinate: to) == nil
        case .osmTrack:
            guard let endJunction = junction.endJunction, edge.length > 0, a != b,
                  Geometry.distanceMeters(a, b) <= RouteGraph.PhysicalJunction.maximumOSMAttachMeters
            else { return false }
            let foreign = RouteGraph.physicalNodeKey(
                endJunction.coordinate, identity: endJunction.identity)
            return current == foreign || edge.to == foreign
        }
    }

    /// The far endpoint of an `osmConnector`, with every stub and path vertex
    /// between. One call is one junction hop; the metres are not an approach.
    private static func osmConnectorHop(
        from current: String, junction: RouteGraph.PhysicalJunction,
        graph: RouteGraph.Graph, rideDate: String?
    ) -> (destination: String, keys: [String])? {
        guard junction.kind == .osmConnector, let keys = junction.chainNodeKeys() else { return nil }
        let ordered: [String]
        if current == keys[0] {
            ordered = keys
        } else if current == keys[keys.count - 1] {
            ordered = Array(keys.reversed())
        } else {
            return nil
        }
        for (start, end) in zip(ordered, ordered.dropFirst()) {
            guard graph.adjacency[start]?.contains(where: { candidate in
                candidate.to == end && candidate.connector == nil
                    && candidate.physicalJunction?.junction.id == junction.id
                    && RouteGraph.RailValidity.isValid(
                        validFrom: candidate.validFrom, validTo: candidate.validTo, on: rideDate)
            }) == true else { return nil }
        }
        guard let destination = ordered.last, destination != current else { return nil }
        return (destination, ordered)
    }

    /// Remove short station-marker bridges only at the ends of a source line.
    /// Interior vertices remain subject to exact surveyed-edge verification.
    /// An anchor within 1 m of the identity's edge may stand up to twice the
    /// off-edge cap away; the shorter cap stays for anchors off the edge.
    public static func trimmedToGraphNodes(
        line: [Coordinate], graph: RouteGraph.Graph,
        maxTrimMeters: Double = RouteNetwork.endpointSnapMeters,
        requiredLines: Set<String> = [],
        requiredOperators: Set<String> = [],
        rideDate: String? = nil
    ) -> [Coordinate]? {
        func isNode(_ coordinate: Coordinate) -> Bool {
            let normalized = Grid.normalizeGraphCoord(coordinate)
            return !RouteGraph.exactNodeKeys(normalized, in: graph).isEmpty
        }
        guard let first = line.firstIndex(where: isNode),
              let last = line.lastIndex(where: isNode), first < last else { return nil }
        let leading = zip(line[...first], line[...first].dropFirst())
            .reduce(0.0) { $0 + Geometry.distanceMeters($1.0, $1.1) }
        let trailing = zip(line[last...], line[last...].dropFirst())
            .reduce(0.0) { $0 + Geometry.distanceMeters($1.0, $1.1) }
        let onEdgeCap = 2 * RouteNetwork.endpointSnapMeters
        func allowed(_ distance: Double, anchor: Coordinate, node: Coordinate) -> Bool {
            if distance <= maxTrimMeters { return true }
            guard distance <= onEdgeCap else { return false }
            return anchorLiesOnIdentityEdge(
                anchor, terminal: node, graph: graph, maxMeters: onEdgeCap,
                requiredLines: requiredLines, requiredOperators: requiredOperators,
                rideDate: rideDate)
        }
        guard allowed(leading, anchor: line[0], node: line[first]),
              allowed(trailing, anchor: line[line.count - 1], node: line[last]) else { return nil }
        return Array(line[first...last])
    }

    private static func physicalIdentity(_ key: String) -> Substring {
        guard let separator = key.lastIndex(of: "@") else { return key[...] }
        return key[..<separator]
    }

    /// Local easting/northing projection. `t` is unclamped; `length` is the
    /// segment. A zero-length segment returns nil.
    private static func segmentProjection(
        _ point: Coordinate, from a: Coordinate, to b: Coordinate
    ) -> (t: Double, distance: Double, length: Double)? {
        let metersPerDegree = 6_371_000.0 * .pi / 180
        let sx = metersPerDegree * cos((a.lat + b.lat) / 2 * .pi / 180)
        let dx = (b.lon - a.lon) * sx
        let dy = (b.lat - a.lat) * metersPerDegree
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return nil }
        let px = (point.lon - a.lon) * sx
        let py = (point.lat - a.lat) * metersPerDegree
        let t = (px * dx + py * dy) / lengthSquared
        return (t, hypot(px - t * dx, py - t * dy), sqrt(lengthSquared))
    }

    /// True when `anchor` lies within 1 m of a same-identity, date-valid rail
    /// edge reachable from `terminal` without a connector or junction.
    private static func anchorLiesOnIdentityEdge(
        _ anchor: Coordinate, terminal: Coordinate, graph: RouteGraph.Graph,
        maxMeters: Double, requiredLines: Set<String>, requiredOperators: Set<String>,
        rideDate: String?
    ) -> Bool {
        let hints = SegmentHints(requiredLines: requiredLines, requiredOperators: requiredOperators)
        let origins = RouteGraph.exactNodeKeys(Grid.normalizeGraphCoord(terminal), in: graph)
        for start in origins {
            let requiredIdentity = physicalIdentity(start)
            var queue: [(key: String, length: Double)] = [(start, 0)]
            var best = [start: 0.0]
            var index = 0
            while index < queue.count {
                let current = queue[index]
                index += 1
                guard let origin = graph.nodes[current.key] else { continue }
                for edge in graph.adjacency[current.key] ?? [] {
                    guard edge.connector == nil, edge.physicalJunction == nil,
                          let destination = graph.nodes[edge.to],
                          physicalIdentity(edge.to) == requiredIdentity,
                          edgeMatchesRequiredHints(edge, hints: hints),
                          RouteGraph.RailValidity.isValid(
                            validFrom: edge.validFrom, validTo: edge.validTo, on: rideDate)
                    else { continue }
                    if let projection = segmentProjection(anchor, from: origin, to: destination),
                       projection.t >= 0, projection.t <= 1, projection.distance <= 1.0
                    {
                        return true
                    }
                    let total = current.length + edge.length
                    guard total <= maxMeters, total < best[edge.to, default: .infinity] else { continue }
                    best[edge.to] = total
                    queue.append((edge.to, total))
                }
            }
        }
        return false
    }

    /// One same-identity walk of at most `maxMeters` whose polyline passes
    /// within 1 m of every pending point in order. Nil when no walk or more
    /// than one walk qualifies. Connectors and junctions stay closed.
    private static func onEdgeIdentityPath(
        from start: String, targetKeys: Set<String>, pendingPoints: [Coordinate],
        graph: RouteGraph.Graph, rideDate: String?, hints: SegmentHints,
        maxMeters: Double
    ) -> [String]? {
        guard graph.nodes[start] != nil, !pendingPoints.isEmpty else { return nil }
        let requiredIdentity = physicalIdentity(start)
        let targets = Set(targetKeys.filter {
            $0 != start && graph.nodes[$0] != nil && physicalIdentity($0) == requiredIdentity
        })
        guard !targets.isEmpty else { return nil }
        struct Item { var key: String; var length: Double; var path: [String] }
        var queue = [Item(key: start, length: 0, path: [start])]
        var matches: [[String]] = []
        var index = 0
        while index < queue.count && index < 64 {
            if Task.isCancelled { return nil }
            let current = queue[index]
            index += 1
            if targets.contains(current.key) {
                let coordinates = current.path.compactMap { graph.nodes[$0] }
                if coordinates.count == current.path.count,
                   pendingPointsFollowPolyline(pendingPoints, vertices: coordinates)
                {
                    matches.append(current.path)
                    if matches.count > 1 { return nil }
                }
                continue
            }
            for edge in graph.adjacency[current.key] ?? [] {
                let total = current.length + edge.length
                guard edge.connector == nil, edge.physicalJunction == nil,
                      graph.nodes[edge.to] != nil,
                      physicalIdentity(edge.to) == requiredIdentity,
                      total <= maxMeters,
                      !current.path.contains(edge.to),
                      edgeMatchesRequiredHints(edge, hints: hints),
                      RouteGraph.RailValidity.isValid(
                        validFrom: edge.validFrom, validTo: edge.validTo, on: rideDate)
                else { continue }
                queue.append(Item(key: edge.to, length: total, path: current.path + [edge.to]))
            }
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private static func pendingPointsFollowPolyline(
        _ pending: [Coordinate], vertices: [Coordinate]
    ) -> Bool {
        guard !pending.isEmpty, vertices.count >= 2 else { return pending.isEmpty }
        var previousArc = 0.0
        var placed = false
        for point in pending {
            var traversed = 0.0
            var match: Double?
            for index in 0..<(vertices.count - 1) {
                let start = vertices[index]
                let end = vertices[index + 1]
                guard let projection = segmentProjection(point, from: start, to: end) else { continue }
                if projection.t >= 0, projection.t <= 1, projection.distance <= 1.0 {
                    let arc = traversed + projection.t * projection.length
                    if (!placed || arc + 0.000_001 >= previousArc), match == nil || arc < match! {
                        match = arc
                    }
                }
                traversed += projection.length
            }
            guard let match else { return false }
            previousArc = match
            placed = true
        }
        return true
    }

    /// Prove a bounded span of surveyed rail within one physical identity.
    public static func sameIdentitySpan(
        from previousKey: String, to firstKey: String, graph: RouteGraph.Graph,
        date: String?, maxMeters: Double = 2 * RouteNetwork.endpointSnapMeters
    ) -> Bool {
        sameIdentitySpanPath(from: previousKey, to: firstKey, graph: graph,
            date: date, maxMeters: maxMeters) != nil
    }

    private static func sameIdentitySpanPath(
        from previousKey: String, to firstKey: String, graph: RouteGraph.Graph,
        date: String?, maxMeters: Double
    ) -> [String]? {
        func identity(_ key: String) -> Substring {
            guard let separator = key.lastIndex(of: "@") else { return key[...] }
            return key[..<separator]
        }
        let requiredIdentity = identity(previousKey)
        guard graph.nodes[previousKey] != nil, graph.nodes[firstKey] != nil,
              requiredIdentity == identity(firstKey) else { return nil }
        var pending: [(key: String, length: Double, path: [String])] = [(previousKey, 0, [previousKey])]
        var best = [previousKey: 0.0]
        var index = 0
        while index < pending.count {
            guard !Task.isCancelled else { return nil }
            let current = pending[index]
            index += 1
            if current.key == firstKey { return current.path }
            for edge in graph.adjacency[current.key] ?? [] {
                let total = current.length + edge.length
                guard edge.connector == nil, edge.physicalJunction == nil,
                      graph.nodes[edge.to] != nil, identity(edge.to) == requiredIdentity,
                      total <= maxMeters,
                      RouteGraph.RailValidity.isValid(validFrom: edge.validFrom, validTo: edge.validTo, on: date),
                      total < best[edge.to, default: .infinity] else { continue }
                best[edge.to] = total
                pending.append((edge.to, total, current.path + [edge.to]))
            }
        }
        return nil
    }

    /// Station snaps can lie away from a reviewed branching vertex. Bound each
    /// surveyed approach (including the span between two junctions) to 1.5 km.
    public static let physicalJunctionMaxApproachMeters: Double = 1_500

    public static func physicalBoundaryIsProven(
        from previous: String, to first: String, graph: RouteGraph.Graph, rideDate: String?
    ) -> Bool {
        if previous == first
            || sameIdentitySpan(from: previous, to: first, graph: graph, date: rideDate) { return true }
        guard graph.nodes[previous] != nil, graph.nodes[first] != nil else { return false }
        func identity(_ key: String) -> Substring {
            guard let separator = key.lastIndex(of: "@") else { return key[...] }
            return key[..<separator]
        }
        // Each layer is a multi-source bounded Dijkstra after exactly N reviewed
        // junctions. Reset distance only across a junction, never along rail.
        var sources: Set<String> = [previous]
        for hops in 0...2 {
            var pending = sources.map { (key: $0, length: 0.0) }
            var best = Dictionary(uniqueKeysWithValues: sources.map { ($0, 0.0) })
            var nextSources = Set<String>()
            while let index = pending.indices.min(by: { pending[$0].length < pending[$1].length }) {
                guard !Task.isCancelled else { return false }
                let current = pending.remove(at: index)
                guard current.length == best[current.key] else { continue }
                if hops > 0, current.key == first { return true }
                for edge in graph.adjacency[current.key] ?? [] {
                    guard edge.connector == nil, graph.nodes[edge.to] != nil,
                          RouteGraph.RailValidity.isValid(
                            validFrom: edge.validFrom, validTo: edge.validTo, on: rideDate) else { continue }
                    if let junction = edge.physicalJunction?.junction {
                        guard hops < 2, !junction.evidence.isEmpty,
                              junctionGeometryIsValid(junction, edge: edge, current: current.key, graph: graph),
                              RouteGraph.RailValidity.isValid(validFrom: junction.validFrom,
                                validTo: junction.validTo, on: rideDate) else { continue }
                        if junction.kind == .osmConnector {
                            guard let hop = osmConnectorHop(
                                from: current.key, junction: junction, graph: graph, rideDate: rideDate)
                            else { continue }
                            nextSources.insert(hop.destination)
                            continue
                        }
                        if junction.kind == .osmTrack, junction.endJunction != nil {
                            nextSources.insert(edge.to)
                            continue
                        }
                        let from = RouteGraph.physicalNodeKey(junction.from.coordinate, identity: junction.from.identity)
                        let to = RouteGraph.physicalNodeKey(junction.to.coordinate, identity: junction.to.identity)
                        guard (current.key == from && edge.to == to)
                            || (current.key == to && edge.to == from) else { continue }
                        nextSources.insert(edge.to)
                    } else {
                        let length = current.length + edge.length
                        guard identity(current.key) == identity(edge.to),
                              length <= physicalJunctionMaxApproachMeters,
                              length < best[edge.to, default: .infinity] else { continue }
                        best[edge.to] = length
                        pending.append((edge.to, length))
                    }
                }
            }
            sources = nextSources
            if sources.isEmpty { break }
        }
        return false
    }

    /// When the certified ends of two sections fail ``physicalBoundaryIsProven``,
    /// try the stop's other surveyed nodes. Candidate keys on a side are the
    /// nodes snapped from any station feature in the stop's N02 group, within
    /// ``stationSnapMaxDistanceMeters``, plus endpoints of date-valid reviewed
    /// junctions whose `station` / `stationCode` is that stop and whose identity
    /// is the certified end's line. The first pair that is the same key, a
    /// same-identity span of at most 520 m, or ``physicalBoundaryIsProven``
    /// replaces the continuity keys. The certified strokes stay.
    ///
    /// Returns nil without searching when the sections do not share an explicit
    /// station code. An unjoined co-located identity is not a proof.
    public static func provenStationBoundaryPair(
        from previous: String, to first: String,
        previousSection: RouteSection, nextSection: RouteSection,
        graph: RouteGraph.Graph, stations: Stations.Index, rideDate: String?
    ) -> (previous: String, first: String)? {
        let previousCode = trimmedStationCode(previousSection.toN02StationCode)
        let nextCode = trimmedStationCode(nextSection.fromN02StationCode)
        guard !previousCode.isEmpty, previousCode == nextCode else { return nil }
        guard graph.nodes[previous] != nil, graph.nodes[first] != nil else { return nil }
        let stopName = Stations.normalizeStationName(
            previousSection.to ?? nextSection.from ?? "")
        let stopCodes = stationGroupCodes(stopCode: previousCode, stations: stations, rideDate: rideDate)
        let previousKeys = boundaryCandidateKeys(
            identityOf: previous, section: previousSection, stopCodes: stopCodes,
            stopName: stopName, graph: graph, stations: stations, rideDate: rideDate)
        let firstKeys = boundaryCandidateKeys(
            identityOf: first, section: nextSection, stopCodes: stopCodes,
            stopName: stopName, graph: graph, stations: stations, rideDate: rideDate)
        for previousKey in previousKeys {
            for firstKey in firstKeys {
                if previousKey == firstKey
                    || sameIdentitySpan(from: previousKey, to: firstKey, graph: graph, date: rideDate)
                    || physicalBoundaryIsProven(
                        from: previousKey, to: firstKey, graph: graph, rideDate: rideDate) {
                    return (previousKey, firstKey)
                }
            }
        }
        return nil
    }

    /// Certified ends when they already prove, otherwise the station-boundary
    /// pair. Nil when neither proves. Callers keep the certified stroke and
    /// use the returned keys only as the boundary's previous and first.
    public static func provenBoundaryContinuation(
        previous: String?, first: String?,
        previousSection: RouteSection, nextSection: RouteSection,
        graph: RouteGraph.Graph, stations: Stations.Index, rideDate: String?
    ) -> (previous: String, first: String)? {
        guard let previous, let first else { return nil }
        if physicalBoundaryIsProven(from: previous, to: first, graph: graph, rideDate: rideDate) {
            return (previous, first)
        }
        guard routeSectionBoundarySharesExplicitStop(previousSection, nextSection) else { return nil }
        return provenStationBoundaryPair(
            from: previous, to: first, previousSection: previousSection,
            nextSection: nextSection, graph: graph, stations: stations, rideDate: rideDate)
    }

    private static func trimmedStationCode(_ code: String?) -> String {
        code?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// The stop code, its N02 group, and every membership code in that group.
    private static func stationGroupCodes(
        stopCode: String, stations: Stations.Index, rideDate: String?
    ) -> Set<String> {
        var codes: Set<String> = [stopCode]
        var groups: Set<String> = []
        func absorb(_ feature: Stations.Feature) {
            let code = trimmedStationCode(Stations.stationCode(feature))
            let group = trimmedStationCode(Stations.stationGroupCode(feature))
            if !code.isEmpty { codes.insert(code) }
            if !group.isEmpty {
                codes.insert(group)
                groups.insert(group)
            }
        }
        for feature in stations.features {
            guard stationFeatureIsCurrent(feature, rideDate: rideDate) else { continue }
            let code = trimmedStationCode(Stations.stationCode(feature))
            let group = trimmedStationCode(Stations.stationGroupCode(feature))
            if code == stopCode || group == stopCode { absorb(feature) }
        }
        guard !groups.isEmpty else { return codes }
        for feature in stations.features {
            guard stationFeatureIsCurrent(feature, rideDate: rideDate) else { continue }
            let code = trimmedStationCode(Stations.stationCode(feature))
            let group = trimmedStationCode(Stations.stationGroupCode(feature))
            if (!group.isEmpty && groups.contains(group)) || codes.contains(code) {
                absorb(feature)
            }
        }
        return codes
    }

    private static func stationFeatureIsCurrent(
        _ feature: Stations.Feature, rideDate: String?
    ) -> Bool {
        RouteGraph.RailValidity.isValid(
            validFrom: Stations.stationValidFrom(feature),
            validTo: Stations.stationValidTo(feature), on: rideDate)
    }

    /// Snaps first, then junction endpoints, each in stable order.
    private static func boundaryCandidateKeys(
        identityOf certified: String, section: RouteSection, stopCodes: Set<String>,
        stopName: String, graph: RouteGraph.Graph, stations: Stations.Index,
        rideDate: String?
    ) -> [String] {
        let requiredIdentity = String(physicalIdentity(certified))
        var keys: [String] = []
        var seen = Set<String>()
        func add(_ key: String) {
            guard graph.nodes[key] != nil, seen.insert(key).inserted,
                  String(physicalIdentity(key)) == requiredIdentity,
                  nodeMatchesSectionLine(key, section: section, graph: graph) else { return }
            keys.append(key)
        }
        var snaps: [(key: String, distance: Double, order: Int)] = []
        var order = 0
        for feature in stations.features {
            guard stationFeatureIsCurrent(feature, rideDate: rideDate) else { continue }
            let code = trimmedStationCode(Stations.stationCode(feature))
            let group = trimmedStationCode(Stations.stationGroupCode(feature))
            guard stopCodes.contains(code) || stopCodes.contains(group) else { continue }
            for source in stationGeometryCoordinates(feature) {
                for nearest in RouteGraph.nearbyNodes(
                    source, in: graph, radiusDeg: 0.006, limit: 160)
                where nearest.distance <= stationSnapMaxDistanceMeters {
                    snaps.append((nearest.key, nearest.distance, order))
                    order += 1
                }
            }
        }
        snaps.sort { lhs, rhs in
            if lhs.distance != rhs.distance { return lhs.distance < rhs.distance }
            return lhs.order < rhs.order
        }
        for snap in snaps { add(snap.key) }
        var junctions: [(id: String, key: String)] = []
        var seenJunctions = Set<String>()
        for (fromKey, edges) in graph.adjacency {
            for edge in edges {
                guard let junction = edge.physicalJunction?.junction,
                      seenJunctions.insert(junction.id).inserted,
                      !junction.evidence.isEmpty,
                      junctionServesStop(junction, stopCodes: stopCodes, stopName: stopName),
                      RouteGraph.RailValidity.isValid(
                        validFrom: junction.validFrom, validTo: junction.validTo, on: rideDate)
                else { continue }
                junctions.append((junction.id, fromKey))
                junctions.append((junction.id, edge.to))
            }
        }
        junctions.sort { lhs, rhs in
            if lhs.id != rhs.id { return lhs.id < rhs.id }
            return lhs.key < rhs.key
        }
        for junction in junctions { add(junction.key) }
        return keys
    }

    private static func nodeMatchesSectionLine(
        _ key: String, section: RouteSection, graph: RouteGraph.Graph
    ) -> Bool {
        let lines = Set((section.lineNames ?? []).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty })
        let operators = Set((section.operatorNames ?? []).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty })
        guard !lines.isEmpty || !operators.isEmpty else { return true }
        guard let meta = graph.nodeMeta[key] else { return false }
        if !lines.isEmpty && !RouteGraph.intersects(lines, meta.lineNames) { return false }
        if !operators.isEmpty && !RouteGraph.intersects(operators, meta.operators) { return false }
        return true
    }

    private static func junctionServesStop(
        _ junction: RouteGraph.PhysicalJunction, stopCodes: Set<String>, stopName: String
    ) -> Bool {
        let code = trimmedStationCode(junction.stationCode)
        if !code.isEmpty { return stopCodes.contains(code) }
        let name = Stations.normalizeStationName(junction.station ?? "")
        return !stopName.isEmpty && name == stopName
    }

    public struct StationSectionInference: Sendable {
        public var hints: [Int: RouteHints] = [:]
        public var ambiguous: Set<Int> = []
    }

    /// Resolve the entire compatible station run so later via stations can
    /// distinguish an earlier branch. Preferences and journey IDs never turn
    /// multiple physical choices into a unique inferred choice.
    public static func inferStationSections(
        _ sections: [RouteSection], resolver: StationIntervalResolver?, network: RouteNetwork?,
        eligibility: StationRouteEligibility?, allowedCodes: [String], hard: Bool
    ) -> StationSectionInference {
        var result = StationSectionInference()
        guard let resolver, let network, let eligibility else { return result }
        let knownIDs = Set(network.lines.map(\.lineId))
        var index = 0
        while index < sections.count {
            let first = sections[index]
            guard first.sectionCodes?.isEmpty != false else { index += 1; continue }
            let ids = first.lineIDs ?? [], names = first.lineNames ?? [], operators = first.operatorNames ?? []
            var end = index + 1
            while end < sections.count {
                let next = sections[end]
                guard next.sectionCodes?.isEmpty != false,
                      (next.lineIDs ?? []) == ids, (next.lineNames ?? []) == names,
                      (next.operatorNames ?? []) == operators,
                      routeSectionBoundarySharesExplicitStop(sections[end - 1], next) else { break }
                end += 1
            }
            defer { index = end }
            if !ids.allSatisfy(knownIDs.contains) {
                result.ambiguous.formUnion(index..<end)
                continue
            }
            guard let candidates = resolver.candidateLineIDs(
                requiredLineIDs: ids, requiredLineNames: names, requiredOperatorNames: operators),
                  network.lines.filter({ candidates.contains($0.lineId) }).allSatisfy({
                      eligibility.permits($0, allowedInstitutionCodes: allowedCodes, hard: hard)
                  }),
                  let from = eligibility.stationCode(first.fromN02StationCode) else { continue }
            let destinations = sections[index..<end].compactMap { eligibility.stationCode($0.toN02StationCode) }
            guard destinations.count == end - index,
                  sections[(index + 1)..<end].enumerated().allSatisfy({ offset, section in
                      eligibility.stationCode(section.fromN02StationCode) == destinations[offset]
                  }) else { continue }
            switch resolver.resolve(
                stationCodes: [from] + destinations, requiredLineIDs: ids,
                requiredLineNames: names, requiredOperatorNames: operators) {
            case .resolved(let selection):
                for offset in selection.legIntervals.indices {
                    let leg = selection.legIntervals[offset]
                    result.hints[index + offset] = RouteHints(
                        requiredLineIDs: Array(Set(leg.map(\.lineID))).sorted(), sectionCodes: leg.map(\.code),
                        fromStationCode: selection.stationCodes[offset],
                        toStationCode: selection.stationCodes[offset + 1])
                }
            case .ambiguous: result.ambiguous.formUnion(index..<end)
            case .unsupported: break
            }
        }
        return result
    }

    public static func routeSectionBoundarySharesExplicitStop(
        _ previous: RouteSection, _ next: RouteSection
    ) -> Bool {
        let previousCode = previous.toN02StationCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let nextCode = next.fromN02StationCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !previousCode.isEmpty, !nextCode.isEmpty { return previousCode == nextCode }
        let previousName = Stations.normalizeStationName(previous.to ?? "")
        let nextName = Stations.normalizeStationName(next.from ?? "")
        return !previousName.isEmpty && previousName == nextName
    }

    /// Package row `name` to the graph's `lineName`. `-2` and `-p1` are row
    /// ids, and a trailing 本線 is the passenger spelling of 線.
    public static func displayRowGraphLineName(_ name: String) -> String {
        var units = Array(name.utf16)
        while true {
            let end = units.count
            var digits = 0
            while end - digits > 0, (0x30...0x39).contains(units[end - digits - 1]) { digits += 1 }
            guard digits > 0 else { break }
            var start = end - digits
            if start > 0, units[start - 1] == 0x70 { start -= 1 }
            guard start > 0, units[start - 1] == 0x2D else { break }
            start -= 1
            units.removeSubrange(start..<end)
        }
        var text = String(decoding: units, as: UTF16.self)
        if text.hasSuffix("本線") {
            text = String(text.dropLast(2)) + "線"
        }
        return text
    }

    /// Shared by production source certification and real-data regression tests.
    ///
    /// `displayRowNames` are package row names for a display-interval polyline.
    /// A name that is an identity of the line's first graph node becomes the
    /// required line. A name that matches nothing there leaves the section's
    /// own hints unchanged. `anchorIndices` are interval joins in each source
    /// line, in that line's original vertex order.
    public static func verifiedSourcePath(
        _ lines: [[Coordinate]], graph: RouteGraph.Graph,
        context: TrainContext, section: RouteSection,
        displayRowNames: [String] = [], anchorIndices: [Set<Int>] = []
    ) -> [String]? {
        var result: [String] = []
        for (lineIndex, sourceLine) in lines.enumerated() {
            let required = certificationHints(
                line: sourceLine, graph: graph, section: section, displayRowNames: displayRowNames)
            guard let trimmed = trimmedToGraphNodes(
                    line: sourceLine, graph: graph, requiredLines: required.lines,
                    requiredOperators: required.operators, rideDate: context.rideDate),
                  let offset = firstGraphNodeIndex(sourceLine, graph: graph) else { return nil }
            let anchors = lineIndex < anchorIndices.count
                ? Set(anchorIndices[lineIndex].compactMap { index -> Int? in
                    let local = index - offset
                    guard local >= 0, local < trimmed.count else { return nil }
                    return local
                })
                : []
            guard let keys = verifiedPhysicalPathKeys(
                trimmed, graph: graph, rideDate: context.rideDate,
                requiredLines: required.lines, requiredOperators: required.operators,
                anchorIndices: anchors) else { return nil }
            if let previous = result.last, let first = keys.first {
                guard let bridge = physicalContinuationPath(
                    from: previous, to: first, graph: graph, rideDate: context.rideDate)
                    ?? sameIdentitySpanPath(from: previous, to: first, graph: graph,
                        date: context.rideDate, maxMeters: 2 * RouteNetwork.endpointSnapMeters) else { return nil }
                result += bridge.dropFirst()
            }
            result += keys.dropFirst(result.isEmpty ? 0 : 1)
        }
        return result.isEmpty ? nil : result
    }

    private static func firstGraphNodeIndex(_ line: [Coordinate], graph: RouteGraph.Graph) -> Int? {
        line.firstIndex { coordinate in
            !RouteGraph.exactNodeKeys(Grid.normalizeGraphCoord(coordinate), in: graph).isEmpty
        }
    }

    /// Display-row identities that sit on the first certified node, or the
    /// section hints when none of the row names do.
    private static func certificationHints(
        line: [Coordinate], graph: RouteGraph.Graph, section: RouteSection,
        displayRowNames: [String]
    ) -> (lines: Set<String>, operators: Set<String>) {
        let operators = Set(section.operatorNames ?? [])
        let sectionLines = Set(section.lineNames ?? [])
        guard !displayRowNames.isEmpty,
              let index = firstGraphNodeIndex(line, graph: graph) else {
            return (sectionLines, operators)
        }
        let keys = RouteGraph.exactNodeKeys(Grid.normalizeGraphCoord(line[index]), in: graph)
        var identities = Set<String>()
        for key in keys {
            identities.formUnion(graph.nodeMeta[key]?.lineNames ?? [])
        }
        let hinted = Set(displayRowNames.map(displayRowGraphLineName).filter { identities.contains($0) })
        return (hinted.isEmpty ? sectionLines : hinted, operators)
    }

    /// Certify an already selected source polyline without replacing its rail
    /// choice with a newly solved route. Every step must be a surveyed edge
    /// (including an `osmTrack` drawn on the line's own identity). Only
    /// reviewed, service-valid physical junctions cross identities: zero-length
    /// at an identical vertex, a reviewed short link of at most 30 m, or an
    /// `osmConnector` with reviewed OpenStreetMap stubs of at most 50 m.
    public static func verifiedPhysicalPathKeys(
        _ coordinates: [Coordinate], graph: RouteGraph.Graph, rideDate: String?,
        requiredLines: Set<String> = [], requiredOperators: Set<String> = [],
        anchorIndices: Set<Int> = []
    ) -> [String]? {
        guard coordinates.count >= 2, let first = coordinates.first else { return nil }
        struct Step { let key: String; let parent: Int? }
        var steps: [Step] = []
        var frontier: [String: Int] = [:]
        // Keys entered by a surveyed rail edge. A zero-length junction copy at
        // the same vertex is not one of these.
        var arrivedByRail: Set<String> = []
        let firstCoordinate = Grid.normalizeGraphCoord(first)
        for key in RouteGraph.exactNodeKeys(firstCoordinate, in: graph) {
            frontier[key] = steps.count
            steps.append(Step(key: key, parent: nil))
        }
        // Measured off-grid error: max 0.7 m, p99 0.06 m; five-decimal
        // coordinate rounding has a worst-case displacement of about 0.72 m.
        let onEdgeToleranceMeters = 1.0
        let anchorSpanMeters = 2 * RouteNetwork.endpointSnapMeters
        var pending: [Coordinate] = []
        var skippedAnchor = false
        let hints = SegmentHints(requiredLines: requiredLines, requiredOperators: requiredOperators)

        func pendingPointsFollowEdge(from a: Coordinate, to b: Coordinate) -> Bool {
            guard !pending.isEmpty else { return true }
            let metersPerDegree = 6_371_000.0 * .pi / 180
            let sx = metersPerDegree * cos((a.lat + b.lat) / 2 * .pi / 180)
            let dx = (b.lon - a.lon) * sx
            let dy = (b.lat - a.lat) * metersPerDegree
            let lengthSquared = dx * dx + dy * dy
            guard lengthSquared > 0 else { return false }
            var previousProjection = 0.0
            for point in pending {
                let px = (point.lon - a.lon) * sx
                let py = (point.lat - a.lat) * metersPerDegree
                let projection = (px * dx + py * dy) / lengthSquared
                guard projection >= previousProjection, projection <= 1,
                      hypot(px - projection * dx, py - projection * dy)
                        <= onEdgeToleranceMeters else { return false }
                previousProjection = projection
            }
            return true
        }

        // A station-table join that is neither a node nor on a surveyed edge
        // is not a vertex of the ride. The keys on either side still have to
        // be one date-valid same-identity walk of at most 520 m.
        func anchorWithinOneMeter(_ coordinate: Coordinate) -> Bool {
            for key in frontier.keys {
                guard let terminal = graph.nodes[key] else { continue }
                if anchorLiesOnIdentityEdge(
                    coordinate, terminal: terminal, graph: graph, maxMeters: anchorSpanMeters,
                    requiredLines: requiredLines, requiredOperators: requiredOperators,
                    rideDate: rideDate)
                {
                    return true
                }
            }
            return false
        }

        func bridgeSkippedAnchor(to nextCoordinate: Coordinate) -> [String: Int]? {
            let targets = RouteGraph.exactNodeKeys(nextCoordinate, in: graph)
            guard !targets.isEmpty else { return nil }
            var bridged: [String: Int] = [:]
            for (key, parent) in frontier.sorted(by: { $0.value < $1.value }) {
                for target in targets {
                    guard let span = sameIdentitySpanPath(
                        from: key, to: target, graph: graph, date: rideDate,
                        maxMeters: anchorSpanMeters) else { continue }
                    var cursor = parent
                    for node in span.dropFirst() {
                        steps.append(Step(key: node, parent: cursor))
                        cursor = steps.count - 1
                    }
                    bridged[target] = cursor
                    if span.count >= 2 { arrivedByRail.insert(target) }
                }
            }
            return bridged.isEmpty ? nil : bridged
        }

        /// Nodes within 520 m whose incoming edge passes within 1 m of `anchor`.
        /// The walk stops on that edge. It does not use `sameIdentitySpan`.
        func carryTargets(from start: String, anchor: Coordinate) -> Set<String> {
            let requiredIdentity = physicalIdentity(start)
            var targets = Set<String>()
            var queue: [(key: String, length: Double)] = [(start, 0)]
            var best = [start: 0.0]
            var index = 0
            while index < queue.count && index < 64 {
                let current = queue[index]
                index += 1
                guard let origin = graph.nodes[current.key] else { continue }
                for edge in graph.adjacency[current.key] ?? [] {
                    let total = current.length + edge.length
                    guard edge.connector == nil, edge.physicalJunction == nil,
                          let destination = graph.nodes[edge.to],
                          physicalIdentity(edge.to) == requiredIdentity,
                          edgeMatchesRequiredHints(edge, hints: hints),
                          RouteGraph.RailValidity.isValid(
                            validFrom: edge.validFrom, validTo: edge.validTo, on: rideDate)
                    else { continue }
                    let onAnchor = segmentProjection(anchor, from: origin, to: destination)
                        .map { $0.t >= 0 && $0.t <= 1 && $0.distance <= onEdgeToleranceMeters } ?? false
                    if onAnchor, total <= anchorSpanMeters {
                        targets.insert(edge.to)
                    }
                    guard total <= anchorSpanMeters, !onAnchor,
                          total < best[edge.to, default: .infinity] else { continue }
                    best[edge.to] = total
                    queue.append((edge.to, total))
                }
            }
            return targets
        }

        /// Carry an on-edge station dot along its edge to the next node.
        /// Nil when that walk is longer than 520 m or is not unique, so the
        /// caller keeps the direct-edge path (a 700 m edge still certifies).
        func carryOnEdgeAnchor(_ anchor: Coordinate) -> [String: Int]? {
            var carried: [String: Int] = [:]
            let pendingPoints = pending + [anchor]
            for (key, parent) in frontier.sorted(by: { $0.value < $1.value }) {
                guard let currentCoordinate = graph.nodes[key] else { continue }
                for candidateKey in RouteGraph.exactNodeKeys(currentCoordinate, in: graph) {
                    guard pending.isEmpty || candidateKey == key,
                          let prefix = physicalContinuationPath(
                            from: key, to: candidateKey, graph: graph, rideDate: rideDate)
                    else { continue }
                    let targets = carryTargets(from: candidateKey, anchor: anchor)
                    guard let path = onEdgeIdentityPath(
                        from: candidateKey, targetKeys: targets, pendingPoints: pendingPoints,
                        graph: graph, rideDate: rideDate, hints: hints,
                        maxMeters: anchorSpanMeters), path.count >= 2 else { continue }
                    var cursor = parent
                    for prefixKey in prefix.dropFirst() {
                        steps.append(Step(key: prefixKey, parent: cursor))
                        cursor = steps.count - 1
                    }
                    for node in path.dropFirst() {
                        steps.append(Step(key: node, parent: cursor))
                        cursor = steps.count - 1
                    }
                    if let end = path.last {
                        carried[end] = cursor
                        arrivedByRail.insert(end)
                    }
                }
            }
            return carried.isEmpty ? nil : carried
        }

        for (offset, coordinate) in coordinates.enumerated().dropFirst() {
            guard !Task.isCancelled else { return nil }
            let nextCoordinate = Grid.normalizeGraphCoord(coordinate)
            let isNode = !RouteGraph.exactNodeKeys(nextCoordinate, in: graph).isEmpty
            if !isNode, anchorIndices.contains(offset), offset < coordinates.count - 1 {
                if !anchorWithinOneMeter(coordinate) {
                    skippedAnchor = true
                    continue
                }
                if let carried = carryOnEdgeAnchor(coordinate) {
                    frontier = carried
                    pending.removeAll(keepingCapacity: true)
                    skippedAnchor = false
                    continue
                }
            }
            if isNode, skippedAnchor, pending.isEmpty {
                guard let bridged = bridgeSkippedAnchor(to: nextCoordinate) else { return nil }
                frontier = bridged
                skippedAnchor = false
                continue
            }
            let nearby = isNode ? []
                : RouteGraph.nearbyNodes(nextCoordinate, in: graph, radiusDeg: 0, limit: Int.max)
            // nearbyNodes measures from a normalized coordinate. Rounding must
            // instead be bounded by the original source vertex.
            let roundedKeys = isNode ? Set<String>() : Set(nearby.compactMap { candidate in
                graph.nodes[candidate.key].flatMap {
                    Geometry.distanceMeters(coordinate, $0) <= onEdgeToleranceMeters ? candidate.key : nil
                }
            })
            var next: [String: Int] = [:]
            // In step order, not dictionary order: when two co-located
            // identities reach one vertex, the later visit wins `next`, and
            // a seeded dictionary made that winner differ between launches.
            for (key, parent) in frontier.sorted(by: { $0.value < $1.value }) {
                guard let currentCoordinate = graph.nodes[key] else { continue }
                for candidateKey in RouteGraph.exactNodeKeys(currentCoordinate, in: graph) {
                    // A buffered point can only be carried by one surveyed edge,
                    // never by a connector or a reviewed junction transition.
                    guard pending.isEmpty || candidateKey == key,
                          let prefix = physicalContinuationPath(
                            from: key, to: candidateKey, graph: graph, rideDate: rideDate) else { continue }
                    var prefixParent = parent
                    for prefixKey in prefix.dropFirst() {
                        steps.append(Step(key: prefixKey, parent: prefixParent))
                        prefixParent = steps.count - 1
                    }
                    if isNode && currentCoordinate == nextCoordinate && pending.isEmpty {
                        next[candidateKey] = prefixParent
                        continue
                    }
                    var tookDirectEdge = false
                    for edge in graph.adjacency[candidateKey] ?? [] {
                        guard edge.connector == nil, edge.physicalJunction == nil,
                              let destination = graph.nodes[edge.to],
                              (isNode ? destination == nextCoordinate : roundedKeys.contains(edge.to)),
                              !(skippedAnchor && edge.length > anchorSpanMeters),
                              edgeMatchesRequiredHints(edge, hints: hints),
                              RouteGraph.RailValidity.isValid(
                                validFrom: edge.validFrom, validTo: edge.validTo, on: rideDate),
                              pendingPointsFollowEdge(from: currentCoordinate, to: destination) else { continue }
                        steps.append(Step(key: edge.to, parent: prefixParent))
                        next[edge.to] = steps.count - 1
                        arrivedByRail.insert(edge.to)
                        tookDirectEdge = true
                    }
                    // A station anchor can sit on the identity between two
                    // nodes that the package polyline does not show as one
                    // graph edge. Carry it only along the unique same-identity
                    // walk whose polyline actually passes through the anchor.
                    if !tookDirectEdge, !pending.isEmpty {
                        let targets = isNode
                            ? Set(RouteGraph.exactNodeKeys(nextCoordinate, in: graph))
                            : roundedKeys
                        if let path = onEdgeIdentityPath(
                            from: candidateKey, targetKeys: targets, pendingPoints: pending,
                            graph: graph, rideDate: rideDate, hints: hints,
                            maxMeters: 2 * RouteNetwork.endpointSnapMeters)
                        {
                            var cursor = prefixParent
                            for node in path.dropFirst() {
                                steps.append(Step(key: node, parent: cursor))
                                cursor = steps.count - 1
                            }
                            if let end = path.last {
                                next[end] = cursor
                                arrivedByRail.insert(end)
                            }
                        }
                    }
                }
            }
            if next.isEmpty {
                // An anchor that is itself a graph node (a reviewed osmTrack
                // through the station dot) can be followed by a display vertex
                // that skips the track's intermediate points. Those points are
                // not polyline vertices, so this is not a skipped non-anchor:
                // the next node still has to be the same identity within 520 m.
                if isNode, pending.isEmpty, anchorIndices.contains(offset - 1),
                   let bridged = bridgeSkippedAnchor(to: nextCoordinate) {
                    frontier = bridged
                    skippedAnchor = false
                    continue
                }
                guard !isNode else { return nil }
                pending.append(coordinate)
            } else {
                frontier = next
                pending.removeAll(keepingCapacity: true)
                skippedAnchor = false
            }
        }
        guard pending.isEmpty, !skippedAnchor else { return nil }
        frontier = droppingTerminalJunctionSiblings(
            frontier, arrivedByRail: arrivedByRail, graph: graph, rideDate: rideDate)
        // Ambiguous identities remain unconfirmed rather than selecting one
        // merely because its coordinates coincide with the recorded path.
        guard frontier.count == 1, var index = frontier.values.first else { return nil }
        var path: [String] = []
        while true {
            path.append(steps[index].key)
            guard let parent = steps[index].parent else { break }
            index = parent
        }
        return path.reversed()
    }

    /// At the last vertex, keep the one identity that rode a rail edge and
    /// drop siblings copied there by a date-valid zero-length junction. Two
    /// identities that each rode their own edge stay ambiguous. A key at
    /// another coordinate is a real fork and stays.
    private static func droppingTerminalJunctionSiblings(
        _ frontier: [String: Int], arrivedByRail: Set<String>,
        graph: RouteGraph.Graph, rideDate: String?
    ) -> [String: Int] {
        let arrivals = frontier.keys.filter { arrivedByRail.contains($0) }
        guard arrivals.count == 1, let arrival = arrivals.first,
              let coordinate = graph.nodes[arrival] else { return frontier }
        var kept = frontier
        for key in frontier.keys where key != arrival {
            guard graph.nodes[key] == coordinate,
                  zeroLengthJunctionSibling(
                    from: arrival, to: key, graph: graph, rideDate: rideDate) else { continue }
            kept.removeValue(forKey: key)
        }
        return kept
    }

    private static func zeroLengthJunctionSibling(
        from arrival: String, to key: String, graph: RouteGraph.Graph, rideDate: String?
    ) -> Bool {
        guard arrival != key,
              let path = physicalContinuationPath(
                from: arrival, to: key, graph: graph, rideDate: rideDate),
              path.count >= 2 else { return false }
        for (start, end) in zip(path, path.dropFirst()) {
            guard graph.nodes[start] == graph.nodes[end],
                  let edge = (graph.adjacency[start] ?? []).first(where: { candidate in
                      candidate.to == end && candidate.connector == nil
                          && candidate.physicalJunction != nil
                  }),
                  let junction = edge.physicalJunction?.junction,
                  junction.kind == .zeroLength, edge.length == 0, !junction.evidence.isEmpty,
                  junctionGeometryIsValid(junction, edge: edge, current: start, graph: graph),
                  RouteGraph.RailValidity.isValid(
                    validFrom: junction.validFrom, validTo: junction.validTo, on: rideDate)
            else { return false }
        }
        return true
    }

    public struct OfficialIntervalIndex: Sendable {
        struct Record: Sendable {
            let featureIndex: Int
            let coordinates: [Coordinate]
            let lineName: String
            let operatorName: String
            let institutionTypeCode: String
            let reversed: Bool
            let validFrom: String?
            let validTo: String?
            let historyIDs: [String]
            let temporalKind: RouteGraph.TemporalKind
        }
        let records: [String: [Record]]

        public init(sections: [RouteGraph.SectionFeature]) {
            var records: [String: [Record]] = [:]
            for (index, feature) in sections.enumerated() {
                guard feature.geometryType == "LineString", feature.lines.count == 1,
                      let coordinates = feature.lines.first, coordinates.count >= 2 else { continue }
                let line = normalizeRouteHintText(feature.properties.lineName)
                let operatorName = normalizeRouteHintText(feature.properties.operator)
                guard let first = coordinates.first, let last = coordinates.last else { continue }
                let forward = officialIntervalKey(
                    line: line, operatorName: operatorName, from: first, to: last)
                let reverse = officialIntervalKey(
                    line: line, operatorName: operatorName, from: last, to: first)
                if !forward.isEmpty {
                    records[forward, default: []].append(Record(
                        featureIndex: index, coordinates: coordinates, lineName: line,
                        operatorName: operatorName,
                        institutionTypeCode: feature.properties.institutionTypeCode,
                        reversed: false, validFrom: feature.properties.validFrom,
                        validTo: feature.properties.validTo,
                        historyIDs: feature.properties.carriedHistoryIDs,
                        temporalKind: feature.properties.temporalKind))
                }
                if !reverse.isEmpty {
                    records[reverse, default: []].append(Record(
                        featureIndex: index, coordinates: coordinates, lineName: line,
                        operatorName: operatorName,
                        institutionTypeCode: feature.properties.institutionTypeCode,
                        reversed: true, validFrom: feature.properties.validFrom,
                        validTo: feature.properties.validTo,
                        historyIDs: feature.properties.carriedHistoryIDs,
                        temporalKind: feature.properties.temporalKind))
                }
            }
            self.records = records
        }
    }

    /// Exact station-cut interval path for Taiwan, Hong Kong and Macao. It
    /// preserves ordered reversals and the six-decimal display geometry rather
    /// than allowing a shortest-path graph to jump across a switchback.
    public static func solveOfficialInterval(
        _ rawSection: RouteSection,
        segmentIndex: Int,
        train: TrainContext,
        country: String,
        allowedCodes: [String],
        intervalIndex: OfficialIntervalIndex,
        stations: Stations.Index,
        continuityAnchor: Coordinate? = nil
    ) -> SolvedSection? {
        guard ["tw", "hk", "mo"].contains(country) else { return nil }
        let requiredLines = normalizedHintValues(rawSection.lineNames ?? [])
        let requiredOperators = normalizedHintValues(rawSection.operatorNames ?? [])
        guard !requiredLines.isEmpty else { return nil }
        var section = rawSection
        if section.from?.isEmpty != false {
            section.from = stations.name(forCode: section.fromN02StationCode)
        }
        if section.to?.isEmpty != false {
            section.to = stations.name(forCode: section.toN02StationCode)
        }
        let fromStations = filterStationCandidatesByRideDate(
            stations.candidateIndices(for: .stop(.init(
                name: section.from, n02StationCode: section.fromN02StationCode))),
            in: stations, rideDate: train.rideDate)
        let toStations = filterStationCandidatesByRideDate(
            stations.candidateIndices(for: .stop(.init(
                name: section.to, n02StationCode: section.toN02StationCode))),
            in: stations, rideDate: train.rideDate)
        guard !fromStations.isEmpty, !toStations.isEmpty else { return nil }

        struct Identity: Hashable { let featureIndex: Int; let reversed: Bool }
        var identities = Set<Identity>()
        var matches: [OfficialIntervalIndex.Record] = []
        for line in requiredLines {
            let fromOnLine = fromStations.filter {
                let feature = stations.features[$0]
                return Stations.stationLineName(feature) == line
                    && (requiredOperators.isEmpty
                        || requiredOperators.contains(Stations.stationOperator(feature)))
            }
            let toOnLine = toStations.filter {
                let feature = stations.features[$0]
                return Stations.stationLineName(feature) == line
                    && (requiredOperators.isEmpty
                        || requiredOperators.contains(Stations.stationOperator(feature)))
            }
            for from in fromOnLine {
                for to in toOnLine {
                    let fromOperator = Stations.stationOperator(stations.features[from])
                    let toOperator = Stations.stationOperator(stations.features[to])
                    guard !fromOperator.isEmpty, fromOperator == toOperator,
                          requiredOperators.isEmpty || requiredOperators.contains(fromOperator),
                          let fromCoordinate = coordinate(Stations.displayCoordinate(stations.features[from])),
                          let toCoordinate = coordinate(Stations.displayCoordinate(stations.features[to]))
                    else { continue }
                    let key = officialIntervalKey(
                        line: line, operatorName: fromOperator,
                        from: fromCoordinate, to: toCoordinate)
                    for record in intervalIndex.records[key] ?? [] {
                        guard RouteGraph.RailValidity.isValid(
                            validFrom: record.validFrom, validTo: record.validTo,
                            on: train.rideDate) else { continue }
                        if identities.insert(.init(
                            featureIndex: record.featureIndex, reversed: record.reversed)).inserted
                        {
                            matches.append(record)
                        }
                    }
                }
            }
        }
        guard matches.count == 1 else { return nil }
        let match = matches[0]
        if train.institutionFilterMode == "hard", !allowedCodes.isEmpty,
           !match.institutionTypeCode.isEmpty,
           !allowedCodes.contains(match.institutionTypeCode) { return nil }
        if Set(train.policy.hardExcludedInstitutionTypeCodes).contains(match.institutionTypeCode) {
            return nil
        }
        let coordinates = match.reversed ? Array(match.coordinates.reversed()) : match.coordinates
        guard let first = coordinates.first else { return nil }
        if let continuityAnchor,
           Geometry.distanceMeters(continuityAnchor, first) > 60 { return nil }
        let length = pathLength(for: coordinates)
        var preferredLines = Set(normalizedHintValues(train.preferredLineNames + requiredLines))
        preferredLines.formUnion(requiredLines)
        var preferredOperators = Set(normalizedHintValues(
            train.preferredOperatorNames
                + RouteGraph.derivedPreferredOperatorNames(
                    company: train.company, country: country)
                + [match.operatorName]))
        preferredOperators.formUnion(requiredOperators)
        let hints = SegmentHints(
            preferredLines: preferredLines, preferredOperators: preferredOperators,
            requiredLines: Set(requiredLines), requiredOperators: Set(requiredOperators),
            solveMode: "official_interval_exact")
        let provenance = RouteGraph.TemporalProvenance.aggregate(
            historyIDs: match.historyIDs, validFrom: [match.validFrom],
            validTo: [match.validTo], kinds: [match.temporalKind])
        return SolvedSection(
            segmentIndex: segmentIndex,
            fromStationIndex: fromStations[0], toStationIndex: toStations[0],
            coordinates: coordinates, rawPathKeys: coordinates.map(Grid.coordKey),
            hints: hints, allowedInstitutionTypeCodes: allowedCodes,
            usedInstitutionTypeCodes: match.institutionTypeCode.isEmpty
                ? [] : [match.institutionTypeCode],
            snapFrom: 0, snapTo: 0, physicalLength: length,
            rawPhysicalLength: length, cost: length, attemptIndex: 0,
            historyIDs: provenance.historyIDs, validFrom: provenance.validFrom,
            validTo: provenance.validTo, temporalKind: provenance.temporalKind)
    }

    /// Operator and line-name spellings that identify one package line on a
    /// graph edge. The family key uses `nameNorm`; rail-section edges use the
    /// N02 line name, which is usually the same spelling.
    private static func directionIdentityKeys(_ line: RouteNetwork.Line) -> Set<String> {
        let op = line.operator ?? ""
        var keys: Set<String> = [RouteNetwork.familyKey(line)]
        for name in [line.name, line.compactLine?.name, line.compactLine?.nameNorm] {
            if let name, !name.isEmpty { keys.insert(op + "\0" + name) }
        }
        return keys
    }

    private struct DirectionIntervalRecord: Sendable {
        var identityKeys: Set<String>
        var family: String
        var allowedDirections: Set<Int>
        var interior: Set<Coordinate>
        var allPoints: Set<Coordinate>
    }

    /// One scan of a network's lines. Later solves reuse it. `stamp` is an
    /// in-process content hash, not a persisted hash.
    private struct PreparedDirectionExclusions: Sendable {
        var records: [[DirectionIntervalRecord]]
        /// Family → direction → coordinates of intervals that allow that direction.
        var permittedPoints: [String: [Int: Set<Coordinate>]]
    }

    private final class DirectionExclusionCache: @unchecked Sendable {
        let lock = NSLock()
        var prepared: [Int: PreparedDirectionExclusions] = [:]
        var perInterval: [IntervalDirectionKey: Set<Coordinate>] = [:]
    }

    private struct IntervalDirectionKey: Hashable, Sendable {
        var stamp: Int
        var lineID: String
        var intervalIndex: Int
        var direction: Int
    }

    private static let directionExclusionCache = DirectionExclusionCache()
    /// Distinct networks kept in the direction caches. Past this, both maps
    /// are dropped so a run cannot retain every network it built.
    private static let directionCacheLimit = 32

    /// Line ids, station order, and the direction fields the exclusion scan
    /// reads. Counts collide when two networks differ in the middle.
    /// `RouteNetwork` is a struct, so this is a content hash, not identity.
    private static func directionNetworkStamp(_ network: RouteNetwork) -> Int {
        var hasher = Hasher()
        for line in network.lines {
            hasher.combine(line.lineId)
            hasher.combine(line.alignmentDirection)
            hasher.combine(line.operator)
            hasher.combine(line.name)
            if let compact = line.compactLine {
                hasher.combine(compact.id)
                hasher.combine(compact.name)
                hasher.combine(compact.nameNorm)
                hasher.combine(compact.alignmentDirection)
                hasher.combine(compact.stationOrderDirection)
                hasher.combine(compact.permittedTraversal)
                for station in compact.stations {
                    hasher.combine(station.id)
                    hasher.combine(station.name)
                }
                for pair in compact.alignmentPairs {
                    hasher.combine(pair.with)
                    hasher.combine(pair.from)
                    hasher.combine(pair.to)
                    hasher.combine(pair.direction)
                }
            }
            for interval in line.intervals {
                hasher.combine(interval.fromStationCode)
                hasher.combine(interval.toStationCode)
            }
        }
        return hasher.finalize()
    }

    private static func preparedDirectionExclusions(
        _ network: RouteNetwork, stamp: Int
    ) -> PreparedDirectionExclusions {
        directionExclusionCache.lock.lock()
        if let cached = directionExclusionCache.prepared[stamp] {
            directionExclusionCache.lock.unlock()
            return cached
        }
        directionExclusionCache.lock.unlock()
        var records: [[DirectionIntervalRecord]] = []
        records.reserveCapacity(network.lines.count)
        var permitted: [String: [Int: Set<Coordinate>]] = [:]
        for line in network.lines {
            let family = RouteNetwork.familyKey(line)
            let keys = directionIdentityKeys(line)
            var row: [DirectionIntervalRecord] = []
            row.reserveCapacity(line.intervals.count)
            for (index, interval) in line.intervals.enumerated() {
                let points = interval.coordinates.map(Grid.normalizeGraphCoord)
                let allowed = Set(line.compactLine.map {
                    RailwayDirection.allowedDirections(for: $0, intervalIndex: index)
                } ?? [-1, 1])
                row.append(DirectionIntervalRecord(
                    identityKeys: keys, family: family, allowedDirections: allowed,
                    interior: Set(points.dropFirst().dropLast()), allPoints: Set(points)))
                for direction in allowed {
                    var byDirection = permitted[family] ?? [:]
                    var bucket = byDirection[direction] ?? []
                    bucket.formUnion(points)
                    byDirection[direction] = bucket
                    permitted[family] = byDirection
                }
            }
            records.append(row)
        }
        let prepared = PreparedDirectionExclusions(records: records, permittedPoints: permitted)
        directionExclusionCache.lock.lock()
        directionExclusionCache.prepared[stamp] = prepared
        if directionExclusionCache.prepared.count > directionCacheLimit {
            directionExclusionCache.prepared.removeAll(keepingCapacity: true)
            directionExclusionCache.perInterval.removeAll(keepingCapacity: true)
            directionExclusionCache.prepared[stamp] = prepared
        }
        directionExclusionCache.lock.unlock()
        return prepared
    }

    /// Exclusive interior of one direction-restricted interval, minus geometry
    /// of family intervals that allow the same direction. Computed once per
    /// `(network, line, interval, direction)`.
    private static func cachedIntervalExclusion(
        stamp: Int, line: RouteNetwork.Line, lineIndex: Int, intervalIndex: Int,
        direction: Int, prepared: PreparedDirectionExclusions
    ) -> Set<Coordinate> {
        let key = IntervalDirectionKey(
            stamp: stamp, lineID: line.lineId, intervalIndex: intervalIndex, direction: direction)
        directionExclusionCache.lock.lock()
        if let cached = directionExclusionCache.perInterval[key] {
            directionExclusionCache.lock.unlock()
            return cached
        }
        directionExclusionCache.lock.unlock()
        let record = prepared.records[lineIndex][intervalIndex]
        let shared = prepared.permittedPoints[record.family]?[direction] ?? []
        let value = record.interior.subtracting(shared)
        directionExclusionCache.lock.lock()
        directionExclusionCache.perInterval[key] = value
        if directionExclusionCache.perInterval.count > directionCacheLimit {
            directionExclusionCache.perInterval.removeAll(keepingCapacity: true)
            directionExclusionCache.perInterval[key] = value
        }
        directionExclusionCache.lock.unlock()
        return value
    }

    private struct DirectionExclusion: Sendable {
        var coordinates: Set<Coordinate>
        var families: Set<String>
    }

    /// Only station order on a sourced package row establishes direction here.
    /// Exclude the forbidden interval's exclusive interior, and only on edges
    /// of that package line family. Shared approaches that also belong to a
    /// permitted sibling alignment stay. This is section-local: the physical
    /// graph remains bidirectional.
    private static func directionExclusion(
        section: RouteSection, network: RouteNetwork?
    ) -> DirectionExclusion {
        guard let network, let from = section.fromN02StationCode,
              let to = section.toN02StationCode, from != to else {
            return DirectionExclusion(coordinates: [], families: [])
        }
        let stamp = directionNetworkStamp(network)
        let prepared = preparedDirectionExclusions(network, stamp: stamp)
        let candidates = (network.stationLineIndices[from] ?? [])
            .intersection(network.stationLineIndices[to] ?? [])
        var excluded: Set<Coordinate> = []
        var families: Set<String> = []
        for lineIndex in candidates {
            guard prepared.records.indices.contains(lineIndex) else { continue }
            let line = network.lines[lineIndex]
            guard let compact = line.compactLine,
                  let start = compact.stations.firstIndex(where: { $0.id == from }),
                  let end = compact.stations.firstIndex(where: { $0.id == to }), start != end else { continue }
            let direction = start < end ? 1 : -1
            let row = prepared.records[lineIndex]
            for index in min(start, end)..<max(start, end) where row.indices.contains(index) {
                guard !row[index].allowedDirections.contains(direction) else { continue }
                families.formUnion(row[index].identityKeys)
                excluded.formUnion(cachedIntervalExclusion(
                    stamp: stamp, line: line, lineIndex: lineIndex, intervalIndex: index,
                    direction: direction, prepared: prepared))
            }
        }
        return DirectionExclusion(coordinates: excluded, families: families)
    }

    /// A coordinate on restricted geometry blocks only an edge of that family.
    /// Another identity that merely shares the coordinate stays traversable.
    private static func directionPermits(
        _ edge: RouteGraph.Edge, hints: SegmentHints, graph: RouteGraph.Graph
    ) -> Bool {
        guard !hints.directionExcludedCoordinates.isEmpty,
              let destination = graph.nodes[edge.to],
              hints.directionExcludedCoordinates.contains(destination) else { return true }
        return !hints.directionExcludedFamilies.contains(edge.operator + "\0" + edge.lineName)
    }

    /// Solve one itinerary section, including station expansion, candidate
    /// snapping, ordered hint fallbacks, detour rejection and endpoint
    /// completion. A nil result means no real rail geometry connected the two
    /// endpoints; it never manufactures a straight-line fallback.
    public static func solveSection(
        _ rawSection: RouteSection,
        segmentIndex: Int,
        train: TrainContext,
        country: String,
        graph: RouteGraph.Graph,
        stations: Stations.Index,
        continuityAnchor: Coordinate? = nil,
        physicalContinuationKey: String? = nil,
        traversalPolicy: TraversalPolicy = .physicalRail,
        directionNetwork: RouteNetwork? = nil
    ) -> SolvedSection? {
        var section = rawSection
        if section.from?.isEmpty != false {
            section.from = stations.name(forCode: section.fromN02StationCode)
        }
        if section.to?.isEmpty != false {
            section.to = stations.name(forCode: section.toN02StationCode)
        }
        let cacheTrain = RouteGraph.CacheKeyTrain(
            trainType: train.trainType, company: train.company,
            preferredLineNames: train.preferredLineNames,
            preferredOperatorNames: train.preferredOperatorNames,
            allowedInstitutionTypeCodes: train.allowedInstitutionTypeCodes,
            institutionFilterMode: train.institutionFilterMode)
        let allowedCodes = RouteGraph.allowedInstitutionTypeCodes(cacheTrain, country: country)
        let lineNames = (section.lineNames ?? []).filter { !$0.isEmpty }
        let fromStop = Stations.Stop(
            name: section.from, n02StationCode: section.fromN02StationCode)
        let toStop = Stations.Stop(
            name: section.to, n02StationCode: section.toN02StationCode)
        let fromStations = filterStationCandidatesByRideDate(
            resolveRouteEndpointStationCandidates(
                .stop(fromStop), in: stations, allowedCodes: allowedCodes,
                sectionLineNames: lineNames,
                sectionOperatorNames: section.operatorNames ?? [], rideDate: train.rideDate),
            in: stations, rideDate: train.rideDate)
        let toStations = filterStationCandidatesByRideDate(
            resolveRouteEndpointStationCandidates(
                .stop(toStop), in: stations, allowedCodes: allowedCodes,
                sectionLineNames: lineNames,
                sectionOperatorNames: section.operatorNames ?? [], rideDate: train.rideDate),
            in: stations, rideDate: train.rideDate)
        guard !fromStations.isEmpty, !toStations.isEmpty else { return nil }

        var baseHints = buildSegmentRouteHints(
            section: section,
            fromStationIndices: fromStations,
            toStationIndices: toStations,
            stations: stations, train: train, country: country)
        let exclusion = directionExclusion(section: section, network: directionNetwork)
        baseHints.directionExcludedCoordinates = exclusion.coordinates
        baseHints.directionExcludedFamilies = exclusion.families

        struct Best {
            var pathKeys: [String]
            var edges: [RouteGraph.Edge]
            var scoredCost: Double
            var totalCost: Double
            var physicalLength: Double
            var from: StationNodeCandidate
            var to: StationNodeCandidate
            var hints: SegmentHints
            var attemptIndex: Int
        }
        func stationCoordinates(_ indices: [Int]) -> [Int: Coordinate] {
            var result: [Int: Coordinate] = [:]
            for index in indices {
                if let coord = coordinate(Stations.displayCoordinate(stations.features[index])) {
                    result[index] = coord
                }
            }
            return result
        }
        let fromStationCoordinates = stationCoordinates(fromStations)
        let toStationCoordinates = stationCoordinates(toStations)
        func nearestAlternative(
            _ candidates: [Int: Coordinate], excluding: Int, from anchor: Coordinate
        ) -> Double? {
            var nearest: Double?
            for (index, coord) in candidates where index != excluding {
                let distance = Geometry.distanceMeters(coord, anchor)
                if nearest == nil || distance < nearest! { nearest = distance }
            }
            return nearest
        }
        let fromIsNameOnly = (section.fromN02StationCode ?? "").isEmpty
        let toIsNameOnly = (section.toN02StationCode ?? "").isEmpty
        /// See `endpointAmbiguityDistanceFactor`.
        func endpointIsImplausible(
            fromStationIndex: Int, toStationIndex: Int, fromAnchored: Bool
        ) -> Bool {
            guard fromIsNameOnly || toIsNameOnly,
                  let fromCoord = fromStationCoordinates[fromStationIndex],
                  let toCoord = toStationCoordinates[toStationIndex] else { return false }
            let straight = Geometry.distanceMeters(fromCoord, toCoord)
            guard straight > endpointAmbiguityMinStraightMeters else { return false }
            if toIsNameOnly, let alternative = nearestAlternative(
                toStationCoordinates, excluding: toStationIndex, from: fromCoord),
               straight > alternative * endpointAmbiguityDistanceFactor { return true }
            if fromIsNameOnly, !fromAnchored, let alternative = nearestAlternative(
                fromStationCoordinates, excluding: fromStationIndex, from: toCoord),
               straight > alternative * endpointAmbiguityDistanceFactor { return true }
            return false
        }
        /// `guarded` is the attempt's best result among those the endpoint
        /// plausibility guard rejected; it is only used when nothing else
        /// solves.
        func runAttempt(
            hints: SegmentHints, attemptIndex: Int, allowedCodes: [String]
        ) -> (best: Best?, guarded: Best?) {
            let excludedInstitutions = train.policy.hardExcludedInstitutionTypeCodes
            var fromCandidates = cappedStationCandidates(
                collectStationCandidateGraphNodes(
                    stationIndices: fromStations, stations: stations, graph: graph,
                    hints: hints, allowedCodes: allowedCodes,
                    hardExcludedInstitutionTypeCodes: excludedInstitutions),
                hints: hints, graph: graph)
            var fromAnchored = false
            if let continuityAnchor, physicalContinuationKey == nil {
                let continuous = fromCandidates.filter {
                    guard let stationCoordinate = coordinate(Stations.displayCoordinate(
                        stations.features[$0.stationIndex])) else { return false }
                    return Geometry.distanceMeters(stationCoordinate, continuityAnchor) <= 60
                }
                if !continuous.isEmpty {
                    fromCandidates = continuous
                    fromAnchored = true
                }
            }
            var continuationPaths: [String: [String]] = [:]
            if let physicalContinuationKey {
                guard let coordinate = graph.nodes[physicalContinuationKey],
                      let stationIndex = fromStations.first else { return (nil, nil) }
                // The preceding leg already selected a surveyed endpoint.
                // Resnapping its station can discard that vertex through the
                // visual-anchor filter or nearest-candidate limits. Start at
                // the exact node instead; only reviewed junctions (zero-length,
                // short-link ≤30 m, or osmConnector with reviewed OSM stubs ≤50 m) can
                // change identity before this section's line constraints.
                let possibleKeys = [physicalContinuationKey] + RouteGraph.nearbyNodes(
                    coordinate, in: graph, radiusDeg: 0, limit: Int.max).map(\.key)
                    .filter { $0 != physicalContinuationKey }
                fromCandidates = possibleKeys.compactMap { key in
                    guard graph.nodes[key] == coordinate,
                          let path = physicalContinuationPath(
                            from: physicalContinuationKey, to: key,
                            graph: graph, rideDate: train.rideDate) else { return nil }
                    continuationPaths[key] = path
                    let codes = graph.nodeMeta[key]?.institutionTypeCodes ?? []
                    if nodeIsExcludedInstitution(codes, excluded: Set(excludedInstitutions)) {
                        return nil
                    }
                    return StationNodeCandidate(
                        key: key, distance: 0, score: 0,
                        hasPreferredInstitution: allowedCodes.isEmpty
                            || !codes.isDisjoint(with: Set(allowedCodes)),
                        stationIndex: stationIndex)
                }
                fromAnchored = true
            }
            let toCandidates = cappedStationCandidates(
                collectStationCandidateGraphNodes(
                    stationIndices: toStations, stations: stations, graph: graph,
                    hints: hints, allowedCodes: allowedCodes,
                    hardExcludedInstitutionTypeCodes: excludedInstitutions),
                hints: hints, graph: graph)
            guard !fromCandidates.isEmpty, !toCandidates.isEmpty else { return (nil, nil) }
            let fromByKey = Dictionary(uniqueKeysWithValues: fromCandidates.map { ($0.key, $0) })
            let toByKey = Dictionary(uniqueKeysWithValues: toCandidates.map { ($0.key, $0) })
            let solved = dijkstra(
                graph: graph,
                sourceCandidates: fromCandidates.map { .init(key: $0.key, distance: $0.distance) },
                targetKeys: Set(toByKey.keys), train: train.policy,
                allowedCodes: allowedCodes, hints: hints, traversalPolicy: traversalPolicy)
            var attemptBest: Best?
            var guardedBest: Best?
            for result in solved where result.pathKeys.count >= 2 {
                guard let from = fromByKey[result.sourceKey],
                      let to = toByKey[result.targetKey],
                      let fromCoord = graph.nodes[from.key], let toCoord = graph.nodes[to.key]
                else { continue }
                let straight = Geometry.distanceMeters(fromCoord, toCoord)
                let physicalLength = pathLengthMeters(graph: graph, pathKeys: result.pathKeys)
                let detourLimit = max(straight * 3.8 + 6_000, 12_000)
                if straight > 1_500 && physicalLength > detourLimit { continue }
                let snapPenalty = (from.distance + to.distance) * stationSnapCostFactor
                let totalCost = result.cost + snapPenalty
                let scoredCost = totalCost + routeLineMismatchPenalty(
                    edges: result.edges, hints: hints)
                let prefix = continuationPaths[result.sourceKey] ?? [result.sourceKey]
                let prefixEdges = zip(prefix, prefix.dropFirst()).compactMap { from, to in
                    graph.adjacency[from]?.first {
                        $0.to == to && $0.physicalJunction != nil
                            && RouteGraph.RailValidity.isValid(
                                validFrom: $0.validFrom, validTo: $0.validTo, on: train.rideDate)
                    }
                }
                let candidate = Best(
                    pathKeys: Array(prefix.dropLast()) + result.pathKeys,
                    edges: prefixEdges + result.edges, scoredCost: scoredCost,
                    totalCost: totalCost, physicalLength: physicalLength,
                    from: from, to: to, hints: hints, attemptIndex: attemptIndex)
                if endpointIsImplausible(
                    fromStationIndex: from.stationIndex, toStationIndex: to.stationIndex,
                    fromAnchored: fromAnchored)
                {
                    if guardedBest == nil || scoredCost < guardedBest!.scoredCost {
                        guardedBest = candidate
                    }
                    continue
                }
                if attemptBest == nil || scoredCost < attemptBest!.scoredCost {
                    attemptBest = candidate
                }
            }
            return (attemptBest, guardedBest)
        }

        var best: Best?
        var guardedFallback: Best?
        let baseAttempts = buildSegmentRouteSolveAttempts(baseHints)
        for (attemptIndex, hints) in baseAttempts.enumerated() {
            let attempt = runAttempt(
                hints: hints, attemptIndex: attemptIndex, allowedCodes: allowedCodes)
            if guardedFallback == nil { guardedFallback = attempt.guarded }
            if let attemptBest = attempt.best {
                best = attemptBest
                break
            }
        }
        // Fallback for `institutionFilterMode == "soft"` legs where every
        // preferred-institution attempt either forbids the non-preferred
        // track outright or pays the institution penalty, so a physically
        // through-running leg (e.g. JR 糸魚川→魚津, which crosses third-sector
        // track sharing institution code "5" with the JR line) has no
        // surviving path within the detour guard. Retry once with the
        // institution preference dropped entirely and the default allowed
        // codes, so any real rail geometry can still be found.
        // Explicit per-section line/operator constraints are user intent and
        // survive; only the inferred hints and the institution preference
        // are dropped.
        if best == nil, train.institutionFilterMode != "hard" {
            var fallback = baseHints
            fallback.requiredLines = baseHints.explicitRequiredLines
            fallback.requiredOperators = baseHints.explicitRequiredOperators
            fallback.preferredLines = []
            fallback.preferredOperators = []
            fallback.requirePreferredInstitution = false
            fallback.solveMode = "institution_unpenalised_soft_fallback"
            let fallbackAllowedCodes = RouteGraph.defaultAllowedInstitutionTypeCodes
            let attempt = runAttempt(
                hints: fallback, attemptIndex: baseAttempts.count,
                allowedCodes: fallbackAllowedCodes)
            if guardedFallback == nil { guardedFallback = attempt.guarded }
            best = attempt.best
        }
        // Last resort: a result the endpoint guard rejected is better than
        // no route at all (see `endpointAmbiguityDistanceFactor`).
        if best == nil { best = guardedFallback }
        guard let best else { return nil }
        func fixedIdentityStationIndex(
            _ candidates: [Int], requestedCode: String?, routingIndex: Int
        ) -> Int {
            guard let requestedCode, !requestedCode.isEmpty else { return routingIndex }
            return candidates.first {
                Stations.stationCode(stations.features[$0]) == requestedCode
            } ?? routingIndex
        }
        let fromIdentityIndex = fixedIdentityStationIndex(
            fromStations, requestedCode: section.fromN02StationCode,
            routingIndex: best.from.stationIndex)
        let toIdentityIndex = fixedIdentityStationIndex(
            toStations, requestedCode: section.toN02StationCode,
            routingIndex: best.to.stationIndex)
        // A passenger-graph result is never drawable railway geometry.
        guard best.edges.allSatisfy({ $0.connector == nil }) else { return nil }
        let rawCoordinates = best.pathKeys.compactMap { graph.nodes[$0] }
        guard rawCoordinates.count == best.pathKeys.count else { return nil }
        // Only surveyed railway vertices belong in train geometry. Station
        // display points and the previous section's visual anchor can sit off
        // the track; connecting them here would invent runnable railway.
        let coordinates = rawCoordinates
        let provenance = RouteGraph.TemporalProvenance.aggregate(edges: best.edges)
        return SolvedSection(
            segmentIndex: segmentIndex,
            fromStationIndex: fromIdentityIndex,
            toStationIndex: toIdentityIndex,
            coordinates: coordinates,
            rawPathKeys: best.pathKeys,
            hints: best.hints,
            allowedInstitutionTypeCodes: allowedCodes,
            usedInstitutionTypeCodes: usedInstitutionTypeCodes(edges: best.edges),
            snapFrom: best.from.distance, snapTo: best.to.distance,
            physicalLength: pathLength(for: coordinates),
            rawPhysicalLength: best.physicalLength,
            cost: best.totalCost, attemptIndex: best.attemptIndex,
            historyIDs: provenance.historyIDs, validFrom: provenance.validFrom,
            validTo: provenance.validTo, temporalKind: provenance.temporalKind)
    }

    public static func solveSectionOnDemand(
        _ section: RouteSection,
        segmentIndex: Int,
        train: TrainContext,
        country: String,
        graphStore: RouteGraph.RouteGraphStore,
        stations: Stations.Index,
        continuityAnchor: Coordinate? = nil,
        physicalContinuationKey: String? = nil,
        traversalPolicy: TraversalPolicy = .physicalRail,
        directionNetwork: RouteNetwork? = nil
    ) -> SolvedSection? {
        guard !Task.isCancelled else { return nil }
        guard let bbox = sectionEndpointBBox(
            section, train: train, country: country, stations: stations)
        else {
            return solveSection(
                section, segmentIndex: segmentIndex, train: train, country: country,
                graph: graphStore.fullGraph(), stations: stations,
                continuityAnchor: continuityAnchor, physicalContinuationKey: physicalContinuationKey, traversalPolicy: traversalPolicy, directionNetwork: directionNetwork)
        }
        let straight = RouteGraph.bboxDiagonalMeters(bbox)
        let margins = [max(30_000, straight * 0.6), max(90_000, straight * 1.5)]
        var lastResult: SolvedSection?
        for margin in margins {
            guard !Task.isCancelled else { return nil }
            let graph = graphStore.regionalGraph(
                for: RouteGraph.padBBoxMeters(bbox, meters: margin),
                routeSolveInProgress: true)
            if let result = solveSection(
                section, segmentIndex: segmentIndex, train: train, country: country,
                graph: graph, stations: stations, continuityAnchor: continuityAnchor, physicalContinuationKey: physicalContinuationKey, traversalPolicy: traversalPolicy, directionNetwork: directionNetwork)
            {
                lastResult = result
                // A regional result is only trustworthy without checking wider
                // margins or the full graph when it came from the very first
                // (strictest) solve attempt AND it doesn't touch the region
                // edge. With ordered hint attempts, a later/looser attempt can
                // win inside a small region while the strict attempt would
                // still have won on the full graph — so a non-zero attempt
                // index has to keep widening/falling back exactly like a path
                // that touches the edge does.
                if result.attemptIndex == 0,
                   !RouteGraph.pathTouchesRegionEdge(
                    lines: [result.coordinates], regionBBox: graph.regionBBox, marginDeg: 0.02)
                {
                    return result
                }
            }
        }
        guard !Task.isCancelled else { return nil }
        return solveSection(
            section, segmentIndex: segmentIndex, train: train, country: country,
            graph: graphStore.fullGraph(), stations: stations,
            continuityAnchor: continuityAnchor, physicalContinuationKey: physicalContinuationKey, traversalPolicy: traversalPolicy, directionNetwork: directionNetwork) ?? lastResult
    }

    public static func completeRouteEndpointCoordinates(
        _ coordinates: [Coordinate],
        fromStation: Stations.Feature,
        toStation: Stations.Feature
    ) -> [Coordinate] {
        guard coordinates.count >= 2 else { return coordinates }
        let startTrimmed = trimRouteEndpointToStationDisplay(
            coordinates, station: fromStation, isStart: true)
        return trimRouteEndpointToStationDisplay(
            startTrimmed, station: toStation, isStart: false)
    }

    public static func pathLength(for coordinates: [Coordinate]) -> Double {
        guard coordinates.count >= 2 else { return 0 }
        return zip(coordinates, coordinates.dropFirst()).reduce(0) {
            $0 + Geometry.distanceMeters($1.0, $1.1)
        }
    }

    public static func edgeMatchesAllowedCodes(
        _ edge: RouteGraph.Edge,
        allowedCodes: [String],
        train: TrainPolicy,
        hints: SegmentHints = SegmentHints()
    ) -> Bool {
        if edgeUsesExcludedInstitution(
            edge, excluded: Set(train.hardExcludedInstitutionTypeCodes.filter { !$0.isEmpty }))
        {
            return false
        }
        let hardFilter = train.institutionFilterMode == "hard"
            || hints.requirePreferredInstitution
        return !hardFilter || edgeHasPreferredInstitution(edge, allowedCodes: allowedCodes)
    }

    public static func institutionPreferencePenalty(
        for edge: RouteGraph.Edge, allowedCodes: [String], train: TrainPolicy
    ) -> Double {
        if train.institutionFilterMode == "hard" { return 0 }
        return institutionPreferencePenalty(
            for: edge, preferred: Set(allowedCodes.filter { !$0.isEmpty }), train: train)
    }

    private static func institutionPreferencePenalty(
        for edge: RouteGraph.Edge, preferred: Set<String>, train: TrainPolicy
    ) -> Double {
        if train.institutionFilterMode == "hard" { return 0 }
        if preferred.isEmpty || edge.institutionTypeCode.isEmpty
            || preferred.contains(edge.institutionTypeCode)
        {
            return 0
        }
        return edge.length * nonPreferredInstitutionLengthFactor
            + nonPreferredInstitutionEdgePenalty
    }

    public static func edgeMatchesRequiredHints(
        _ edge: RouteGraph.Edge, hints: SegmentHints,
        traversalPolicy: TraversalPolicy = .physicalRail
    ) -> Bool {
        guard traversalPolicy.permits(edge) else { return false }
        if edge.connector != nil { return true }
        if let junction = edge.physicalJunction {
            return [junction.junction.from.identity, junction.junction.to.identity].allSatisfy {
                (hints.requiredLines.isEmpty || hints.requiredLines.contains($0.lineName))
                    && (hints.requiredOperators.isEmpty || hints.requiredOperators.contains($0.operatorName))
            }
        }
        if !hints.requiredLines.isEmpty && !hints.requiredLines.contains(edge.lineName) {
            return false
        }
        if !hints.requiredOperators.isEmpty
            && !hints.requiredOperators.contains(edge.operator)
        {
            return false
        }
        return true
    }

    public static func nonPreferredLineOperatorPenalty(
        for edge: RouteGraph.Edge,
        preferredLines: Set<String>,
        preferredOperators: Set<String>
    ) -> Double {
        var penalty = 0.0
        if !preferredLines.isEmpty && !edge.lineName.isEmpty
            && !preferredLines.contains(edge.lineName)
        {
            penalty += edge.length * nonPreferredLineLengthFactor
        }
        if !preferredOperators.isEmpty && !edge.operator.isEmpty
            && !preferredOperators.contains(edge.operator)
        {
            penalty += edge.length * nonPreferredOperatorLengthFactor
        }
        return penalty
    }

    public static func routeLineMismatchPenalty(
        edges: [RouteGraph.Edge], hints: SegmentHints
    ) -> Double {
        guard !hints.preferredLines.isEmpty || !hints.preferredOperators.isEmpty else {
            return 0
        }
        var penalty = 0.0
        for edge in edges where edge.connector == nil {
            penalty += nonPreferredLineOperatorPenalty(
                for: edge,
                preferredLines: hints.preferredLines,
                preferredOperators: hints.preferredOperators)
        }
        return penalty
    }

    public static func usedInstitutionTypeCodes(
        edges: [RouteGraph.Edge]
    ) -> [String] {
        var used = Set<String>()
        for edge in edges where !edge.institutionTypeCode.isEmpty {
            used.insert(edge.institutionTypeCode)
        }
        return used.sorted { Array($0.utf16).lexicographicallyPrecedes(Array($1.utf16)) }
    }

    /// JavaScript's one-run multi-source → multi-target Dijkstra.
    ///
    /// Heap comparisons intentionally use only `priority`. Equal priorities
    /// retain the exact binary-heap behaviour of the frontend rather than
    /// acquiring a Swift-specific string tiebreaker that could choose another
    /// equally cheap railway at a junction.
    public static func dijkstra(
        graph: RouteGraph.Graph,
        sourceCandidates: [Candidate],
        targetKeys: Set<String>,
        train: TrainPolicy,
        allowedCodes: [String],
        hints: SegmentHints = SegmentHints(),
        traversalPolicy: TraversalPolicy = .physicalRail
    ) -> [SolvedTarget] {
        guard !sourceCandidates.isEmpty, !targetKeys.isEmpty, !Task.isCancelled else { return [] }
        if traversalPolicy == .physicalRail,
           !sourceCandidates.contains(where: { targetKeys.contains($0.key) }) {
            guard let components = graph.physicalRailComponents() else { return [] }
            let sourceComponents = Set(sourceCandidates.compactMap { components[$0.key] })
            guard targetKeys.contains(where: { key in
                components[key].map { sourceComponents.contains($0) } ?? false
            }) else { return [] }
        }
        let preferredCodes = Set(allowedCodes.filter { !$0.isEmpty })
        let excludedInstitutions = Set(train.hardExcludedInstitutionTypeCodes.filter { !$0.isEmpty })
        let hardInstitutionFilter = train.institutionFilterMode == "hard"
            || hints.requirePreferredInstitution
        let requiresPhysicalRail = !hints.requiredLines.isEmpty
            || !hints.requiredOperators.isEmpty
        var distance: [DijkstraState: Double] = [:]
        var previous: [DijkstraState: DijkstraState] = [:]
        // Index into `graph.adjacency[current.state.key]` rather than a copy of the
        // `Edge` itself — resolved back to an `Edge` in
        // `reconstructPathEdges`, using `previous` for the adjacency list's
        // key. Avoids copying the `Edge` struct on every relaxation.
        var previousEdgeIndex: [DijkstraState: Int] = [:]
        var sourceOf: [DijkstraState: DijkstraState] = [:]
        var seedCost: [DijkstraState: Double] = [:]
        var heap = MinHeap()

        for candidate in sourceCandidates {
            let initial = candidate.distance * stationSnapCostFactor
            let state = DijkstraState(
                key: candidate.key, usedRequiredRail: !requiresPhysicalRail)
            if initial < (distance[state] ?? .infinity) {
                distance[state] = initial
                sourceOf[state] = state
                seedCost[state] = initial
                heap.push(Item(state: state, priority: initial))
            }
        }

        var visited = Set<DijkstraState>()
        var remaining = targetKeys
        var settled: [(targetState: DijkstraState, settledCost: Double)] = []
        var iterations = 0

        // ADR 0011: shape-check the ride date once, not per edge.
        let rideDate: String? = train.rideDate.flatMap { RouteGraph.isPlainISODay($0) ? $0 : nil }
        while !heap.isEmpty && !remaining.isEmpty {
            if iterations & 255 == 0, Task.isCancelled { return [] }
            iterations += 1
            guard let current = heap.pop() else { break }
            guard visited.insert(current.state).inserted else { continue }
            if current.state.usedRequiredRail,
               remaining.remove(current.state.key) != nil
            {
                settled.append((current.state, current.priority))
            }
            for (edgeIndex, edge) in (graph.adjacency[current.state.key] ?? []).enumerated() {
                guard traversalPolicy.permits(edge),
                    !edgeUsesExcludedInstitution(edge, excluded: excludedInstitutions),
                    directionPermits(edge, hints: hints, graph: graph),
                    !hardInstitutionFilter
                    || edgeHasPreferredInstitution(edge, allowed: preferredCodes),
                    edgeMatchesRequiredHints(edge, hints: hints, traversalPolicy: traversalPolicy),
                    RouteGraph.RailValidity.isValid(
                        validFrom: edge.validFrom, validTo: edge.validTo, onPlainDay: rideDate)
                else { continue }

                var weight = edge.length
                if edge.connector == nil && edge.physicalJunction == nil {
                    weight += institutionPreferencePenalty(
                        for: edge, preferred: preferredCodes, train: train)
                    weight += nonPreferredLineOperatorPenalty(
                        for: edge,
                        preferredLines: hints.preferredLines,
                        preferredOperators: hints.preferredOperators)
                }
                let nextCost = current.priority + weight
                let nextState = DijkstraState(
                    key: edge.to,
                    usedRequiredRail: current.state.usedRequiredRail || (edge.connector == nil && edge.physicalJunction == nil))
                if nextCost < (distance[nextState] ?? .infinity) {
                    distance[nextState] = nextCost
                    previous[nextState] = current.state
                    previousEdgeIndex[nextState] = edgeIndex
                    sourceOf[nextState] = sourceOf[current.state]
                    heap.push(Item(state: nextState, priority: nextCost))
                }
            }
        }

        return settled.compactMap { entry in
            guard let sourceState = sourceOf[entry.targetState] else { return nil }
            return SolvedTarget(
                targetKey: entry.targetState.key,
                sourceKey: sourceState.key,
                cost: entry.settledCost - (seedCost[sourceState] ?? 0),
                pathKeys: reconstructPath(
                    previous: previous, sourceState: sourceState,
                    targetState: entry.targetState),
                edges: reconstructPathEdges(
                    graph: graph, previous: previous, previousEdgeIndex: previousEdgeIndex,
                    sourceState: sourceState, targetState: entry.targetState))
        }
    }

    public static func pathLengthMeters(
        graph: RouteGraph.Graph, pathKeys: [String]
    ) -> Double {
        guard pathKeys.count >= 2 else { return 0 }
        var length = 0.0
        for index in 0..<(pathKeys.count - 1) {
            guard let a = graph.nodes[pathKeys[index]],
                  let b = graph.nodes[pathKeys[index + 1]] else { continue }
            length += Geometry.distanceMeters(a, b)
        }
        return length
    }

    private static func sectionEndpointBBox(
        _ rawSection: RouteSection,
        train: TrainContext,
        country: String,
        stations: Stations.Index
    ) -> RouteGraph.BBox? {
        var section = rawSection
        if section.from?.isEmpty != false {
            section.from = stations.name(forCode: section.fromN02StationCode)
        }
        if section.to?.isEmpty != false {
            section.to = stations.name(forCode: section.toN02StationCode)
        }
        let cacheTrain = RouteGraph.CacheKeyTrain(
            trainType: train.trainType, company: train.company,
            preferredLineNames: train.preferredLineNames,
            preferredOperatorNames: train.preferredOperatorNames,
            allowedInstitutionTypeCodes: train.allowedInstitutionTypeCodes,
            institutionFilterMode: train.institutionFilterMode)
        let allowed = RouteGraph.allowedInstitutionTypeCodes(cacheTrain, country: country)
        let lines = (section.lineNames ?? []).filter { !$0.isEmpty }
        let from = filterStationCandidatesByRideDate(
            resolveRouteEndpointStationCandidates(
                .stop(.init(name: section.from, n02StationCode: section.fromN02StationCode)),
                in: stations, allowedCodes: allowed, sectionLineNames: lines,
                sectionOperatorNames: section.operatorNames ?? [], rideDate: train.rideDate),
            in: stations, rideDate: train.rideDate)
        let to = filterStationCandidatesByRideDate(
            resolveRouteEndpointStationCandidates(
                .stop(.init(name: section.to, n02StationCode: section.toN02StationCode)),
                in: stations, allowedCodes: allowed, sectionLineNames: lines,
                sectionOperatorNames: section.operatorNames ?? [], rideDate: train.rideDate),
            in: stations, rideDate: train.rideDate)
        let coordinates = (from + to).compactMap {
            coordinate(Stations.displayCoordinate(stations.features[$0]))
        }
        guard let first = coordinates.first else { return nil }
        return coordinates.dropFirst().reduce(
            RouteGraph.BBox(minX: first.lon, minY: first.lat, maxX: first.lon, maxY: first.lat)
        ) { box, coordinate in
            RouteGraph.BBox(
                minX: min(box.minX, coordinate.lon), minY: min(box.minY, coordinate.lat),
                maxX: max(box.maxX, coordinate.lon), maxY: max(box.maxY, coordinate.lat))
        }
    }

    private static func trimRouteEndpointToStationDisplay(
        _ coordinates: [Coordinate], station: Stations.Feature, isStart: Bool
    ) -> [Coordinate] {
        guard coordinates.count >= 2,
              let display = coordinate(Stations.displayCoordinate(station)) else {
            return coordinates
        }
        let endpoint = isStart ? coordinates[0] : coordinates[coordinates.count - 1]
        if coordinatesClose(display, endpoint, toleranceMeters: 1.5) { return coordinates }

        let searchLimit = min(12, coordinates.count - 1)
        let firstSegment = isStart ? 0 : max(0, coordinates.count - 1 - searchLimit)
        let lastSegment = isStart ? searchLimit - 1 : coordinates.count - 2
        var best: (distance: Double, t: Double, index: Int)?
        if firstSegment <= lastSegment {
            for index in firstSegment...lastSegment {
                let projected = projectPointToSegmentMeters(
                    display, coordinates[index], coordinates[index + 1])
                if projected.t < -0.02 || projected.t > 1.02 { continue }
                if best == nil || projected.distance < best!.distance {
                    best = (projected.distance, projected.t, index)
                }
            }
        }
        if let best, best.distance <= 45 {
            if isStart {
                let tail = Array(coordinates[(best.index + 1)...])
                if let first = tail.first,
                   coordinatesClose(display, first, toleranceMeters: 1.5) { return tail }
                return [display] + tail
            }
            let head = Array(coordinates[...best.index])
            if let last = head.last,
               coordinatesClose(last, display, toleranceMeters: 1.5) { return head }
            return head + [display]
        }
        if Geometry.distanceMeters(display, endpoint) <= stationSnapMaxDistanceMeters {
            return isStart ? [display] + coordinates : coordinates + [display]
        }
        return coordinates
    }

    private static func coordinatesClose(
        _ a: Coordinate, _ b: Coordinate, toleranceMeters: Double = 1.5
    ) -> Bool {
        Geometry.distanceMeters(a, b) <= toleranceMeters
    }

    private static func projectPointToSegmentMeters(
        _ point: Coordinate, _ a: Coordinate, _ b: Coordinate
    ) -> (distance: Double, t: Double) {
        let latitude = ((point.lat + a.lat + b.lat) / 3) * .pi / 180
        let metresPerLongitude = 111_320.0 * JSMath.cos(latitude)
        let metresPerLatitude = 110_540.0
        let px = point.lon * metresPerLongitude
        let py = point.lat * metresPerLatitude
        let ax = a.lon * metresPerLongitude
        let ay = a.lat * metresPerLatitude
        let bx = b.lon * metresPerLongitude
        let by = b.lat * metresPerLatitude
        let dx = bx - ax
        let dy = by - ay
        let denominator = dx * dx + dy * dy
        let t = denominator > 0 ? ((px - ax) * dx + (py - ay) * dy) / denominator : 0
        let clamped = max(0, min(1, t))
        let qx = ax + clamped * dx
        let qy = ay + clamped * dy
        return (JSMath.hypot(px - qx, py - qy), t)
    }

    private static func edgeUsesExcludedInstitution(
        _ edge: RouteGraph.Edge, excluded: Set<String>
    ) -> Bool {
        if excluded.isEmpty || edge.connector != nil { return false }
        if let junction = edge.physicalJunction {
            return junction.institutionTypeCodes.contains { excluded.contains($0) }
        }
        return excluded.contains(edge.institutionTypeCode)
    }

    private static func nodeIsExcludedInstitution(
        _ codes: Set<String>, excluded: Set<String>
    ) -> Bool {
        !excluded.isEmpty && !codes.isEmpty && codes.allSatisfy(excluded.contains)
    }

    private static func graphNodeHasPreferredInstitution(
        _ meta: RouteGraph.NodeMeta, preferred: Set<String>
    ) -> Bool {
        if preferred.isEmpty { return true }
        return RouteGraph.intersects(meta.institutionTypeCodes, preferred)
    }

    private static func preferredStationPool(
        _ indices: [Int], stations: Stations.Index, allowedCodes: [String]
    ) -> [Int] {
        let preferred = filterStationsByPreferredInstitution(
            indices, in: stations, allowedCodes: allowedCodes)
        return preferred.isEmpty ? indices : preferred
    }

    private static func stationSet(
        _ indices: [Int], stations: Stations.Index,
        getter: (Stations.Feature) -> String
    ) -> Set<String> {
        Set(indices.map { getter(stations.features[$0]) }.filter { !$0.isEmpty && $0 != "-" })
    }

    /// Stations on the 日豊線 corridor east of 小倉 that ソニック actually uses
    /// 日豊線 for. West of 小倉 (e.g. 黒崎, 戸畑, 博多) the train runs on 鹿児島線.
    private static let sonicNippoCorridorStations: Set<String> = [
        "小倉", "西小倉", "城野", "行橋", "苅田", "宇佐", "中津", "柳ヶ浦", "杵築",
        "亀川", "別府", "大分", "鶴崎", "大在", "幸崎", "臼杵", "津久見", "佐伯",
    ]

    private static func sectionEndpointNames(_ section: RouteSection) -> [String] {
        [normalizeRouteHintText(section.from ?? ""), normalizeRouteHintText(section.to ?? "")]
            .filter { !$0.isEmpty }
    }

    private static func sectionHasAnyEndpoint(_ section: RouteSection, names: Set<String>) -> Bool {
        sectionEndpointNames(section).contains { names.contains($0) }
    }

    private static func sectionHasEndpointPair(
        _ section: RouteSection, _ a: Set<String>, _ b: Set<String>
    ) -> Bool {
        let endpoints = sectionEndpointNames(section)
        return endpoints.contains { a.contains($0) } && endpoints.contains { b.contains($0) }
    }

    private static func asciiCaseInsensitiveContains(_ text: String, _ needle: String) -> Bool {
        text.lowercased().contains(needle.lowercased())
    }

    /// ECMAScript `String(value || "").trim()` for route hint fields.
    private static func normalizeRouteHintText(_ text: String) -> String {
        let units = Array(text.utf16)
        var start = 0
        var end = units.count
        while start < end, isJSTrimUnit(units[start]) { start += 1 }
        while end > start, isJSTrimUnit(units[end - 1]) { end -= 1 }
        return String(decoding: units[start..<end], as: UTF16.self)
    }

    private static func normalizedHintValues(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let normalized = normalizeRouteHintText(value)
            if !normalized.isEmpty, seen.insert(normalized).inserted {
                result.append(normalized)
            }
        }
        return result
    }

    private static func officialIntervalKey(
        line: String, operatorName: String, from: Coordinate, to: Coordinate
    ) -> String {
        guard !line.isEmpty, !operatorName.isEmpty else { return "" }
        let locale = Locale(identifier: "en_US_POSIX")
        func fixed(_ coordinate: Coordinate) -> String {
            String(format: "%.6f,%.6f", locale: locale, coordinate.lon, coordinate.lat)
        }
        return "\(line)\u{001F}\(operatorName)\u{001F}\(fixed(from))\u{001F}\(fixed(to))"
    }

    private static func isJSTrimUnit(_ value: UInt16) -> Bool {
        switch value {
        case 0x0009...0x000D, 0x0020, 0x00A0, 0x1680, 0x2000...0x200A,
             0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF:
            return true
        default:
            return false
        }
    }

    private static func jsSorted<S: Sequence>(_ values: S) -> [String]
    where S.Element == String {
        values.sorted { Array($0.utf16).lexicographicallyPrecedes(Array($1.utf16)) }
    }

    private static func dedupeStationIndices(
        _ indices: [Int], in index: Stations.Index
    ) -> [Int] {
        let features = indices.map { index.features[$0] }
        return Stations.dedupeStationFeatureIndices(features).map { indices[$0] }
    }

    private static func coordinate(_ pair: [Double]?) -> Coordinate? {
        pair.flatMap(Coordinate.init(pair:))
    }

    /// `iterateGeometryLines(feature.geometry)`, falling back to the display
    /// point only when the station has no path geometry.
    private static func stationGeometryCoordinates(_ feature: Stations.Feature) -> [Coordinate] {
        var lines: [[Coordinate]] = []
        if let geometry = feature.geometry,
           case .array(let outer)? = geometry.coordinates
        {
            switch geometry.type {
            case "LineString":
                let line = outer.compactMap(position)
                if !line.isEmpty { lines.append(line) }
            case "MultiLineString":
                for value in outer {
                    guard case .array(let rawLine) = value else { continue }
                    let line = rawLine.compactMap(position)
                    if !line.isEmpty { lines.append(line) }
                }
            default:
                break
            }
        }
        if !lines.isEmpty { return lines.flatMap { $0 } }
        return coordinate(Stations.displayCoordinate(feature)).map { [$0] } ?? []
    }

    private static func position(_ value: Stations.Value) -> Coordinate? {
        guard case .array(let values) = value, values.count >= 2,
              case .number(let lon) = values[0], case .number(let lat) = values[1]
        else { return nil }
        return Coordinate(lon: lon, lat: lat)
    }

    private static func reconstructPath(
        previous: [DijkstraState: DijkstraState],
        sourceState: DijkstraState, targetState: DijkstraState
    ) -> [String] {
        var path = [targetState.key]
        var current = targetState
        while current != sourceState {
            guard let prior = previous[current] else { return [] }
            current = prior
            path.append(current.key)
        }
        return path.reversed()
    }

    /// Same walk as `reconstructPath`, but yields the edge relaxed onto each
    /// node instead of the node key. `edges[i]` is the edge from
    /// `pathKeys[i]` to `pathKeys[i + 1]`.
    private static func reconstructPathEdges(
        graph: RouteGraph.Graph,
        previous: [DijkstraState: DijkstraState],
        previousEdgeIndex: [DijkstraState: Int],
        sourceState: DijkstraState, targetState: DijkstraState
    ) -> [RouteGraph.Edge] {
        var edges: [RouteGraph.Edge] = []
        var current = targetState
        while current != sourceState {
            guard let index = previousEdgeIndex[current], let prior = previous[current],
                  let adjacent = graph.adjacency[prior.key], index >= 0, index < adjacent.count
            else { return [] }
            edges.append(adjacent[index])
            current = prior
        }
        return edges.reversed()
    }

    private struct DijkstraState: Hashable {
        var key: String
        var usedRequiredRail: Bool
    }

    private struct Item {
        var state: DijkstraState
        var priority: Double
    }

    private struct MinHeap {
        private var items: [Item] = []
        var isEmpty: Bool { items.isEmpty }

        mutating func push(_ item: Item) {
            items.append(item)
            bubbleUp(items.count - 1)
        }

        mutating func pop() -> Item? {
            guard !items.isEmpty else { return nil }
            if items.count == 1 { return items.removeLast() }
            let top = items[0]
            items[0] = items.removeLast()
            bubbleDown(0)
            return top
        }

        private mutating func bubbleUp(_ start: Int) {
            var index = start
            while index > 0 {
                let parent = (index - 1) / 2
                if items[parent].priority <= items[index].priority { break }
                items.swapAt(parent, index)
                index = parent
            }
        }

        private mutating func bubbleDown(_ start: Int) {
            var index = start
            while true {
                let left = index * 2 + 1
                let right = left + 1
                var smallest = index
                if left < items.count && items[left].priority < items[smallest].priority {
                    smallest = left
                }
                if right < items.count && items[right].priority < items[smallest].priority {
                    smallest = right
                }
                if smallest == index { break }
                items.swapAt(smallest, index)
                index = smallest
            }
        }
    }
}
