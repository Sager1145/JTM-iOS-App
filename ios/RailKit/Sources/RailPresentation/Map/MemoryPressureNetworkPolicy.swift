import Foundation

/// A map rect as plain numbers, so the memory-pressure rules below are pure
/// and testable without MapKit.
public struct DisplayRectValue: Equatable, Sendable {
    public var x: Double, y: Double, width: Double, height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// True when `other` lies wholly inside this rect.
    public func contains(_ other: DisplayRectValue) -> Bool {
        other.x >= x && other.y >= y
            && other.x + other.width <= x + width
            && other.y + other.height <= y + height
    }
}

/// A camera request the display store answered: the rect it was asked for and
/// the zoom used to pick lines.
public struct DisplayCameraRequest: Equatable, Sendable {
    public var rect: DisplayRectValue
    public var cameraZoom: Double

    public init(rect: DisplayRectValue, cameraZoom: Double) {
        self.rect = rect
        self.cameraZoom = cameraZoom
    }
}

/// Which rects keep their lines through a memory-warning trim.
public enum MemoryTrimProtection {
    /// The last built rect and the rect on screen now. The camera can have
    /// moved since the last build (a pan or zoom in flight), so protecting only
    /// the built rect would evict lines the reader is looking at. A visible
    /// rect already inside the built one adds nothing.
    public static func protectedRects(
        lastBuilt: DisplayRectValue?, visible: DisplayRectValue?
    ) -> [DisplayRectValue] {
        switch (lastBuilt, visible) {
        case (nil, nil): return []
        case let (built?, nil): return [built]
        case let (nil, visible?): return [visible]
        case let (built?, visible?):
            return built.contains(visible) ? [built] : [built, visible]
        }
    }
}

/// Holds the idle prefetch ring back after a memory warning. The trim evicts
/// lines nothing needs; the ring would reload exactly those for the same
/// camera. It stays suspended until a request for a different rect or zoom
/// arrives, which is a camera that has moved on.
public struct MemoryPressurePrefetchGate: Equatable, Sendable {
    private var suspended = false
    private var baseline: DisplayCameraRequest?

    public init() {}

    public var isPrefetchSuspended: Bool { suspended }

    /// A memory warning trimmed the store; `lastRequest` is what it was
    /// answering (nil before any camera request).
    public mutating func suspend(after lastRequest: DisplayCameraRequest?) {
        suspended = true
        baseline = lastRequest
    }

    /// A camera request arrived. Any request that differs from the one the
    /// warning came during lifts the suspension.
    public mutating func noteRequest(_ request: DisplayCameraRequest) {
        guard suspended, request != baseline else { return }
        suspended = false
        baseline = nil
    }

    public mutating func reset() {
        suspended = false
        baseline = nil
    }
}
