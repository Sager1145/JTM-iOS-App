import XCTest

/// Acceptance probe for the opt-in public-API rail surface. Passing this fixed
/// scene is a projection milestone, not production-network/backend acceptance.
@MainActor
final class MapIndependentRailPrototypeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RAILMAP_RUN_INDEPENDENT_RAIL_PROTOTYPE"] == "1",
            "Experimental map projection probe; opt in with ios/tools/run-independent-rail-prototype-tests.py.")
    }

    func testAnimatedCameraProjectionAgainstNativePresentation() throws {
        let app = launch(trace: true)
        let status = app.staticTexts["railIndependentPrototypeStatus"]
        try waitFor(status) { self.value("phase", $0) == 6 && self.value("referenceFrames", $0) > 120 }
        let metrics = status.label
        attach(app, metrics: metrics, name: "independent-rail-camera-trace")
        XCTAssertGreaterThan(value("samples", metrics), 300,
            "Too few independently displayed native marker samples to assess camera synchronization.")
        XCTAssertGreaterThan(value("fittedFrames", metrics), 120)
        XCTAssertGreaterThan(value("motionFitSamples", metrics), 30)
        XCTAssertLessThanOrEqual(value("holdoutFitP95Px", metrics), 1)
        XCTAssertGreaterThan(value("motionSamples", metrics), 30,
            "Moving-frame errors must be measured independently of settled samples.")
        XCTAssertLessThanOrEqual(value("motionErrorP95Px", metrics), 1)
        XCTAssertEqual(value("veilAlpha", metrics), 0.1, accuracy: 0.001)
        XCTAssertEqual(value("wrapBreaks", metrics), 0,
            "A connected route produced a visible date-line/world-copy discontinuity.")
        XCTAssertLessThanOrEqual(value("errorP95Px", metrics), 1,
            "The independent rail does not follow displayed native camera geometry within one device pixel.")
        XCTAssertLessThanOrEqual(value("pairedP95Ms", metrics), 16)
        XCTAssertLessThanOrEqual(value("projectionP95Ms", metrics), 8,
            "Public conversion of the 5,000-vertex probe exceeds the frozen projection frame budget.")
        XCTAssertLessThanOrEqual(value("paintP95Ms", metrics), 8)
        XCTAssertLessThanOrEqual(value("maxFrameGapMs", metrics), 150)
    }

    func testGesturesAndViewportResizeAgainstNativePresentation() throws {
#if !targetEnvironment(macCatalyst)
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch(trace: false)
        let status = app.staticTexts["railIndependentPrototypeStatus"]
        let target = app.otherElements["railMapGestureTarget"]
        try waitFor(status) { self.value("referenceFrames", $0) > 60 }
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        let initialDistance = value("cameraDistance", status.label)
        target.pinch(withScale: 1.5, velocity: 1)
        try waitFor(status) { abs(self.value("cameraDistance", $0) - initialDistance) > 50 }
        let initialHeading = value("cameraHeading", status.label)
        target.rotate(.pi / 4, withVelocity: .pi / 2)
        try waitFor(status) { abs(self.value("cameraHeading", $0) - initialHeading) > 5 }
        let initialLongitude = value("cameraLon", status.label)
        target.swipeLeft()
        try waitFor(status) { abs(self.value("cameraLon", $0) - initialLongitude) > 0.0001 }
        XCUIDevice.shared.orientation = .landscapeLeft
        let keepsPortrait = UIDevice.current.userInterfaceIdiom == .phone
        try waitFor(status) {
            keepsPortrait
                ? self.value("viewportHeight", $0) > self.value("viewportWidth", $0)
                : self.value("viewportWidth", $0) > self.value("viewportHeight", $0)
        }
        XCUIDevice.shared.orientation = .portrait
        try waitFor(status) { self.value("viewportHeight", $0) > self.value("viewportWidth", $0) }
        let metrics = status.label
        attach(app, metrics: metrics, name: "independent-rail-gestures-resize")
        XCTAssertGreaterThan(value("fittedFrames", metrics), 120)
        XCTAssertGreaterThan(value("motionFitSamples", metrics), 30)
        XCTAssertLessThanOrEqual(value("holdoutFitP95Px", metrics), 1)
        XCTAssertGreaterThan(value("motionSamples", metrics), 30,
            "Moving-frame errors must be measured independently of settled samples.")
        XCTAssertLessThanOrEqual(value("motionErrorP95Px", metrics), 1)
        XCTAssertEqual(value("veilAlpha", metrics), 0.1, accuracy: 0.001)
        XCTAssertLessThanOrEqual(value("errorP95Px", metrics), 1)
        XCTAssertLessThanOrEqual(value("pairedP95Ms", metrics), 16)
        XCTAssertLessThanOrEqual(value("projectionP95Ms", metrics), 8)
        XCTAssertLessThanOrEqual(value("maxFrameGapMs", metrics), 150)
#else
        throw XCTSkip("Pinch/rotate gestures are unavailable on Mac Catalyst")
#endif
    }

    func testNativePolylineRasterFrameProbe() throws {
        try captureNativeRaster(projection: "native")
    }

    func testDirectConvertNativePolylineRasterFrameProbe() throws {
        try captureNativeRaster(projection: "convert")
    }

    private func captureNativeRaster(projection: String) throws {
        let app = launch(trace: true, rasterReference: true, projection: projection)
        let status = app.staticTexts["railIndependentPrototypeStatus"]
        for phase in 0...3 {
            try waitFor(status) { self.value("phase", $0) == Double(phase) }
            attach(app, metrics: status.label, name: "same-frame-\(projection)-raster-phase-\(phase)")
        }
        // This is evidence collection: geometric acceptance still belongs to
        // the unchanged pixel-error assertions above and the native raster.
    }

    private func launch(trace: Bool, rasterReference: Bool = false, projection: String = "native") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-auto-focus-zoom", "NO", "-appearance", "light"]
        app.launchEnvironment["RAILMAP_UI_TEST_STORAGE_ID"] = UUID().uuidString
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "all"
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "compact"
        app.launchEnvironment["RAILMAP_UI_TEST_GESTURE_TARGET"] = "1"
        app.launchEnvironment["RAILMAP_UI_TEST_CAMERA"] = "35.68,139.77,0.06"
        app.launchEnvironment["RAILMAP_INDEPENDENT_RAIL_PROTOTYPE"] = "1"
        app.launchEnvironment["RAILMAP_INDEPENDENT_RAIL_TRACE"] = trace ? "1" : "0"
        app.launchEnvironment["RAILMAP_INDEPENDENT_RAIL_VERTICES"] = "5000"
        app.launchEnvironment["RAILMAP_INDEPENDENT_RAIL_PROJECTION"] = projection
        if rasterReference {
            app.launchEnvironment["RAILMAP_INDEPENDENT_RAIL_RASTER_REFERENCE"] = "1"
            app.launchEnvironment["RAILMAP_INDEPENDENT_RAIL_TRACE_DELAY"] = "10"
            app.launchEnvironment["RAILMAP_INDEPENDENT_RAIL_PHASE_DURATION"] = "4"
        }
        app.launch()
        return app
    }

    private func value(_ key: String, _ text: String) -> Double {
        for field in text.split(separator: ";") {
            let pair = field.split(separator: ":", maxSplits: 1).map(String.init)
            if pair.count == 2, pair[0] == key { return Double(pair[1]) ?? -1 }
        }
        return -1
    }

    private func waitFor(_ status: XCUIElement, condition: @escaping (String) -> Bool) throws {
        XCTAssertTrue(status.waitForExistence(timeout: 20))
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { object, _ in
            guard let status = object as? XCUIElement else { return false }
            return condition(status.label)
        }, object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 35), .completed, status.label)
    }

    private func attach(_ app: XCUIApplication, metrics: String, name: String) {
        print(name + ": " + metrics)
        let capture = app.screenshot()
        if name.hasPrefix("same-frame-") {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(name + ".png")
            do {
                try capture.pngRepresentation.write(to: file)
                print("RAIL_NATIVE_RASTER_ARTIFACT " + file.path)
            } catch { XCTFail("Cannot preserve native raster evidence: \(error)") }
        }
        let screenshot = XCTAttachment(screenshot: capture)
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let diagnostics = XCTAttachment(string: metrics)
        diagnostics.name = name + "-metrics"
        diagnostics.lifetime = .keepAlways
        add(diagnostics)
    }
}
