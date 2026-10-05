import Foundation
import Testing
@testable import RailCore

/// Opt-in display census. The loop below mirrors PhysicalEndpointTrimTests.gapCounts,
/// also used by JunctionApproachTests, and delegates all proofs to RailCore.
struct ExpressDatabaseDisplayCensusTests {
    private let pipeline = PhysicalEndpointTrimTests()
    private struct JunctionDocument: Decodable {
        struct Record: Decodable { let id: String; let station: String }
        let junctions: [Record]
    }
    private struct Gap: Codable {
        let index: Int
        let from: String
        let to: String
        let isBoundary: Bool
        let reason: String
        let prevIdentity: String?
        let firstIdentity: String?
        let station: String?
    }
    private struct Unsolved: Codable {
        let index: Int
        let from: String
        let to: String
        let reason: String
        let knownFailure: Bool
    }
    private struct Result: Encodable {
        let patternID: String
        let variant: String
        let date: String
        var outcome = "unavailable"
        var segmentsDrawn = 0
        var gaps: [Gap] = []
        var unsolvedSections: [Unsolved] = []
        var dataIssues: [String] = []
        var knownUnsolvableLegs: [[String]] = []
        var paths: [Int: [Coordinate]] = [:]
        enum CodingKeys: String, CodingKey {
            case patternID, variant, date, outcome, segmentsDrawn, gaps, unsolvedSections, dataIssues, knownUnsolvableLegs
        }
    }

