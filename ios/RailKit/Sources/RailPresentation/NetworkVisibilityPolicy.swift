import Foundation

/// Screen-space workload policy for the complete railway network. Dimensions are
/// logical points, independent of device type and display pixel density.
/// Camera zoom remains the renderer's 256-point-tile scale; only network
/// eligibility uses the detail delay. Recorded journeys keep their
/// own visibility rules and physical stroke geometry.
public struct NetworkVisibilityPolicy: Equatable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    /// At the same ground scale, a larger viewport covers more railway
    /// geometry. Delay detail there instead of admitting it earlier and then
    /// paying to build overlays that the vertex budget will discard.
    /// The shorter edge keeps rotation stable; narrow iPad and Mac windows
    /// use the phone's baseline. These offsets affect eligibility only, never
    /// stroke width, simplification, or recorded journeys.
    public var detailZoomDelay: Double {
        let shortEdge = min(width, height)
        if shortEdge >= 900 { return 1 }
        if shortEdge >= 600 { return 0.5 }
        return 0
    }

    public func visibilityZoom(cameraZoom: Double) -> Double {
        cameraZoom - detailZoomDelay
    }

    /// Native network floors are integers. Cache this independently of the
    /// camera bucket: a half-level delay crosses those floors mid-bucket.
    public func visibilityBucket(cameraZoom: Double) -> Int {
        Int(floor(visibilityZoom(cameraZoom: cameraZoom)))
    }
}
