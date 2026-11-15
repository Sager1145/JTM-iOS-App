import Foundation

/// Where each newly added overlay goes so it lands in its final stack position.
///
/// `addOverlays` appends every new overlay above the mounted ones, so a new
/// network batch that belongs beneath the ride layers had to be swapped back
/// down with one `exchangeOverlay` call per step (20 to 30 ms per camera
/// settle). Inserting each new overlay at its final index leaves the swap loop
/// with nothing to do for a fresh install. Pure and map-free so the rule is
/// testable on the host.
public enum OverlayInsertionPlan {
    public struct Step: Equatable, Sendable {
        public let id: Int
        public let index: Int
        public init(id: Int, index: Int) {
            self.id = id
            self.index = index
        }
    }

    /// - Parameters:
    ///   - mounted: the overlays on the map now, bottom to top.
    ///   - target: the full desired stack, bottom to top (may contain overlays
    ///     that are not mounted and are not new, and duplicates).
    ///   - new: the overlays to add. One already mounted is skipped.
    /// - Returns: insertions, in order, each at an index valid at its turn.
    public static func steps(mounted: [Int], target: [Int], new: Set<Int>) -> [Step] {
        var present = Set(mounted)
        var seen: Set<Int> = []
        var count = mounted.count
        var result: [Step] = []
        var placed = 0
        for id in target {
            guard present.contains(id) || new.contains(id), seen.insert(id).inserted else { continue }
            defer { placed += 1 }
            guard new.contains(id), !present.contains(id) else { continue }
            let index = min(placed, count)
            result.append(Step(id: id, index: index))
            present.insert(id)
            count += 1
        }
        // New overlays missing from the target keep MapKit's append order.
        for id in new.sorted() where !present.contains(id) {
            result.append(Step(id: id, index: count))
            present.insert(id)
            count += 1
        }
        return result
    }
}
