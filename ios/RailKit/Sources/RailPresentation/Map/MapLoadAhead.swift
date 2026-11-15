import Foundation

/// Where to load display lines while the camera is still moving.
///
/// A throttled pass (about every ``interval`` seconds) asks the loader for
/// the visible rect extended in the direction of travel by a velocity-based
/// look-ahead (at least one screen), plus a margin ring on every side. Loading
/// only ever adds; nothing on screen is unloaded or replaced by this request.
/// Pure and map-free so every rule is testable on the host.
public enum MapLoadAhead {
    public typealias Rect = MapBuildArea.Rect

    /// Seconds between moving-camera load passes.
    public static let interval: Double = 0.2
    /// The look-ahead is at least this many screens in the direction of travel.
    public static let minimumScreensAhead: Double = 1
    /// Seconds of travel the look-ahead covers at the current velocity.
    public static let horizonSeconds: Double = 1.5
    /// The look-ahead never reaches further than this many screens.
    public static let maximumScreensAhead: Double = 4
    /// Margin ring added on every side, as a fraction of the visible size.
    public static let marginFraction: Double = 0.5

    /// Camera velocity in map points per second.
    public struct Velocity: Equatable, Sendable {
        public var dx: Double
        public var dy: Double
        public init(dx: Double, dy: Double) {
            self.dx = dx
            self.dy = dy
        }
        public static let zero = Velocity(dx: 0, dy: 0)
    }

    /// Velocity between two visible rects `elapsed` seconds apart (centre to centre).
    public static func velocity(from previous: Rect, to current: Rect, elapsed: Double) -> Velocity {
        guard elapsed > 0 else { return .zero }
        let dx = (current.x + current.width / 2) - (previous.x + previous.width / 2)
        let dy = (current.y + current.height / 2) - (previous.y + previous.height / 2)
        return Velocity(dx: dx / elapsed, dy: dy / elapsed)
    }

    /// Whether a moving-camera pass is due.
    public static func isDue(now: Double, lastPass: Double?) -> Bool {
        guard let lastPass else { return true }
        return now - lastPass >= interval
    }

    /// How far ahead along one axis: velocity over the horizon, clamped to
    /// [one screen, ``maximumScreensAhead`` screens]. Zero velocity still
    /// yields the minimum, in the (zero) direction, so it contributes nothing.
    static func ahead(velocity: Double, screen: Double) -> Double {
        guard velocity != 0, screen > 0 else { return 0 }
        let travel = abs(velocity) * horizonSeconds
        let clamped = min(max(travel, minimumScreensAhead * screen), maximumScreensAhead * screen)
        return clamped * (velocity > 0 ? 1 : -1)
    }

    /// The rect to request: `visible` extended ahead of travel, then a margin
    /// ring on every side. It always contains `visible`.
    public static func requestRect(visible: Rect, velocity: Velocity) -> Rect {
        let aheadX = ahead(velocity: velocity.dx, screen: visible.width)
        let aheadY = ahead(velocity: velocity.dy, screen: visible.height)
        var minX = visible.x, maxX = visible.x + visible.width
        var minY = visible.y, maxY = visible.y + visible.height
        if aheadX > 0 { maxX += aheadX } else { minX += aheadX }
        if aheadY > 0 { maxY += aheadY } else { minY += aheadY }
        let marginX = visible.width * marginFraction
        let marginY = visible.height * marginFraction
        return Rect(
            x: minX - marginX, y: minY - marginY,
            width: maxX - minX + 2 * marginX, height: maxY - minY + 2 * marginY)
    }

    /// The area geometry is built for while the camera moves: the visible
    /// rect extended exactly one screen in the direction of travel, plus the
    /// margin ring. Loading may reach further than building.
    public static func movingBuildRect(visible: Rect, velocity: Velocity) -> Rect {
        func axis(_ v: Double, _ screen: Double) -> Double {
            v == 0 ? 0 : (v > 0 ? screen : -screen)
        }
        let aheadX = axis(velocity.dx, visible.width)
        let aheadY = axis(velocity.dy, visible.height)
        var minX = visible.x, maxX = visible.x + visible.width
        var minY = visible.y, maxY = visible.y + visible.height
        if aheadX > 0 { maxX += aheadX } else { minX += aheadX }
        if aheadY > 0 { maxY += aheadY } else { minY += aheadY }
        let marginX = visible.width * marginFraction
        let marginY = visible.height * marginFraction
        return Rect(
            x: minX - marginX, y: minY - marginY,
            width: maxX - minX + 2 * marginX, height: maxY - minY + 2 * marginY)
    }