    private func inspect(train: Train, pattern: TrainServicePatterns.Pattern, variant: String,
                         data: PhysicalEndpointTrimTests.RealData,
                         junctions: [RouteGraph.PhysicalJunction], junctionStations: [String: String]) throws -> Result {
        let sections = train.routeSections ?? []
        try #require(sections.isEmpty == false)
        let context = RouteSolver.TrainContext(
            id: train.id, number: train.number, trainType: train.trainType ?? "",
            company: train.company ?? "", origin: train.origin, destination: train.destination,
            preferredLineNames: train.routePolicy?.preferredLineNames ?? [],
            preferredOperatorNames: train.routePolicy?.preferredOperatorNames ?? [],
            allowedInstitutionTypeCodes: train.routePolicy?.allowedInstitutionTypeCodes,
            institutionFilterMode: train.routePolicy?.institutionFilterMode ?? "soft",
            rideDate: Dates.normalizeDateString(train.date))
        let allowedCodes = RouteGraph.allowedInstitutionTypeCodes(.init(
            trainType: context.trainType, company: context.company,
            preferredLineNames: context.preferredLineNames,
            preferredOperatorNames: context.preferredOperatorNames,
            allowedInstitutionTypeCodes: context.allowedInstitutionTypeCodes,
            institutionFilterMode: context.institutionFilterMode), country: "jp")
        let inferred = RouteSolver.inferStationSections(
            sections, resolver: data.resolver, network: data.network, eligibility: data.eligibility,
            allowedCodes: allowedCodes, hard: context.institutionFilterMode == "hard")

        var result = Result(patternID: pattern.id, variant: variant, date: train.date ?? "")
        var currentIndex = 0
        var currentPrevious: String?
        var currentFirst: String?
        var failureDetail: String?
        func record(_ reason: String, boundary: Bool = false) {
            let section = sections[currentIndex]
            let previous = currentPrevious.map(identity)
            let first = currentFirst.map(identity)
            var cause = failureDetail ?? reason
            if boundary {
                cause = "boundary-unverified-endpoint"
                if let previous, let first {
                    cause = previous == first ? "boundary-same-identity-unproven" : "boundary-identity-change-without-junction"
                    let matches = junctions.filter { junctionStations[$0.id] == section.from && Set([identity(RouteGraph.physicalNodeKey($0.from.coordinate, identity: $0.from.identity)), identity(RouteGraph.physicalNodeKey($0.to.coordinate, identity: $0.to.identity))]) == Set([previous, first]) }
                    if let label = Self.reviewedJunctionBoundaryLabel(
                        previous: previous, first: first, date: result.date,
                        junctions: matches.map { ($0.validFrom, $0.validTo) }) {
                        cause = label
                    }
                }
            }
            result.gaps.append(Gap(index: currentIndex, from: section.from ?? "", to: section.to ?? "", isBoundary: boundary, reason: cause, prevIdentity: previous, firstIdentity: first, station: boundary ? section.from : nil))
        }
        var lastSolvedIndex: Int?
        var physicalKey: String?
        var continuity: Coordinate?
        var displayContinuity: Coordinate?
        var projectionCache = RouteProjectionCache()
        var boundaryGapIndices: Set<Int> = []
        var diagnosticLastKey: String?

        for (index, section) in sections.enumerated() {
            currentIndex = index
            currentFirst = nil
            failureDetail = nil
            let sharesBoundary = index > 0 && lastSolvedIndex == index - 1
                && RouteSolver.routeSectionBoundarySharesExplicitStop(sections[index - 1], section)
            let previousKey = sharesBoundary ? physicalKey : nil
            let anchor = sharesBoundary ? continuity : nil
            currentPrevious = sharesBoundary ? (previousKey ?? diagnosticLastKey) : nil
            if inferred.ambiguous.contains(index) {
                record("ambiguous-inference")
                lastSolvedIndex = nil
                physicalKey = nil
                continuity = nil
                displayContinuity = nil
                continue
            }
            let useSource = section.sectionCodes?.isEmpty == false || inferred.hints[index] != nil
            if useSource {
                try #require(section.sectionCodes?.isEmpty == false || inferred.hints[index] != nil)
                var hints = inferred.hints[index] ?? RouteHints(
                    requiredLineIDs: section.lineIDs ?? [], sectionCodes: section.sectionCodes ?? [],
                    fromStationCode: section.fromN02StationCode,
                    toStationCode: section.toN02StationCode)
                hints.fromStationCode = data.eligibility.stationCode(hints.fromStationCode)
                    ?? hints.fromStationCode
                hints.toStationCode = data.eligibility.stationCode(hints.toStationCode)
                    ?? hints.toStationCode
                let sourceResult = data.network.sourceCertification(for: hints)
                let exactResult = data.network.canonicalizeRouteFeature(
                    RouteFeature(geometry: nil, hints: hints),
                    continueFrom: sharesBoundary ? displayContinuity : nil,
                    cache: &projectionCache)
                if let certified = sourceResult, let exact = exactResult,
                   certified.geometry.lines.count == exact.geometry.lines.count {
                    let source = certified.geometry
                    let graph = pipeline.proofGraph(source.lines.flatMap { $0 }, store: data.graphStore)
                    let keys = RouteSolver.verifiedSourcePath(
                        source.lines, graph: graph, context: context, section: section,
                        displayRowNames: certified.rowNames, anchorIndices: certified.anchorIndices)
                    currentFirst = keys?.first ?? endpointKey(source.lines.first?.first, graph: graph)
                    if keys == nil { failureDetail = verificationReason(source.lines, graph: graph); record("source-verification"); failureDetail = nil }
                    result.segmentsDrawn += exact.geometry.lines.count
                    result.paths[index] = source.lines.flatMap { $0 }
                    if sharesBoundary,
                       RouteSolver.provenBoundaryContinuation(
                           previous: previousKey, first: keys?.first,
                           previousSection: sections[index - 1], nextSection: section,
                           graph: graph, stations: data.stations, rideDate: context.rideDate) == nil {
                        if boundaryGapIndices.insert(index).inserted {
                            record("boundary", boundary: true)
                        }
                    }
                    diagnosticLastKey = keys?.last ?? endpointKey(source.lines.last?.last, graph: graph)
                    physicalKey = keys?.last
                    continuity = source.lines.last?.last
                    displayContinuity = exact.geometry.lines.last?.last
                    lastSolvedIndex = index
                    continue
                }
                record("source-materialization")
                lastSolvedIndex = nil
                physicalKey = nil
                continuity = nil
                displayContinuity = nil
                if inferred.hints[index] == nil { continue }
            } else {
                try #require(section.sectionCodes?.isEmpty != false && inferred.hints[index] == nil)
            }

            var solved = RouteSolver.solveOfficialInterval(
                section, segmentIndex: index, train: context, country: "jp",
                allowedCodes: allowedCodes, intervalIndex: data.intervals,
                stations: data.stations, continuityAnchor: anchor)
                ?? RouteSolver.solveSectionOnDemand(
                    section, segmentIndex: index, train: context, country: "jp",
                    graphStore: data.graphStore, stations: data.stations,
                    continuityAnchor: anchor, physicalContinuationKey: previousKey,
                    traversalPolicy: .physicalRail)
            if solved == nil, sharesBoundary {
                solved = RouteSolver.solveSectionOnDemand(
                    section, segmentIndex: index, train: context, country: "jp",
                    graphStore: data.graphStore, stations: data.stations,
                    traversalPolicy: .physicalRail)
            }
            guard var resolved = solved, resolved.coordinates.count >= 2 else {
                let reason = unsolvedReason(section, context: context, allowedCodes: allowedCodes, data: data)
                result.unsolvedSections.append(.init(index: index, from: section.from ?? "", to: section.to ?? "", reason: reason, knownFailure: pattern.unsolvableLegs.contains([section.from ?? "", section.to ?? ""])))
                record(reason)
                if sharesBoundary, boundaryGapIndices.insert(index).inserted {
                    record("boundary", boundary: true)
                }
                physicalKey = nil
                continuity = nil
                displayContinuity = nil
                lastSolvedIndex = nil
                continue
            }
            let solvedGraph = pipeline.proofGraph(resolved.coordinates, store: data.graphStore)
            if resolved.rawPathKeys.first?.contains("@") != true {
                resolved.rawPathKeys = RouteSolver.verifiedPhysicalPathKeys(
                    resolved.coordinates, graph: solvedGraph, rideDate: context.rideDate,
                    requiredLines: Set(section.lineNames ?? []),
                    requiredOperators: Set(section.operatorNames ?? [])) ?? []
            }
            currentFirst = resolved.rawPathKeys.first ?? endpointKey(resolved.coordinates.first, graph: solvedGraph)
            if resolved.rawPathKeys.isEmpty { record("legacy-path-verification") }
            if sharesBoundary,
               RouteSolver.provenBoundaryContinuation(
                   previous: previousKey, first: resolved.rawPathKeys.first,
                   previousSection: sections[index - 1], nextSection: section,
                   graph: pipeline.proofGraph([resolved.coordinates[0]], store: data.graphStore),
                   stations: data.stations, rideDate: context.rideDate) == nil {
                if boundaryGapIndices.insert(index).inserted {
                    record("boundary", boundary: true)
                }
            }
            diagnosticLastKey = resolved.rawPathKeys.last ?? endpointKey(resolved.coordinates.last, graph: solvedGraph)
            physicalKey = resolved.rawPathKeys.last
            continuity = resolved.coordinates.last

            let hints = RouteHints(
                requiredLineNames: (section.lineNames ?? []).map(Optional.some),
                preferredLineNames: context.preferredLineNames.map(Optional.some),
                requiredOperatorNames: (section.operatorNames ?? []).map(Optional.some),
                preferredOperatorNames: context.preferredOperatorNames.map(Optional.some),
                requiredLineIDs: section.lineIDs ?? [], sectionCodes: section.sectionCodes ?? [],
                fromStationCode: section.fromN02StationCode,
                toStationCode: section.toN02StationCode)
            let canonical = RouteGraph.TemporalKind.shouldCanonicalizeDisplayNetwork(
                resolved.temporalKind)
                ? data.network.canonicalizeRouteFeature(
                    RouteFeature(geometry: .lineString(resolved.coordinates), hints: hints),
                    continueFrom: sharesBoundary ? displayContinuity : nil, cache: &projectionCache)
                : nil
            var matchedSource: RouteGeometry?
            var matchedCertification: RouteNetwork.SourceGeometryCertification?
            if let codes = canonical?.matchedSectionCodes, !codes.isEmpty {
                var matchedHints = hints
                matchedHints.sectionCodes = codes
                matchedHints.requiredLineIDs = canonical?.displayLineIds ?? []
                matchedCertification = data.network.sourceCertification(for: matchedHints)
                matchedSource = matchedCertification?.geometry
            }
            if let matchedSource {
                let matchedGraph = pipeline.proofGraph(matchedSource.lines.flatMap { $0 }, store: data.graphStore)
                let keys = RouteSolver.verifiedSourcePath(
                    matchedSource.lines, graph: matchedGraph, context: context, section: section,
                    displayRowNames: matchedCertification?.rowNames ?? [],
                    anchorIndices: matchedCertification?.anchorIndices ?? [])
                currentFirst = keys?.first ?? endpointKey(matchedSource.lines.first?.first, graph: matchedGraph)
                if keys == nil { failureDetail = verificationReason(matchedSource.lines, graph: matchedGraph); record("matched-source-verification"); failureDetail = nil }
                if sharesBoundary,
                   RouteSolver.provenBoundaryContinuation(
                       previous: previousKey, first: keys?.first,
                       previousSection: sections[index - 1], nextSection: section,
                       graph: matchedGraph, stations: data.stations,
                       rideDate: context.rideDate) == nil, boundaryGapIndices.insert(index).inserted {
                    record("boundary", boundary: true)
                }
                diagnosticLastKey = keys?.last ?? endpointKey(matchedSource.lines.last?.last, graph: matchedGraph)
                physicalKey = keys?.last
                continuity = matchedSource.lines.last?.last
            }
            result.segmentsDrawn += canonical?.geometry.lines.count ?? 1
            result.paths[index] = matchedSource?.lines.flatMap { $0 } ?? resolved.coordinates
            displayContinuity = canonical?.geometry.lines.last?.last ?? resolved.coordinates.last
            lastSolvedIndex = index
        }
        for (index, section) in sections.enumerated()
            where result.paths[index] == nil && !result.unsolvedSections.contains(where: { $0.index == index }) {
            result.unsolvedSections.append(.init(index: index, from: section.from ?? "", to: section.to ?? "",
                reason: result.gaps.first(where: { $0.index == index && !$0.isBoundary })?.reason ?? "no-display-geometry",
                knownFailure: pattern.unsolvableLegs.contains([section.from ?? "", section.to ?? ""])))
        }
        result.outcome = result.segmentsDrawn == 0 ? "unavailable" : result.gaps.isEmpty ? "complete" : "partial"
        result.knownUnsolvableLegs = pattern.unsolvableLegs
        for stop in train.stops {
            if data.stations.candidateIndices(for: .stop(.init(n02StationCode: stop.n02StationCode))).isEmpty {
                result.dataIssues.append("unknown station code: \(stop.name) [\(stop.n02StationCode ?? "nil")]")
            }
        }
        return result
    }

