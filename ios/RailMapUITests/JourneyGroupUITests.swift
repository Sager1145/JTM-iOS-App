import XCTest

@MainActor
final class JourneyGroupUITests: XCTestCase {
    func testDraftGroupNameRemainsEditableWhenReselectedAndAfterConfirmation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["RAILMAP_UI_TEST_STORAGE_ID"] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-interface-language", "en"]
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "all"
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "expanded"
        app.launchEnvironment["RAILMAP_UI_TEST_SHEET"] = "new"
        app.launch()
        let next = app.buttons["rideEditorNext"]
        XCTAssertTrue(next.waitForExistence(timeout: 30))
        next.tap()
        for (index, stationName) in ["Tokyo", "Shinagawa"].enumerated() {
            let stop = app.descendants(matching: .any)["rideEditorStop-\(index)"].firstMatch
            EditorUITestSupport.tap(stop, in: app)
            let field = app.otherElements["rideEditorStopName"].textFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeText(stationName)
            app.navigationBars[stationName].buttons.firstMatch.tap()
        }
        next.tap()
        let number = app.otherElements["rideEditorNumber"].textFields.firstMatch
        XCTAssertTrue(number.waitForExistence(timeout: 8))
        number.tap()
        number.typeText("Group draft\n")
        next.tap()
        let create = app.buttons["createJourneyGroup"]
        for _ in 0..<5 where !create.isHittable { app.swipeUp() }
        XCTAssertTrue(create.waitForExistence(timeout: 8))
        create.tap()
        let name = app.textFields["journeyGroupName"]
        XCTAssertFalse(app.buttons["rideEditorNext"].isEnabled,
                       "Creating the empty group must select its unfinished draft.")
        XCTAssertTrue(revealNewGroupName(name, in: app))
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
        next.tap()
        XCTAssertTrue(app.buttons["rideEditorSave"].waitForExistence(timeout: 8))
        app.buttons["rideEditorPrevious"].tap()
        for _ in 0..<5 where !name.isHittable { app.swipeUp() }
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Rail holiday")
        // Put the insertion point after the final character before replacing it.
        name.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        name.typeText(XCUIKeyboardKey.delete.rawValue + "s\n")
        XCTAssertEqual(name.value as? String, "Rail holidas")
        next.tap()
        let save = app.buttons["rideEditorSave"]
        XCTAssertTrue(save.waitForExistence(timeout: 8))
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
    private func revealNewGroupName(_ name: XCUIElement, in app: XCUIApplication) -> Bool {
        let form = app.descendants(matching: .any)["rideEditorForm"].firstMatch
        guard form.waitForExistence(timeout: 5) else { return false }
        for _ in 0..<8 {
            var bounds = form.frame.intersection(app.frame)
            let next = app.buttons["rideEditorNext"]
            if next.exists && next.frame.intersects(bounds) {
                bounds.size.height = max(0, next.frame.minY - bounds.minY)
            }
            let keyboard = app.keyboards.firstMatch
            if keyboard.exists && keyboard.frame.intersects(bounds) {
                bounds.size.height = max(0, keyboard.frame.minY - bounds.minY)
            }
            bounds = bounds.insetBy(dx: 8, dy: 8)
            guard bounds.height > 40 else { return false }
            if name.exists && name.isHittable && bounds.contains(name.frame) { return true }
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: bounds.midX - app.frame.minX,
                dy: bounds.minY + bounds.height * 0.65 - app.frame.minY))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(
                    dx: bounds.midX - app.frame.minX,
                    dy: bounds.minY + bounds.height * 0.35 - app.frame.minY)))
        }
        return false
    }

}
