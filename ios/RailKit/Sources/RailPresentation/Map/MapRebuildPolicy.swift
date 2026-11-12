import Foundation
import RailCore

/// The camera-state conditions that require the map's expensive geometry to
/// be rebuilt. MapKit owns projection and padded-rect construction; this
/// policy receives only their scalar outcomes so its boundaries remain
/// testable without a map view.
public struct MapRebuildPolicy: Equatable, Sendable {
    public var zoom: Double
    public var visibilityBucket: Int
    public var viewportWidth: Double
    public var viewportHeight: Double
    public var builtZoomBucket: Int?
    public var builtVisibilityBucket: Int?
    public var builtViewportWidth: Double?
    public var builtViewportHeight: Double?
    public var hasLanedLines: Bool
    /// The geometry level (``GeometryZoomLevels``) the installed overlays
    /// were built at.
    public var builtGeometryLevel: Int?
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
        builtGeometryLevel: Int?,
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
        self.builtGeometryLevel = builtGeometryLevel
        self.visibleRectIsContained = visibleRectIsContained
    }

    public var shouldRebuild: Bool {
        // Lane gap, corner rounding and simplification are baked per level.
        // The wanted level moves only past the hysteresis, so a camera
        // hovering near a boundary does not flap.
        let geometryLevelMoved = hasLanedLines
            && (builtGeometryLevel.map {
                GeometryZoomLevels.wantedLevel(zoom: zoom, installed: $0) != $0
            } ?? true)
        let viewportChanged = viewportWidth != builtViewportWidth
            || viewportHeight != builtViewportHeight

        return Int(floor(zoom)) != builtZoomBucket
            || visibilityBucket != builtVisibilityBucket
            || viewportChanged
            || geometryLevelMoved
            || visibleRectIsContained == false
    }
}
