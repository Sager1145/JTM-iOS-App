import RailPresentation
import Testing

struct MapRebuildPolicyTests {
    private func policy(
        zoom: Double = 12.2,
        visibilityBucket: Int = 12,
        viewportWidth: Double = 390,
        viewportHeight: Double = 844,
        builtZoomBucket: Int? = 12,
        builtVisibilityBucket: Int? = 12,
        builtViewportWidth: Double? = 390,
        builtViewportHeight: Double? = 844,
        hasLanedLines: Bool = false,
        builtLaneZoom: Double? = 12.2,
        builtLaneLODBucket: Int? = 2,
        visibleRectIsContained: Bool = true
    ) -> MapRebuildPolicy {
        MapRebuildPolicy(
            zoom: zoom,
            visibilityBucket: visibilityBucket,
            viewportWidth: viewportWidth,
            viewportHeight: viewportHeight,
            builtZoomBucket: builtZoomBucket,
            builtVisibilityBucket: builtVisibilityBucket,
            builtViewportWidth: builtViewportWidth,
            builtViewportHeight: builtViewportHeight,
            hasLanedLines: hasLanedLines,
            builtLaneZoom: builtLaneZoom,
            builtLaneLODBucket: builtLaneLODBucket,
            visibleRectIsContained: visibleRectIsContained)
    }

    @Test("Panning inside the padded build rect reuses the current geometry")
    func panWithinBuildRectReusesGeometry() {
        #expect(policy().shouldRebuild == false)
        #expect(policy(visibleRectIsContained: false).shouldRebuild)
    }

    @Test("Camera and visibility floors rebuild at their exact boundaries")
    func zoomAndVisibilityBoundaries() {
        #expect(policy(zoom: 12.999).shouldRebuild == false)
        #expect(policy(zoom: 13, builtZoomBucket: 12).shouldRebuild)
        #expect(policy(visibilityBucket: 11).shouldRebuild)
    }

    @Test("Any viewport dimension change rebuilds")
    func viewportChange() {
        #expect(policy(viewportWidth: 391).shouldRebuild)
        #expect(policy(viewportHeight: 843).shouldRebuild)
        #expect(policy(builtViewportWidth: nil).shouldRebuild)
    }

    @Test("Laned geometry rebuilds at the scale delta boundary")
    func laneScaleBoundary() {
        #expect(policy(
            zoom: 10.124,
            visibilityBucket: 10,
            builtZoomBucket: 10,
            builtVisibilityBucket: 10,
            hasLanedLines: true,
            builtLaneZoom: 10,
            builtLaneLODBucket: 1).shouldRebuild == false)
        #expect(policy(
            zoom: 10.125,
            visibilityBucket: 10,
            builtZoomBucket: 10,
            builtVisibilityBucket: 10,
            hasLanedLines: true,
            builtLaneZoom: 10,
            builtLaneLODBucket: 1).shouldRebuild)
    }

    @Test("Lane LOD crossing rebuilds before the scale delta is reached")
    func laneLODBoundary() {
        #expect(policy(
            zoom: 12.26,
            hasLanedLines: true,
            builtLaneZoom: 12.2,
            builtLaneLODBucket: 1).shouldRebuild)
    }
}
