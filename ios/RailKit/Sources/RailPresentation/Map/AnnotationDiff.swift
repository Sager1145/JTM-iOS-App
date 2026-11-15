import Foundation

/// Which existing annotation answers which wanted one, decided from identity
/// alone. Pure and map-free so the rule is testable on the host.
///
/// Coordinate and zoom-dependent fields are NOT part of an identity: a station
/// that moved a few points when the geometry level changed is the same
/// station, kept and moved in place, never removed and re-added. A kind that
/// cannot move or restyle in place says so with ``Item/canMove`` /
/// ``Item/canRestyle``, and then a difference in that respect is a mismatch
/// (old removed, new added), exactly as before.
public struct AnnotationDiff: Equatable, Sendable {
    public struct Item<Style> {
        public var key: String
        public var latitude: Double
        public var longitude: Double
        public var canMove: Bool
        public var canRestyle: Bool
        public var style: Style
        public init(key: String, latitude: Double, longitude: Double,
                    canMove: Bool, canRestyle: Bool, style: Style) {
            self.key = key
            self.latitude = latitude
            self.longitude = longitude
            self.canMove = canMove
            self.canRestyle = canRestyle
            self.style = style
        }
    }

    public struct Kept: Equatable, Sendable {
        public var oldIndex: Int
        public var newIndex: Int
        /// The coordinate differs; the existing annotation takes the new one.
        public var moved: Bool
        /// The style differs; the existing view is refreshed from the new item.
        public var restyled: Bool
    }

    /// Ordered by `newIndex`.
    public var kept: [Kept]
    /// New indices with no existing counterpart.
    public var added: [Int]
    /// Old indices with no wanted counterpart.
    public var removed: [Int]

    public static func make<Style>(
        old: [Item<Style>], new: [Item<Style>],
        sameStyle: (Style, Style) -> Bool
    ) -> AnnotationDiff {
        var available: [String: [Int]] = [:]
        for (index, item) in old.enumerated() { available[item.key, default: []].append(index) }
        var taken = Set<Int>()
        var kept: [Kept] = []
        var added: [Int] = []
        for (newIndex, wanted) in new.enumerated() {
            guard let candidates = available[wanted.key] else {
                added.append(newIndex)
                continue
            }
            var best: (position: Int, moved: Bool, restyled: Bool, distance: Double)?
            for (position, oldIndex) in candidates.enumerated() {
                let existing = old[oldIndex]
                let moved = existing.latitude != wanted.latitude
                    || existing.longitude != wanted.longitude
                let restyled = !sameStyle(existing.style, wanted.style)
                if moved && !(existing.canMove && wanted.canMove) { continue }
                if restyled && !(existing.canRestyle && wanted.canRestyle) { continue }
                let dLat = existing.latitude - wanted.latitude
                let dLon = existing.longitude - wanted.longitude
                let distance = moved ? dLat * dLat + dLon * dLon : 0
                // Exact matches first, then the nearest compatible one.
                if let current = best {
                    let rank = (restyled ? 1 : 0, distance)
                    let currentRank = (current.restyled ? 1 : 0, current.distance)
                    if rank >= currentRank { continue }
                }
                best = (position, moved, restyled, distance)
                if !moved && !restyled { break }
            }
            guard let chosen = best else {
                added.append(newIndex)
                continue
            }
            let oldIndex = available[wanted.key]!.remove(at: chosen.position)
            taken.insert(oldIndex)
            kept.append(Kept(oldIndex: oldIndex, newIndex: newIndex,
                             moved: chosen.moved, restyled: chosen.restyled))
        }
        let removed = old.indices.filter { !taken.contains($0) }
        return AnnotationDiff(kept: kept, added: added, removed: removed)
    }

    public static func make<Style: Equatable>(
        old: [Item<Style>], new: [Item<Style>]
    ) -> AnnotationDiff {
        make(old: old, new: new, sameStyle: ==)
    }
}

/// Which of a set of circular touch targets a point lands in. Used for the
/// trip dots the overlay draws, which are not annotation views any more.
public enum DotHitTest {
    public struct Dot: Equatable, Sendable {
        public var x: Double
        public var y: Double
        /// Half the touch target's side: the larger of the minimum target and
        /// the drawn diameter, halved.
        public var reach: Double
        public init(x: Double, y: Double, reach: Double) {
            self.x = x
            self.y = y
            self.reach = reach
        }
    }

    /// Index of the dot whose centre is nearest the point among those that
    /// reach it, or nil.
    public static func hit(x: Double, y: Double, among dots: [Dot]) -> Int? {
        var best: (index: Int, distance: Double)?
        for (index, dot) in dots.enumerated() {
            let distance = hypot(dot.x - x, dot.y - y)
            guard distance <= dot.reach else { continue }
            if best == nil || distance < best!.distance { best = (index, distance) }
        }
        return best?.index
    }
}
