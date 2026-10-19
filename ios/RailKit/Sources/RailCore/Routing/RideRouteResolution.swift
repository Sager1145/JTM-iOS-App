import Foundation

/// One worker owns the complete physical-route policy for each recorded ride.
/// Source/drawn coordinates are WGS84; native datum conversion and publication
/// remain with the caller. Mutable graphs never cross this synchronous seam.
public struct RideRouteResolution {
    /// One immutable data snapshot; its bounded memo and lazy interval index
    /// are shared by workers, while each worker owns its mutable graph.
    public struct SourceInputs: Sendable {
        public let snapshotID = UUID()
        public let sections: [RouteGraph.SectionFeature]
        public let stationCollection: Stations.FeatureCollection
        public let stationIndex: Stations.Index
        public let physicalJunctions: [RouteGraph.PhysicalJunction]
        public let identityPeriods: [RailHistoryOverlay.IdentityPeriod]
        public let officialIntervals: OfficialIntervals
        let resolutionMemo = RouteResolutionMemo()

        public init(sections: [RouteGraph.SectionFeature], stationCollection: Stations.FeatureCollection,
                    physicalJunctions: [RouteGraph.PhysicalJunction] = [],
                    identityPeriods: [RailHistoryOverlay.IdentityPeriod] = []) {
            self.sections = sections
            self.stationCollection = stationCollection
            stationIndex = Stations.Index(stationCollection)
            self.physicalJunctions = physicalJunctions
            self.identityPeriods = identityPeriods
            officialIntervals = OfficialIntervals(sections: sections)
        }
    }

    /// The app may retain this owner in its bounded revision-keyed cache.
    /// Merely retaining it never builds the legacy index. All mutable state
    /// is protected by the lock; no mutable graph or operation is retained.
    public final class OfficialIntervals: @unchecked Sendable {
        private let lock = NSLock()
        private let sections: [RouteGraph.SectionFeature]
        private var ready: RouteSolver.OfficialIntervalIndex?
        fileprivate init(sections: [RouteGraph.SectionFeature]) { self.sections = sections }
        fileprivate func value() -> RouteSolver.OfficialIntervalIndex {
            lock.lock()
            defer { lock.unlock() }
            if let ready { return ready }
            let made = RouteSolver.OfficialIntervalIndex(sections: sections)
            ready = made
            return made
        }
    }

    public struct NetworkInputs: Sendable {
        let network: RouteNetwork
        let eligibility: StationRouteEligibility
        let resolver: StationIntervalResolver
        public init(network: RouteNetwork, inputs: SourceInputs) {
            self.network = network
            eligibility = StationRouteEligibility(network: network, sections: inputs.sections,
                stations: inputs.stationCollection.features)
            resolver = StationIntervalResolver(network: network)
        }
    }

    public struct Request: Sendable {
        public let train: Train
        public let canonicalTrain: Train
        public let databaseSections: Set<Int>
        public let databaseProvenance: TimetablePhysicalRouteMatch.Provenance?
        public init(train: Train, canonicalTrain: Train? = nil, databaseSections: Set<Int> = [],
                    databaseProvenance: TimetablePhysicalRouteMatch.Provenance? = nil) {
            self.train = train
            self.canonicalTrain = canonicalTrain ?? train
            self.databaseSections = databaseSections
            self.databaseProvenance = databaseProvenance
        }
    }

    public struct PhysicalRouteSelection: Codable, Equatable, Sendable {
        public enum Provenance: String, Codable, Sendable {
            case explicit, database, stationSequence, corridorPreference, matchedGeometry
        }
        public let fromStationCode: String
        public let toStationCode: String
        public let intervals: [StationIntervalResolver.DirectedInterval]
        public let lines: [ResolvedRailLine]
        public let provenance: Provenance
        public var databaseProvenance: TimetablePhysicalRouteMatch.Provenance? = nil
    }

