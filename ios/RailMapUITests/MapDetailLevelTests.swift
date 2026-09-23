import XCTest

/// Native scale and backbone regressions, including the cold region loader.
@MainActor
final class MapDetailLevelTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testWidestViewKeepsHighSpeedNetworkAndRestoresLayer() throws {
        let app = launch(camera: "37,138,160")
        let status = app.staticTexts["railMapRenderStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 15))
        try waitFor(status) { self.number("camera", $0) < 4 && self.number("backbones", $0) >= 9 }
        let target = app.otherElements["railMapGestureTarget"]
        XCTAssertTrue(target.waitForExistence(timeout: 8))
        // Pull all the way back. The second pinch verifies MapKit's far limit
        // rather than mistaking an arbitrary national camera for maximum zoom.
        for _ in 0..<3 {
            target.pinch(withScale: 0.25, velocity: -1)
            Thread.sleep(forTimeInterval: 2)
        }
        try waitFor(status) { self.number("camera", $0) < 4 && self.number("backbones", $0) >= 9 }
        let widest = status.label
        assertViewportAdjustedDetail(widest)
        XCTAssertEqual(number("networkStations", widest), 0)
        XCTAssertEqual(number("budgetDrops", widest), 0)
        target.pinch(withScale: 0.25, velocity: -1)
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(number("distance", status.label), number("distance", widest), accuracy: 1_000)
        attach(app, status: status.label, name: "maximum-map-backbone")

        let toggle = app.buttons["mapNetworkToggle"]
        toggle.tap()
        XCTAssertFalse(toggle.isSelected)
        waitForNetworkOff(status)
        toggle.tap()
        XCTAssertTrue(toggle.isSelected)
        try waitFor(status) { self.number("backbones", $0) >= 9 }
        XCTAssertEqual(number("lines", status.label), number("lines", widest))
        attach(app, status: status.label, name: "maximum-map-layer-restored")
    }

    func testRotationPreservesScaleAndRailwayDetail() throws {
        let app = launch(camera: "35.68,139.75,0.12")
        let status = app.staticTexts["railMapRenderStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 15))
        try waitFor(status) { self.number("camera", $0) > 10 }
        let before = status.label
        let target = app.otherElements["railMapGestureTarget"]
        XCTAssertTrue(target.waitForExistence(timeout: 8))
        target.rotate(.pi / 3, withVelocity: 0.6)
        // Trigger a layer refresh at the rotated camera even when the padded
        // rect contains it; a pure rotation need not rebuild geometry itself.
        Thread.sleep(forTimeInterval: 2)
        app.buttons["mapNetworkToggle"].tap()
        waitForNetworkOff(status)
        app.buttons["mapNetworkToggle"].tap()
        try waitFor(status) { abs(sin(self.number("heading", $0) * .pi / 180)) > 0.2 }
        XCTAssertEqual(number("camera", status.label), number("camera", before), accuracy: 0.08)
        assertViewportAdjustedDetail(status.label)
        attach(app, status: status.label, name: "rotation-detail-scale")
    }

    private func assertViewportAdjustedDetail(
        _ status: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        let shortEdge = min(number("viewportWidth", status), number("viewportHeight", status))
        XCTAssertGreaterThan(shortEdge, 0, file: file, line: line)
        guard shortEdge > 0 else { return }
        // Detail is calibrated to a 390-point viewport, not raw camera zoom.
        // Compute the expected offset independently from the reported bounds.
        let adjustment = min(0.5, max(-1.5, log2(390 / shortEdge)))
        XCTAssertEqual(number("lod", status), number("camera", status) + adjustment,
                       accuracy: 0.01, file: file, line: line)
    }

    private func launch(camera: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-AppleInterfaceStyle", "Light", "-appearance", "light"]
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "all"
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "compact"
        app.launchEnvironment["RAILMAP_UI_TEST_LAYERS"] = "network,routes"
        app.launchEnvironment["RAILMAP_UI_TEST_GESTURE_TARGET"] = "1"
        app.launchEnvironment["RAILMAP_UI_TEST_CAMERA"] = camera
        app.launch()
        return app
    }

    private func waitFor(_ status: XCUIElement, condition: (String) -> Bool) throws {
        let deadline = Date().addingTimeInterval(30)
        repeat {
            let value = status.label
            if value.hasPrefix("network:rendered;"), number("covered", value) == 1, condition(value) { return }
            Thread.sleep(forTimeInterval: 0.75)
        } while Date() < deadline
        XCTFail("Railway state did not settle: \(status.label)")
    }

    private func waitForNetworkOff(_ status: XCUIElement) {
        let predicate = NSPredicate(format: "label BEGINSWITH %@", "network:off;lines:0;overlays:0")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed)
    }

    private func number(_ name: String, _ status: String) -> Double {
        let field = status.split(separator: ";").first { $0.hasPrefix("\(name):") }
        return field.flatMap { Double($0.dropFirst(name.count + 1)) } ?? -.infinity
    }

    private func attach(_ app: XCUIApplication, status: String, name: String) {
        print("[\(name)] \(status)")
        for attachment in [XCTAttachment(string: status), XCTAttachment(screenshot: app.screenshot())] {
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
