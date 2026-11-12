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
        // 120 > 100 after c: a goes, b stays.
        #expect(residency.order == ["b", "c"])
        _ = residency.begin("b")
        _ = residency.begin("d")
        let evicted = residency.setBytes(40, for: "d")
        #expect(evicted == ["c"])
        #expect(residency.order == ["b", "d"])
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
}