    public struct PhysicalGap: Codable, Equatable, Sendable {
        public let segmentIndex: Int
        /// True marks a missing connection before an independently drawn leg.
        public let isBoundary: Bool
    }

    public struct Segment: Sendable {
        public let segmentIndex: Int
        public let partIndex: Int
        public let from: String?
        public let to: String?
        public let sourceCoordinates: [Coordinate]
        public let drawnCoordinates: [Coordinate]
        public let country: String
        public let historyIDs: [String]
        public let validFrom: String?
        public let validTo: String?
        public let temporalKind: RouteGraph.TemporalKind
        public let physicalRoute: PhysicalRouteSelection?

        init(segmentIndex: Int, partIndex: Int = 0, from: String?, to: String?,
             coordinates: [Coordinate], sourceCoordinates: [Coordinate]? = nil,
             country: String, historyIDs: [String] = [], validFrom: String? = nil,
             validTo: String? = nil, temporalKind: RouteGraph.TemporalKind = .current,
             physicalRoute: PhysicalRouteSelection? = nil) {
            self.segmentIndex = segmentIndex; self.partIndex = partIndex
            self.from = from; self.to = to
            self.sourceCoordinates = sourceCoordinates ?? coordinates
            drawnCoordinates = coordinates; self.country = country
            self.historyIDs = historyIDs; self.validFrom = validFrom; self.validTo = validTo
            self.temporalKind = temporalKind; self.physicalRoute = physicalRoute
        }
    }

    public struct Result: Sendable {
        public enum Disposition: Equatable, Sendable {
            case geometry, unavailable, unsupported, awaitingConfirmation, noSections
        }
        public let disposition: Disposition
        public let segments: [Segment]
        public let physicalGaps: [PhysicalGap]
        public let expectedSections: [RouteSection]
        public let requiresPrecomputedRejection: Bool
        /// Dated, certified source path per recorded section. Keys refer to
        /// this source snapshot's physical graph; they are inspection evidence,
        /// not persisted identities or drawing vertices. Missing means unproved.
        public let sourcePhysicalPathKeys: [Int: [String]]

        init(disposition: Disposition, segments: [Segment], physicalGaps: [PhysicalGap],
             expectedSections: [RouteSection], requiresPrecomputedRejection: Bool,
             sourcePhysicalPathKeys: [Int: [String]] = [:]) {
            self.disposition = disposition; self.segments = segments
            self.physicalGaps = physicalGaps; self.expectedSections = expectedSections
            self.requiresPrecomputedRejection = requiresPrecomputedRejection
            self.sourcePhysicalPathKeys = sourcePhysicalPathKeys
        }
    }

    private let inputs: SourceInputs
    private let country: String
    private let network: NetworkInputs?
    private let intervalSource: OfficialIntervals
    private var graph: RouteGraph.RouteGraphStore?

    public init(inputs: SourceInputs, country: String, network: NetworkInputs? = nil,
                officialIntervals: OfficialIntervals? = nil,
                graphStore: RouteGraph.RouteGraphStore? = nil) {
        self.inputs = inputs; self.country = country; self.network = network
        intervalSource = officialIntervals ?? inputs.officialIntervals
        graph = graphStore
    }

    /// Cache admission uses the same station-choice policy as resolution.
    public func hasAmbiguousStationChoice(_ request: Request) -> Bool {
        let context = Self.routeContext(request.train)
        let key = RouteGraph.CacheKeyTrain(trainType: context.trainType, company: context.company,
            allowedInstitutionTypeCodes: context.allowedInstitutionTypeCodes,
            institutionFilterMode: context.institutionFilterMode)
        return !RouteSolver.inferStationSections(
            request.canonicalTrain.requiresRouteConfirmation ? [] : request.canonicalTrain.routeSections ?? [],
            resolver: network?.resolver, network: network?.network, eligibility: network?.eligibility,
            allowedCodes: RouteGraph.allowedInstitutionTypeCodes(key, country: country),
            hard: context.institutionFilterMode == "hard", country: country).ambiguous.isEmpty
    }

