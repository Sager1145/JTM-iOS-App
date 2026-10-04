import XCTest

@MainActor
final class JourneyGroupUITests: XCTestCase {
    func testDraftGroupNameRemainsEditableWhenReselectedAndAfterConfirmation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        let compact = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        EditorLaunchSupport.launchEditing(app, journey: [
            "id": "uitest_\(compact.prefix(12))",
            "date": "2026-10-12",
            "number": "Group draft",
            "origin": "Tokyo",
            "destination": "Shinagawa",
            "region": "jp",
            "stops": [
                EditorLaunchSupport.stop("Tokyo", code: "003768", type: "origin", departure: "09:00"),
                EditorLaunchSupport.stop("Shinagawa", code: "004092", type: "destination", arrival: "09:20"),
            ],
        ])
        let create = app.buttons["createJourneyGroup"]
        XCTAssertTrue(EditorUITestSupport.reveal(create, in: app), app.debugDescription)
        XCTAssertTrue(create.waitForExistence(timeout: 8))
        create.tap()
        let name = app.textFields["journeyGroupName"]
        XCTAssertTrue(EditorUITestSupport.reveal(name, in: app))
        XCTAssertFalse(app.buttons["rideEditorSave"].isEnabled,
                       "Creating the empty group must select its unfinished draft.")
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Rail holiday\n")
        let picker = app.descendants(matching: .any)["journeyGroupPicker"].firstMatch
        picker.tap()
        let choice = app.buttons["Rail holiday"]
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        choice.tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5),
                      "Reselecting the new draft group must keep its name editable.")
        XCTAssertEqual(name.value as? String, "Rail holiday")
        // Edit mode has no confirmation step. A stop round-trip is the draft
        // leaving the form and coming back.
        let origin = app.descendants(matching: .any)["rideEditorStop-0"].firstMatch
        EditorUITestSupport.tap(origin, in: app)
        XCTAssertTrue(app.otherElements["rideEditorStopName"].waitForExistence(timeout: 8))
        app.navigationBars["Tokyo"].buttons.firstMatch.tap()
        XCTAssertTrue(EditorUITestSupport.reveal(name, in: app))
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Rail holiday")
        // Put the insertion point after the final character before replacing it.
        name.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        name.typeText(XCUIKeyboardKey.delete.rawValue + "s\n")
        XCTAssertEqual(name.value as? String, "Rail holidas")
        let save = app.buttons["rideEditorSave"]
        XCTAssertTrue(save.waitForExistence(timeout: 8))
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 15))
    }

    func testExistingJourneyGroupPersistsAndCanBeSelectedInStatistics() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["RAILMAP_UI_TEST_STORAGE_ID"] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-interface-language", "en"]
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "search"
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "expanded"
        app.launchEnvironment["RAILMAP_UI_TEST_SAMPLE"] = "train-store"
        app.launchEnvironment["RAILMAP_UI_TEST_QUERY"] = "haruka"
        app.launch()

        let row = app.descendants(matching: .any)["journeyRow-20260703_01_haruka"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 60))
        row.press(forDuration: 1)
        app.buttons["Journey group"].tap()
        let create = app.buttons["createJourneyGroup"]
        XCTAssertTrue(create.waitForExistence(timeout: 8))
        create.tap()
        let field = app.textFields["journeyGroupName"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        let name = "Trip" + String(UUID().uuidString.prefix(8))
        field.typeText(name + "Extra\n")
        XCTAssertEqual(field.value as? String, name, "Names must stop at 12 characters.")
        let save = app.buttons["saveJourneyGroup"]
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 15))

        app.terminate()
        app.launchEnvironment["RAILMAP_UI_TEST_SAMPLE"] = ""
        app.launchEnvironment["RAILMAP_UI_TEST_QUERY"] = ""
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "stats"
        app.launch()
        let calendar = app.buttons["statisticsDateButton"]
        XCTAssertTrue(calendar.waitForExistence(timeout: 60))
        calendar.tap()
        let byGroup = app.buttons["statisticsClassification-journeyGroup"]
        XCTAssertTrue(byGroup.waitForExistence(timeout: 10))
        byGroup.tap()
        let filter = app.descendants(matching: .any)["statisticsJourneyGroupFilter"].firstMatch
        XCTAssertTrue(filter.waitForExistence(timeout: 10))
        let choice = app.buttons[name]
        XCTAssertTrue(choice.waitForExistence(timeout: 5), "The saved group must survive relaunch.")
        choice.tap()
        app.buttons["Done"].tap()
        let scope = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "（" + name)).firstMatch
        XCTAssertTrue(scope.waitForExistence(timeout: 120), "The record ticket must name the selected group.")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "JourneyGroup-12-character-ticket"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

}
