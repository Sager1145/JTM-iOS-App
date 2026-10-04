import XCTest

@MainActor
final class StopDateTimeUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testJourneyDateIsSharedAndNextDayStopTimeShowsItsCivilDate() {
        let app = XCUIApplication()
        let compact = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        EditorLaunchSupport.launchEditing(app, journey: [
            "id": "uitest_\(compact.prefix(12))",
            "date": "2026-01-01",
            "number": "Date share",
            "origin": "Tokyo",
            "destination": "Shinagawa",
            "region": "jp",
            "stops": [
                EditorLaunchSupport.stop("Tokyo", code: "003768", type: "origin"),
                EditorLaunchSupport.stop("Shinagawa", code: "004092", type: "destination"),
            ],
        ])

        let first = app.buttons["rideEditorStop-0"]
        XCTAssertTrue(app.buttons["rideEditorCancel"].waitForExistence(timeout: 30))
        XCTAssertTrue(EditorUITestSupport.reveal(first, in: app), app.debugDescription)
        EditorUITestSupport.tap(first, in: app)

        // Edit mode always shows the shared journey date. The new-journey
        // include-date switch is not on this screen.
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

        app.navigationBars["Tokyo"].buttons.firstMatch.tap()
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
