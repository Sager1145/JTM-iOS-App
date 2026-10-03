import Foundation
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
/// Publishes into ``RideStatusCenter`` so every surface that reads
/// `RideStatusCenter.shared.traversedLines(forTrainID:)` re-renders when a
/// detection lands, without threading the result through view initialisers.
@MainActor
final class TraversedLineDetector {
    static let shared = TraversedLineDetector()

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

    private var cache: [String: CachedResult] = [:]
    private var task: Task<Void, Never>?

    /// Selected route identity is already known when the map receives a ride.
    /// Publishing it never starts or restarts an edge-index geometry match.
    func publishSelected(rides: [RiddenRouteStore.DrawnRide]) {
        task?.cancel()
        task = nil
        var lines: [String: [Statistics.TraversedLine]] = [:]
        for ride in rides {
            let selected = Self.selectedLines(ride)
            if !selected.isEmpty { lines[ride.id] = selected }
            else if let hit = cache[ride.id], hit.digest == Self.detectionDigest(ride) {
                lines[ride.id] = hit.lines
            }
        }
        RideStatusCenter.shared.publish(traversedLines: lines)
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

    /// Re-detect whatever changed in `rides` and publish the full dictionary.
    ///
    /// Unchanged rides (same id, same `geometryDigest`) are served from
    /// `cache` at no cost; only new or redrawn rides are re-walked. Cancels
    /// any detection still in flight for a previous `rides` snapshot, since
    /// its answer would be for a route that has since moved on.
    func update(rides: [RiddenRouteStore.DrawnRide]) {
        task?.cancel()
        let wantedIDs = Set(rides.map(\.id))
        cache = cache.filter { wantedIDs.contains($0.key) }

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
                stale.append(ride)
            }
        }

        guard !stale.isEmpty else {
            RideStatusCenter.shared.publish(traversedLines: reusable)
            return
        }

        let staleRides = stale
        let reusableLines = reusable
        task = Task.detached(priority: .utility) {
            var fresh: [String: (digest: Int, lines: [Statistics.TraversedLine])] = [:]
            let byCountry = Dictionary(grouping: staleRides, by: \.country)
            for (country, group) in byCountry {
                guard !Task.isCancelled else { return }
                guard let index = try? await EdgeIndexCache.shared.index(country: country) else {
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
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard !Task.isCancelled else { return }
                var merged = reusableLines
                for (id, result) in fresh {
                    self.cache[id] = CachedResult(digest: result.digest, lines: result.lines)
                    merged[id] = result.lines
                }
                RideStatusCenter.shared.publish(traversedLines: merged)
            }
        }
    }

    /// Cancel in-flight detection and drop every cached result — the ride
    /// store's own reset, for the same reason `RideStatusCenter.clear()`
    /// exists.
    func reset() {
        task?.cancel()
        task = nil
        cache.removeAll()
    }
}