    public mutating func resolve(_ request: Request, allowLegacy: Bool = true) throws -> Result {
        try Task.checkCancellation()
        guard !request.train.requiresRouteConfirmation else {
            return Result(disposition: .awaitingConfirmation, segments: [], physicalGaps: [],
                expectedSections: [], requiresPrecomputedRejection: false)
        }
        let sections = request.canonicalTrain.requiresRouteConfirmation ? [] : request.canonicalTrain.routeSections ?? []
        guard !sections.isEmpty else {
            return Result(disposition: .noSections, segments: [], physicalGaps: [],
                expectedSections: [], requiresPrecomputedRejection: false)
        }
        let stationIndex = inputs.stationIndex
        let displayNetwork = network?.network
        let eligibility = network?.eligibility
        let intervalResolver = network?.resolver
        var officialIntervals: RouteSolver.OfficialIntervalIndex?
        var graphStore = graph
        defer { graph = graphStore }
        var context = Self.routeContext(request.train)
        context.rideDate = Dates.normalizeDateString(request.canonicalTrain.date)
        let cacheTrain = RouteGraph.CacheKeyTrain(
            trainType: context.trainType, company: context.company,
            preferredLineNames: context.preferredLineNames,
            preferredOperatorNames: context.preferredOperatorNames,
            allowedInstitutionTypeCodes: context.allowedInstitutionTypeCodes,
            institutionFilterMode: context.institutionFilterMode)
        let allowedCodes = RouteGraph.allowedInstitutionTypeCodes(
            cacheTrain, country: country)
        let inferred = RouteSolver.inferStationSections(
            sections, resolver: intervalResolver, network: displayNetwork, eligibility: eligibility,
            allowedCodes: allowedCodes, hard: context.institutionFilterMode == "hard",
            country: country)
        let rejectPrecomputed = !allowLegacy && !inferred.ambiguous.isEmpty
        var segments: [Segment] = []
        var unsupported = false
        var lastSolvedIndex: Int?
        var physicalContinuationKey: String?
        var physicalGaps: [PhysicalGap] = []
        var continuity: Coordinate?
        var displayContinuity: Coordinate?
        var projectionCache = RouteProjectionCache()
        var sourcePhysicalPathKeys: [Int: [String]] = [:]
        for (index, materializedSection) in sections.enumerated() {
            var section = materializedSection
            let recordedSection = request.train.routeSections.flatMap { $0.indices.contains(index) ? $0[index] : nil }
            let origin = RecordedRouteAdmission.materializedOrigin(section: section, recorded: recordedSection,
                database: request.databaseSections.contains(index), stationInferred: inferred.hints[index] != nil)
            try Task.checkCancellation()
            let sharesBoundary = index > 0
                && lastSolvedIndex == index - 1
                && RouteSolver.routeSectionBoundarySharesExplicitStop(sections[index - 1], section)
            let anchor = sharesBoundary ? continuity : nil
            let previousPhysicalKey = sharesBoundary ? physicalContinuationKey : nil
            if inferred.ambiguous.contains(index) {
                continuity = nil
                displayContinuity = nil
                lastSolvedIndex = nil
                physicalContinuationKey = nil
                continue
            }
            if section.sectionCodes?.isEmpty == false || inferred.hints[index] != nil {
                // Selected physical intervals already define the path.
                // The N02 graph uses older railway names for the Tokyo
                // tunnel, so solving by those names first can discard a
                // perfectly valid ordinary Sobu/Yokosuka choice or return
                // the parallel surface railway. Resolve identity first.
                var hints = inferred.hints[index] ?? RouteHints(
                    requiredLineIDs: section.lineIDs ?? [],
                    sectionCodes: section.sectionCodes ?? [],
                    fromStationCode: section.fromN02StationCode,
                    toStationCode: section.toN02StationCode)
                hints.fromStationCode = SolverRegistryInput.hintedGraphStationCode(
                    stationID: section.fromStationID, rawCode: hints.fromStationCode,
                    region: country, eligibility: eligibility)
                hints.toStationCode = SolverRegistryInput.hintedGraphStationCode(
                    stationID: section.toStationID, rawCode: hints.toStationCode,
                    region: country, eligibility: eligibility)
                if let certified = displayNetwork?.sourceCertification(for: hints),
                   let exact = displayNetwork?.canonicalizeRouteFeature(
                    RouteFeature(geometry: nil, hints: hints),
                    continueFrom: sharesBoundary ? displayContinuity : nil,
                    cache: &projectionCache),
                   certified.geometry.lines.count == exact.geometry.lines.count,
                   var selection = Self.physicalSelection(
                    hints: hints, network: displayNetwork,
                    provenance: origin == .database ? .database :
                        (origin == .corridorPreference ? .corridorPreference :
                         (origin == .authored ? .explicit : .stationSequence))) {
                    if selection.provenance == .database { selection.databaseProvenance = request.databaseProvenance }
                    let source = certified.geometry
                    if graphStore == nil {
                        graphStore = Self.graphStore(inputs)
                    }
                    let graph = Self.physicalProofGraph(coordinates: source.lines.flatMap { $0 }, store: graphStore!)
                    let recordedKeys = try Self.verifiedSourcePath(
                        source.lines, graph: graph, context: context, section: section,
                        displayRowNames: certified.rowNames, anchorIndices: certified.anchorIndices,
                        selectedLineIDs: certified.selectedLineIDs, memo: inputs.resolutionMemo)
                    let verified = recordedKeys != nil
                    if let recordedKeys { sourcePhysicalPathKeys[index] = recordedKeys }
                    if !verified {
                        physicalGaps.append(PhysicalGap(segmentIndex: index, isBoundary: false))
                    }
                    if sharesBoundary,
                       RouteSolver.provenBoundaryContinuation(
                           previous: physicalContinuationKey, first: recordedKeys?.first,
                           previousSection: sections[index - 1], nextSection: section,
                           graph: graph, stations: stationIndex, rideDate: context.rideDate) == nil,
                       !physicalGaps.contains(where: { $0.segmentIndex == index && $0.isBoundary }) {
                        physicalGaps.append(PhysicalGap(segmentIndex: index, isBoundary: true))
                    }
                    physicalContinuationKey = recordedKeys?.last
                    for (partIndex, coordinates) in exact.geometry.lines.enumerated() {
                        segments.append(Segment(
                            segmentIndex: index, partIndex: partIndex,
                            from: section.from ?? stationIndex.name(forCode: section.fromN02StationCode),
                            to: section.to ?? stationIndex.name(forCode: section.toN02StationCode),
                            coordinates: coordinates, sourceCoordinates: source.lines[partIndex],
                            country: country, physicalRoute: selection))
                    }
                    lastSolvedIndex = index
                    continuity = source.lines.last?.last
                    displayContinuity = exact.geometry.lines.last?.last
                    continue
                }
                continuity = nil
                displayContinuity = nil
                lastSolvedIndex = nil
                physicalContinuationKey = nil
                // An authored physical choice must not silently change.
                // A failed inferred materialization may use the dated solver.
                if !origin.permitsFallback { continue }
                // Failed machine materialization does not retain a hard interval
                // choice. Keep the passenger's original constraints when present.
                if let recordedSection, recordedSection.sectionCodes?.isEmpty != false {
                    section = recordedSection
                } else {
                    section.sectionCodes = nil
                    section.sectionCodesOrigin = nil
                }
                unsupported = true
            }
            if !allowLegacy { unsupported = true; continue }
            if graphStore == nil {
                graphStore = Self.graphStore(inputs)
            }
            if officialIntervals == nil {
                officialIntervals = intervalSource.value()
            }
            var solved = try inputs.resolutionMemo.solve(section: section, segmentIndex: index,
                context: context, country: country, stations: stationIndex,
                continuityAnchor: anchor, physicalContinuationKey: previousPhysicalKey) {
                RouteSolver.solveOfficialInterval(
                section, segmentIndex: index, train: context, country: country,
                allowedCodes: allowedCodes, intervalIndex: officialIntervals!,
                stations: stationIndex, continuityAnchor: anchor)
                ?? RouteSolver.solveSectionOnDemand(
                    section, segmentIndex: index, train: context, country: country,
                    graphStore: graphStore!, stations: stationIndex,
                    continuityAnchor: anchor,
                    physicalContinuationKey: sharesBoundary ? physicalContinuationKey : nil,
                    traversalPolicy: .physicalRail, directionNetwork: displayNetwork)
            }
            if solved == nil, sharesBoundary {
                // Keep independently proven sections visible. Failure to
                // continue cannot certify a connected through journey.
                solved = RouteSolver.solveSectionOnDemand(
                    section, segmentIndex: index, train: context, country: country,
                    graphStore: graphStore!, stations: stationIndex, traversalPolicy: .physicalRail,
                    directionNetwork: displayNetwork)
            }
            try Task.checkCancellation()
            if var solved, solved.coordinates.count >= 2 {
                if solved.rawPathKeys.first?.contains("@") != true {
                    solved.rawPathKeys = RouteSolver.verifiedPhysicalPathKeys(
                        solved.coordinates, graph: Self.physicalProofGraph(coordinates: solved.coordinates, store: graphStore!), rideDate: context.rideDate,
                        requiredLines: Set(section.lineNames ?? []),
                        requiredOperators: Set(section.operatorNames ?? [])) ?? []
                }
                if solved.rawPathKeys.isEmpty {
                    physicalGaps.append(PhysicalGap(segmentIndex: index, isBoundary: false))
                }
                if sharesBoundary,
                   RouteSolver.provenBoundaryContinuation(
                       previous: physicalContinuationKey, first: solved.rawPathKeys.first,
                       previousSection: sections[index - 1], nextSection: section,
                       graph: Self.physicalProofGraph(coordinates: [solved.coordinates[0]], store: graphStore!),
                       stations: stationIndex, rideDate: context.rideDate) == nil,
                   !physicalGaps.contains(where: { $0.segmentIndex == index && $0.isBoundary }) {
                    physicalGaps.append(PhysicalGap(segmentIndex: index, isBoundary: true))
                }
                physicalContinuationKey = solved.rawPathKeys.last
                if !solved.rawPathKeys.isEmpty { sourcePhysicalPathKeys[index] = solved.rawPathKeys }

                let hints = RouteHints(
                    requiredLineNames: (section.lineNames ?? []).map(Optional.some),
                    preferredLineNames: context.preferredLineNames.map(Optional.some),
                    requiredOperatorNames: (section.operatorNames ?? []).map(Optional.some),
                    preferredOperatorNames: context.preferredOperatorNames.map(Optional.some),
                    requiredLineIDs: section.lineIDs ?? [],
                    sectionCodes: section.sectionCodes ?? [],
                    fromStationCode: section.fromN02StationCode,
                    toStationCode: section.toN02StationCode)
                // Historical and relocated geometry is not on the current
                // display network. Canonicalizing it would pull the stroke
                // onto today's alignment.
                var canonical = RouteGraph.TemporalKind.shouldCanonicalizeDisplayNetwork(
                    solved.temporalKind)
                    ? displayNetwork?.canonicalizeRouteFeature(
                        RouteFeature(
                            geometry: .lineString(solved.coordinates), hints: hints),
                        continueFrom: sharesBoundary ? displayContinuity : nil,
                        cache: &projectionCache)
                    : nil
                if let candidate = canonical,
                   !canonicalMatchesSourcePath(candidate, rawPathKeys: solved.rawPathKeys,
                                               network: displayNetwork) {
                    canonical = nil
                }
                let drawnParts = canonical?.geometry.lines ?? [solved.coordinates]
                // Name-only requests still have exact station identities selected
                // by the solver. Retain those source IDs in metadata without
                // changing the hints used to match or draw the solved geometry.
                var selectionHints = hints
                if selectionHints.fromStationCode?.isEmpty != false,
                   stationIndex.features.indices.contains(solved.fromStationIndex) {
                    selectionHints.fromStationCode = Stations.stationCode(
                        stationIndex.features[solved.fromStationIndex])
                }
                if selectionHints.toStationCode?.isEmpty != false,
                   stationIndex.features.indices.contains(solved.toStationIndex) {
                    selectionHints.toStationCode = Stations.stationCode(
                        stationIndex.features[solved.toStationIndex])
                }
                let selected = Self.canonicalSelection(canonical, hints: selectionHints, network: displayNetwork,
                                                  sourceCoordinates: solved.coordinates)
                // A matched physical chain can correct the legacy solver's
                // opposite-direction bore. Mileage and exports must use
                // the same corrected source intervals as the drawn path.
                var matchedSource: RouteGeometry?
                var matchedCertification: RouteNetwork.SourceGeometryCertification?
                if let codes = canonical?.matchedSectionCodes, !codes.isEmpty {
                    var matchedHints = hints
                    matchedHints.sectionCodes = codes
                    matchedHints.requiredLineIDs = canonical?.displayLineIds ?? []
                    matchedCertification = displayNetwork?.sourceCertification(for: matchedHints)
                    matchedSource = matchedCertification?.geometry
                }
                if let matchedSource {
                    let keys = try Self.verifiedSourcePath(matchedSource.lines,
                        graph: Self.physicalProofGraph(coordinates: matchedSource.lines.flatMap { $0 }, store: graphStore!),
                        context: context, section: section,
                        displayRowNames: matchedCertification?.rowNames ?? [],
                        anchorIndices: matchedCertification?.anchorIndices ?? [],
                        selectedLineIDs: matchedCertification?.selectedLineIDs ?? [], memo: inputs.resolutionMemo)
                    if keys == nil {
                        physicalGaps.append(PhysicalGap(segmentIndex: index, isBoundary: false))
                    }
                    if sharesBoundary,
                       RouteSolver.provenBoundaryContinuation(
                           previous: previousPhysicalKey, first: keys?.first,
                           previousSection: sections[index - 1], nextSection: section,
                           graph: Self.physicalProofGraph(
                               coordinates: matchedSource.lines.first?.first.map { [$0] } ?? [],
                               store: graphStore!),
                           stations: stationIndex, rideDate: context.rideDate) == nil,
                       !physicalGaps.contains(where: { $0.segmentIndex == index && $0.isBoundary }) {
                        physicalGaps.append(PhysicalGap(segmentIndex: index, isBoundary: true))
                    }
                    physicalContinuationKey = keys?.last
                    sourcePhysicalPathKeys[index] = keys
                }
                var sourceStart = 0
                for (partIndex, drawnCoordinates) in drawnParts.enumerated() {
                let sourceEnd: Int
                if partIndex == drawnParts.count - 1 { sourceEnd = solved.coordinates.count - 1 }
                else if let end = drawnCoordinates.last {
                    sourceEnd = (sourceStart..<solved.coordinates.count).min {
                        RailCore.Geometry.distanceMeters(solved.coordinates[$0], end)
                            < RailCore.Geometry.distanceMeters(solved.coordinates[$1], end)
                    } ?? sourceStart
                } else { sourceEnd = sourceStart }
                let sourcePart: [Coordinate]
                if let matchedSource, matchedSource.lines.indices.contains(partIndex) {
                    sourcePart = matchedSource.lines[partIndex]
                } else {
                    sourcePart = Array(solved.coordinates[sourceStart...sourceEnd])
                }
                sourceStart = sourceEnd
                segments.append(Segment(
                    segmentIndex: index, partIndex: partIndex,
                    from: section.from ?? stationIndex.name(forCode: section.fromN02StationCode),
                    to: section.to ?? stationIndex.name(forCode: section.toN02StationCode),
                    coordinates: drawnCoordinates,
                    // The map gets the canonical slice; the statistics get
                    // the path the solver actually walked, which is N02's
                    // own vertices and is the datum the edge index is in.
                    sourceCoordinates: sourcePart,
                    country: country,
                    historyIDs: solved.historyIDs,
                    validFrom: solved.validFrom,
                    validTo: solved.validTo,
                    temporalKind: solved.temporalKind, physicalRoute: selected))
                }
                lastSolvedIndex = index
                continuity = matchedSource?.lines.last?.last ?? solved.coordinates.last
                displayContinuity = drawnParts.last?.last
            }
        }
        graphStore?.trimRegionalGraphCache(target: RouteGraph.regionalGraphNodeBudget)
        try Task.checkCancellation()
        return Result(disposition: unsupported && !allowLegacy ? .unsupported : (segments.isEmpty ? .unavailable : .geometry),
            segments: segments, physicalGaps: physicalGaps, expectedSections: sections,
            requiresPrecomputedRejection: rejectPrecomputed, sourcePhysicalPathKeys: sourcePhysicalPathKeys)
    }

