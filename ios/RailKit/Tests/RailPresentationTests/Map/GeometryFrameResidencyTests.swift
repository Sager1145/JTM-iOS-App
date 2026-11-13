import Testing

@testable import RailPresentation

@Suite("GeometryFrameResidency")
struct GeometryFrameResidencyTests {
    @Test func underTheCapNothingIsEvicted() {
        var residency = GeometryFrameResidency(byteCap: 100)
        for key in ["a", "b", "c"] {
            _ = residency.begin(key)
            #expect(residency.setBytes(30, for: key).isEmpty)
        }
        #expect(residency.order == ["a", "b", "c"])
    }

    @Test func overTheCapEvictsLeastRecentlyUsedFirst() {
        var residency = GeometryFrameResidency(byteCap: 100)
        for key in ["a", "b", "c"] {
            _ = residency.begin(key)
            _ = residency.setBytes(40, for: key)
        }
        // c is current (pinned): only a and b count, 80 <= 100, nothing goes.
        #expect(residency.order == ["a", "b", "c"])
        // d becomes current, so a, b and c are all unpinned: 120 > 100 and the
        // least recently used (a) goes at once.
        #expect(residency.begin("d") == ["a"])
        #expect(residency.order == ["b", "c", "d"])
        _ = residency.setBytes(40, for: "d")
        _ = residency.begin("b")
        // e current: unpinned c, d, b = 120, and c was used least recently.
        #expect(residency.begin("e") == ["c"])
        #expect(residency.order == ["d", "b", "e"])
    }

    @Test func currentAndOneNeighbourAreNeverEvicted() {
        var residency = GeometryFrameResidency(byteCap: 10)
        _ = residency.begin("old")
        _ = residency.setBytes(50, for: "old")
        _ = residency.begin("cur")
        _ = residency.setBytes(50, for: "cur")
        #expect(!residency.order.contains("old"))
        _ = residency.pinNeighbour("n1")
        _ = residency.setBytes(50, for: "n1")
        #expect(residency.order.contains("cur") && residency.order.contains("n1"))
        // A second neighbour replaces the pin; the first becomes evictable.
        let evicted = residency.pinNeighbour("n2")
        #expect(evicted == ["n1"])
        #expect(residency.neighbour == "n2")
        #expect(residency.current == "cur")
    }

    @Test func aNeighbourBecomingCurrentIsNoLongerTheNeighbour() {
        var residency = GeometryFrameResidency(byteCap: 100)
        _ = residency.begin("a")
        _ = residency.pinNeighbour("b")
        _ = residency.begin("b")
        #expect(residency.neighbour == nil)
        #expect(residency.current == "b")
    }

    @Test func memoryWarningKeepsOnlyTheCurrentFrame() {
        var residency = GeometryFrameResidency(byteCap: 1_000)
        for key in ["a", "b", "c"] {
            _ = residency.begin(key)
            _ = residency.setBytes(10, for: key)
        }
        _ = residency.pinNeighbour("n")
        let dropped = residency.dropNonCurrent()
        #expect(Set(dropped) == ["a", "b", "n"])
        #expect(residency.order == ["c"])
        #expect(residency.neighbour == nil)
        #expect(residency.totalBytes == 10)
    }

    @Test func prebuildNeedsRoomUnderTheCap() {
        var residency = GeometryFrameResidency(byteCap: 100)
        _ = residency.begin("a")
        _ = residency.setBytes(99, for: "a")
        // The current frame is pinned and does not count, however large.
        #expect(residency.hasRoomToPrebuild)
        _ = residency.begin("b")
        // a is now unpinned at 99 < 100.
        #expect(residency.hasRoomToPrebuild)
        _ = residency.setBytes(100, for: "a")
        #expect(!residency.hasRoomToPrebuild)
    }

    @Test func prebuildNeighbourFollowsTheLastZoomDirection() {
        #expect(GeometryZoomLevels.prebuildNeighbour(of: 20, lastZoomDirection: 1) == 21)
        #expect(GeometryZoomLevels.prebuildNeighbour(of: 20, lastZoomDirection: -1) == 19)
        #expect(GeometryZoomLevels.prebuildNeighbour(of: 20, lastZoomDirection: 0) == 21)
    }

    @Test func bytesAreEstimatedFromVertexCounts() {
        #expect(GeometryFrameBytes.estimate(polylineVertices: 1_000, strokeVertices: 0) == 16_000)
        #expect(GeometryFrameBytes.estimate(polylineVertices: 0, strokeVertices: 100) == 4_800)
        #expect(GeometryFrameBytes.estimate(polylineVertices: -5, strokeVertices: -5) == 0)
    }

    @Test func pinnedFramesDoNotCountAgainstTheCap() {
        var residency = GeometryFrameResidency(byteCap: 100)
        _ = residency.begin("a")
        _ = residency.setBytes(30, for: "a")
        _ = residency.begin("b")
        _ = residency.setBytes(30, for: "b")
        _ = residency.begin("cur")
        _ = residency.setBytes(150, for: "cur")
        _ = residency.pinNeighbour("nb")
        _ = residency.setBytes(150, for: "nb")
        // Current + neighbour are 300 > 100, yet the unpinned a and b survive.
        #expect(residency.order.contains("a") && residency.order.contains("b"))
        #expect(residency.unpinnedBytes == 60)
        #expect(residency.hasRoomToPrebuild)
        // Growing the unpinned frames past the cap evicts the oldest: 30 + 80 > 100.
        _ = residency.setBytes(80, for: "b")
        #expect(!residency.order.contains("a"))
        #expect(residency.order.contains("b"))
    }
}
