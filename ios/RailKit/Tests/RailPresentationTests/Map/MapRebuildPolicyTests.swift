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

    @Test("The shipped stroke bucket is a quarter zoom; DEBUG may override it")
    func strokeStepConfiguration() {
        #expect(MapRebuildPolicy.defaultStrokeZoomStep == 0.25)
        #expect(MapRebuildPolicy.configuredStrokeZoomStep(environment: [:]) == 0.25)
        #expect(MapRebuildPolicy.configuredStrokeZoomStep(
            environment: [MapRebuildPolicy.strokeZoomStepEnvironmentKey: "0"]) == 0.25)
        #expect(MapRebuildPolicy.configuredStrokeZoomStep(
            environment: [MapRebuildPolicy.strokeZoomStepEnvironmentKey: "x"]) == 0.25)
        #if DEBUG
        #expect(MapRebuildPolicy.configuredStrokeZoomStep(
            environment: [MapRebuildPolicy.strokeZoomStepEnvironmentKey: "0.125"]) == 0.125)
        #endif
        #expect(MapRebuildPolicy.laneZoomDelta == MapRebuildPolicy.strokeZoomStep)
        // The website constant is unchanged; an explicit step still buckets it.
        #expect(MapRebuildPolicy.strokeBucket(zoom: 10.06, step: 0.125) == 80)
        #expect(MapRebuildPolicy.strokeBucket(zoom: 10.07, step: 0.125) == 81)
    }

    @Test("Laned geometry rebuilds only when the stroke zoom bucket changes")
    func laneScaleBoundary() throws {
        // The test process sets no override, so the policy runs at 0.25.
        try #require(MapRebuildPolicy.strokeZoomStep == 0.25)
        // 10 and 10.12 both round to bucket 40 at a step of 0.25.
        #expect(MapRebuildPolicy.strokeBucket(zoom: 10) == 40)
        #expect(MapRebuildPolicy.strokeBucket(zoom: 10.12) == 40)
        #expect(MapRebuildPolicy.nominalZoom(bucket: 40) == 10)
        #expect(MapRebuildPolicy.nominalZoom(bucket: 41) == 10.25)
        #expect(policy(
            zoom: 10.12,
            visibilityBucket: 10,
            builtZoomBucket: 10,
            builtVisibilityBucket: 10,
            hasLanedLines: true,
            builtLaneZoom: 10,
            builtLaneLODBucket: 1).shouldRebuild == false)
        // 10.13 rounds to bucket 41, so the boundary itself rebuilds.
        #expect(MapRebuildPolicy.strokeBucket(zoom: 10.13) == 41)
        #expect(policy(
            zoom: 10.13,
            visibilityBucket: 10,
            builtZoomBucket: 10,
            builtVisibilityBucket: 10,
            hasLanedLines: true,
            builtLaneZoom: 10,
            builtLaneLODBucket: 1).shouldRebuild)
        // No installed lane zoom is a different bucket from the live camera.
        #expect(policy(
            zoom: 10,
            visibilityBucket: 10,
            builtZoomBucket: 10,
            builtVisibilityBucket: 10,
            hasLanedLines: true,
            builtLaneZoom: nil,
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
