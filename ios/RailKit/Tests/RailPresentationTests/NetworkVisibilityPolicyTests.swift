import RailPresentation
import Testing

struct NetworkVisibilityPolicyTests {
    @Test(arguments: [
        (390.0, 844.0, 0.0),
        (844.0, 390.0, 0.0),
        (1_180.0, 599.0, 0.0),
        (600.0, 1_180.0, 0.5),
        (834.0, 1_194.0, 0.5),
        (1_194.0, 834.0, 0.5),
        (1_500.0, 899.0, 0.5),
        (1_500.0, 900.0, 1.0),
        (1_024.0, 1_366.0, 1.0),
    ])
    func windowDetailDelay(width: Double, height: Double, expected: Double) {
        let policy = NetworkVisibilityPolicy(width: width, height: height)
        #expect(policy.detailZoomDelay == expected)
    }

    @Test("Larger windows defer detail to limit the visible network workload")
    func detailThresholds() {
        let phone = NetworkVisibilityPolicy(width: 390, height: 844)
        let tablet = NetworkVisibilityPolicy(width: 834, height: 1_194)
        let desktop = NetworkVisibilityPolicy(width: 1_500, height: 900)
        let smallLineFloor = 8.0
        #expect(phone.visibilityZoom(cameraZoom: 7.5) < smallLineFloor)
        #expect(phone.visibilityZoom(cameraZoom: 8) == smallLineFloor)
        #expect(tablet.visibilityZoom(cameraZoom: 8.49) < smallLineFloor)
        #expect(tablet.visibilityZoom(cameraZoom: 8.5) == smallLineFloor)
        #expect(desktop.visibilityZoom(cameraZoom: 8.99) < smallLineFloor)
        #expect(desktop.visibilityZoom(cameraZoom: 9) == smallLineFloor)
    }

    @Test("Both directions refresh when the visibility floor crosses inside a camera bucket")
    func fractionalCacheBoundary() {
        let tablet = NetworkVisibilityPolicy(width: 834, height: 1_194)
        #expect(tablet.visibilityBucket(cameraZoom: 8.49) == 7)
        #expect(tablet.visibilityBucket(cameraZoom: 8.5) == 8)
        #expect(tablet.visibilityBucket(cameraZoom: 8.51) == 8)
        #expect(tablet.visibilityBucket(cameraZoom: 8.49) == 7)
    }

    @Test("Resize can change visibility without a camera change")
    func resize() {
        let narrow = NetworkVisibilityPolicy(width: 599, height: 1_000)
        let wide = NetworkVisibilityPolicy(width: 600, height: 1_000)
        #expect(narrow.visibilityBucket(cameraZoom: 8.25) == 8)
        #expect(wide.visibilityBucket(cameraZoom: 8.25) == 7)
    }

    @Test("Growing the viewport never admits more detail at the same camera scale")
    func workloadDoesNotGrowThroughEarlierEligibility() {
        let windows = [(390.0, 844.0), (834.0, 1_194.0), (1_500.0, 900.0)]
        for zoom in stride(from: 3.0, through: 16.0, by: 0.25) {
            let levels = windows.map {
                NetworkVisibilityPolicy(width: $0.0, height: $0.1).visibilityZoom(cameraZoom: zoom)
            }
            #expect(levels[0] >= levels[1])
            #expect(levels[1] >= levels[2])
        }
    }
}
