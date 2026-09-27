import XCTest

@MainActor
final class TrainServicePatternUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testSelectedPatternRechecksChangedDateWithoutReplacingStops() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "all"
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "expanded"
        app.launchEnvironment["RAILMAP_UI_TEST_SHEET"] = "new"
        app.launch()

        let next = app.buttons["rideEditorNext"]
        XCTAssertTrue(next.waitForExistence(timeout: 30))
        next.tap()

        let picker = app.buttons["rideEditorServicePattern"]
        XCTAssertTrue(picker.waitForExistence(timeout: 8))
        picker.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.tap()
        search.typeText("はちおうじ")
        let pattern = app.buttons.matching(NSPredicate(
            format: "label CONTAINS %@", "東京〜八王子")).firstMatch
        XCTAssertTrue(pattern.waitForExistence(timeout: 8))
        pattern.tap()

        let origin = app.descendants(matching: .any)["rideEditorStop-0"].firstMatch
        XCTAssertTrue(origin.waitForExistence(timeout: 8))
        XCTAssertTrue(origin.label.contains("東京"))
        origin.tap()

        let departure = app.textFields["rideEditorStopDeparture"]
        XCTAssertTrue(departure.waitForExistence(timeout: 8))
        departure.tap()
        departure.typeText("07:15")
        let ridden = app.switches["rideEditorStopRidden"]
        XCTAssertTrue(ridden.waitForExistence(timeout: 8))
        ridden.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()

        next.tap()
        let number = app.otherElements["rideEditorNumber"].textFields.firstMatch
        XCTAssertTrue(number.waitForExistence(timeout: 8))
        next.tap()

        let includeDate = app.switches["Include a date"]
        XCTAssertTrue(includeDate.waitForExistence(timeout: 8))
        includeDate.switches.firstMatch.tap()
        let date = app.otherElements["rideEditorDateInput"].textFields.firstMatch
        XCTAssertTrue(date.waitForExistence(timeout: 8))
        let oldValue = date.value as? String ?? ""
        date.tap()
        date.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,
                             count: oldValue.count) + "2026-10-12")
        XCTAssertTrue(app.descendants(matching: .any)["rideEditorPatternDateNotice"]
            .waitForExistence(timeout: 8))

        app.buttons["rideEditorPrevious"].tap()
        app.buttons["rideEditorPrevious"].tap()
        XCTAssertTrue(origin.waitForExistence(timeout: 8))
        XCTAssertTrue(origin.label.contains("東京"),
                      "Changing the ride date must not rewrite selected stops.")
        origin.tap()
        let departureAfter = app.textFields["rideEditorStopDeparture"]
        XCTAssertTrue(departureAfter.waitForExistence(timeout: 8))
        XCTAssertEqual(departureAfter.value as? String, "07:15")
        let riddenAfter = app.switches["rideEditorStopRidden"]
        XCTAssertTrue(riddenAfter.waitForExistence(timeout: 8))
        XCTAssertNotEqual(riddenAfter.value as? String, "1",
                          "A reader-cleared ride segment must survive the date change.")
    }
}
