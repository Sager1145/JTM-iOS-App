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

    @Test func aPrebuildOfTheLevelTheCameraReachedIsKept() {
        // Installed 24 (zoom 12), prebuilding 23, camera at 11.4 now wants 23.
        #expect(GeometryZoomLevels.wantedLevel(zoom: 11.4, installed: 24) == 23)
        #expect(GeometryZoomLevels.keepsNeighbourPrebuild(levels: [23], zoom: 11.4, installed: 24))
        // Its idle neighbour is kept too.
        #expect(GeometryZoomLevels.keepsNeighbourPrebuild(levels: [22], zoom: 11.4, installed: 24))
    }

    @Test func aPrebuildTwoLevelsAwayIsCancelled() {
        #expect(!GeometryZoomLevels.keepsNeighbourPrebuild(levels: [21], zoom: 11.4, installed: 24))
        #expect(!GeometryZoomLevels.keepsNeighbourPrebuild(levels: [25, 21], zoom: 11.4, installed: 24))
    }

    @Test func aCoarserPrebuildRectScalesAboutTheCentre() {
        let visible = MapBuildArea.Rect(x: 100, y: 200, width: 40, height: 60)
        // Camera at level 24's nominal zoom (12); level 23 is half a zoom out.
        let out = GeometryZoomLevels.prebuildVisibleRect(visible: visible, zoom: 12, level: 23)
        #expect(abs(out.width / visible.width - 2.0.squareRoot()) < 1e-9)
        #expect(abs(out.height / visible.height - 2.0.squareRoot()) < 1e-9)
        #expect(abs((out.x + out.width / 2) - (visible.x + visible.width / 2)) < 1e-9)
        #expect(abs((out.y + out.height / 2) - (visible.y + visible.height / 2)) < 1e-9)
    }

    @Test func aFinerOrEqualPrebuildRectIsUnchanged() {
        let visible = MapBuildArea.Rect(x: 100, y: 200, width: 40, height: 60)
        #expect(GeometryZoomLevels.prebuildVisibleRect(visible: visible, zoom: 12, level: 25) == visible)
        #expect(GeometryZoomLevels.prebuildVisibleRect(visible: visible, zoom: 12, level: 24) == visible)
    }

    @Test func aRunningPrebuildSurvivesASmallCameraMove() {
        let running = MapBuildArea.Rect(x: 0, y: 0, width: 100, height: 100)
        #expect(GeometryZoomLevels.prebuildStillCovers(running: running, wanted: running))
        // Shifted by a fifth: 80 percent still inside.
        #expect(GeometryZoomLevels.prebuildStillCovers(
            running: running, wanted: .init(x: 20, y: 0, width: 100, height: 100)))
        // Shifted by most of its width, or disjoint: restart.
        #expect(!GeometryZoomLevels.prebuildStillCovers(
            running: running, wanted: .init(x: 60, y: 0, width: 100, height: 100)))
        #expect(!GeometryZoomLevels.prebuildStillCovers(
            running: running, wanted: .init(x: 500, y: 500, width: 10, height: 10)))
    }

    // MARK: - travel preparation

    @Test func zoomTravelReadsZeroOnceTheLastChangeIsStale() {
        var travel = ZoomTravel()
        for step in 0...10 { travel.note(zoom: 10 - Double(step) * 0.083, at: Double(step) * 0.1) }
        #expect(abs(travel.rate(at: 1.0) + 0.83) < 0.05)
        #expect(travel.rate(at: 1.0 + ZoomTravel.staleAfter + 0.01) == 0)
        // Noise is not travel.
        var still = ZoomTravel()
        still.note(zoom: 8, at: 0)
        still.note(zoom: 8.0004, at: 0.1)
        #expect(still.rate(at: 0.1) == 0)
    }

    @Test func travelLevelIsNilUnlessZoomingOutFastEnough() {
        func level(_ rate: Double, _ seconds: Double = 1) -> Int? {
            GeometryZoomLevels.travelLevel(zoom: 10, rate: rate, prepareSeconds: seconds, minimumLevel: 4)
        }
        #expect(level(0) == nil)
        #expect(level(0.8) == nil)
        #expect(level(-0.4) == nil)
        #expect(level(-0.5) == nil)
        // -0.8 zoom/s for 1 s: aims 1.2 further out, z8.8, level 18 (nominal 9).
        #expect(level(-0.8) == GeometryZoomLevels.nearestLevel(zoom: 10 - 1.2))
        // Never more than three zoom levels ahead, and never below the minimum.
        #expect(level(-2, 4) == GeometryZoomLevels.nearestLevel(zoom: 7))
        #expect(GeometryZoomLevels.travelLevel(zoom: 4, rate: -2, prepareSeconds: 4, minimumLevel: 4) == 4)
    }

    @Test func inFlightInstallsOnlyWhileItsRectCoversTheView() {
        func can(_ covers: Bool, _ stopped: Bool, _ requested: Bool) -> Bool {
            GeometryPreparationGate.inFlightCanInstall(
                rectCoversView: covers, stopped: stopped, isRequestedLevel: requested)
        }
        #expect(!can(false, false, true))
        #expect(!can(false, true, false))
        #expect(can(true, false, false))
        // Stopped: only the wanted level may hold the permit.
        #expect(!can(true, true, false))
        #expect(can(true, true, true))
    }

    @Test func gateCancelsOnlyAnInFlightForAnotherKeyThatCannotInstall() {
        let keep = GeometryPreparationGate.decide(
            inFlightKey: "a", requestedKey: "b", prebuildKey: nil, missingWork: true)
        #expect(!keep.cancelInFlight && !keep.start)
        let drop = GeometryPreparationGate.decide(
            inFlightKey: "a", requestedKey: "b", prebuildKey: nil, missingWork: true,
            inFlightCanInstall: false)
        #expect(drop.cancelInFlight && drop.start)
        let same = GeometryPreparationGate.decide(
            inFlightKey: "a", requestedKey: "a", prebuildKey: nil, missingWork: true,
            inFlightCanInstall: false)
        #expect(!same.cancelInFlight && !same.start)
    }
}
