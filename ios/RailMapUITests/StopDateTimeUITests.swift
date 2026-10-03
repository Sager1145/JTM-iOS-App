import XCTest

@MainActor
final class StopDateTimeUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testJourneyDateIsSharedAndNextDayStopTimeShowsItsCivilDate() {
        let app = XCUIApplication()
        app.launchEnvironment["RAILMAP_UI_TEST_STORAGE_ID"] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "all"
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "expanded"
        app.launchEnvironment["RAILMAP_UI_TEST_SHEET"] = "new"
        app.launch()

        let next = app.buttons["rideEditorNext"]
        XCTAssertTrue(next.waitForExistence(timeout: 30))
        next.tap()
        let first = app.buttons["rideEditorStop-0"]
        XCTAssertTrue(EditorUITestSupport.reveal(first, in: app), app.debugDescription)
        XCTAssertTrue(first.waitForExistence(timeout: 8))
        EditorUITestSupport.tap(first, in: app)

        let includeDate = app.switches["rideEditorStopIncludeDate"]
        XCTAssertTrue(includeDate.waitForExistence(timeout: 8))
        let control = includeDate.switches.firstMatch
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        if includeDate.value as? String == "0" { control.tap() }
        XCTAssertEqual(includeDate.value as? String, "1")
        let date = app.textFields["rideEditorStopJourneyDate"]
        for _ in 0..<8 where !date.exists { app.swipeUp() }
        XCTAssertTrue(date.waitForExistence(timeout: 8), app.debugDescription)
        let previousDate = date.value as? String ?? ""
        date.tap()
        date.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,
                             count: previousDate.count) + "2026-10-12")
        XCTAssertEqual(date.value as? String, "2026-10-12")

        let departure = app.textFields["rideEditorStopDeparture"]
        for _ in 0..<8 where !departure.isHittable { app.swipeUp() }
        XCTAssertTrue(departure.waitForExistence(timeout: 8))
        departure.tap()
        departure.typeText("25:10")
        XCTAssertTrue(app.descendants(matching: .any)["rideEditorStopDepartureDate"].exists,
                      "A stop time should offer an actual calendar date.")
        let civilTime = app.staticTexts["rideEditorStopDepartureCivil"]
        XCTAssertTrue(civilTime.waitForExistence(timeout: 8))
        XCTAssertTrue(civilTime.label.contains("2026-10-13 01:10"), civilTime.label)

        app.navigationBars.buttons.element(boundBy: 0).tap()
        let firstSummary = app.buttons["rideEditorStop-0"]
        XCTAssertTrue(EditorUITestSupport.reveal(firstSummary, in: app), app.debugDescription)
        XCTAssertTrue(firstSummary.waitForExistence(timeout: 8))
        XCTAssertTrue(firstSummary.label.contains("2026-10-13 01:10"), firstSummary.label)
        let second = app.buttons["rideEditorStop-1"]
        EditorUITestSupport.tap(second, in: app)
        let sharedDate = app.textFields["rideEditorStopJourneyDate"]
        XCTAssertTrue(sharedDate.waitForExistence(timeout: 8))
        XCTAssertEqual(sharedDate.value as? String, "2026-10-12")
        let secondDeparture = app.textFields["rideEditorStopDeparture"]
        for _ in 0..<8 where !secondDeparture.exists { app.swipeUp() }
        XCTAssertTrue(secondDeparture.waitForExistence(timeout: 8))
        XCTAssertTrue(["", "H:MM"].contains(secondDeparture.value as? String ?? ""))
    }
}
