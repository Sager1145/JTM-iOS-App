import XCTest

@MainActor
final class MapCameraIntentTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testSelectedJourneyKeepsWholeRouteWhilePanningAndZoomingAway() throws {
#if !targetEnvironment(macCatalyst)
        let app = launch(tab: "all", stage: "compact", selected: "20260703_01_haruka",
                         autoFocus: false, layers: "")
        let status = app.staticTexts["railMapRenderStatus"]
        // The selected Japanese route must remain installed even while the
        // camera starts in New York, far outside every route segment.
        try waitFor(status) {
            self.number("targetRideReady", $0) == 1
                && self.number("targetRouteParts", $0) > 0
                && self.number("installedTargetRouteParts", $0) == self.number("targetRouteParts", $0)
        }
        let expected = number("targetRouteParts", status.label)
        let target = app.otherElements["railMapGestureTarget"]
        XCTAssertTrue(target.waitForExistence(timeout: 8))
        let before = status.label
        target.swipeLeft()
        try waitFor(status) {
            abs(self.number("centerLon", $0) - self.number("centerLon", before)) > 0.001
                && self.number("covered", $0) == 1
        }
        XCTAssertEqual(number("installedTargetRouteParts", status.label), expected)
        let distance = number("distance", status.label)
        target.pinch(withScale: 0.5, velocity: -1)
        try waitFor(status) {
            self.number("distance", $0) > distance * 1.2 && self.number("covered", $0) == 1
        }
        XCTAssertEqual(number("installedTargetRouteParts", status.label), expected)
#else
        throw XCTSkip("Pinch/rotate gestures are unavailable on Mac Catalyst")
#endif
    }

    func testSelectedJourneyDoesNotReframeAfterLayoutReplacementOrStatistics() throws {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch(tab: "all", stage: "compact", selected: "20260703_01_haruka")
        let status = app.staticTexts["railMapRenderStatus"]
        try waitFor(status) {
            self.number("targetRideReady", $0) == 1
                && self.number("focusRevision", $0) == 1
                && (134...137).contains(self.number("centerLon", $0))
                && (33...36).contains(self.number("centerLat", $0))
        }
        // The launch selection uses the real journey-pick path. Preserve
        // that explicit focus through passive layout and destination changes.
        let before = status.label
        assertCameraStays(status, equalTo: before, for: 2)
        XCUIDevice.shared.orientation = .landscapeLeft
        let keepsPortrait = UIDevice.current.userInterfaceIdiom == .phone
        try waitFor(status) {
            keepsPortrait
                ? self.number("viewportHeight", $0) > self.number("viewportWidth", $0)
                : self.number("viewportWidth", $0) > self.number("viewportHeight", $0)
        }
        assertSameCamera(status.label, before)

        XCTAssertEqual(number("focusRevision", status.label), number("focusRevision", before))
        // Explicit picking now opens a separate journey menu. Close it before
        // using the source destination tabs; dismissal must preserve the map.
        let back = app.buttons["journeyBackToList"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        back.tap()
        assertCameraStays(status, equalTo: before, for: 2)

        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 8))
        tabs.buttons.element(boundBy: 1).tap()
        // Wait through the old animated statistics fit as well as the new
        // statistics redraw, so a transient preserved frame cannot pass.
        assertCameraStays(status, equalTo: before, for: 2)
        tabs.buttons.element(boundBy: 2).tap()
        assertCameraStays(status, equalTo: before, for: 2)
        XCTAssertEqual(number("focusRevision", status.label), number("focusRevision", before))
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
        try waitFor(status) { self.number("basemapMuted", $0) == 0 }
    }

    func testUserSelectionZoomsFromNearbyOverviewAndKeepsStationNames() throws {
        let app = launch(tab: "search", stage: "half", autoFocus: false,
                         camera: "32.5,135.4,10")
        let status = app.staticTexts["railMapRenderStatus"]
        try waitFor(status) {
            self.number("targetRideReady", $0) == 1 && abs(self.number("centerLat", $0) - 32.5) < 0.01
        }
        let before = number("distance", status.label)
        let row = app.descendants(matching: .any)["journeyRow-20260703_01_haruka"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        row.tap()
        try waitFor(status) { self.number("distance", $0) < before * 0.5 }
        let origin = app.descendants(matching: .any).matching(NSPredicate(
            format: "label BEGINSWITH %@ AND label CONTAINS %@", "Start ", "関西空港")).firstMatch
        XCTAssertTrue(origin.waitForExistence(timeout: 15), app.debugDescription)
        try waitFor(status) { self.number("basemapMuted", $0) == 0 }
        // Close the independent menu to restore the source map selection.
        let back = app.buttons["journeyBackToList"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        back.tap()
        try waitFor(status) { self.number("basemapMuted", $0) == 0 }
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

    func testRegionSelectionFramesWholeCountryWithAutoFocusDisabled() throws {
        let app = launch(tab: "all", stage: "compact", autoFocus: false, region: "all")
        let status = app.staticTexts["railMapRenderStatus"]
        try waitFor(status) {
            self.number("targetRideReady", $0) == 1 && abs(self.number("centerLon", $0) + 74.027) < 0.01
        }
        selectJapan(in: app)
        try waitFor(status) {
            self.number("centerLon", $0) > 125 && self.number("distance", $0) > 2_000_000
        }
        XCTAssertEqual(app.buttons["regionScopeButton"].firstMatch.value as? String, "Japan")
    }

    func testReselectingRegionZoomsFromOverviewEvenWhenCountryIsVisible() throws {
        let app = launch(tab: "all", stage: "compact", autoFocus: false,
                         camera: "35,136,60", region: "jp")
        let status = app.staticTexts["railMapRenderStatus"]
        try waitFor(status) {
            self.number("targetRideReady", $0) == 1 && abs(self.number("centerLat", $0) - 35) < 0.01
        }
        let before = number("distance", status.label)
        selectJapan(in: app)
        try waitFor(status) { self.number("distance", $0) < before * 0.8 }
        XCTAssertGreaterThan(number("distance", status.label), 2_000_000)
    }

    private func selectJapan(in app: XCUIApplication) {
        let region = app.buttons["regionScopeButton"].firstMatch
        XCTAssertTrue(region.waitForExistence(timeout: 10))
        region.tap()
        let japan = app.buttons["Japan"].firstMatch
        XCTAssertTrue(japan.waitForExistence(timeout: 5), app.debugDescription)
        japan.tap()
    }

    private func launch(tab: String, stage: String, selected: String? = nil,
                        autoFocus: Bool = true,
                        camera: String = "40.735,-74.027,0.016", region: String? = nil,
                        layers: String = "routes,focus") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["RAILMAP_UI_TEST_STORAGE_ID"] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-auto-focus-zoom", autoFocus ? "YES" : "NO"]
        if let region {
            app.launchArguments += ["-region-scope", region, "-interface-language", "en"]
        }
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = tab
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = stage
        app.launchEnvironment["RAILMAP_UI_TEST_SAMPLE"] = "train-store"
        app.launchEnvironment["RAILMAP_UI_TEST_QUERY"] = "haruka"
        app.launchEnvironment["RAILMAP_UI_TEST_READY_RIDE"] = "20260703_01_haruka"
        app.launchEnvironment["RAILMAP_UI_TEST_LAYERS"] = layers
        app.launchEnvironment["RAILMAP_UI_TEST_CAMERA"] = camera
        app.launchEnvironment["RAILMAP_UI_TEST_SELECT"] = selected
        app.launchEnvironment["RAILMAP_UI_TEST_GESTURE_TARGET"] = "1"
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
