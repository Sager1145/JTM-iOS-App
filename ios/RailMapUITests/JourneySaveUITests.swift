import XCTest

@MainActor
final class JourneySaveUITests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        await MainActor.run {
            XCUIDevice.shared.orientation = .portrait
        }
    }

    func testSavedJourneyIsStillPresentAfterRelaunch() {
        let number = "Persist \(UUID().uuidString.prefix(8))"
        let app = launchNewJourney()
        advanceToRoute(in: app)
        fillRequiredStops(in: app)

        app.buttons["rideEditorNext"].tap()
        let numberField = app.otherElements["rideEditorNumber"].textFields.firstMatch
        XCTAssertTrue(numberField.waitForExistence(timeout: 8))
        numberField.tap()
        numberField.typeText(number + "\n")

        let vehicle = app.otherElements["rideEditorVehicleType"].textFields.firstMatch
        EditorUITestSupport.tap(vehicle, in: app)
        vehicle.typeText("E235")

        app.buttons["rideEditorNext"].tap()
        XCTAssertTrue(app.switches["Include a date"].waitForExistence(timeout: 8))
        app.buttons["rideEditorNext"].tap()

        let save = app.buttons["rideEditorSave"]
        XCTAssertTrue(save.waitForExistence(timeout: 8))
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 8))

        app.tabBars.firstMatch.buttons.element(boundBy: 3).tap()
        let savedSearch = app.textFields["journeySearchField"]
        XCTAssertTrue(savedSearch.waitForExistence(timeout: 8))
        savedSearch.tap()
        savedSearch.typeText(number)
        let inserted = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "journeyRow-", number)).firstMatch
        XCTAssertTrue(inserted.waitForExistence(timeout: 15),
                      "Saving must return to a list containing the inserted journey.")

        // The store write is asynchronous. Waiting here tests the same
        // completion window a reader naturally spends looking at the saved
        // journey before closing the app, then the relaunch proves disk state.
        Thread.sleep(forTimeInterval: 1)
        app.terminate()
        app.launchEnvironment["RAILMAP_UI_TEST_SHEET"] = ""
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "search"
        app.launchEnvironment["RAILMAP_UI_TEST_QUERY"] = number
        app.launch()

        let savedRow = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "journeyRow-", number)).firstMatch
        XCTAssertTrue(savedRow.waitForExistence(timeout: 30),
                      "A completed save must survive process termination and reload.")
        savedRow.press(forDuration: 1)
        let information = app.buttons["Journey information"]
        XCTAssertTrue(information.waitForExistence(timeout: 5))
        information.tap()
        XCTAssertTrue(app.buttons["journeyMenuEdit"].waitForExistence(timeout: 8))
        guard let detailScroll = app.scrollViews.allElementsBoundByIndex.first(where: {
            $0.descendants(matching: .any)["rideDetailStops"].exists
        }) else {
            XCTFail("The opened journey must contain its native detail scroll view.")
            return
        }
        XCTAssertTrue(detailScroll.waitForExistence(timeout: 5))
        for value in ["Tokyo", "Shinagawa", "E235"] {
            let persistedValue = detailScroll.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS %@", value)).firstMatch
            for _ in 0..<6 where !persistedValue.exists { detailScroll.swipeUp() }
            XCTAssertTrue(persistedValue.waitForExistence(timeout: 5),
                          "The saved detail must retain \(value) after relaunch.")
        }
    }

    func testNewJourneyGroupNameCanBeEditedAfterReturningFromConfirmation() {
        let app = launchNewJourney()
        advanceToRoute(in: app)
        fillRequiredStops(in: app)
        app.buttons["rideEditorNext"].tap()
        let number = app.otherElements["rideEditorNumber"].textFields.firstMatch
        XCTAssertTrue(number.waitForExistence(timeout: 8))
        number.tap()
        number.typeText("Group test\n")
        app.buttons["rideEditorNext"].tap()
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
        app.buttons["rideEditorNext"].tap()
        XCTAssertTrue(app.buttons["rideEditorSave"].waitForExistence(timeout: 8))
        app.buttons["rideEditorPrevious"].tap()
        XCTAssertTrue(revealNewGroupName(name, in: app), app.debugDescription)
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Rail holiday")
        // Put the insertion point after the final character before replacing it.
        name.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        name.typeText(XCUIKeyboardKey.delete.rawValue + "s\n")
        XCTAssertEqual(name.value as? String, "Rail holidas")
        app.buttons["rideEditorNext"].tap()
        let save = app.buttons["rideEditorSave"]
        XCTAssertTrue(save.waitForExistence(timeout: 8))
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 15))
    }

    func testDirtyCancelCanKeepEditingThenDiscardDraft() {
        let unsavedName = "Unsaved \(UUID().uuidString.prefix(8))"
        let app = launchNewJourney()
        advanceToRoute(in: app)

        let origin = app.descendants(matching: .any)["rideEditorStop-0"].firstMatch
        XCTAssertTrue(origin.waitForExistence(timeout: 8))
        origin.tap()
        let name = app.otherElements["rideEditorStopName"].textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(unsavedName)
        app.navigationBars[unsavedName].buttons.firstMatch.tap()

        let cancel = app.buttons["rideEditorCancel"]
        cancel.tap()
        let discardDialog = app.sheets.firstMatch
        XCTAssertTrue(discardDialog.waitForExistence(timeout: 5))
        // Compact confirmation dialogs expose their destructive action as a
        // button but treat tapping outside the popover as the cancel role.
        // Dismiss that way to exercise “Keep editing” without accidentally
        // finding the editor toolbar's own Cancel button behind the dialog.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.95)).tap()
        XCTAssertTrue(discardDialog.waitForNonExistence(timeout: 5))

        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        XCTAssertTrue(origin.label.contains(unsavedName),
                      "Keeping the editor open must preserve the local draft.")

        cancel.tap()
        let discard = app.buttons["Discard changes"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        discard.tap()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 8),
                      "Discarding must close the editor without committing the draft.")
        app.terminate()
        app.launchEnvironment["RAILMAP_UI_TEST_SHEET"] = ""
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "search"
        app.launchEnvironment["RAILMAP_UI_TEST_QUERY"] = unsavedName
        app.launch()
        let search = app.textFields["journeySearchField"]
        XCTAssertTrue(search.waitForExistence(timeout: 30))
        XCTAssertEqual(search.value as? String, unsavedName,
                       "The relaunch must finish applying the discard-proof query.")
        let completedEmptyState = app.staticTexts.matching(NSPredicate(
            format: "label IN %@", ["No matching journeys", "No journeys yet"])).firstMatch
        XCTAssertTrue(completedEmptyState.waitForExistence(timeout: 30),
                      "The loaded library must finish searching before absence is meaningful.")
        let discardedRow = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "journeyRow-", unsavedName)).firstMatch
        XCTAssertFalse(discardedRow.waitForExistence(timeout: 8),
                       "A discarded draft must not appear after process relaunch.")
    }

    private func advanceToRoute(in app: XCUIApplication) {
        let next = app.buttons["rideEditorNext"]
        XCTAssertTrue(next.waitForExistence(timeout: 30))
        next.tap()
        let stop = app.descendants(matching: .any)["rideEditorStop-0"].firstMatch
        XCTAssertTrue(EditorUITestSupport.reveal(stop, in: app), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["rideEditorStop-0"]
            .waitForExistence(timeout: 8))
    }

    private func fillRequiredStops(in app: XCUIApplication) {
        for (index, name) in ["Tokyo", "Shinagawa"].enumerated() {
            let stop = app.descendants(matching: .any)["rideEditorStop-\(index)"].firstMatch
            EditorUITestSupport.tap(stop, in: app)
            let field = app.otherElements["rideEditorStopName"].textFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeText(name)
            app.navigationBars[name].buttons.firstMatch.tap()
        }
    }

    private func launchNewJourney() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["RAILMAP_UI_TEST_STORAGE_ID"] = UUID().uuidString
        app.launchArguments = [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-interface-language", "en",
        ]
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "all"
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "expanded"
        app.launchEnvironment["RAILMAP_UI_TEST_SHEET"] = "new"
        app.launch()
        return app
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