    private static func graphStore(_ inputs: SourceInputs) -> RouteGraph.RouteGraphStore {
        RouteGraph.RouteGraphStore(sections: inputs.sections, policy: .physicalRailway,
            junctions: inputs.physicalJunctions, cachePolicy: .bounded(maximumNodes: 100_000),
            identityPeriods: inputs.identityPeriods, sourceSnapshotID: inputs.snapshotID)
    }

    private static func physicalSelection(
        hints: RouteHints, network: RouteNetwork?, provenance: PhysicalRouteSelection.Provenance
    ) -> PhysicalRouteSelection? {
        guard let network, let from = hints.fromStationCode, let to = hints.toStationCode,
              let intervals = network.directedIntervals(sectionCodes: hints.sectionCodes,
                                                       fromStationCode: from, toStationCode: to),
              let lines = network.resolvedLines(sectionCodes: hints.sectionCodes) else { return nil }
        return PhysicalRouteSelection(fromStationCode: from, toStationCode: to,
                                      intervals: intervals, lines: lines, provenance: provenance)
    }

    /// A source-qualified CN solve has already identified the tracks it used.
    /// A nearby display row cannot replace that evidence with another identity.
    /// Keep the older display contract for paths without original node keys.
    private func canonicalMatchesSourcePath(
        _ canonical: CanonicalRoute, rawPathKeys: [String], network: RouteNetwork?
    ) -> Bool {
        guard country.lowercased() == "cn" else { return true }
        let prefixes = Set(rawPathKeys.compactMap { key -> String? in
            guard let marker = key.range(of: "@source-node:", options: .backwards) else { return nil }
            return String(key[..<marker.upperBound])
        })
        guard !prefixes.isEmpty else { return true }
        guard let network, !canonical.displayLineIds.isEmpty else { return false }
        let candidateIDs = Set(canonical.displayLineIds)
        let traversed = inputs.sections.filter { feature in
            guard let track = feature.properties.trackID, candidateIDs.contains(track) else { return false }
            // This prefix includes operator/name/class/level/track/source ID,
            // using the graph's own encoding rather than a partial label match.
            return prefixes.contains(RouteGraph.physicalSourceNodeKey("", identity: feature.physicalTrackIdentity))
        }
        return canonical.displayLineIds.allSatisfy { id in
            guard let line = network.lines.first(where: { $0.lineId == id }),
                  let name = line.compactLine?.name ?? line.name, !name.isEmpty,
                  let op = line.operator, !op.isEmpty else { return false }
            return traversed.contains { feature in
                let p = feature.properties
                return p.trackID == id && p.lineName == name && p.operator == op
            }
        }
    }

