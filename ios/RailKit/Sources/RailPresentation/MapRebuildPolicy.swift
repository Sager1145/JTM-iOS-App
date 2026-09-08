import Foundation
import RailCore

/// The camera-state conditions that require the map's expensive geometry to
/// be rebuilt. MapKit owns projection and padded-rect construction; this
/// policy receives only their scalar outcomes so its boundaries remain
/// testable without a map view.
public struct MapRebuildPolicy: Equatable, Sendable {
    public static let laneZoomDelta: Double = 0.125

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
            && abs(zoom - (builtLaneZoom ?? -Double.infinity)) >= Self.laneZoomDelta
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
