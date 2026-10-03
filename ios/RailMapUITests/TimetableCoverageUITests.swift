import XCTest

@MainActor
final class TimetableCoverageUITests: XCTestCase {
    func testPartialDailyInventoryAndIncompleteTripsAreBothExplained() {
        continueAfterFailure = false
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
        let picker = app.buttons["rideEditorServicePattern"]
        XCTAssertTrue(EditorUITestSupport.reveal(picker, in: app), app.debugDescription)
        XCTAssertTrue(picker.waitForExistence(timeout: 8))
        EditorUITestSupport.tap(picker, in: app)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.tap()
        search.typeText("はちおうじ")
        let legacy = app.buttons.matching(NSPredicate(
            format: "label CONTAINS %@", "東京〜八王子")).firstMatch
        XCTAssertTrue(legacy.waitForExistence(timeout: 8))
        legacy.tap()

        next.tap()
        next.tap()
        let includeDate = app.switches["Include a date"]
        XCTAssertTrue(includeDate.waitForExistence(timeout: 8))
        includeDate.switches.firstMatch.tap()
        let date = app.textFields["rideEditorDateInput"]
        XCTAssertTrue(date.waitForExistence(timeout: 8))
        let old = date.value as? String ?? ""
        date.tap()
        date.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,
                             count: old.count) + "2026-09-30")

        app.buttons["rideEditorPrevious"].tap()
        XCTAssertTrue(app.otherElements["rideEditorNumber"].textFields.firstMatch
            .waitForExistence(timeout: 8))
        app.buttons["rideEditorPrevious"].tap()
        XCTAssertTrue(EditorUITestSupport.reveal(picker, in: app), app.debugDescription)
        XCTAssertTrue(picker.waitForExistence(timeout: 8))
        EditorUITestSupport.tap(picker, in: app)
        let replace = app.buttons["rideEditorReplaceStops"].firstMatch
        XCTAssertTrue(replace.waitForExistence(timeout: 8))
        replace.tap()

        XCTAssertTrue(app.staticTexts["timetableInventoryIncomplete"]
            .waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.staticTexts["timetableTripsNotApplicable"]
            .waitForExistence(timeout: 15), app.debugDescription)
    }
}