    /// A legacy path may have been sliced onto known display rows without a
    /// complete interval match. Those actual drawn identities still determine
    /// the card; this provenance does not claim station-topology inference.
    private static func canonicalSelection(
        _ canonical: CanonicalRoute?, hints: RouteHints, network: RouteNetwork?,
        sourceCoordinates: [Coordinate]
    ) -> PhysicalRouteSelection? {
        guard let canonical else { return nil }
        return displaySelection(lineIDs: canonical.displayLineIds, sectionCodes: canonical.matchedSectionCodes,
                                hints: hints, network: network, sourceCoordinates: sourceCoordinates)
    }

    public static func displaySelection(
        lineIDs: [String], sectionCodes: [String], hints: RouteHints, network: RouteNetwork?,
        sourceCoordinates: [Coordinate]
    ) -> PhysicalRouteSelection? {
        guard let network else { return nil }
        var selectedHints = hints
        selectedHints.sectionCodes = sectionCodes
        selectedHints.requiredLineIDs = lineIDs
        if let exact = physicalSelection(hints: selectedHints, network: network, provenance: .matchedGeometry) {
            return exact
        }
        let lines = lineIDs.compactMap { id -> ResolvedRailLine? in
            guard let line = network.lines.first(where: { $0.lineId == id }),
                  let name = line.compactLine?.nameNorm ?? line.name, !name.isEmpty else { return nil }
            return ResolvedRailLine(lineID: id, name: name, operatorName: line.operator,
                                    km: lineIDs.count == 1 ? zip(sourceCoordinates, sourceCoordinates.dropFirst()).reduce(0) {
                                        $0 + RailCore.Geometry.distanceMeters($1.0, $1.1)
                                    } / 1000 : 0)
        }
        guard !lines.isEmpty,
              let from = hints.fromStationCode, !from.isEmpty,
              let to = hints.toStationCode, !to.isEmpty else { return nil }
        return PhysicalRouteSelection(fromStationCode: from,
                                      toStationCode: to, intervals: [],
                                      lines: lines, provenance: .matchedGeometry)
    }

