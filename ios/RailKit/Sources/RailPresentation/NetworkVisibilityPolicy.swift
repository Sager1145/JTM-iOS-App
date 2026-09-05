import Foundation

/// Screen-space allowance for the complete railway network. Dimensions are
/// logical points, independent of device type and display pixel density.
/// Camera zoom remains the renderer's 256-point-tile scale; only network
/// eligibility uses the additional allowance. Recorded journeys keep their
/// own visibility rules and physical stroke geometry.
public struct NetworkVisibilityPolicy: Equatable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    /// The shorter edge avoids granting phone landscape a tablet's density.
    /// A narrow iPad or Mac window follows the same rules as a phone.
    public var zoomAllowance: Double {
        let shortEdge = min(width, height)
        if shortEdge >= 900 { return 1 }
        if shortEdge >= 600 { return 0.5 }
        return 0
    }

    public func visibilityZoom(cameraZoom: Double) -> Double {
        cameraZoom + zoomAllowance
    }

    /// Native network floors are integers. Cache this independently of the
    /// camera bucket: a half-level allowance crosses those floors mid-bucket.
    public func visibilityBucket(cameraZoom: Double) -> Int {
        Int(floor(visibilityZoom(cameraZoom: cameraZoom)))
    }
}
