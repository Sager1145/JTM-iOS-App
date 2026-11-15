import Testing
import RailPresentation

@Suite("TripAreaExtension")
struct TripAreaExtensionTests {
    typealias R = MapBuildArea.Rect

    @Test func containedCameraNeedsNoExtension() {
        let installed = R(x: 0, y: 0, width: 100, height: 100)
        #expect(TripAreaExtension.area(installed: installed, cameraPadded: R(x: 10, y: 10, width: 50, height: 50)) == nil)
        #expect(TripAreaExtension.area(installed: installed, cameraPadded: installed) == nil)
    }

    @Test func outgrownCameraYieldsTheUnion() {
        let installed = R(x: 0, y: 0, width: 100, height: 100)
        let area = TripAreaExtension.area(installed: installed, cameraPadded: R(x: -50, y: 20, width: 100, height: 300))
        #expect(area == R(x: -50, y: 0, width: 150, height: 320))
    }

    @Test func dueUsesTheLoadAheadInterval() {
        #expect(TripAreaExtension.isDue(now: 1, last: nil))
        #expect(!TripAreaExtension.isDue(now: 1.1, last: 1))
        #expect(TripAreaExtension.isDue(now: 1 + MapLoadAhead.interval + 0.05, last: 1))
    }
}
