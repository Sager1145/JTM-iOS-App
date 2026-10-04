import XCTest

@MainActor
final class TimetableCoverageUITests: XCTestCase {
    func testPartialDailyInventoryAndIncompleteTripsAreBothExplained() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        EditorLaunchSupport.launchEditing(app, journey: hachiojiJourney(date: "2026-09-30"))
        XCTAssertTrue(app.descendants(matching: .any)["rideEditorForm"].firstMatch.waitForExistence(timeout: 30))

        let picker = app.buttons["rideEditorServicePattern"]
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
