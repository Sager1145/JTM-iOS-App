import Foundation

/// Completed, graph-free results belonging to exactly one immutable solver-input
/// snapshot. Create a new memo whenever its stations, railway data, direction
/// network or graph-building policy changes. Fresh private graph stores made from
/// that same snapshot may share this owner; arbitrary graph solves may not.
///
/// Call these synchronous operations from inside the caller's RouteSolveLimiter
/// permit. The lock protects retained values, never a graph or an operation. This
/// memo does not admit work, retain closures, or cache failed/cancelled attempts.
public final class RouteResolutionMemo: @unchecked Sendable {
    private struct SolveRequest: Hashable {
        let section: RouteSection
        let constraintKey: String
        let country: String
        let rideDate: String?
        let hardExcludedCodes: [String]
        let continuityAnchor: Coordinate?
        let physicalContinuationKey: String?
    }

    private struct ProofRequest: Hashable {
        let source: RouteGraph.SourceProofRequest
        let provenance: RouteGraph.SourceProofProvenance
    }

    private enum Key: Hashable {
        case solve(SolveRequest)
        case proof(ProofRequest)
    }

    private enum Value {
        case solve(RouteSolver.SolvedSection)
        case proof([String])
    }

    private struct Entry {
        let value: Value
        let cost: Int
    }

    private let lock = NSLock()
    private let maxEntries: Int
    private let maxRetainedCost: Int
    private var entries: [Key: Entry] = [:]
    private var order: [Key] = []
    private var cost = 0

    /// `maxRetainedCost` bounds a conservative byte estimate of both requests
    /// and values, including geometry, hints and strings. Oversized results are
    /// returned to the caller without retention. Either zero limit disables it.
    public init(maxEntries: Int = 96, maxRetainedCost: Int = 262_144) {
        self.maxEntries = max(0, maxEntries)
        self.maxRetainedCost = max(0, maxRetainedCost)
    }

    /// Memoize a complete physical-rail section solve against the owning
    /// snapshot, using its station index and fixed direction/graph policy.
    /// Train identity affects the key only through the constraints it derives.
    /// The returned index always belongs to this caller's itinerary.
    func solve(
        section: RouteSection, segmentIndex: Int,
        context: RouteSolver.TrainContext, country: String, stations: Stations.Index,
        continuityAnchor: Coordinate? = nil, physicalContinuationKey: String? = nil,
        operation: () throws -> RouteSolver.SolvedSection?
    ) throws -> RouteSolver.SolvedSection? {
        try Task.checkCancellation()
        // Match prepareSectionEndpoints before deriving Sonic/Haruka hints.
        // The original section remains in the request, preserving every field.
        var constraintSection = section
        if constraintSection.from?.isEmpty != false {
            constraintSection.from = stations.name(forCode: section.fromN02StationCode)
        }
        if constraintSection.to?.isEmpty != false {
            constraintSection.to = stations.name(forCode: section.toN02StationCode)
        }
        let train = RouteGraph.CacheKeyTrain(
            id: context.id, number: context.number, trainType: context.trainType,
            company: context.company, origin: context.origin, destination: context.destination,
            preferredLineNames: context.preferredLineNames,
            preferredOperatorNames: context.preferredOperatorNames,
            allowedInstitutionTypeCodes: context.allowedInstitutionTypeCodes,
            institutionFilterMode: context.institutionFilterMode,
            operatorID: context.operatorID, operatorIDs: context.operatorIDs)
        let graphSection = RouteGraph.RouteSection(constraintSection)
        // A one-section context always exists. Keep the exact date separately:
        // solveContext normalizes its spelling, while the solver reads it raw.
        // Pending registry: no key and no cached miss. The caller retries after preload.
        guard let constraintKey = RouteGraph.solveContext(
            train: train, routeSections: [graphSection], country: country,
            rideDate: context.rideDate)?.cacheKey else { return nil }
        let key = Key.solve(.init(section: section, constraintKey: constraintKey,
            country: country, rideDate: context.rideDate,
            hardExcludedCodes: context.policy.hardExcludedInstitutionTypeCodes,
            continuityAnchor: continuityAnchor, physicalContinuationKey: physicalContinuationKey))
        if case .solve(var solved)? = lookup(key) {
            try Task.checkCancellation()
            solved.segmentIndex = segmentIndex
            return solved
        }
        try Task.checkCancellation()
        var solved = try operation()
        try Task.checkCancellation()
        if var retained = solved {
            retained.segmentIndex = 0
            try retain(.solve(retained), for: key)
            solved?.segmentIndex = segmentIndex
        }
        return solved
    }

