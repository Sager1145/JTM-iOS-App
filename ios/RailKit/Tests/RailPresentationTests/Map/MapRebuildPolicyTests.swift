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
        builtGeometryLevel: Int? = 24,
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
            builtGeometryLevel: builtGeometryLevel,
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

    @Test("Laned geometry rebuilds only once the camera leaves the level's hysteresis band")
    func geometryLevelBoundary() {
        // Level 20 is zoom 10; the band is 0.25 + 0.2 = 0.45 either side.
        func laned(_ zoom: Double, level: Int?) -> MapRebuildPolicy {
            policy(zoom: zoom, visibilityBucket: 10, builtZoomBucket: 10,
                builtVisibilityBucket: 10, hasLanedLines: true, builtGeometryLevel: level)
        }
        #expect(laned(10.44, level: 20).shouldRebuild == false)
        #expect(laned(9.56, level: 20).shouldRebuild == false)
        #expect(laned(10.46, level: 20).shouldRebuild)
        // No installed level is a different level from the live camera.
        #expect(laned(10, level: nil).shouldRebuild)
        // Lines without lanes or strokes never need a level change.
        #expect(policy(zoom: 10.46, visibilityBucket: 10, builtZoomBucket: 10,
            builtVisibilityBucket: 10, hasLanedLines: false,
            builtGeometryLevel: 20).shouldRebuild == false)
    }
}
