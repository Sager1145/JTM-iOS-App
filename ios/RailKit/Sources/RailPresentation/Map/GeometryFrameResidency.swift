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
/// the frames together exceed `byteCap`. A memory warning drops everything
/// that is not current.
public struct GeometryFrameResidency: Equatable, Sendable {
    /// Least recently used first; the current frame is the last it was made.
    public private(set) var order: [String] = []
    public private(set) var current: String?
    public private(set) var neighbour: String?
    public private(set) var frameBytes: [String: Int] = [:]
    public let byteCap: Int

    public init(byteCap: Int) { self.byteCap = max(byteCap, 0) }

    public var totalBytes: Int { frameBytes.values.reduce(0, +) }

    /// Whether another neighbour may be prebuilt: resident geometry is under the cap.
    public var hasRoomToPrebuild: Bool { totalBytes < byteCap }

    /// Makes `key` the current frame. Returns the keys evicted.
    public mutating func begin(_ key: String) -> [String] {
        touch(key)
        current = key
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

    /// Memory pressure: everything but the current frame goes.
    public mutating func dropNonCurrent() -> [String] {
        let dropped = order.filter { $0 != current }
        order.removeAll { $0 != current }
        for key in dropped { frameBytes.removeValue(forKey: key) }
        neighbour = nil
        return dropped
    }

    private mutating func touch(_ key: String) {
        order.removeAll { $0 == key }
        order.append(key)
        if frameBytes[key] == nil { frameBytes[key] = 0 }
    }

    private mutating func evict() -> [String] {
        var evicted: [String] = []
        while totalBytes > byteCap,
              let index = order.firstIndex(where: { $0 != current && $0 != neighbour }) {
            let key = order.remove(at: index)
            frameBytes.removeValue(forKey: key)
            evicted.append(key)
        }
        return evicted
    }
}
