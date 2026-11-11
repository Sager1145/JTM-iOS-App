import Foundation
import Observation
import RailCore

/// The railways a ride actually ran over, detected from its drawn route
/// rather than read off `route_sections[].line_names` / the itinerary's
/// `route_policy.preferred_line_names`.
///
/// A recorded journey names the lines a reader typed in; a through-running
/// train (サンライズ出雲: 東海道線→山陽線→伯備線→山陰線) crosses several
/// railways whether or not the import listed every one of them. Walking the
/// drawn geometry onto the region's N02 edge index answers the question the
/// record cannot: which track did this train's route actually cross.
///
/// One instance is owned by ``RiddenRouteStore`` and injected with it. The
/// published table is the result; readers do not keep a second copy.
@MainActor
@Observable
final class TraversedLineDetector {
    /// Geometry plus the ride date: an undated ride must not keep a match
    /// that only a dated ride is allowed to take.
    private nonisolated static func detectionDigest(_ ride: RiddenRouteStore.DrawnRide) -> Int {
        var hasher = Hasher()
        hasher.combine(ride.geometryDigest)
        hasher.combine(ride.daySpan.date)
        return hasher.finalize()
    }

    private struct CachedResult {
        let digest: Int
        let lines: [Statistics.TraversedLine]
        var sectionLines: [Int: [Statistics.TraversedLine]] = [:]
    }

    /// Detected lines for rides in the current snapshot.
    private(set) var linesByTrainID: [String: [Statistics.TraversedLine]] = [:]
    /// Geometry-detected lines per route section, only for drawn sections
    /// without a physical selection: `[trainID: [sectionIndex: lines]]`.
    private(set) var sectionLinesByTrainID: [String: [Int: [Statistics.TraversedLine]]] = [:]
    /// The rides of the current snapshot, which ``lineSequence(for:)`` reads.
    private(set) var ridesByID: [String: RiddenRouteStore.DrawnRide] = [:]
    private(set) var failuresByCountry: [String: String] = [:]

    @ObservationIgnored private var cache: [String: CachedResult] = [:]
    @ObservationIgnored private var countriesByTrainID: [String: String] = [:]
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Bumped on every new snapshot. A finished background walk applies only
    /// when it is still the current snapshot.
    @ObservationIgnored private var generation = 0
    /// Ids the current snapshot may publish. A stale walk cannot add an id
    /// that has since left the set.
    @ObservationIgnored private var liveIDs: Set<String> = []
    private struct SequenceMemo {
        let train: Train
        let digest: Int?
        let sectionLines: [Int: [Statistics.TraversedLine]]?
        let detected: [Statistics.TraversedLine]?
        let expectedSections: [RouteSection]?
        let authoritative: Bool?
        let settled: Bool
        let sequence: RiddenLineSequence
    }
    @ObservationIgnored private var sequenceMemo: [String: SequenceMemo] = [:]

