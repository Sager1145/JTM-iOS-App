import XCTest

@MainActor
final class RailwayRouteEntryUITests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testNewJourneyCanOpenAndCancelRailwayRouteGuide() {
        let app = launchEditor(sheet: "new")
        let next = app.buttons["rideEditorNext"]
        XCTAssertTrue(next.waitForExistence(timeout: 30), "The new journey editor must show its first step.")
        next.tap()

        for (index, name, code) in [(0, "Tokyo", "003766"), (1, "Shinagawa", "004095")] {
            let row = app.descendants(matching: .any)["rideEditorStop-\(index)"].firstMatch
            reveal(row, in: app)
            row.tap()
            let field = app.otherElements["rideEditorStopName"].textFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 8), "Stop \(index) must expose its station name field.")
            field.tap()
            field.typeText(name)
            let suggestion = app.buttons["rideEditorStationSuggestion-\(code)"]
            XCTAssertTrue(suggestion.waitForExistence(timeout: 8), "Station search must resolve \(name) to \(code).")
            suggestion.tap()
            app.navigationBars.buttons.firstMatch.tap()
        }

        openAndCancelGuide(in: app)
        XCTAssertTrue(app.descendants(matching: .any)["rideEditorStop-0"].firstMatch.exists,
                      "Cancelling must retain the origin stop.")
        XCTAssertTrue(app.descendants(matching: .any)["rideEditorStop-1"].firstMatch.exists,
                      "Cancelling must retain the destination stop.")
        XCTAssertFalse(app.descendants(matching: .any)["rideEditorStop-2"].firstMatch.exists,
                       "Opening and cancelling the guide must leave the draft with exactly two stops.")
    }

    func testSavedJourneyCanOpenAndCancelRailwayRouteGuide() {
        let app = launchEditor(sheet: "edit")
        XCTAssertTrue(app.descendants(matching: .any)["rideEditorForm"].firstMatch.waitForExistence(timeout: 30),
                      "The saved journey launch harness must open the edit form.")
        openAndCancelGuide(in: app)
        XCTAssertTrue(app.buttons["rideEditorCancel"].exists,
                      "Cancelling the railway guide must keep the saved journey editor open.")
    }

    private func launchEditor(sheet: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-interface-language", "en"]
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "all"
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "expanded"
        app.launchEnvironment["RAILMAP_UI_TEST_SHEET"] = sheet
        if sheet == "edit" {
            app.launchEnvironment["RAILMAP_UI_TEST_SAMPLE"] = "train-store"
        }
        app.launch()
        return app
    }

    private func openAndCancelGuide(in app: XCUIApplication) {
        let lines = app.buttons["rideEditorLines"]
        reveal(lines, in: app)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: lines)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 15), .completed,
                       "Railway route entry must become enabled for the journey's station codes.")
        lines.tap()
        for identifier in ["routeCorrectionFrom", "routeCorrectionTo", "routeCorrectionCompare", "routeCorrectionCancel"] {
            XCTAssertTrue(app.descendants(matching: .any)[identifier].firstMatch.waitForExistence(timeout: 8),
                          "Railway route entry must present the guided correction control \(identifier).")
        }
        let cancel = app.buttons["routeCorrectionCancel"]
        cancel.tap()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 8), "Cancel must dismiss the railway route guide.")
        XCTAssertTrue(app.descendants(matching: .any)["rideEditorForm"].firstMatch.waitForExistence(timeout: 8),
                      "The journey editor must remain open after cancelling the route guide.")
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let form = app.descendants(matching: .any)["rideEditorForm"].firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 8), "Scrolling requires the journey editor form.")
        for _ in 0..<14 {
            if element.exists && element.isHittable && element.frame.maxY < app.frame.maxY - 120 { break }
            let start = form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
            let end = form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(element.exists && element.isHittable,
                      "The editor form must reveal \(element.identifier) within fourteen scroll gestures.")
    }
}
