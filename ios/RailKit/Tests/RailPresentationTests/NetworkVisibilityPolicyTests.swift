import Foundation
import RailCore
import RailPresentation
import Testing

struct NetworkVisibilityPolicyTests {
    @Test(arguments: [(390.0, 844.0), (780.0, 1_688.0), (1_024.0, 1_366.0), (1_366.0, 1_024.0)])
    func sameContentFitHasSameDetail(width: Double, height: Double) {
        let policy = NetworkVisibilityPolicy(width: width, height: height)
        let reference = NetworkVisibilityPolicy(width: 390, height: 844)
        let shift = log2(min(width, height) / 390)
        for zoom in stride(from: -8.0, through: 20.0, by: 0.25) {
            #expect(abs(policy.visibilityZoom(cameraZoom: zoom)
                - reference.visibilityZoom(cameraZoom: zoom - shift)) < 1e-9)
        }
    }

    @Test("Phone landscape and portrait, at the same short edge, have the same detail")
    func phoneOrientationIsSymmetric() {
        let portrait = NetworkVisibilityPolicy(width: 390, height: 844)
        let landscape = NetworkVisibilityPolicy(width: 844, height: 390)
        for zoom in stride(from: -8.0, through: 20.0, by: 0.25) {
            #expect(portrait.visibilityZoom(cameraZoom: zoom) == landscape.visibilityZoom(cameraZoom: zoom))
        }
    }

    @Test("The adjustment clamps at extreme viewport sizes")
    func adjustmentClamps() {
        #expect(NetworkVisibilityPolicy(width: 2_000, height: 2_000)
            .visibilityZoom(cameraZoom: 10) == 10 - 1.5)
        #expect(NetworkVisibilityPolicy(width: 200, height: 200)
            .visibilityZoom(cameraZoom: 10) == 10 + 0.5)
    }

    @Test("A degenerate viewport applies no adjustment")
    func degenerateViewportIsUnadjusted() {
        #expect(NetworkVisibilityPolicy(width: 0, height: 0).visibilityZoom(cameraZoom: 5) == 5)
    }

    @Test("visibilityBucket floors the adjusted zoom")
    func visibilityBucketFloorsAdjustedZoom() {
        let policy = NetworkVisibilityPolicy(width: 780, height: 1_688)
        #expect(policy.visibilityBucket(cameraZoom: 8) == Int(floor(policy.visibilityZoom(cameraZoom: 8))))
    }

    @Test("The same boundary applies when zooming in and back out")
    func reversibleDetailBoundary() {
        let policy = NetworkVisibilityPolicy(width: 390, height: 844)
        let zooms = [7.99, 8, 8.01, 8, 7.99]
        #expect(zooms.map { policy.visibilityBucket(cameraZoom: $0) } == [7, 8, 8, 8, 7])
    }

    @Test("Short high-speed branches stay in the overview, ordinary branches wait")
    func backboneAndBranch() {
        #expect(lineFloor(rank: 0, km: 66) < -8)
        #expect(lineFloor(rank: 1, km: 66, region: "kr") < -8)
        #expect(lineFloor(rank: 1, km: 66, region: "hk") == 5)
        #expect(lineFloor(rank: 4, km: 10) == 7)
        #expect(lineFloor(rank: 1, km: 350) == 3)
        #expect(lineFloor(rank: 1, km: 150) == 4)
        #expect(lineFloor(rank: 3, km: 25) == 6)
    }

    @Test("Every shipped railway has monotonic detail and the full high-speed network survives overview")
    func shippedPackages() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        var backboneCounts: [String: Int] = [:]
        for region in ["jp", "tw", "hk", "mo", "kr", "us", "ca"] {
            let package = try CompactPackage.load(contentsOf:
                root.appendingPathComponent("app/public/rail/\(region)-2025.json"))
            let lengths = Visibility.groupLengthByLineId(package)
            var previous: Set<String> = []
            let thresholds = Dictionary(package.lines.map { line in
                let km = lengths[line.id] ?? 0
                return (line.id, NetworkVisibilityPolicy.lineMinZoomMapLibre(
                    portedMinZoom: Visibility.minZoomForLength(totalKm: km),
                    rank: line.rank, visibilityLengthKm: km, region: region,
                    operator: line.operator, name: line.name))
            }, uniquingKeysWith: { _, last in last })
            backboneCounts[region] = thresholds.values.filter { $0 < -8 }.count
            for zoom in -8...8 {
                let visible = Set(thresholds.filter { $0.value <= zoom - 1 }.keys)
                #expect(previous.isSubset(of: visible), "\(region) lost a line while zooming in")
                previous = visible
            }
            #expect(previous == Set(package.lines.map(\.id)))
        }
        // jp: nine Shinkansen; tw: THSR; kr: three 고속선; us: Acela, Brightline
        // and Amtrak's 36 rank-1 corridors; ca: VIA Rail's four and Amtrak's one.
        #expect(backboneCounts == ["jp": 9, "tw": 1, "kr": 3, "us": 38, "hk": 0, "mo": 0, "ca": 5])
    }

    @Test("Intercity operators stay in the overview regardless of rank; other rank-1 lines do not")
    func operatorBackbones() {
        #expect(NetworkVisibilityPolicy.isOverviewBackbone(rank: 1, region: "us", operator: "Amtrak"))
        #expect(NetworkVisibilityPolicy.isOverviewBackbone(rank: 1, region: "ca", operator: "Via Rail Canada"))
        #expect(NetworkVisibilityPolicy.isOverviewBackbone(rank: 1, region: "ca", operator: "Amtrak"))
        #expect(!NetworkVisibilityPolicy.isOverviewBackbone(rank: 1, region: "us", operator: "MBTA"))
        #expect(!NetworkVisibilityPolicy.isOverviewBackbone(rank: 1, region: "jp", operator: "Amtrak"))
        #expect(NetworkVisibilityPolicy.isOverviewBackbone(rank: 2, region: "jp", name: "山形新幹線"))
        #expect(!NetworkVisibilityPolicy.isOverviewBackbone(rank: 1, region: "jp", name: "東海道線"))
        #expect(lineFloor(rank: 1, km: 350, region: "us", operator: "Amtrak") < -8)
        #expect(lineFloor(rank: 1, km: 350, region: "us", operator: "Metra") == 3)
    }

    private func lineFloor(
        rank: Int, km: Double, region: String = "jp", operator: String? = nil
    ) -> Int {
        NetworkVisibilityPolicy.lineMinZoomMapLibre(
            portedMinZoom: Visibility.minZoomForLength(totalKm: km),
            rank: rank, visibilityLengthKm: km, region: region, operator: `operator`)
    }
}
