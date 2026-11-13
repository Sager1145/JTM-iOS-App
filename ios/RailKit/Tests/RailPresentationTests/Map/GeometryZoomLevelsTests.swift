import RailPresentation
import Testing

struct GeometryZoomLevelsTests {
    @Test func levelChoiceWithoutHistoryIsNearest() {
        #expect(GeometryZoomLevels.wantedLevel(zoom: 12.0, installed: nil) == 24)
        #expect(GeometryZoomLevels.wantedLevel(zoom: 12.2, installed: nil) == 24)
        #expect(GeometryZoomLevels.wantedLevel(zoom: 12.3, installed: nil) == 25)
    }

    @Test func installedLevelHoldsInsideHysteresis() {
        // Level 24 is z12; it holds until more than 0.45 away.
        #expect(GeometryZoomLevels.wantedLevel(zoom: 12.44, installed: 24) == 24)
        #expect(GeometryZoomLevels.wantedLevel(zoom: 11.56, installed: 24) == 24)
        #expect(GeometryZoomLevels.wantedLevel(zoom: 12.46, installed: 24) == 25)
        #expect(GeometryZoomLevels.wantedLevel(zoom: 11.54, installed: 24) == 23)
    }

    @Test func sweepAcrossABoundaryChangesAtMostOnceEachWay() {
        var installed = 24
        var changes = 0
        var z = 12.0
        while z <= 12.6 {
            let w = GeometryZoomLevels.wantedLevel(zoom: z, installed: installed)
            if w != installed { changes += 1; installed = w }
            z += 0.01
        }
        #expect(changes == 1 && installed == 25)
        while z >= 11.8 {
            let w = GeometryZoomLevels.wantedLevel(zoom: z, installed: installed)
            if w != installed { changes += 1; installed = w }
            z -= 0.01
        }
        #expect(changes == 2 && installed == 24)
    }

    @Test func jitterAroundTheMidpointNeverFlaps() {
        var installed = 24
        var changes = 0
        for i in 0..<400 {
            let z = 12.25 + (i.isMultiple(of: 2) ? 0.1 : -0.1)
            let w = GeometryZoomLevels.wantedLevel(zoom: z, installed: installed)
            if w != installed { changes += 1; installed = w }
        }
        #expect(changes == 0)
    }

    @Test func neighbourSetIsOneBelowAndOneAbove() {
        #expect(GeometryZoomLevels.neighbourLevels(of: 24) == [23, 25])
    }

    @Test func midGestureSwapNeedsDriftAndReadiness() {
        let swap = GeometryZoomLevels.shouldSwapDuringGesture
        #expect(swap(12.6, 24, 25, true))
        #expect(!swap(12.6, 24, 25, false))
        #expect(!swap(12.5, 24, 25, true))   // exactly 0.5: not past it
        #expect(!swap(12.6, 24, 24, true))   // already wanted
        #expect(swap(11.4, 24, 23, true))
    }

    @Test func levelGeometryEvaluatesAtNominalZoom() {
        #expect(GeometryZoomLevels.nominalZoom(level: 25) == 12.5)
        #expect(GeometryZoomLevels.laneLOD(level: 17).bucket == 0)
        #expect(GeometryZoomLevels.laneLOD(level: 18).bucket == 1)
        #expect(GeometryZoomLevels.laneLOD(level: 23).bucket == 1)
        #expect(GeometryZoomLevels.laneLOD(level: 24).bucket == 2)
        #expect(GeometryZoomLevels.laneLOD(level: 24).scale == 1)
    }

    @Test func cacheKeyDistinguishesLevelAndGeneration() {
        let a = GeometryLevelCacheKey(lineID: "x", level: 24, strokeGeneration: 1)
        #expect(a != GeometryLevelCacheKey(lineID: "x", level: 25, strokeGeneration: 1))
        #expect(a != GeometryLevelCacheKey(lineID: "x", level: 24, strokeGeneration: 2))
        #expect(a == GeometryLevelCacheKey(lineID: "x", level: 24, strokeGeneration: 1))
    }

    @Test func gateKeepsWantedPreparationOnTouchDown() {
        let cancels = GeometryPreparationGate.cancelsOnTouchDown
        #expect(!cancels(24, 12.1, 24))        // wanted level
        #expect(!cancels(25, 12.1, 24))        // neighbour, pre-building
        #expect(cancels(27, 12.1, 24))         // level the camera has left
        #expect(!cancels(nil, 12.1, 24))       // nothing in flight
    }

    @Test("Swapping whenever the level is wanted bounds the baked-zoom error by half a zoom")
    func installedErrorStaysWithinHalfZoom() {
        var installed = GeometryZoomLevels.nearestLevel(zoom: 8)
        var worst = 0.0
        var z = 8.0
        for step in 0...1200 {
            // Zoom in, then back out.
            z = step <= 600 ? 8 + Double(step) * 0.01 : 14 - Double(step - 600) * 0.01
            installed = GeometryZoomLevels.wantedLevel(zoom: z, installed: installed)
            worst = max(worst, abs(z - GeometryZoomLevels.nominalZoom(level: installed)))
        }
        #expect(worst <= GeometryZoomLevels.spacing / 2 + GeometryZoomLevels.hysteresis)
        #expect(worst < GeometryZoomLevels.spacing)
    }
}
