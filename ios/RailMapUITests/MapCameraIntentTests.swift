import XCTest

@MainActor
final class MapCameraIntentTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testSelectedJourneyDoesNotReframeAfterLayoutReplacementOrStatistics() throws {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch(tab: "all", stage: "compact", selected: "20260703_01_haruka")
        let status = app.staticTexts["railMapRenderStatus"]
        try waitFor(status) {
            self.number("targetRideReady", $0) == 1 && abs(self.number("centerLon", $0) + 74.027) < 0.01
        }
        let before = status.label
        XCUIDevice.shared.orientation = .landscapeLeft
        try waitFor(status) {
            self.number("viewportWidth", $0) > self.number("viewportHeight", $0)
        }
        assertSameCamera(status.label, before)

        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 8))
        tabs.buttons.element(boundBy: 1).tap()
        // Wait through the old animated statistics fit as well as the new
        // statistics redraw, so a transient preserved frame cannot pass.
        assertCameraStays(status, equalTo: before, for: 2)
        tabs.buttons.element(boundBy: 2).tap()
        assertCameraStays(status, equalTo: before, for: 2)
    }

    func testUserSelectionFocusesWithAutoFocusDisabled() throws {
        let app = launch(tab: "search", stage: "expanded", autoFocus: false)
        let status = app.staticTexts["railMapRenderStatus"]
        try waitFor(status) {
            self.number("targetRideReady", $0) == 1 && abs(self.number("centerLon", $0) + 74.027) < 0.01
        }
        let row = app.descendants(matching: .any)["journeyRow-20260703_01_haruka"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        row.tap()
        try waitFor(status) { self.number("centerLon", $0) > 125 }
    }

    func testSelectedJourneyEndpointLabelsStaySeparate() throws {
        let app = launch(tab: "all", stage: "compact", selected: "20260703_01_haruka",
                         autoFocus: false, camera: "34.55,135.4,0.55")
        let status = app.staticTexts["railMapRenderStatus"]
        try waitFor(status) { self.number("targetRideReady", $0) == 1 }
        try waitFor(status) { self.number("centerLon", $0) > 125 }
        let origin = app.descendants(matching: .any).matching(NSPredicate(
            format: "label BEGINSWITH %@ AND label CONTAINS %@", "Start ", "関西空港")).firstMatch
        let destination = app.descendants(matching: .any).matching(NSPredicate(
            format: "label BEGINSWITH %@ AND label CONTAINS %@", "End ", "新大阪")).firstMatch
        XCTAssertTrue(origin.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(destination.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(origin.frame.intersects(destination.frame),
                       "Endpoint cards must occupy distinct screen space.")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "selected-haruka-role-labels"
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func launch(tab: String, stage: String, selected: String? = nil,
                        autoFocus: Bool = true,
                        camera: String = "40.735,-74.027,0.016") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-auto-focus-zoom", autoFocus ? "YES" : "NO"]
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = tab
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = stage
        app.launchEnvironment["RAILMAP_UI_TEST_SAMPLE"] = "train-store"
        app.launchEnvironment["RAILMAP_UI_TEST_QUERY"] = "haruka"
        app.launchEnvironment["RAILMAP_UI_TEST_READY_RIDE"] = "20260703_01_haruka"
        app.launchEnvironment["RAILMAP_UI_TEST_LAYERS"] = "routes,focus"
        app.launchEnvironment["RAILMAP_UI_TEST_CAMERA"] = camera
        app.launchEnvironment["RAILMAP_UI_TEST_SELECT"] = selected
        app.launch()
        return app
    }

    private func waitFor(_ status: XCUIElement, predicate: @escaping (String) -> Bool) throws {
        XCTAssertTrue(status.waitForExistence(timeout: 15))
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in predicate(status.label) }, object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 45), .completed, status.label)
    }

    private func assertCameraStays(_ status: XCUIElement, equalTo before: String, for seconds: TimeInterval) {
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            abs(self.number("centerLon", status.label) - self.number("centerLon", before)) > 0.01
                || abs(self.number("centerLat", status.label) - self.number("centerLat", before)) > 0.01
        }, object: status)
        moved.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: seconds), .completed, status.label)
        assertSameCamera(status.label, before)
    }

    private func assertSameCamera(_ actual: String, _ expected: String) {
        // Six-decimal diagnostics are compared in integer microdegrees, so a
        // decimal boundary such as -74.026000 vs -74.027000 remains exactly
        // the original 0.001-degree allowance rather than failing on binary
        // subtraction roundoff.
        for key in ["centerLon", "centerLat"] {
            let observed = (number(key, actual) * 1_000_000).rounded()
            let baseline = (number(key, expected) * 1_000_000).rounded()
            XCTAssertLessThanOrEqual(abs(observed - baseline), 1_000,
                                     "Before: \(expected)\nAfter: \(actual)")
        }
        XCTAssertEqual(number("distance", actual), number("distance", expected),
                       accuracy: max(1, number("distance", expected) * 0.02))
    }

    private func number(_ key: String, _ status: String) -> Double {
        let prefix = key + ":"
        guard let field = status.split(separator: ";").first(where: { $0.hasPrefix(prefix) }),
            let value = Double(field.dropFirst(prefix.count)) else { return .nan }
        return value
    }
}
