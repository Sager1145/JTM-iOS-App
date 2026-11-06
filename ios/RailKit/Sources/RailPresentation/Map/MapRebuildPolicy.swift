import Foundation
import RailCore

/// The camera-state conditions that require the map's expensive geometry to
/// be rebuilt. MapKit owns projection and padded-rect construction; this
/// policy receives only their scalar outcomes so its boundaries remain
/// testable without a map view.
public struct MapRebuildPolicy: Equatable, Sendable {
    /// The shipped stroke bucket width. The website's
    /// `STROKE_REBUILD_ZOOM_STEP` stays 0.125; the app rebuilds every network
    /// stroke on a bucket change, so it uses half as many buckets.
    public static let defaultStrokeZoomStep: Double = 0.25

    /// DEBUG builds read `RAILMAP_STROKE_ZOOM_STEP` from the launch
    /// environment (a value in (0, 1]) to compare widths; release builds
    /// always use ``defaultStrokeZoomStep``.
    public static let strokeZoomStepEnvironmentKey = "RAILMAP_STROKE_ZOOM_STEP"

    public static func configuredStrokeZoomStep(environment: [String: String]) -> Double {
        #if DEBUG
        if let raw = environment[strokeZoomStepEnvironmentKey], let step = Double(raw),
           step > 0, step <= 1 {
            return step
        }
        #endif
        return defaultStrokeZoomStep
    }

    /// Stroke geometry is rebuilt when the camera crosses a bucket of this
    /// width. Resolved once per process.
    public static let strokeZoomStep: Double =
        configuredStrokeZoomStep(environment: ProcessInfo.processInfo.environment)

    /// Lane offsets scale with the same bucket as the strokes they offset.
    public static var laneZoomDelta: Double { strokeZoomStep }

    public static func strokeBucket(zoom: Double, step: Double = strokeZoomStep) -> Int {
        Int((zoom / step).rounded())
    }

    public static func nominalZoom(bucket: Int, step: Double = strokeZoomStep) -> Double {
        Double(bucket) * step
    }

    public var zoom: Double
    public var visibilityBucket: Int
    public var viewportWidth: Double
    public var viewportHeight: Double
    public var builtZoomBucket: Int?
    public var builtVisibilityBucket: Int?
    public var builtViewportWidth: Double?
    public var builtViewportHeight: Double?
    public var hasLanedLines: Bool
    public var builtLaneZoom: Double?
    public var builtLaneLODBucket: Int?
    public var visibleRectIsContained: Bool

    public init(
        zoom: Double,
        visibilityBucket: Int,
        viewportWidth: Double,
        viewportHeight: Double,
        builtZoomBucket: Int?,
        builtVisibilityBucket: Int?,
        builtViewportWidth: Double?,
        builtViewportHeight: Double?,
        hasLanedLines: Bool,
        builtLaneZoom: Double?,
        builtLaneLODBucket: Int?,
        visibleRectIsContained: Bool
    ) {
        self.zoom = zoom
        self.visibilityBucket = visibilityBucket
        self.viewportWidth = viewportWidth
        self.viewportHeight = viewportHeight
        self.builtZoomBucket = builtZoomBucket
        self.builtVisibilityBucket = builtVisibilityBucket
        self.builtViewportWidth = builtViewportWidth
        self.builtViewportHeight = builtViewportHeight
        self.hasLanedLines = hasLanedLines
        self.builtLaneZoom = builtLaneZoom
        self.builtLaneLODBucket = builtLaneLODBucket
        self.visibleRectIsContained = visibleRectIsContained
    }

    public var shouldRebuild: Bool {
        let laneScaleMoved = hasLanedLines
            && Self.strokeBucket(zoom: zoom) != builtLaneZoom.map { Self.strokeBucket(zoom: $0) }
        let laneLODBucketMoved = hasLanedLines
            && LaneLOD.resolve(zoom: zoom, previousBucket: builtLaneLODBucket).bucket
                != builtLaneLODBucket
        let viewportChanged = viewportWidth != builtViewportWidth
            || viewportHeight != builtViewportHeight

        return Int(floor(zoom)) != builtZoomBucket
            || visibilityBucket != builtVisibilityBucket
            || viewportChanged
            || laneScaleMoved
            || laneLODBucketMoved
            || visibleRectIsContained == false
    }
}
