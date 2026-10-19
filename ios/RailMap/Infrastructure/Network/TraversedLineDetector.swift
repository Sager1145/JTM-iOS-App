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
    }

    /// Detected lines for rides in the current snapshot.
    private(set) var linesByTrainID: [String: [Statistics.TraversedLine]] = [:]
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
            ride.segments.contains { $0.physicalRoute == nil }
        }.map { ($0.id, $0.country) }, uniquingKeysWith: { _, last in last })
        let countries = Set(countriesByTrainID.values)
        failuresByCountry = failuresByCountry.filter { countries.contains($0.key) }
    }

    /// Selected route identity is already known when the map receives a ride.
    /// Publishing it never starts or restarts an edge-index geometry match.
    func publishSelected(rides: [RiddenRouteStore.DrawnRide]) {
        generation &+= 1
        task?.cancel()
        task = nil
        let ids = Set(rides.map(\.id))
        liveIDs = ids
        retainCountries(for: rides)
        cache = cache.filter { ids.contains($0.key) }
        var lines: [String: [Statistics.TraversedLine]] = [:]
        for ride in rides {
            let selected = Self.selectedLines(ride)
            if !selected.isEmpty { lines[ride.id] = selected }
            else if let hit = cache[ride.id], hit.digest == Self.detectionDigest(ride) {
                lines[ride.id] = hit.lines
            }
        }
        linesByTrainID = lines
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

    /// Re-detect whatever changed in `rides` and publish lines for that set.
    ///
    /// Unchanged rides (same id, same `geometryDigest`) are served from
    /// `cache` at no cost; only new or redrawn rides are re-walked. Cancelling
    /// the previous walk preserves unchanged rides' published lines. Changed
    /// routes retain only their explicit physical selections until detection
    /// finishes, and a cancelled walk returns without writing.
    func update(rides: [RiddenRouteStore.DrawnRide]) {
        generation &+= 1
        let snapshot = generation
        task?.cancel()
        let ids = Set(rides.map(\.id))
        liveIDs = ids
        retainCountries(for: rides)
        cache = cache.filter { ids.contains($0.key) }

        var stale: [RiddenRouteStore.DrawnRide] = []
        var reusable: [String: [Statistics.TraversedLine]] = [:]
        for ride in rides {
            let selected = Self.selectedLines(ride)
            if !selected.isEmpty && ride.segments.allSatisfy({ $0.physicalRoute != nil }) {
                let digest = Self.detectionDigest(ride)
                cache[ride.id] = CachedResult(digest: digest, lines: selected)
                reusable[ride.id] = selected
            } else if let hit = cache[ride.id], hit.digest == Self.detectionDigest(ride) {
                reusable[ride.id] = hit.lines
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
        let pendingCountries = Set(stale.map(\.country))
        failuresByCountry = failuresByCountry.filter { pendingCountries.contains($0.key) }

        guard !stale.isEmpty else {
            task = nil
            return
        }

        let staleRides = stale
        task = Task.detached(priority: .utility) {
            var fresh: [String: (digest: Int, lines: [Statistics.TraversedLine])] = [:]
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
                    let features = ride.segments.filter { $0.physicalRoute == nil }.map { segment in
                        Statistics.RouteFeature(
                            lines: [segment.sourceCoordinates], hasGeometry: true,
                            // The route the train runs, not the stretch the
                            // reader rode — every segment counts.
                            rideSegment: true,
                            from: segment.from, to: segment.to)
                    }
                    let entry = Statistics.collectTrainStatsEntry(
                        features: features, index: index, rideDate: ride.daySpan.date)
                    let selected = Self.selectedLines(ride)
                    let names = Set(selected.map { TrainServiceBranding.canonicalLineName($0.name) })
                    let lines = selected + Statistics.traversedLines(edges: entry.edges, index: index)
                        .filter { !names.contains(TrainServiceBranding.canonicalLineName($0.name)) }
                    fresh[ride.id] = (Self.detectionDigest(ride), lines)
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
                    self.cache[id] = CachedResult(digest: result.digest, lines: result.lines)
                    self.linesByTrainID[id] = result.lines
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
    }
}