    /// The ridden lines of one journey, per section, from this snapshot's
    /// solved route, its gaps and the per-section geometry. A journey with no
    /// ride yet reads its recorded sections, still pending.
    func lineSequence(for train: Train) -> RiddenLineSequence {
        let ride = ridesByID[train.id]
        let geometry = sectionLinesByTrainID[train.id]
        let detected = linesByTrainID[train.id]
        let settled = ride.map { !$0.needsLineDetection || cache[train.id] != nil } ?? false
        if let memo = sequenceMemo[train.id], memo.train == train, memo.digest == ride?.geometryDigest,
           memo.sectionLines == geometry, memo.detected == detected,
           memo.expectedSections == ride?.expectedSections,
           memo.authoritative == ride?.indicesAreAuthoritative, memo.settled == settled {
            return memo.sequence
        }
        let sequence: RiddenLineSequence
        if let ride, ride.indicesAreAuthoritative {
            let stops = ride.stops
            let recordedCount = train.routeSections?.count ?? 0
            // Sections solved for a different train (stops or section count
            // changed) say nothing about this one: recorded-only until the
            // re-solve arrives.
            let current = ride.stops.map(\.n02StationCode) == train.stops.map(\.n02StationCode)
                && (ride.expectedSections.isEmpty || ride.expectedSections.count == recordedCount)
            if current {
                sequence = RiddenLineSequence(
                    train: train,
                    sections: ride.expectedSections.isEmpty ? nil : ride.expectedSections,
                    selections: RiddenLineSequence.selections(
                        ride.segments.map { (segmentIndex: $0.segmentIndex, selection: $0.physicalRoute) }),
                    drawnSections: Set(ride.segments.map(\.segmentIndex)),
                    gaps: ride.physicalGaps,
                    geometryLines: geometry ?? [:],
                    solveSettled: settled,
                    stationName: { code in stops.first { $0.n02StationCode == code }?.name })
            } else {
                sequence = RiddenLineSequence(train: train, sections: nil, solveSettled: settled)
            }
        } else {
            // Positional (non-authoritative) indices say nothing about which
            // section a stroke belongs to, so only the record speaks. When the
            // record names nothing, the train-level detected lines stand in as
            // geometry lines of one section, so the physical lines and
            // operators the ride showed before are not lost.
            let recorded = RiddenLineSequence(train: train, solveSettled: ride != nil)
            if recorded.summary.runs.isEmpty, let detected, !detected.isEmpty,
               (train.routeSections?.count ?? 0) >= 1 {
                sequence = RiddenLineSequence(
                    train: train, drawnSections: [0], geometryLines: [0: detected], solveSettled: ride != nil)
            } else {
                sequence = recorded
            }
        }
        sequenceMemo[train.id] = SequenceMemo(
            train: train, digest: ride?.geometryDigest, sectionLines: geometry, detected: detected,
            expectedSections: ride?.expectedSections, authoritative: ride?.indicesAreAuthoritative,
            settled: settled, sequence: sequence)
        return sequence
    }

    /// The detected railways for one journey, or empty when none have landed
    /// or the record is still awaiting route confirmation.
    func lines(
        forTrainID id: String, pendingConfirmationIDs: Set<String>
    ) -> [Statistics.TraversedLine] {
        guard !pendingConfirmationIDs.contains(id) else { return [] }
        return linesByTrainID[id] ?? []
    }

    func failureMessage(forTrainID id: String) -> String? {
        guard cache[id] == nil, let country = countriesByTrainID[id],
              let message = failuresByCountry[country] else { return nil }
        return "\(country): \(message)"
    }

    private func retainCountries(for rides: [RiddenRouteStore.DrawnRide]) {
        countriesByTrainID = Dictionary(rides.filter { ride in
            ride.needsLineDetection
        }.map { ($0.id, $0.country) }, uniquingKeysWith: { _, last in last })
        let countries = Set(countriesByTrainID.values)
        failuresByCountry = failuresByCountry.filter { countries.contains($0.key) }
    }

