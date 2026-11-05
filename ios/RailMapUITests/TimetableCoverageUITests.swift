import XCTest

@MainActor
final class TimetableCoverageUITests: XCTestCase {
    func testPartialDailyInventoryAndIncompleteTripsAreBothExplained() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-interface-language", "en"]
        EditorLaunchSupport.launchEditing(app, journey: hachiojiJourney(date: "2026-09-30"))
        XCTAssertTrue(app.descendants(matching: .any)["newTripForm"].firstMatch.waitForExistence(timeout: 30))

        // Entry moved: fill sheet (newTripFillDetails) -> newTripTimetableBrowse; picking applies immediately.
        let fill = app.buttons["newTripFillDetails"]
        XCTAssertTrue(EditorUITestSupport.reveal(fill, in: app), app.debugDescription)
        EditorUITestSupport.tap(fill, in: app)
        let picker = app.buttons["newTripTimetableBrowse"]
        XCTAssertTrue(picker.waitForExistence(timeout: 8), app.debugDescription)
        EditorUITestSupport.tap(picker, in: app)

        XCTAssertTrue(app.staticTexts["timetableInventoryIncomplete"]
            .waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.staticTexts["timetableTripsNotApplicable"]
            .waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.staticTexts["timetableInventoryIncomplete"].label.contains("still being researched"))
        XCTAssertTrue(app.staticTexts["timetableTripsNotApplicable"].label.contains("full routes unverified"))
    }

    private func hachiojiJourney(date: String) -> [String: Any] {
        [
            "id": "ui-hachioji",
            "number": "",
            "origin": "東京",
            "destination": "八王子",
            "region": "jp",
            "date": date,
            "visible": true,
            "stops": [
                EditorLaunchSupport.stop("東京", code: "003766", type: "origin"),
                EditorLaunchSupport.stop("新宿", code: "003700", type: "passenger_stop"),
                EditorLaunchSupport.stop("立川", code: "003634", type: "passenger_stop"),
                EditorLaunchSupport.stop("八王子", code: "003947", type: "destination"),
            ],
        ]
    }
}