    /// Whether the geometry already built still covers one screen ahead of
    /// the camera. When it does not, a moving-camera extension is due.
    public static func needsExtension(built: Rect, visible: Rect, velocity: Velocity) -> Bool {
        func axis(_ v: Double, _ screen: Double) -> Double {
            v == 0 ? 0 : (v > 0 ? screen : -screen)
        }
        let aheadX = axis(velocity.dx, visible.width)
        let aheadY = axis(velocity.dy, visible.height)
        var minX = visible.x, maxX = visible.x + visible.width
        var minY = visible.y, maxY = visible.y + visible.height
        if aheadX > 0 { maxX += aheadX } else { minX += aheadX }
        if aheadY > 0 { maxY += aheadY } else { minY += aheadY }
        let need = Rect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        return !contains(built, need)
    }

    public static func contains(_ outer: Rect, _ inner: Rect) -> Bool {
        outer.x <= inner.x && outer.y <= inner.y
            && outer.x + outer.width >= inner.x + inner.width
            && outer.y + outer.height >= inner.y + inner.height
    }
}

/// A square tile grid over map points. A line's overlay polylines are binned
/// by tile so a batch is (colour group, tile) and a new area adds batches
/// instead of changing the old ones.
public enum MapOverlayTiling {
    /// Tile edge in screen points at the level's scale.
    public static let tileScreenPoints: Double = 1024

    public struct Tile: Hashable, Comparable, Sendable {
        public var x: Int
        public var y: Int
        public init(x: Int, y: Int) {
            self.x = x
            self.y = y
        }
        public static func < (lhs: Tile, rhs: Tile) -> Bool {
            lhs.x == rhs.x ? lhs.y < rhs.y : lhs.x < rhs.x
        }
        public var label: String { "\(x),\(y)" }
    }

    public static func tileSize(mapPointsPerScreenPoint: Double) -> Double {
        tileScreenPoints * max(mapPointsPerScreenPoint, .leastNonzeroMagnitude)
    }

    /// The tile holding `(x, y)`.
    public static func tile(x: Double, y: Double, tileSize: Double) -> Tile {
        Tile(x: Int((x / tileSize).rounded(.down)), y: Int((y / tileSize).rounded(.down)))
    }

    /// The tile holding the centre of `rect`.
    public static func tile(of rect: Rect, tileSize: Double) -> Tile {
        tile(x: rect.x + rect.width / 2, y: rect.y + rect.height / 2, tileSize: tileSize)
    }

    public typealias Rect = MapBuildArea.Rect
}

/// Overlay batches keyed by (colour group, tile) that only ever grow with area.
///
/// A batch's membership is fixed when it is created. Items the ledger has not
/// seen go into a NEW batch for their group and tile, so adding area never
/// replaces a batch already on the map. A batch is rebuilt under a new key
/// (from its still-offered members) when a member inside the build area is no
/// longer offered (replaced, culled, filtered) or is offered under another
/// group (a colour change). A member that is no longer offered because it
/// left the build area is tolerated: the batch stays as it is. A batch nothing
/// offers any more is dropped. Reset it when the geometry level changes.
public struct AddOnlyBatchLedger<Item: Hashable> {
    public struct Entry {
        public var item: Item
        public var group: String
        public var tile: MapOverlayTiling.Tile
        /// The item's extent in map points; decides whether a no-longer-offered
        /// item left the build area or was replaced inside it.
        public var bounds: MapBuildArea.Rect?
        public init(
            item: Item, group: String, tile: MapOverlayTiling.Tile,
            bounds: MapBuildArea.Rect? = nil
        ) {
            self.item = item
            self.group = group
            self.tile = tile
            self.bounds = bounds
        }
    }