    /// Selected route identity is already known when the map receives a ride.
    /// Publishing it never starts or restarts an edge-index geometry match.
    func publishSelected(rides: [RiddenRouteStore.DrawnRide]) {
        RailSignpost.ui.mark("derived.lines.selected", rides.count)
        generation &+= 1
        task?.cancel()
        task = nil
        let ids = Set(rides.map(\.id))
        liveIDs = ids
        retainCountries(for: rides)
        cache = cache.filter { ids.contains($0.key) }
        // Every id here is (re)published below: its memo is stale.
        sequenceMemo = [:]
        var lines: [String: [Statistics.TraversedLine]] = [:]
        var sectionLines: [String: [Int: [Statistics.TraversedLine]]] = [:]
        for ride in rides {
            let selected = Self.selectedLines(ride)
            let hit = cache[ride.id].flatMap { $0.digest == Self.detectionDigest(ride) ? $0 : nil }
            if !selected.isEmpty { lines[ride.id] = selected }
            else if let hit { lines[ride.id] = hit.lines }
            if let hit, !hit.sectionLines.isEmpty { sectionLines[ride.id] = hit.sectionLines }
        }
        linesByTrainID = lines
        sectionLinesByTrainID = sectionLines
        ridesByID = Dictionary(rides.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    }

    private nonisolated static func selectedLines(_ ride: RiddenRouteStore.DrawnRide) -> [Statistics.TraversedLine] {
        var seenSelections: [Int: [RiddenRouteStore.PhysicalRouteSelection]] = [:]
        var positions: [String: Int] = [:]
        var lines: [Statistics.TraversedLine] = []
        for segment in ride.segments {
            guard let selected = segment.physicalRoute,
                  !(seenSelections[segment.segmentIndex] ?? []).contains(selected) else { continue }
            seenSelections[segment.segmentIndex, default: []].append(selected)
            for line in selected.lines {
                if let index = positions[line.lineID] { lines[index].km += line.km }
                else {
                    positions[line.lineID] = lines.count
                    lines.append(.init(name: line.name, operatorName: line.operatorName,
                                       km: line.km, selectedLineID: line.lineID))
                }
            }
        }
        return lines
    }

    #if DEBUG
    /// Test seam: how many times ``update(rides:)`` ran.
    @ObservationIgnored private(set) var updateCallCount = 0
    #endif

    /// Re-detect whatever changed in `rides` and publish lines for that set.
    ///
    /// Unchanged rides (same id, same `geometryDigest`) are served from
    /// `cache` at no cost; only new or redrawn rides are re-walked. Cancelling
    /// the previous walk preserves unchanged rides' published lines. Changed
    /// routes retain only their explicit physical selections until detection
    /// finishes, and a cancelled walk returns without writing.
    func update(rides: [RiddenRouteStore.DrawnRide]) {
        #if DEBUG
        updateCallCount += 1
        #endif
        RailSignpost.ui.mark("derived.lines.detect", rides.count)
        generation &+= 1
        let snapshot = generation
        task?.cancel()
        let ids = Set(rides.map(\.id))
        liveIDs = ids
        retainCountries(for: rides)
        cache = cache.filter { ids.contains($0.key) }
        // Every id here is (re)published below: its memo is stale.
        sequenceMemo = [:]
        ridesByID = Dictionary(rides.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })

        var stale: [RiddenRouteStore.DrawnRide] = []
        var reusable: [String: [Statistics.TraversedLine]] = [:]
        var reusableSections: [String: [Int: [Statistics.TraversedLine]]] = [:]
        for ride in rides {
            let selected = Self.selectedLines(ride)
            if !selected.isEmpty && !ride.needsLineDetection {
                let digest = Self.detectionDigest(ride)
                cache[ride.id] = CachedResult(digest: digest, lines: selected)
                reusable[ride.id] = selected
            } else if let hit = cache[ride.id], hit.digest == Self.detectionDigest(ride) {
                reusable[ride.id] = hit.lines
                if !hit.sectionLines.isEmpty { reusableSections[ride.id] = hit.sectionLines }
            } else {
                // Changed geometry cannot retain labels inferred from its old route.
                // Explicit physical selections are still evidence in this snapshot.
                cache[ride.id] = nil
                reusable[ride.id] = selected
                stale.append(ride)
            }
        }

        // Drop deleted records and outdated inferred lines immediately.
        var published = linesByTrainID.filter { ids.contains($0.key) }
        for (id, lines) in reusable { published[id] = lines }
        linesByTrainID = published
        // Stale rides drop their per-section geometry with their old route.
        sectionLinesByTrainID = reusableSections
        let pendingCountries = Set(stale.map(\.country))
        failuresByCountry = failuresByCountry.filter { pendingCountries.contains($0.key) }

        guard !stale.isEmpty else {
            task = nil
            return
        }

        let staleRides = stale
        task = Task.detached(priority: .utility) {
            var fresh: [String: (digest: Int, lines: [Statistics.TraversedLine],
                                 sections: [Int: [Statistics.TraversedLine]])] = [:]
            var failures: [String: String] = [:]
            var completedCountries = Set<String>()
            let byCountry = Dictionary(grouping: staleRides, by: \.country)
            for (country, group) in byCountry {
                guard !Task.isCancelled else { return }
                let index: Statistics.EdgeIndex
                do {
                    index = try await EdgeIndexCache.shared.index(country: country)
                } catch is CancellationError {
                    return
                } catch {
                    guard !Task.isCancelled else { return }
                    failures[country] = error.localizedDescription
                    continue
                }
                for ride in group {
                    guard !Task.isCancelled else { return }
                    let unproven = ride.unprovenSegmentIndices
                    let candidates = ride.segments.filter {
                        $0.physicalRoute == nil && !unproven.contains($0.segmentIndex)
                    }
                    // One walk per section, in drawn order. Features are
                    // walked independently, so the concatenated section edges
                    // are exactly the edges of one walk over the whole ride.
                    var order: [Int] = []
                    var partsBySection: [Int: [RiddenRouteStore.DrawnSegment]] = [:]
                    for segment in candidates {
                        if partsBySection[segment.segmentIndex] == nil { order.append(segment.segmentIndex) }
                        partsBySection[segment.segmentIndex, default: []].append(segment)
                    }
                    var edges: [Int] = []
                    var sectionLines: [Int: [Statistics.TraversedLine]] = [:]
                    for sectionIndex in order {
                        let features = (partsBySection[sectionIndex] ?? []).map { segment in
                            Statistics.RouteFeature(
                                lines: [segment.sourceCoordinates], hasGeometry: true,
                                // The route the train runs, not the stretch the
                                // reader rode — every segment counts.
                                rideSegment: true,
                                from: segment.from, to: segment.to)
                        }
                        let entry = Statistics.collectTrainStatsEntry(
                            features: features, index: index, rideDate: ride.daySpan.date)
                        edges += entry.edges
                        let lines = Statistics.traversedLines(edges: entry.edges, index: index)
                        if !lines.isEmpty { sectionLines[sectionIndex] = lines }
                    }
                    let whole = Statistics.traversedLines(edges: edges, index: index)
                    // A section's own floor is a fraction of that section; keep
                    // only lines that also clear the whole ride's threshold.
                    let wholeNames = Set(whole.map { TrainServiceBranding.canonicalLineName($0.name) })
                    sectionLines = sectionLines.compactMapValues { lines in
                        let kept = lines.filter { wholeNames.contains(TrainServiceBranding.canonicalLineName($0.name)) }
                        return kept.isEmpty ? nil : kept
                    }
                    let selected = Self.selectedLines(ride)
                    let names = Set(selected.map { TrainServiceBranding.canonicalLineName($0.name) })
                    let lines = selected + whole
                        .filter { !names.contains(TrainServiceBranding.canonicalLineName($0.name)) }
                    fresh[ride.id] = (Self.detectionDigest(ride), lines, sectionLines)
                }
                completedCountries.insert(country)
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                // A newer snapshot owns the table. Do not replace it, and do
                // not remove lines this walk did not recompute.
                guard !Task.isCancelled, self.generation == snapshot else { return }
                for country in completedCountries { self.failuresByCountry[country] = nil }
                self.failuresByCountry.merge(failures, uniquingKeysWith: { _, latest in latest })
                for (id, result) in fresh {
                    guard self.liveIDs.contains(id) else { continue }
                    self.cache[id] = CachedResult(
                        digest: result.digest, lines: result.lines, sectionLines: result.sections)
                    self.linesByTrainID[id] = result.lines
                    self.sectionLinesByTrainID[id] = result.sections.isEmpty ? nil : result.sections
                }
            }
        }
    }

    /// Cancel in-flight detection and drop every cached result. Used when the
    /// route store itself resets, so no ride from the previous working set
    /// remains readable.
    func reset() {
        generation &+= 1
        task?.cancel()
        task = nil
        cache.removeAll()
        countriesByTrainID = [:]
        failuresByCountry = [:]
        liveIDs = []
        linesByTrainID = [:]
        sectionLinesByTrainID = [:]
        ridesByID = [:]
        sequenceMemo = [:]
    }
}

private extension RiddenRouteStore.DrawnRide {
    /// A detached segment needs detection; an unproven one is deliberately
    /// excluded from traversed-line statistics.
    var needsLineDetection: Bool {
        let unproven = unprovenSegmentIndices
        return segments.contains { $0.physicalRoute == nil && !unproven.contains($0.segmentIndex) }
    }
}
