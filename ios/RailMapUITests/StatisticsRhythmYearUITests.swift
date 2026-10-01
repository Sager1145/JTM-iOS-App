import XCTest

@MainActor
final class StatisticsRhythmYearUITests: XCTestCase {
    func testMonthColumnsStayWithinSelectedYear() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "stats"
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "expanded"
        app.launchEnvironment["RAILMAP_UI_TEST_SAMPLE"] = "new-year-grand-loop"
        app.launchEnvironment["RAILMAP_UI_TEST_STATS_REGION"] = "jp"
        app.launch()

        let menu = element("statisticsRhythmYearMenu", in: app)
        XCTAssertTrue(menu.waitForExistence(timeout: 120))
        for _ in 0..<8 where !menu.isHittable { app.swipeUp() }
        XCTAssertTrue(menu.isHittable)

        select(2026, from: menu, in: app)
        XCTAssertEqual(element("statisticsRhythmColumn-1", in: app).value as? String,
                       "17 train(s)")
        XCTAssertEqual(element("statisticsRhythmColumn-12", in: app).value as? String,
                       "0 train(s)")

        select(2025, from: menu, in: app)
        XCTAssertEqual(element("statisticsRhythmColumn-1", in: app).value as? String,
                       "0 train(s)")
        XCTAssertEqual(element("statisticsRhythmColumn-12", in: app).value as? String,
                       "22 train(s)")
    }

    private func select(_ year: Int, from menu: XCUIElement, in app: XCUIApplication) {
        menu.tap()
        let choice = element("statisticsRhythmYear-\(year)", in: app)
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        choice.tap()
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
