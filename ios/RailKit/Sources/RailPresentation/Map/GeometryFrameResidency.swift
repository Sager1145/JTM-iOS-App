import Foundation

/// Rough resident size of prepared network geometry, so frames can be held
/// under a byte cap rather than a count. Estimated from vertex counts.
public enum GeometryFrameBytes {
    /// An `MKPolyline` vertex is one `MKMapPoint`.
    public static let bytesPerPolylineVertex = 16
    /// A stroke build keeps its run coordinates, projected points and measures.
    public static let bytesPerStrokeVertex = 48

    public static func estimate(polylineVertices: Int, strokeVertices: Int) -> Int {
        max(polylineVertices, 0) * bytesPerPolylineVertex
            + max(strokeVertices, 0) * bytesPerStrokeVertex
    }
}

/// Which geometry frames stay resident. The current frame and at most one
/// neighbour (the one being prebuilt in the direction of the last zoom) are
/// pinned; every other frame is evicted, least recently used first, whenever
/// the unpinned frames together exceed `byteCap` or number more than
/// `maxUnpinnedFrames` (the byte estimate undercounts MapKit's own polyline
/// storage, so a frame count bounds the real heap too). One more frame, the
/// overview, is pinned beside them: the coarse frame a zoom-out lands on, so
/// the zoom-out does not wait to prepare it again. It is outside the count and
/// the byte cap, unless its own size passes `overviewPinByteCap`: then it is
/// not pinned and lives under normal residency like any other frame. A memory warning drops everything that is not current,
/// the overview included.
public struct GeometryFrameResidency: Equatable, Sendable {
    /// Least recently used first; the current frame is the last it was made.
    public private(set) var order: [String] = []
    public private(set) var current: String?
    public private(set) var neighbour: String?
    /// The pinned overview frame, if any. At most one: a new one unpins the old.
    public private(set) var overview: String?
    public private(set) var frameBytes: [String: Int] = [:]
    public let byteCap: Int
    public let maxUnpinnedFrames: Int
    /// Largest overview frame that is still pinned outside the caps.
    public let overviewPinByteCap: Int
    public static let defaultOverviewPinByteCap = 30 * 1024 * 1024

    public init(
        byteCap: Int, maxUnpinnedFrames: Int = .max,
        overviewPinByteCap: Int = GeometryFrameResidency.defaultOverviewPinByteCap
    ) {
        self.byteCap = max(byteCap, 0)
        self.maxUnpinnedFrames = max(maxUnpinnedFrames, 0)
        self.overviewPinByteCap = max(overviewPinByteCap, 0)
    }

    private func isPinned(_ key: String) -> Bool {
        key == current || key == neighbour || isPinnedOverview(key)
    }

    private func isPinnedOverview(_ key: String) -> Bool {
        key == overview && (frameBytes[key] ?? 0) <= overviewPinByteCap
    }

    /// Frames that are neither current, the pinned neighbour nor the overview.
    public var unpinnedFrameCount: Int {
        order.filter { !isPinned($0) }.count
    }

    public var totalBytes: Int { frameBytes.values.reduce(0, +) }

    /// Bytes held by frames that are neither current, the pinned neighbour nor
    /// the overview. Only these count against `byteCap`.
    public var unpinnedBytes: Int {
        frameBytes.filter { !isPinned($0.key) }.values.reduce(0, +)
    }

    /// Whether another neighbour may be prebuilt: unpinned geometry is under the cap.
    public var hasRoomToPrebuild: Bool { unpinnedBytes < byteCap }

    /// Makes `key` the current frame. Returns the keys evicted. An overview
    /// frame also becomes the pinned overview, replacing the previous one; a
    /// frame that is not an overview leaves the pin alone.
    public mutating func begin(_ key: String, isOverview: Bool = false) -> [String] {
        touch(key)
        current = key
        if isOverview { overview = key }
        if neighbour == key { neighbour = nil }
        return evict()
    }

    /// Pins `key` as the one neighbour (unpinning the previous one) without
    /// making it current. Returns the keys evicted.
    public mutating func pinNeighbour(_ key: String) -> [String] {
        guard key != current else { return [] }
        if !order.contains(key) {
            if let current, let index = order.firstIndex(of: current) {
                order.insert(key, at: index)
            } else {
                order.append(key)
            }
            frameBytes[key] = 0
        }
        neighbour = key
        return evict()
    }

    /// Records the estimated size of a resident frame. Returns the keys evicted.
    public mutating func setBytes(_ bytes: Int, for key: String) -> [String] {
        guard order.contains(key) else { return [] }
        frameBytes[key] = max(bytes, 0)
        return evict()
    }

    /// Memory pressure: everything but the current frame goes, the overview
    /// pin with it.
    public mutating func dropNonCurrent() -> [String] {
        let dropped = order.filter { $0 != current }
        order.removeAll { $0 != current }
        for key in dropped { frameBytes.removeValue(forKey: key) }
        neighbour = nil
        overview = nil
        return dropped
    }

    private mutating func touch(_ key: String) {
        order.removeAll { $0 == key }
        order.append(key)
        if frameBytes[key] == nil { frameBytes[key] = 0 }
    }

    private mutating func evict() -> [String] {
        var evicted: [String] = []
        while unpinnedBytes > byteCap || unpinnedFrameCount > maxUnpinnedFrames,
              let index = order.firstIndex(where: { !isPinned($0) }) {
            let key = order.remove(at: index)
            frameBytes.removeValue(forKey: key)
            evicted.append(key)
        }
        return evicted
    }
}