    /// Memoize a complete source proof, preserving the full qualified node path.
    /// Provenance must come from the immutable graph build that the operation
    /// uses. Missing provenance deliberately bypasses shared retention.
    func proof(
        lines: [[Coordinate]], context: RouteSolver.TrainContext, section: RouteSection,
        graphProvenance: RouteGraph.SourceProofProvenance?,
        displayRowNames: [String] = [], anchorIndices: [Set<Int>] = [],
        selectedLineIDs: [Set<String>] = [],
        operation: () throws -> [String]?
    ) throws -> [String]? {
        try Task.checkCancellation()
        let key = graphProvenance.map { provenance in
            Key.proof(.init(source: .init(lines: lines, rideDate: context.rideDate,
                requiredLines: section.lineNames ?? [], requiredOperators: section.operatorNames ?? [],
                displayRowNames: displayRowNames, anchorIndices: anchorIndices,
                selectedLineIDs: selectedLineIDs), provenance: provenance))
        }
        if let key, case .proof(let keys)? = lookup(key) {
            try Task.checkCancellation()
            return keys
        }
        try Task.checkCancellation()
        let keys = try operation()
        try Task.checkCancellation()
        if let key, let keys { try retain(.proof(keys), for: key) }
        return keys
    }

    private func lookup(_ key: Key) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[key] else { return nil }
        order.removeAll { $0 == key }
        order.append(key)
        return entry.value
    }

    private func retain(_ value: Value, for key: Key) throws {
        let entryCost = Self.retainedCost(key: key, value: value)
        try Task.checkCancellation()
        guard maxEntries > 0, entryCost <= maxRetainedCost else { return }
        lock.lock()
        defer { lock.unlock() }
        try Task.checkCancellation()
        if let previous = entries.removeValue(forKey: key) { cost -= previous.cost }
        order.removeAll { $0 == key }
        while entries.count >= maxEntries || cost > maxRetainedCost - entryCost {
            guard !order.isEmpty else { break }
            let oldest = order.removeFirst()
            if let previous = entries.removeValue(forKey: oldest) { cost -= previous.cost }
        }
        entries[key] = Entry(value: value, cost: entryCost)
        order.append(key)
        cost += entryCost
    }

    // Available to focused regression tests without exposing mutable storage.
    var retainedEntryCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    var retainedCost: Int {
        lock.lock()
        defer { lock.unlock() }
        return cost
    }

    private static func retainedCost(key: Key, value: Value) -> Int {
        // Include collection slots and string storage even when Swift shares
        // backing buffers. Saturation declines retention on arithmetic overflow.
        var total = 512
        func add(_ amount: Int) {
            let sum = total.addingReportingOverflow(amount)
            total = sum.overflow ? Int.max : sum.partialValue
        }
        func string(_ value: String?) {
            if let value { add(32); add(value.utf8.count) }
        }
        func strings<S: Sequence>(_ values: S) where S.Element == String {
            add(32)
            for value in values { string(value) }
        }
        func coordinates<S: Sequence>(_ values: S) where S.Element == Coordinate {
            add(32)
            for _ in values { add(32) }
        }
        switch key {
        case .solve(let request):
            let section = request.section
            for value in [section.from, section.to, section.fromN02StationCode,
                section.toN02StationCode, section.number, section.name,
                request.constraintKey, request.country, request.rideDate,
                request.physicalContinuationKey] { string(value) }
            for values in [section.lineNames, section.operatorNames, section.lineIDs,
                section.sectionCodes] { strings(values ?? []) }
            strings(request.hardExcludedCodes)
            if request.continuityAnchor != nil { add(32) }
        case .proof(let request):
            for line in request.source.lines { coordinates(line) }
            string(request.source.rideDate)
            strings(request.source.requiredLines)
            strings(request.source.requiredOperators)
            strings(request.source.displayRowNames)
            for ids in request.source.selectedLineIDs { strings(Array(ids)) }
            for anchors in request.source.anchorIndices {
                add(32)
                for _ in anchors { add(32) }
            }
            for _ in request.provenance.featureIndices { add(16) }
        }
        switch value {
        case .proof(let keys): strings(keys)
        case .solve(let solved):
            coordinates(solved.coordinates)
            strings(solved.rawPathKeys)
            strings(solved.allowedInstitutionTypeCodes)
            strings(solved.usedInstitutionTypeCodes)
            strings(solved.historyIDs)
            string(solved.validFrom)
            string(solved.validTo)
            let hints = solved.hints
            string(hints.solveMode)
            coordinates(hints.directionExcludedCoordinates)
            for values in [hints.preferredLines, hints.preferredOperators, hints.requiredLines,
                hints.requiredOperators, hints.explicitRequiredLines, hints.explicitRequiredOperators,
                hints.commonLines, hints.commonOperators, hints.allCommonLines, hints.allCommonOperators,
                hints.preferredInstitutionCommonLines, hints.preferredInstitutionCommonOperators,
                hints.fromLines, hints.toLines, hints.fromOperators, hints.toOperators,
                hints.fromPreferredLines, hints.toPreferredLines,
                hints.fromPreferredOperators, hints.toPreferredOperators,
                hints.directionExcludedFamilies] { strings(values) }
        }
        return total
    }
}