    /// Proofs inspect only source features within 1 km of the recorded path's
    /// vertices — not the path's whole bbox, which for a long ride is most of
    /// a country. Feature vertices are not clipped, so their qualified keys
    /// match the full graph.
    private static func physicalProofGraph(
        coordinates: [Coordinate], store: RouteGraph.RouteGraphStore
    ) -> RouteGraph.Graph {
        store.corridorGraph(for: coordinates, meters: 1_000)
    }

    private static func verifiedSourcePath(
        _ lines: [[Coordinate]], graph: RouteGraph.Graph,
        context: RouteSolver.TrainContext, section: RouteSection,
        displayRowNames: [String] = [], anchorIndices: [Set<Int>] = [],
        selectedLineIDs: [Set<String>] = [],
        memo: RouteResolutionMemo
    ) throws -> [String]? {
        try memo.proof(lines: lines, context: context, section: section,
            graphProvenance: graph.sourceProofProvenance, displayRowNames: displayRowNames,
            anchorIndices: anchorIndices, selectedLineIDs: selectedLineIDs) { RouteSolver.verifiedSourcePath(
            lines, graph: graph, context: context, section: section,
            displayRowNames: displayRowNames, anchorIndices: anchorIndices, selectedLineIDs: selectedLineIDs) }
    }

    private static func routeContext(_ train: Train) -> RouteSolver.TrainContext {
        .init(
            id: train.id, number: train.number, trainType: train.trainType ?? "",
            company: train.company ?? "", origin: train.origin,
            destination: train.destination,
            preferredLineNames: train.routePolicy?.preferredLineNames ?? [],
            preferredOperatorNames: train.routePolicy?.preferredOperatorNames ?? [],
            allowedInstitutionTypeCodes: train.routePolicy?.allowedInstitutionTypeCodes,
            institutionFilterMode: train.routePolicy?.institutionFilterMode ?? "soft",
            rideDate: Dates.normalizeDateString(train.date),
            operatorID: train.operatorID, operatorIDs: train.operatorIDs ?? [],
            region: train.region ?? "")
    }

}
