import XCTest

@MainActor
final class TimetableDiscoveryUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testDatedEnglishSearchImportsPublishedDraftAndSavesOnlyAfterReview() {
        let app = newJourney()
        let next = app.buttons["rideEditorNext"]
        XCTAssertTrue(next.waitForExistence(timeout: 30))
        next.tap()
        EditorUITestSupport.tap(app.buttons["rideEditorServicePattern"], in: app)
        let dateEditor = app.descendants(matching: .any)["servicePatternDateEditor"].firstMatch
        XCTAssertTrue(dateEditor.waitForExistence(timeout: 8))
        dateEditor.tap()
        let date = app.textFields["servicePatternDateInput"]
        XCTAssertTrue(date.waitForExistence(timeout: 8), app.debugDescription)
        date.tap()
        date.typeText("2026-09-30\n")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.tap()
        search.typeText("AZUSA 松本\n")
        let detail = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "timetableDetails-jr-east.azusa")).firstMatch
        reveal(detail, in: app.collectionViews["servicePatternList"], app: app)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Dated multi-term train search"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        detail.tap()
        let useDraft = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "timetableUseDraft-jr-east.azusa")).firstMatch
        XCTAssertTrue(useDraft.waitForExistence(timeout: 8))
        useDraft.tap()
        XCTAssertTrue(app.buttons["rideEditorStop-0"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["rideEditorSave"].exists)
        next.tap()
        let number = app.otherElements["rideEditorNumber"].textFields.firstMatch
        XCTAssertTrue(number.waitForExistence(timeout: 8))
        XCTAssertTrue((number.value as? String ?? "").contains("あずさ"))
        next.tap()
        XCTAssertEqual(app.textFields["rideEditorDateInput"].value as? String, "2026-09-30")
        XCTAssertTrue(app.buttons["rideEditorTimetableBrowse"].exists)
        let match = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "rideEditorTimetableMatch-jr-east.azusa")).firstMatch
        let form = app.collectionViews["rideEditorForm"]
        for _ in 0..<8 where !match.exists { form.swipeUp() }
        XCTAssertTrue(match.waitForExistence(timeout: 10), app.debugDescription)
        reveal(match, in: form, app: app)
        match.tap()
        XCTAssertTrue(app.buttons["rideEditorReplaceStops"].waitForExistence(timeout: 8), app.debugDescription)
        let keepStops = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(keepStops.waitForExistence(timeout: 8), app.debugDescription)
        keepStops.tap()
        for _ in 0..<6 where !app.textFields["rideEditorDateInput"].isHittable { form.swipeDown() }
        XCTAssertEqual(app.textFields["rideEditorDateInput"].value as? String, "2026-09-30")
        next.tap()
        let save = app.buttons["rideEditorSave"]
        XCTAssertTrue(save.waitForExistence(timeout: 8))
        XCTAssertTrue(save.isEnabled, app.debugDescription)
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 10))
    }

    func testCancellingLocalDateSearchKeepsJourneyDateUnset() {
        let app = newJourney()
        let next = app.buttons["rideEditorNext"]
        XCTAssertTrue(next.waitForExistence(timeout: 30))
        next.tap()
        EditorUITestSupport.tap(app.buttons["rideEditorServicePattern"], in: app)
        app.descendants(matching: .any)["servicePatternDateEditor"].firstMatch.tap()
        let date = app.textFields["servicePatternDateInput"]
        XCTAssertTrue(date.waitForExistence(timeout: 8), app.debugDescription)
        date.tap()
        date.typeText("2026-09-30\n")
        app.buttons["キャンセル"].tap()
        // With no selection, the local picker must leave the draft untouched.
        EditorUITestSupport.tap(app.buttons["rideEditorServicePattern"], in: app)
        XCTAssertFalse(app.switches["servicePatternHistoryFilter"].exists)
    }

    private func newJourney() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["RAILMAP_UI_TEST_STORAGE_ID"] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "all"
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "expanded"
        app.launchEnvironment["RAILMAP_UI_TEST_SHEET"] = "new"
        app.launch()
        return app
    }

    private func reveal(_ element: XCUIElement, in list: XCUIElement, app: XCUIApplication) {
        for _ in 0..<15 {
            if element.exists && element.isHittable && element.frame.maxY < app.frame.maxY - 120 { break }
            list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
                .press(forDuration: 0.1, thenDragTo: list.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42)))
        }
        XCTAssertTrue(element.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }
}
