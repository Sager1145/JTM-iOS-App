import XCTest

@MainActor
final class StatisticsRhythmYearUITests: XCTestCase {
    func testPassportYearBarScopesRidesAndMonthColumns() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "stats"
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "expanded"
        app.launchEnvironment["RAILMAP_UI_TEST_SAMPLE"] = "new-year-grand-loop"
        app.launchEnvironment["RAILMAP_UI_TEST_STATS_REGION"] = "jp"
        app.launch()

        let bar = element("statisticsYearBar", in: app)
        XCTAssertTrue(bar.waitForExistence(timeout: 120))

        assertScope(january: 17, december: 22, rides: 39, in: app)
        select("2026", in: app)
        assertScope(january: 17, december: 0, rides: 17, in: app)
        select("2025", in: app)
        assertScope(january: 0, december: 22, rides: 22, in: app)
        select("allTime", in: app)
        assertScope(january: 17, december: 22, rides: 39, in: app)
    }

    private func select(_ range: String, in app: XCUIApplication) {
        let choice = element("statisticsYear-\(range)", in: app)
        for _ in 0..<10 where !choice.isHittable { app.swipeDown() }
        XCTAssertTrue(choice.isHittable)
        choice.tap()
        XCTAssertTrue(choice.isSelected)
    }

    private func assertScope(january: Int, december: Int, rides: Int, in app: XCUIApplication) {
        let rideCount = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "Rides")).firstMatch
        let countMatches = NSPredicate(format: "value == %@", String(rides))
        expectation(for: countMatches, evaluatedWith: rideCount)
        waitForExpectations(timeout: 120)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "PassportYear-\(rides)-rides"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let januaryColumn = element("statisticsRhythmColumn-1", in: app)
        for _ in 0..<8 where !januaryColumn.isHittable { app.swipeUp() }
        XCTAssertTrue(januaryColumn.isHittable)
        XCTAssertEqual(januaryColumn.value as? String, "\(january) train(s)")
        XCTAssertEqual(element("statisticsRhythmColumn-12", in: app).value as? String,
                       "\(december) train(s)")
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