    public struct Batch {
        public let key: String
        public let group: String
        public let tile: MapOverlayTiling.Tile
        public let serial: Int
        public let items: [Item]
    }

    private struct Slot: Hashable { var group: String; var tile: MapOverlayTiling.Tile }

    private var batchesByKey: [String: Batch] = [:]
    private var nextSerial: [String: Int] = [:]
    private var itemBounds: [Item: MapBuildArea.Rect] = [:]

    public init() {}

    public mutating func reset() {
        batchesByKey = [:]
        nextSerial = [:]
        itemBounds = [:]
    }

    public var batches: [Batch] {
        batchesByKey.values.sorted {
            if $0.group != $1.group { return $0.group < $1.group }
            if $0.tile != $1.tile { return $0.tile < $1.tile }
            return $0.serial < $1.serial
        }
    }

    /// Offers the current items. `buildRect` is the area geometry is built for;
    /// without it every un-offered member counts as replaced. Returns the keys
    /// of batches created now.
    @discardableResult
    public mutating func update(_ entries: [Entry], buildRect: MapBuildArea.Rect? = nil) -> [String] {
        var offeredGroup: [Item: String] = [:]
        for entry in entries { offeredGroup[entry.item] = entry.group }
        for (key, batch) in batchesByKey {
            let anyOffered = batch.items.contains { offeredGroup[$0] != nil }
            let changed = batch.items.contains { item in
                if let group = offeredGroup[item] { return group != batch.group }
                guard let buildRect, let bounds = itemBounds[item] else { return true }
                return Self.intersects(bounds, buildRect)
            }
            if !anyOffered || changed { batchesByKey[key] = nil }
        }
        var member = Set<Item>()
        for batch in batchesByKey.values { for item in batch.items { member.insert(item) } }
        itemBounds = itemBounds.filter { member.contains($0.key) }

        var fresh: [Slot: [Item]] = [:]
        var order: [Slot] = []
        for entry in entries where !member.contains(entry.item) {
            let slot = Slot(group: entry.group, tile: entry.tile)
            if fresh[slot] == nil { order.append(slot) }
            fresh[slot, default: []].append(entry.item)
            member.insert(entry.item)
            if let bounds = entry.bounds { itemBounds[entry.item] = bounds }
        }
        var created: [String] = []
        for slot in order {
            let base = "\(slot.group)|\(slot.tile.label)"
            let serial = nextSerial[base, default: 0]
            nextSerial[base] = serial + 1
            let key = serial == 0 ? base : "\(base)#\(serial)"
            batchesByKey[key] = Batch(
                key: key, group: slot.group, tile: slot.tile, serial: serial,
                items: fresh[slot] ?? [])
            created.append(key)
        }
        return created
    }

    private static func intersects(_ a: MapBuildArea.Rect, _ b: MapBuildArea.Rect) -> Bool {
        a.x < b.x + b.width && b.x < a.x + a.width
            && a.y < b.y + b.height && b.y < a.y + a.height
    }
}

/// Keeps a drawn line's stroke from changing while the map moves.
///
/// A line's stroke depends on which junction neighbours are loaded. While the
/// camera moves, a later load wave must not change a line that is already
/// drawn: its drawn generation is held. Lines not yet drawn take their
/// current generation, and everything refreshes once the camera settles.
public struct StrokeStabilityLedger: Equatable, Sendable {
    /// The stroke generation each drawn line is drawn with.
    public private(set) var drawn: [String: Int] = [:]

    public init() {}

    public mutating func reset() { drawn = [:] }

    /// `current` is the latest stroke generation per line. Returns the
    /// generation to draw each line with.
    @discardableResult
    public mutating func resolve(current: [String: Int], moving: Bool) -> [String: Int] {
        var next: [String: Int] = [:]
        for (id, generation) in current {
            if moving, let held = drawn[id] {
                next[id] = held
            } else {
                next[id] = generation
            }
        }
        drawn = next
        return next
    }

    /// Lines whose drawn stroke lags their latest generation.
    public func held(current: [String: Int]) -> Set<String> {
        Set(drawn.filter { current[$0.key] != nil && current[$0.key] != $0.value }.keys)
    }
}
