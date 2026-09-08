import XCTest

@MainActor
final class WorkspaceEditingTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testSearchSurvivesDetailReturn() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "search"
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "expanded"
        app.launchEnvironment["RAILMAP_UI_TEST_SAMPLE"] = "train-store"
        app.launchEnvironment["RAILMAP_UI_TEST_QUERY"] = "haruka"
        app.launch()
        let row = app.descendants(matching: .any)["journeyRow-20260703_01_haruka"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        row.tap()
        // Search selects on the shared map; its resident detail belongs to All.
        app.tabBars.firstMatch.buttons.element(boundBy: 2).tap()
        let back = app.buttons["journeyBackToList"]
        XCTAssertTrue(back.waitForExistence(timeout: 8))
        back.tap()
        app.tabBars.firstMatch.buttons.element(boundBy: 3).tap()
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        let search = app.textFields["journeySearchField"]
        XCTAssertEqual(search.value as? String, "haruka")
    }

    func testPlaybackCanPauseResumeAndStop() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["RAILMAP_UI_TEST_SAMPLE"] = "train-store"
        app.launchEnvironment["RAILMAP_UI_TEST_PLAYBACK"] = "1"
        app.launch()
        let toggle = app.buttons["playbackPauseResume"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 60))
        let playing = NSPredicate(format: "label == %@", "Pause")
        expectation(for: playing, evaluatedWith: toggle)
        waitForExpectations(timeout: 15)
        toggle.tap()
        XCTAssertEqual(toggle.label, "Play")
        toggle.tap()
        XCTAssertEqual(toggle.label, "Pause")
        app.buttons["playbackStopButton"].tap()
        XCTAssertTrue(toggle.waitForNonExistence(timeout: 8))
    }

    func testDetailEditsSurviveVisibilityChange() {
        let app = launch(sheet: "detail")
        let edit = app.buttons["rideDetailEdit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 30))
        edit.tap()
        let number = app.otherElements["rideEditorNumber"].textFields.firstMatch
        XCTAssertTrue(number.waitForExistence(timeout: 8))
        number.tap()
        number.typeText("X")
        let edited = number.value as? String
        XCTAssertNotEqual(edited, "Review")
        app.buttons["rideEditorSave"].tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 8))
        let hide = app.buttons["rideDetailHide"]
        for _ in 0..<12 {
            if hide.exists && hide.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(hide.isHittable)
        hide.tap()
        edit.tap()
        XCTAssertTrue(number.waitForExistence(timeout: 8))
        XCTAssertEqual(number.value as? String, edited,
                       "A detail action must edit the current record, not the original sheet snapshot.")
    }

    func testEditingCheckedImportRequiresAnotherReview() {
        let app = launch(sheet: "import-review")
        let validate = app.buttons["importValidate"]
        XCTAssertTrue(validate.waitForExistence(timeout: 30))
        validate.tap()
        let commit = app.buttons["importCommit"]
        XCTAssertTrue(commit.waitForExistence(timeout: 15))
        let text = app.textViews["importText"]
        text.tap()
        text.typeText("x")
        XCTAssertTrue(validate.waitForExistence(timeout: 8))
        XCTAssertFalse(commit.exists, "Changed input must not retain a committable report.")
    }

    func testReviewedImportKeepsRegionAfterCancelAndReopen() {
        let app = launch(sheet: "import-reopen")
        let region = app.descendants(matching: .any)["importRegion"].firstMatch
        XCTAssertTrue(app.buttons["importValidate"].waitForExistence(timeout: 30))
        for _ in 0..<12 {
            if region.exists && region.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(region.isHittable, app.debugDescription)
        region.tap()
        app.buttons["Taiwan"].tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "Taiwan"), evaluatedWith: region)
        waitForExpectations(timeout: 5)
        app.buttons["importValidate"].tap()
        let commit = app.buttons["importCommit"]
        XCTAssertTrue(commit.waitForExistence(timeout: 15))
        app.buttons["importCancel"].tap()
        let reopen = app.buttons["Import JSON"].firstMatch
        XCTAssertTrue(reopen.waitForExistence(timeout: 8))
        reopen.tap()
        XCTAssertTrue(commit.waitForExistence(timeout: 8))
        for _ in 0..<12 {
            if region.exists && region.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(region.label.contains("Taiwan"), region.debugDescription)

        XCTAssertTrue(commit.isEnabled)
    }

    private func launch(sheet: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "all"
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "expanded"
        app.launchEnvironment["RAILMAP_UI_TEST_SHEET"] = sheet
        app.launch()
        return app
    }
}