    /// A reviewed junction counts only inside `[validFrom, validTo)`.
    static func reviewedJunctionBoundaryLabel(
        previous: String, first: String, date: String,
        junctions: [(validFrom: String?, validTo: String?)]
    ) -> String? {
        func covers(_ item: (validFrom: String?, validTo: String?)) -> Bool {
            let from = item.validFrom.flatMap { $0.isEmpty ? nil : $0 }
            let to = item.validTo.flatMap { $0.isEmpty ? nil : $0 }
            if let from, from > date { return false }
            if let to, date >= to { return false }
            return true
        }
        if junctions.contains(where: covers), previous != first {
            return "boundary-reviewed-junction-outside-proof"
        }
        if junctions.contains(where: { item in
            guard let from = item.validFrom, !from.isEmpty else { return false }
            return from > date
        }) {
            return "boundary-before-junction-validFrom"
        }
        if junctions.contains(where: { item in
            guard let to = item.validTo, !to.isEmpty else { return false }
            return date >= to
        }) {
            return "after-junction-validTo"
        }
        return nil
    }

    @Test("Reviewed junction labels honour validFrom and validTo")
    func reviewedJunctionValidityLabels() {
        let open = (validFrom: "2017-04-21", validTo: nil as String?)
        let expired = (validFrom: "2017-04-21", validTo: "2024-03-16" as String?)
        let future = (validFrom: "2027-01-01", validTo: nil as String?)
        #expect(Self.reviewedJunctionBoundaryLabel(
            previous: "a", first: "b", date: "2026-10-03", junctions: [open])
            == "boundary-reviewed-junction-outside-proof")
        #expect(Self.reviewedJunctionBoundaryLabel(
            previous: "a", first: "b", date: "2020-01-01", junctions: [expired])
            == "boundary-reviewed-junction-outside-proof")
        #expect(Self.reviewedJunctionBoundaryLabel(
            previous: "a", first: "b", date: "2026-10-03", junctions: [expired])
            == "after-junction-validTo")
        #expect(Self.reviewedJunctionBoundaryLabel(
            previous: "a", first: "b", date: "2026-10-03", junctions: [future])
            == "boundary-before-junction-validFrom")
        #expect(Self.reviewedJunctionBoundaryLabel(
            previous: "a", first: "a", date: "2026-10-03", junctions: [open]) == nil)
    }

    private func identity(_ key: String) -> String {
        key.lastIndex(of: "@").map { String(key[..<$0]) } ?? key
    }

    private func endpointKey(_ point: Coordinate?, graph: RouteGraph.Graph) -> String? {
        guard let point else { return nil }
        let normalized = Grid.normalizeGraphCoord(point)
        let keys = RouteGraph.nearbyNodes(normalized, in: graph, radiusDeg: 0, limit: Int.max)
            .filter { graph.nodes[$0.key] == normalized }.map(\.key)
        return keys.count == 1 ? keys[0] : nil
    }

    private func verificationReason(_ lines: [[Coordinate]], graph: RouteGraph.Graph) -> String {
        for line in lines {
            let nodes = line.filter { point in
                let normalized = Grid.normalizeGraphCoord(point)
                return RouteGraph.nearbyNodes(normalized, in: graph, radiusDeg: 0, limit: Int.max)
                    .contains { graph.nodes[$0.key] == normalized }
            }
            if nodes.count < 2 { return "too-few-nodes" }
            guard let trimmed = RouteSolver.trimmedToGraphNodes(line: line, graph: graph) else {
                return "endpoint-trim-limit"
            }
            for point in trimmed.dropFirst().dropLast() {
                let normalized = Grid.normalizeGraphCoord(point)
                if !RouteGraph.nearbyNodes(normalized, in: graph, radiusDeg: 0, limit: Int.max)
                    .contains(where: { graph.nodes[$0.key] == normalized }) {
                    return "interior-display-vertex-off-grid"
                }
            }
        }
        return "source-edge-or-identity-proof-failed"
    }

    // Diagnostic replay after a nil solve: identical candidates, attempts and
    // detour threshold, without changing the actual display result.
    private func unsolvedReason(_ section: RouteSection, context: RouteSolver.TrainContext,
                                allowedCodes: [String], data: PhysicalEndpointTrimTests.RealData) -> String {
        func candidates(_ name: String?, _ code: String?) -> [Int] {
            RouteSolver.filterStationCandidatesByRideDate(
                RouteSolver.resolveRouteEndpointStationCandidates(
                    .stop(.init(name: name, n02StationCode: code)), in: data.stations,
                    allowedCodes: allowedCodes, sectionLineNames: section.lineNames ?? [],
                    sectionOperatorNames: section.operatorNames ?? [], rideDate: context.rideDate),
                in: data.stations, rideDate: context.rideDate)
        }
        let from = candidates(section.from, section.fromN02StationCode)
        let to = candidates(section.to, section.toN02StationCode)
        guard !from.isEmpty, !to.isEmpty else { return "no-station-candidates" }
        let graph = data.graphStore.fullGraph()
        let base = RouteSolver.buildSegmentRouteHints(section: section, fromStationIndices: from,
            toStationIndices: to, stations: data.stations, train: context, country: "jp")
        var attempts = RouteSolver.buildSegmentRouteSolveAttempts(base).map { ($0, allowedCodes) }
        if context.institutionFilterMode != "hard" {
            var fallback = base
            fallback.requiredLines = base.explicitRequiredLines
            fallback.requiredOperators = base.explicitRequiredOperators
            fallback.preferredLines = []
            fallback.preferredOperators = []
            fallback.requirePreferredInstitution = false
            fallback.solveMode = "institution_unpenalised_soft_fallback"
            attempts.append((fallback, RouteGraph.defaultAllowedInstitutionTypeCodes))
        }
        var hadCandidates = false
        var detour = false
        var otherRejection = false
        for (hints, codes) in attempts {
            let sources = Array(RouteSolver.collectStationCandidateGraphNodes(stationIndices: from,
                stations: data.stations, graph: graph, hints: hints, allowedCodes: codes).prefix(12))
            let targets = Array(RouteSolver.collectStationCandidateGraphNodes(stationIndices: to,
                stations: data.stations, graph: graph, hints: hints, allowedCodes: codes).prefix(12))
            guard !sources.isEmpty, !targets.isEmpty else { continue }
            hadCandidates = true
            let paths = RouteSolver.dijkstra(graph: graph,
                sourceCandidates: sources.map { .init(key: $0.key, distance: $0.distance) },
                targetKeys: Set(targets.map(\.key)), train: context.policy,
                allowedCodes: codes, hints: hints, traversalPolicy: .physicalRail)
            for path in paths where path.pathKeys.count >= 2 {
                guard let start = graph.nodes[path.sourceKey], let end = graph.nodes[path.targetKey] else { continue }
                let straight = Geometry.distanceMeters(start, end)
                let coordinates = path.pathKeys.compactMap { graph.nodes[$0] }
                let length = zip(coordinates, coordinates.dropFirst()).reduce(0.0) {
                    $0 + Geometry.distanceMeters($1.0, $1.1)
                }
                if straight > 1_500 && length > max(straight * 3.8 + 6_000, 12_000) { detour = true }
                else { otherRejection = true }
            }
        }
        if otherRejection { return "post-path-rejection" }
        if detour { return "detour-rejected" }
        return hadCandidates ? "disconnected" : "no-graph-candidates"
    }

    private func rideDate(_ pattern: TrainServicePatterns.Pattern) throws -> String {
        let preferred = "2026-10-03"
        func insideBounds(_ day: String) -> Bool {
            (pattern.validFrom.map { day >= $0 } ?? true)
                && (pattern.validUntil.map { day < $0 } ?? true)
        }
        if insideBounds(preferred) { return preferred }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        func shifted(_ value: String, days: Int) throws -> String {
            let date = try #require(formatter.date(from: value))
            return formatter.string(from: date.addingTimeInterval(Double(days) * 86_400))
        }
        if let start = pattern.validFrom {
            let date = try shifted(start, days: 1)
            if insideBounds(date) { return date }
        }
        if let end = pattern.validUntil {
            let date = try shifted(end, days: -1)
            if insideBounds(date) { return date }
        }
        // Missing validity bounds still use a concrete date, with uncertainty
        // recorded in dataIssues rather than silently inventing a service era.
        return pattern.validFrom ?? preferred
    }

    private func stationCoordinate(_ code: String?, data: PhysicalEndpointTrimTests.RealData) -> Coordinate? {
        guard let index = data.stations.candidateIndices(for: .stop(.init(n02StationCode: code))).first,
              let pair = Stations.displayCoordinate(data.stations.features[index]), pair.count >= 2 else { return nil }
        return Coordinate(lon: pair[0], lat: pair[1])
    }

    /// Optional stops have no insertion metadata. Project onto the selected
    /// required-stop rail path, preserving required order and sorting optional
    /// stops by progress along each leg. Endpoint chords are a flagged fallback.
    private func addingOptionalStops(_ pattern: TrainServicePatterns.Pattern, to train: Train,
                                     required: Result, data: PhysicalEndpointTrimTests.RealData) -> (Train, [String]) {
        var result = train
        var issues: [String] = []
        var insertions: [Int: [(Double, TrainServicePatterns.Pattern.StationRef)]] = [:]
        for ref in pattern.optionalStopRefs {
            guard let point = stationCoordinate(ref.sourceCode, data: data) else {
                issues.append("unknown optional station code: \(ref.name) [\(ref.sourceCode)]")
                insertions[max(0, train.stops.count - 2), default: []].append((Double.infinity, ref))
                continue
            }
            var best: (distance: Double, leg: Int, progress: Double, fallback: Bool)?
            for index in 0..<max(0, train.stops.count - 1) {
                let fallback = required.paths[index] == nil
                let path = required.paths[index] ?? [stationCoordinate(train.stops[index].n02StationCode, data: data),
                    stationCoordinate(train.stops[index + 1].n02StationCode, data: data)].compactMap { $0 }
                var progress = 0.0
                for (a, b) in zip(path, path.dropFirst()) {
                    let scale = cos(point.lat * .pi / 180)
                    let dx = (b.lon - a.lon) * scale, dy = b.lat - a.lat
                    let denominator = dx * dx + dy * dy
                    let t = denominator == 0 ? 0 : max(0, min(1,
                        ((point.lon - a.lon) * scale * dx + (point.lat - a.lat) * dy) / denominator))
                    let projected = Coordinate(lon: a.lon + t * (b.lon - a.lon), lat: a.lat + t * (b.lat - a.lat))
                    let distance = Geometry.distanceMeters(point, projected)
                    let length = Geometry.distanceMeters(a, b)
                    if best == nil || distance < best!.distance {
                        best = (distance, index, progress + t * length, fallback)
                    }
                    progress += length
                }
            }
            if let best {
                insertions[best.leg, default: []].append((best.progress, ref))
                if best.fallback || best.distance > 2_000 {
                    issues.append("optional order requires review: \(ref.name), leg \(best.leg), offset \(Int(best.distance))m, chord fallback=\(best.fallback)")
                }
            } else {
                issues.append("optional order unavailable: \(ref.name)")
                insertions[max(0, train.stops.count - 2), default: []].append((Double.infinity, ref))
            }
        }
        result.stops = []
        for (index, stop) in train.stops.enumerated() {
            result.stops.append(stop)
            for (_, ref) in (insertions[index] ?? []).sorted(by: { $0.0 == $1.0 ? $0.1.sourceCode < $1.1.sourceCode : $0.0 < $1.0 }) {
                result.stops.append(Stop(name: ref.name, n02StationCode: ref.sourceCode,
                    stopType: "passenger_stop", rideSegment: true))
            }
        }
        result.routeSections = nil
        return (result, issues)
    }

    @Test("Every database express pattern through the app display pipeline",
          .enabled(if: ProcessInfo.processInfo.environment["EXPRESS_CENSUS"] == "1"))
    func expressDatabaseDisplayCensus() throws {
        let root = try PortFixtures.repositoryRoot()
        let patterns = try JSONDecoder().decode([TrainServicePatterns.Pattern].self,
            from: Data(contentsOf: root.appending(path: "ios/RailKit/Sources/RailCore/Resources/train-service-patterns.json")))
        let data = try pipeline.loadRealData(root: root)
        let junctions = try PhysicalRailJunctionRegistry(data: Data(contentsOf:
            root.appending(path: "app/data/physical-rail-junctions.json"))).junctions(for: "jp")
        let junctionDocument = try JSONDecoder().decode(JunctionDocument.self, from: Data(contentsOf:
            root.appending(path: "app/data/physical-rail-junctions.json")))
        let junctionStations = Dictionary(uniqueKeysWithValues: junctionDocument.junctions.map { ($0.id, $0.station) })
        var results: [Result] = []
        for (index, pattern) in patterns.enumerated() {
            let date = try rideDate(pattern)
            let applied = TrainServicePatterns.apply(pattern, to:
                Train(id: pattern.id, date: date, number: "", origin: "", destination: "", stops: []))
            func canonical(_ train: Train) -> Train {
                var value = TrainValidation.normalizeExportTrain(train, country: "jp")
                value.routeSections = StoreOperations.rideRouteSections(for: value)
                return value
            }
            var required = try inspect(train: canonical(applied), pattern: pattern, variant: "required",
                data: data, junctions: junctions, junctionStations: junctionStations)
            if !pattern.isValid(on: date) { required.dataIssues.append("validity unconfirmed on \(date)") }
            if applied.stops.map(\.n02StationCode) != pattern.stopRefs.map({ Optional($0.sourceCode) }) {
                required.dataIssues.append("wrong required stop order after apply")
            }
            let (optionalTrain, optionalIssues) = addingOptionalStops(pattern, to: applied, required: required, data: data)
            var optional = try inspect(train: canonical(optionalTrain), pattern: pattern, variant: "required+optional",
                data: data, junctions: junctions, junctionStations: junctionStations)
            optional.dataIssues += optionalIssues
            if !pattern.isValid(on: date) { optional.dataIssues.append("validity unconfirmed on \(date)") }
            required.paths = [:]
            optional.paths = [:]
            results += [required, optional]
            let progress = "Express census \(index + 1)/\(patterns.count): \(pattern.id) \(required.outcome)/\(optional.outcome)\n"
            FileHandle.standardOutput.write(Data(progress.utf8))
        }
        let output = ProcessInfo.processInfo.environment["EXPRESS_CENSUS_OUTPUT"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory.appending(path: "express-census", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(results).write(to: output.appending(path: "census.json"), options: .atomic)
        let summary = summary(results, patternCount: patterns.count)
        try summary.write(to: output.appending(path: "summary.md"), atomically: true, encoding: .utf8)
        print(summary)
        #expect(results.count == patterns.count * 2)
    }

    private func summary(_ results: [Result], patternCount: Int) -> String {
        var lines = ["# Express database display census", "", "\(patternCount) patterns; \(results.count) pattern/variant rides. Forward direction only.",
            "Optional stops are projected onto required-stop rail geometry; uncertain placement is listed below. Outcome measures display geometry plus physical certification, matching the junction census. Segments drawn counts display polylines, including unverified display geometry.", "",
            "| Variant | Complete | Partial with gaps | Unavailable |", "|---|---:|---:|---:|"]
        for variant in ["required", "required+optional", "all"] {
            let subset = results.filter { variant == "all" || $0.variant == variant }
            lines.append("| \(variant) | \(subset.filter { $0.outcome == "complete" }.count) | \(subset.filter { $0.outcome == "partial" }.count) | \(subset.filter { $0.outcome == "unavailable" }.count) |")
        }
        var counts = Dictionary(uniqueKeysWithValues: ["too-few-nodes", "ambiguous-inference",
            "no-station-candidates", "no-graph-candidates"].map { ($0, 0) })
        var patterns: [String: Set<String>] = [:]
        for result in results {
            for gap in result.gaps {
                counts[gap.reason, default: 0] += 1
                patterns[gap.reason, default: []].insert(result.patternID)
            }
        }
        lines += ["", "## Gap causes", "", "| Cause | Gaps | Distinct patterns |", "|---|---:|---:|"]
        for cause in counts.keys.sorted(by: { counts[$0]! == counts[$1]! ? $0 < $1 : counts[$0]! > counts[$1]! }) {
            lines.append("| \(cause) | \(counts[cause]!) | \(patterns[cause]?.count ?? 0) |")
        }
        lines += ["", "## Boundary station and identity pairs", "", "Counts deduplicate patterns across the two variants. Missing identities mean endpoint certification did not establish a unique track.", ""]
        var boundaries: [String: Set<String>] = [:]
        for result in results {
            for gap in result.gaps where gap.isBoundary {
                let label = "\(gap.reason): \(gap.station ?? "?") — \(gap.prevIdentity ?? "unknown") → \(gap.firstIdentity ?? "unknown")"
                boundaries[label, default: []].insert(result.patternID)
            }
        }
        for key in boundaries.keys.sorted() { lines.append("- \(key): \(boundaries[key]!.count) patterns") }
        lines += ["", "## Unsolved sections and known-failure cross-check", "",
            "Reasons replay the solver's unanchored candidates, hint attempts and detour threshold. Known failures match TrainServicePatternRouteTests' unsolvableLegs by exact forward station pair. Different dates and display inference can produce different outcomes.", ""]
        var unsolved: [String: Set<String>] = [:]
        for result in results {
            for section in result.unsolvedSections {
                let label = "\(section.reason): \(section.from) → \(section.to); known=\(section.knownFailure)"
                unsolved[label, default: []].insert(result.patternID)
            }
        }
        for key in unsolved.keys.sorted() { lines.append("- \(key): \(unsolved[key]!.count) patterns") }
        let uniqueKnown = Dictionary(grouping: results.filter { !$0.knownUnsolvableLegs.isEmpty }, by: \.patternID)
        for key in uniqueKnown.keys.sorted() {
            let entries = uniqueKnown[key]!
            for pair in entries[0].knownUnsolvableLegs {
                let failed = entries.filter { result in result.unsolvedSections.contains { [$0.from, $0.to] == pair } }.map(\.variant)
                lines.append("- Known \(key), \(pair.joined(separator: " → ")): unsolved in \(failed.isEmpty ? "neither variant (may not be adjacent with optional stops)" : failed.joined(separator: ", "))")
            }
        }
        lines += ["", "## Pattern data and order issues", "",
            "Order checks cover apply preserving database order and optional projection uncertainty; geographic order is not an independently verified timetable fact.", ""]
        let unknownCodes = results.flatMap(\.dataIssues).filter { $0.hasPrefix("unknown") }.count
        let wrongOrders = results.flatMap(\.dataIssues).filter { $0.hasPrefix("wrong") }.count
        let orderReviews = results.flatMap(\.dataIssues).filter { $0.hasPrefix("optional order") }.count
        lines.append("Unknown-code issues: \(unknownCodes); apply order mismatches: \(wrongOrders); optional placement review flags: \(orderReviews).")
        lines.append("")
        for result in results where !result.dataIssues.isEmpty {
            for issue in result.dataIssues { lines.append("- \(result.patternID) [\(result.variant)]: \(issue)") }
        }
        if results.allSatisfy({ $0.dataIssues.isEmpty }) { lines.append("None detected.") }
        return lines.joined(separator: "\n") + "\n"
    }
}
