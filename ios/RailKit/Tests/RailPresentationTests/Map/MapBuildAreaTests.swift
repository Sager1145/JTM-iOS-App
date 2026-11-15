import Testing
@testable import RailPresentation

@Suite("MapBuildArea")
struct MapBuildAreaTests {
    @Test func growsEverySideByTheScreenPointPaddingInMapPoints() {
        let build = MapBuildArea.Rect(x: 1000, y: 2000, width: 600, height: 900)
        let area = MapBuildArea.expanded(build, mapPointsPerScreenPoint: 4)
        let pad = 256.0 * 4
        #expect(area == .init(x: 1000 - pad, y: 2000 - pad, width: 600 + 2 * pad, height: 900 + 2 * pad))
    }

    @Test func containsTheBuildRectSoNoLineAreaIsSmallerThanTheTripArea() {
        let build = MapBuildArea.Rect(x: 0, y: 0, width: 100, height: 100)
        let area = MapBuildArea.expanded(build, mapPointsPerScreenPoint: 0.5)
        #expect(area.x <= build.x && area.y <= build.y)
        #expect(area.x + area.width >= build.x + build.width)
        #expect(area.y + area.height >= build.y + build.height)
    }

    @Test func zeroScaleLeavesTheRectUnchanged() {
        let build = MapBuildArea.Rect(x: 5, y: 6, width: 7, height: 8)
        #expect(MapBuildArea.expanded(build, mapPointsPerScreenPoint: 0) == build)
    }
}
