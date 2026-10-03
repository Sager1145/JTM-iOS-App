import XCTest

@MainActor
final class StatisticsCalendarUITests: XCTestCase {
    func testCalendarRangeDeselectAndMutuallyExclusiveClassification() {
        let app = XCUIApplication()
        app.launchEnvironment["RAILMAP_UI_TEST_STORAGE_ID"] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "stats"
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "expanded"
        app.launchEnvironment["RAILMAP_UI_TEST_SAMPLE"] = "new-year-grand-loop"
        app.launchEnvironment["RAILMAP_UI_TEST_STATS_REGION"] = "jp"
        app.launch()

        let calendar = element("statisticsDateButton", in: app)
        XCTAssertTrue(calendar.waitForExistence(timeout: 120))
        assertRideCount(39, in: app)
        calendar.tap()
        XCTAssertTrue(element("statisticsCalendar", in: app).waitForExistence(timeout: 10))

        XCTAssertEqual(element("statisticsCalendarMonth", in: app).label, "January 2026")

        let january = element("statisticsCalendarDay-2026-01-01", in: app)
        XCTAssertTrue(january.isEnabled)
        XCTAssertFalse(element("statisticsCalendarDay-2026-01-02", in: app).isEnabled)
        january.tap()
        XCTAssertTrue(january.isSelected)
        app.buttons["Done"].tap()
        assertRideCount(17, in: app)

        // All Time is already selected, but tapping it must clear the calendar day.
        let allTime = element("statisticsYear-allTime", in: app)
        XCTAssertTrue(allTime.waitForExistence(timeout: 10))
        allTime.tap()
        assertRideCount(39, in: app)
        calendar.tap()
        XCTAssertTrue(element("statisticsCalendar", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(january.isSelected)
        january.tap()
        app.buttons["Done"].tap()
        assertRideCount(17, in: app)

        calendar.tap()
        XCTAssertTrue(element("statisticsCalendar", in: app).waitForExistence(timeout: 5))
        element("statisticsCalendarPrevious", in: app).tap()
        XCTAssertEqual(element("statisticsCalendarMonth", in: app).label, "December 2025")
        let december = element("statisticsCalendarDay-2025-12-31", in: app)
        XCTAssertTrue(december.waitForExistence(timeout: 5))
        december.tap()
        XCTAssertTrue(december.isSelected)
        XCTAssertEqual(element("statisticsCalendarSelection", in: app).label,
                       "2025-12-31 – 2026-01-01")
        app.buttons["Done"].tap()
        assertRideCount(39, in: app)
        calendar.tap()
        XCTAssertTrue(element("statisticsCalendar", in: app).waitForExistence(timeout: 5))

        // Removing an endpoint leaves the other date selected.
        december.tap()
        XCTAssertFalse(december.isSelected)
        XCTAssertEqual(element("statisticsCalendarSelection", in: app).label, "2026-01-01")

        let byGroup = element("statisticsClassification-journeyGroup", in: app)
        byGroup.tap()
        XCTAssertTrue(byGroup.isSelected)
        XCTAssertFalse(element("statisticsClassification-date", in: app).isSelected)
        XCTAssertFalse(element("statisticsCalendar", in: app).exists)
        XCTAssertTrue(element("statisticsGroup-all", in: app).exists)

        element("statisticsClassification-date", in: app).tap()
        XCTAssertFalse(byGroup.isSelected)
        XCTAssertEqual(element("statisticsCalendarSelection", in: app).label, "All")
        element("statisticsCalendarNext", in: app).tap()
        january.tap()
        XCTAssertTrue(january.isSelected)
        january.tap()
        XCTAssertFalse(january.isSelected)
        XCTAssertEqual(element("statisticsCalendarSelection", in: app).label, "All")

        // Switching classification with no narrowed scope must still finish loading.
        byGroup.tap()
        app.buttons["Done"].tap()
        assertRideCount(39, in: app)
        calendar.tap()
        XCTAssertTrue(byGroup.waitForExistence(timeout: 5))
        element("statisticsClassification-date", in: app).tap()
        app.buttons["Done"].tap()
        assertRideCount(39, in: app)
        calendar.tap()
        XCTAssertTrue(element("statisticsCalendar", in: app).waitForExistence(timeout: 5))

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "StatisticsCalendar"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func assertRideCount(_ count: Int, in app: XCUIApplication) {
        let rides = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "Rides")).firstMatch
        expectation(for: NSPredicate(format: "value == %@", String(count)), evaluatedWith: rides)
        waitForExpectations(timeout: 120)
    }

    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
}
