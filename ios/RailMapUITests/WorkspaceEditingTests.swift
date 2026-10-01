import XCTest
import UIKit

@MainActor
final class WorkspaceEditingTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        await MainActor.run {
            XCUIDevice.shared.orientation = .portrait
        }
    }

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
        // Sample journeys remain playable after their calendar dates pass.
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "all"
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
        let edited = number.value as? String ?? ""
        XCTAssertNotEqual(edited, "Review")
        app.buttons["rideEditorSave"].tap()

        // Saving returns to the selected journey card. Capture its stable
        // record identity, then search so this undated fixture remains reachable
        // even when earlier tests have loaded hundreds of dated sample rides.
        let selected = app.staticTexts.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "selectedJourney-")).firstMatch
        XCTAssertTrue(selected.waitForExistence(timeout: 15))
        let savedID = String(selected.identifier.dropFirst("selectedJourney-".count))
        let back = app.buttons["journeyBackToList"]
        XCTAssertTrue(back.waitForExistence(timeout: 15))
        back.tap()
        app.tabBars.firstMatch.buttons.element(boundBy: 3).tap()
        let search = app.textFields["journeySearchField"]
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.tap()
        search.typeText(edited)
        let savedRow = app.buttons["journeyRow-\(savedID)"]
        XCTAssertTrue(savedRow.waitForExistence(timeout: 30))
        savedRow.press(forDuration: 1)
        let information = app.buttons["Journey information"]
        XCTAssertTrue(information.waitForExistence(timeout: 5))
        information.tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 8))
        let detailScroll = app.scrollViews["rideDetailScrollView"]
        XCTAssertTrue(detailScroll.waitForExistence(timeout: 5))
        let hide = detailScroll.buttons["rideDetailHide"]
        // Target the detail content. A gesture on `app` can resize the
        // presenting sheet instead, leaving the lazy service card unbuilt and
        // waiting minutes for a detent animation rather than testing Hide.
        for _ in 0..<6 where !hide.isHittable { detailScroll.swipeUp() }
        XCTAssertTrue(hide.waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.buttons["importValidate"].waitForExistence(timeout: 30))

        func revealRegionControl() -> (element: XCUIElement, isPopUpButton: Bool) {
            let anyRegion = app.descendants(matching: .any)["importRegion"].firstMatch
            for _ in 0..<4 {
                if anyRegion.exists, !anyRegion.frame.isEmpty,
                   app.frame.contains(anyRegion.frame) { break }
                app.swipeUp()
            }
            XCTAssertTrue(anyRegion.waitForExistence(timeout: 5))
            XCTAssertFalse(anyRegion.frame.isEmpty)
            XCTAssertTrue(app.frame.contains(anyRegion.frame), anyRegion.debugDescription)

            let popupRegion = app.popUpButtons["importRegion"].firstMatch
            if popupRegion.exists { return (popupRegion, true) }
            let buttonRegion = app.buttons["importRegion"].firstMatch
            XCTAssertTrue(buttonRegion.exists, anyRegion.debugDescription)
            return (buttonRegion, false)
        }

        let resolvedRegion = revealRegionControl()
        let region = resolvedRegion.element
        let regionFrame = region.frame
        XCTAssertFalse(regionFrame.isEmpty)
        XCTAssertTrue(app.frame.contains(regionFrame), region.debugDescription)
        if resolvedRegion.isPopUpButton {
            region.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        } else {
            region.tap()
        }
        let taiwan = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "Taiwan")).firstMatch
        XCTAssertTrue(taiwan.waitForExistence(timeout: 5),
                      "Opening the region pop-up must present Taiwan.")
        EditorUITestSupport.tap(taiwan, in: app)
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
        let reopenedRegion = revealRegionControl().element
        XCTAssertTrue(reopenedRegion.label.contains("Taiwan"), reopenedRegion.debugDescription)

        XCTAssertTrue(commit.isEnabled)
    }

    func testNewJourneyStartsEmptyAndRequiresStops() {
        let app = launch(sheet: "new")
        let next = app.buttons["rideEditorNext"]
        let save = app.buttons["rideEditorSave"]
        XCTAssertTrue(next.waitForExistence(timeout: 30))
        XCTAssertFalse(app.buttons["rideEditorPrevious"].exists)
        XCTAssertFalse(save.exists)

        next.tap()
        let firstStop = app.descendants(matching: .any)["rideEditorStop-0"].firstMatch
        XCTAssertTrue(firstStop.waitForExistence(timeout: 8))

        next.tap()
        XCTAssertTrue(firstStop.waitForExistence(timeout: 5),
                      "The stops step must reject an unnamed origin and destination.")
        XCTAssertFalse(app.otherElements["rideEditorNumber"].exists)

        fillRequiredStops(in: app)
        next.tap()
        let number = app.otherElements["rideEditorNumber"].textFields.firstMatch
        XCTAssertTrue(number.waitForExistence(timeout: 8))
        let emptyNumberValue = number.value as? String

        next.tap()
        XCTAssertTrue(app.switches["Include a date"].waitForExistence(timeout: 8),
                      "An empty train number must allow the date and completion step.")
        XCTAssertFalse(save.exists)
        app.buttons["rideEditorPrevious"].tap()
        XCTAssertTrue(number.waitForExistence(timeout: 8))
        XCTAssertEqual(number.value as? String, emptyNumberValue,
                       "Returning from the date step must retain the empty service field.")
        number.tap()
        number.typeText("My journey\n")
        next.tap()
        XCTAssertTrue(app.switches["Include a date"].waitForExistence(timeout: 8))
        XCTAssertFalse(save.exists)

        next.tap()
        XCTAssertTrue(save.waitForExistence(timeout: 8))
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 8))
    }

    func testAddingStopOpensItsEditorAndCancelProtectsDraft() {
        let app = launch(sheet: "new")
        advanceToStopsStep(in: app)
        let add = app.buttons["rideEditorAddStop"]
        EditorUITestSupport.tap(add, in: app)
        XCTAssertTrue(app.otherElements["rideEditorStopName"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["rideEditorCancel"].tap()
        XCTAssertTrue(app.buttons["Discard changes"].waitForExistence(timeout: 5))
    }

    func testStationTypingOffersCanonicalMatches() {
        let app = launch(sheet: "new")
        advanceToStopsStep(in: app)
        let departure = app.descendants(matching: .any)["rideEditorStop-0"].firstMatch
        for _ in 0..<6 where !departure.isHittable { app.swipeUp() }
        departure.tap()
        let name = app.otherElements["rideEditorStopName"].textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 8))
        name.tap()
        name.typeText("Tokyo")
        let unmatched = app.staticTexts["This station is not matched to the catalog"]
        XCTAssertTrue(unmatched.waitForExistence(timeout: 5),
                      "Typing alone must not assign a canonical station code.")
        let suggestion = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "rideEditorStationSuggestion-")).firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 30))
        let suggestionCode = suggestion.identifier.replacingOccurrences(
            of: "rideEditorStationSuggestion-", with: "")
        XCTAssertFalse(suggestionCode.isEmpty,
                       "A catalog suggestion must carry its canonical station code.")
        suggestion.tap()
        XCTAssertEqual(name.value as? String, "東京", "Exact romanized matches should precede partial station names.")
        XCTAssertTrue(unmatched.waitForNonExistence(timeout: 5),
                      "Choosing the catalog match must assign its station code to the draft.")
    }

    func testServiceTypeSuggestionsAndCustomVehicleInput() {
        let app = launch(sheet: "new")
        advanceToServiceStep(in: app)
        let type = app.otherElements["rideEditorTrainType"].textFields.firstMatch
        EditorUITestSupport.tap(type, in: app)
        type.typeText("Rap")
        let rapid = app.buttons["Rapid"].firstMatch
        XCTAssertTrue(rapid.waitForExistence(timeout: 5))
        rapid.tap()
        XCTAssertEqual(type.value as? String, "Rapid")
        let vehicle = app.otherElements["rideEditorVehicleType"].textFields.firstMatch
        vehicle.tap()
        vehicle.typeText("E235")
        XCTAssertEqual(vehicle.value as? String, "E235")
    }

    func testTypedDateAndLineSearch() {
        let app = launch(sheet: "new")
        advanceToStopsStep(in: app)
        fillRequiredStops(in: app)
        let lines = app.descendants(matching: .any)["rideEditorLines"].firstMatch
        for _ in 0..<10 where !lines.isHittable { app.swipeUp() }
        lines.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("山手")
        let result = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "rideEditorLine-")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 30))
        result.tap()
        let done = app.buttons["rideEditorLinesDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        XCTAssertTrue(lines.waitForExistence(timeout: 5))
        XCTAssertTrue(lines.label.contains("山手"))

        app.buttons["rideEditorNext"].tap()
        let number = app.otherElements["rideEditorNumber"].textFields.firstMatch
        XCTAssertTrue(number.waitForExistence(timeout: 8))
        number.tap()
        number.typeText("Date test\n")
        app.buttons["rideEditorNext"].tap()

        let includeDate = app.switches["Include a date"]
        XCTAssertTrue(includeDate.waitForExistence(timeout: 8))
        includeDate.switches.firstMatch.tap()
        let date = app.textFields["rideEditorDateInput"]
        XCTAssertTrue(date.waitForExistence(timeout: 5))
        let previous = date.value as? String ?? ""
        date.tap()
        date.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count) + "2026-10-12")
        XCTAssertEqual(date.value as? String, "2026-10-12")
    }

    func testNewJourneyWizardPreservesDraftAcrossEveryBackStep() {
        let app = launch(sheet: "new")
        let next = app.buttons["rideEditorNext"]
        let previous = app.buttons["rideEditorPrevious"]
        let save = app.buttons["rideEditorSave"]

        XCTAssertTrue(next.waitForExistence(timeout: 30))
        XCTAssertFalse(previous.exists)
        XCTAssertFalse(save.exists)

        next.tap()
        XCTAssertTrue(app.descendants(matching: .any)["rideEditorStop-0"]
            .waitForExistence(timeout: 8))
        XCTAssertFalse(save.exists)
        fillRequiredStops(in: app, names: ["Tokyo", "Shinagawa"])

        next.tap()
        let number = app.otherElements["rideEditorNumber"].textFields.firstMatch
        XCTAssertTrue(number.waitForExistence(timeout: 8))
        XCTAssertFalse(save.exists)
        number.tap()
        number.typeText("Wizard 42\n")
        let vehicle = app.otherElements["rideEditorVehicleType"].textFields.firstMatch
        vehicle.tap()
        vehicle.typeText("E235")

        next.tap()
        let includeDate = app.switches["Include a date"]
        XCTAssertTrue(includeDate.waitForExistence(timeout: 8))
        XCTAssertFalse(save.exists)
        includeDate.switches.firstMatch.tap()
        let date = app.textFields["rideEditorDateInput"]
        XCTAssertTrue(date.waitForExistence(timeout: 5))
        let initialDate = date.value as? String ?? ""
        date.tap()
        date.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,
                             count: initialDate.count) + "2026-10-12")
        XCTAssertEqual(date.value as? String, "2026-10-12")

        next.tap()
        XCTAssertTrue(save.waitForExistence(timeout: 8))
        XCTAssertTrue(save.isEnabled)
        XCTAssertFalse(next.exists)
        XCTAssertFalse(app.otherElements["rideEditorNumber"].exists,
                       "Confirmation must present the draft read-only.")
        for value in ["Tokyo", "Shinagawa", "Wizard 42", "E235", "2026-10-12"] {
            let summaryValue = app.staticTexts.matching(NSPredicate(
                format: "label ENDSWITH %@", ", " + value)).firstMatch
            for _ in 0..<8 where !summaryValue.exists { app.swipeUp() }
            XCTAssertTrue(summaryValue.waitForExistence(timeout: 5),
                          "Confirmation must summarize \(value).")
        }

        previous.tap()
        XCTAssertTrue(date.waitForExistence(timeout: 8))
        XCTAssertEqual(date.value as? String, "2026-10-12")
        XCTAssertFalse(save.exists)

        previous.tap()
        XCTAssertTrue(number.waitForExistence(timeout: 8))
        XCTAssertEqual(number.value as? String, "Wizard 42")
        XCTAssertEqual(vehicle.value as? String, "E235")
        XCTAssertFalse(save.exists)

        previous.tap()
        let origin = app.descendants(matching: .any)["rideEditorStop-0"].firstMatch
        let destination = app.descendants(matching: .any)["rideEditorStop-1"].firstMatch
        XCTAssertTrue(origin.waitForExistence(timeout: 8))
        XCTAssertTrue(origin.label.contains("Tokyo"))
        XCTAssertTrue(destination.label.contains("Shinagawa"))
        XCTAssertFalse(save.exists)

        previous.tap()
        XCTAssertTrue(next.waitForExistence(timeout: 8))
        XCTAssertFalse(previous.exists)
        XCTAssertFalse(save.exists)

        next.tap()
        XCTAssertTrue(origin.waitForExistence(timeout: 8))
        XCTAssertTrue(origin.label.contains("Tokyo"))
        XCTAssertTrue(destination.label.contains("Shinagawa"))
        next.tap()
        XCTAssertTrue(number.waitForExistence(timeout: 8))
        XCTAssertEqual(number.value as? String, "Wizard 42")
        XCTAssertEqual(vehicle.value as? String, "E235")
        next.tap()
        XCTAssertTrue(date.waitForExistence(timeout: 8))
        XCTAssertEqual(date.value as? String, "2026-10-12")
        next.tap()
        XCTAssertTrue(save.waitForExistence(timeout: 8))
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 8))
    }

    func testConfirmationSurvivesPhoneRotation() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone)
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = launch(sheet: "new")
        advanceToServiceStep(in: app)
        let number = app.otherElements["rideEditorNumber"].textFields.firstMatch
        number.tap()
        number.typeText("Rotate 42\n")
        let vehicle = app.otherElements["rideEditorVehicleType"].textFields.firstMatch
        vehicle.tap()
        vehicle.typeText("E235")

        app.buttons["rideEditorNext"].tap()
        XCTAssertTrue(app.switches["Include a date"].waitForExistence(timeout: 8))
        app.buttons["rideEditorNext"].tap()
        let save = app.buttons["rideEditorSave"]
        XCTAssertTrue(save.waitForExistence(timeout: 8))

        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = XCTNSPredicateExpectation(
            predicate: NSPredicate { object, _ in
                guard let window = object as? XCUIElement else { return false }
                return window.frame.width > window.frame.height
            },
            object: app.windows.firstMatch)
        XCTAssertEqual(XCTWaiter().wait(for: [landscape], timeout: 8), .completed,
                       "The app window must finish rotating before layout is inspected.")
        XCTAssertTrue(save.waitForExistence(timeout: 8),
                      "Rotation must retain the confirmation step.")
        let editorForm = app.descendants(matching: .any)["rideEditorForm"].firstMatch
        XCTAssertTrue(editorForm.waitForExistence(timeout: 5))
        for value in ["Tokyo", "Shinagawa", "Rotate 42", "E235"] {
            let summaryValue = app.staticTexts.matching(NSPredicate(
                format: "label ENDSWITH %@", ", " + value)).firstMatch
            for _ in 0..<12 where !summaryValue.exists {
                let start = editorForm.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
                let end = editorForm.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: 0.44))
                start.press(forDuration: 0.05, thenDragTo: end)
            }
            XCTAssertTrue(summaryValue.waitForExistence(timeout: 5),
                          "Rotation must retain the draft value \(value).")
        }
        attach(app, named: "new-journey-confirmation-landscape")
    }

    func testClearedEnabledDateStaysOnDateStepUntilRepaired() {
        let app = launch(sheet: "new")
        advanceToDateStep(in: app, number: "Date repair")
        let includeDate = app.switches["Include a date"]
        includeDate.switches.firstMatch.tap()
        let date = app.textFields["rideEditorDateInput"]
        XCTAssertTrue(date.waitForExistence(timeout: 5))
        replaceText(in: date, with: "")

        app.buttons["rideEditorNext"].tap()
        XCTAssertTrue(date.waitForExistence(timeout: 5),
                      "An enabled empty date must remain on the date step.")
        let dateError = app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS %@",
            "Enter a valid date in YYYY-MM-DD format.")).firstMatch
        XCTAssertTrue(dateError.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["rideEditorSave"].exists)
        attach(app, named: "new-journey-empty-enabled-date-error")

        date.tap()
        date.typeText("2026-10-12")
        app.buttons["rideEditorNext"].tap()
        XCTAssertTrue(app.buttons["rideEditorSave"].waitForExistence(timeout: 8),
                      "Repairing the date must allow confirmation.")
    }

    func testExplicitUnriddenStopSurvivesChoosingToday() {
        let app = launch(sheet: "new")
        advanceToStopsStep(in: app)
        fillRequiredStops(in: app)
        let origin = app.descendants(matching: .any)["rideEditorStop-0"].firstMatch
        origin.tap()

        func revealRiddenControl() -> XCUIElement {
            // StopEditor places this toggle after the date and both time
            // sections. Its lazy Form must reveal the row before querying it.
            let form = app.collectionViews.firstMatch
            XCTAssertTrue(form.waitForExistence(timeout: 8))
            let ridden = app.switches["rideEditorStopRidden"]
            for _ in 0..<8 {
                if ridden.exists, ridden.isHittable, app.frame.contains(ridden.frame) { break }
                form.swipeUp()
            }
            XCTAssertTrue(ridden.waitForExistence(timeout: 8))
            let control = ridden.switches.firstMatch.exists ? ridden.switches.firstMatch : ridden
            XCTAssertTrue(control.isHittable)
            XCTAssertTrue(app.frame.contains(control.frame))
            return control
        }

        let riddenControl = revealRiddenControl()
        XCTAssertEqual(riddenControl.value as? String, "1")
        riddenControl.tap()
        XCTAssertEqual(riddenControl.value as? String, "0")
        app.navigationBars["Tokyo"].buttons.firstMatch.tap()

        app.buttons["rideEditorNext"].tap()
        let number = app.otherElements["rideEditorNumber"].textFields.firstMatch
        XCTAssertTrue(number.waitForExistence(timeout: 8))
        number.tap()
        number.typeText("Ridden choice\n")
        app.buttons["rideEditorNext"].tap()
        let includeDate = app.switches["Include a date"]
        XCTAssertTrue(includeDate.waitForExistence(timeout: 8))
        EditorUITestSupport.enableDate(in: app)

        app.buttons["rideEditorPrevious"].tap()
        XCTAssertTrue(number.waitForExistence(timeout: 8),
                      "The date step must return to service before returning to stops.")
        app.buttons["rideEditorPrevious"].tap()
        XCTAssertTrue(origin.waitForExistence(timeout: 8))
        origin.tap()
        let riddenAfterDate = revealRiddenControl()
        XCTAssertEqual(riddenAfterDate.value as? String, "0",
                       "Choosing today's date must not overwrite an explicit stop choice.")
    }

    func testChineseAccessibilityXXXLWizardFooterButtonsStayTappable() {
        let app = launch(
            sheet: "new",
            language: "zh-Hans",
            locale: "zh_CN",
            launchArguments: [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL",
            ])
        let next = app.buttons["rideEditorNext"]
        XCTAssertTrue(next.waitForExistence(timeout: 30))
        next.tap()

        let previous = app.buttons["rideEditorPrevious"]
        XCTAssertTrue(previous.waitForExistence(timeout: 8))
        XCTAssertEqual(previous.label, "上一步")
        XCTAssertLessThanOrEqual(previous.frame.height, 100)
        XCTAssertLessThanOrEqual(next.frame.height, 100)
        XCTAssertTrue(app.frame.contains(previous.frame))
        XCTAssertTrue(app.frame.contains(next.frame))
        EditorUITestSupport.tap(previous, in: app)
        XCTAssertTrue(previous.waitForNonExistence(timeout: 8),
                      "Previous must return the wizard to step 1.")
        EditorUITestSupport.tap(next, in: app)
        XCTAssertTrue(previous.waitForExistence(timeout: 8),
                      "Next must advance the wizard to step 2 again.")
        attach(app, named: "new-journey-zh-hans-accessibility-xxxl-footer")
    }

    func testStopDeleteUndoRestoresEndpointRolesAndRegionClearsUndo() {
        let app = launch(sheet: "new")
        advanceToStopsStep(in: app)
        fillRequiredStops(in: app)

        func revealRole(_ role: String) -> XCUIElement {
            let form = app.collectionViews.firstMatch
            XCTAssertTrue(form.waitForExistence(timeout: 8))
            let picker = app.buttons["Stop type, \(role)"]
            // The derived endpoint picker is disabled, so use its visible
            // frame rather than hittability to reveal this final Form section.
            for _ in 0..<8 {
                if picker.exists, app.frame.contains(picker.frame) { break }
                form.swipeUp()
            }
            XCTAssertTrue(picker.waitForExistence(timeout: 8))
            XCTAssertTrue(app.frame.contains(picker.frame))
            return picker
        }

        deleteFirstStop(in: app)
        EditorUITestSupport.tap(app.buttons["rideEditorReorderStops"], in: app)
        let remaining = app.descendants(matching: .any)["rideEditorStop-0"].firstMatch
        remaining.tap()
        let promotedRole = revealRole("Origin")
        XCTAssertFalse(promotedRole.isEnabled,
                       "Deleting the origin must promote the new first stop.")
        app.navigationBars["Shinagawa"].buttons.firstMatch.tap()

        let undo = app.buttons["rideEditorUndoStops"]
        EditorUITestSupport.tap(undo, in: app)

        let origin = app.descendants(matching: .any)["rideEditorStop-0"].firstMatch
        origin.tap()
        let originRole = revealRole("Origin")
        XCTAssertFalse(originRole.isEnabled,
                       "A restored first stop must retain its derived origin role.")
        app.navigationBars["Tokyo"].buttons.firstMatch.tap()

        let destination = app.descendants(matching: .any)["rideEditorStop-1"].firstMatch
        destination.tap()
        let destinationRole = revealRole("Destination")
        XCTAssertFalse(destinationRole.isEnabled,
                       "A restored last stop must retain its derived destination role.")
        let destinationName = app.otherElements["rideEditorStopName"].textFields.firstMatch
        let stopForm = app.collectionViews.firstMatch
        for _ in 0..<8 {
            if destinationName.exists, destinationName.isHittable,
               app.frame.contains(destinationName.frame) { break }
            stopForm.swipeDown()
        }
        XCTAssertTrue(destinationName.waitForExistence(timeout: 8))
        XCTAssertTrue(destinationName.isHittable)
        XCTAssertTrue(app.frame.contains(destinationName.frame))
        replaceText(in: destinationName, with: "")
        let unnamedStopBar = app.navigationBars["Stop 2"]
        XCTAssertTrue(unnamedStopBar.waitForExistence(timeout: 5))
        unnamedStopBar.buttons.firstMatch.tap()

        deleteFirstStop(in: app)
        EditorUITestSupport.tap(app.buttons["rideEditorReorderStops"], in: app)
        app.buttons["rideEditorPrevious"].tap()
        let region = app.descendants(matching: .any)["rideEditorRegion"].firstMatch
        XCTAssertTrue(region.waitForExistence(timeout: 5))
        region.tap()
        app.buttons["Taiwan"].firstMatch.tap()
        XCTAssertFalse(app.buttons["Reset route"].exists,
                       "A blank remaining route should change region directly.")
        app.buttons["rideEditorNext"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["rideEditorStop-0"]
            .waitForExistence(timeout: 8))
        XCTAssertFalse(undo.exists,
                       "Changing region must not offer an undo from the previous route.")
    }

    private func advanceToStopsStep(in app: XCUIApplication) {
        let next = app.buttons["rideEditorNext"]
        XCTAssertTrue(next.waitForExistence(timeout: 30))
        XCTAssertFalse(app.buttons["rideEditorPrevious"].exists)
        next.tap()
        XCTAssertTrue(app.descendants(matching: .any)["rideEditorStop-0"]
            .waitForExistence(timeout: 8))
    }

    private func advanceToServiceStep(in app: XCUIApplication) {
        advanceToStopsStep(in: app)
        fillRequiredStops(in: app)
        app.buttons["rideEditorNext"].tap()
        XCTAssertTrue(app.otherElements["rideEditorNumber"].textFields.firstMatch
            .waitForExistence(timeout: 8))
    }

    private func advanceToDateStep(in app: XCUIApplication, number value: String) {
        advanceToServiceStep(in: app)
        let number = app.otherElements["rideEditorNumber"].textFields.firstMatch
        number.tap()
        number.typeText(value + "\n")
        app.buttons["rideEditorNext"].tap()
        XCTAssertTrue(app.switches["Include a date"].waitForExistence(timeout: 8))
    }

    private func replaceText(in field: XCUIElement, with replacement: String) {
        let current = field.value as? String ?? ""
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,
                              count: current.count) + replacement)
    }

    private func attach(_: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func deleteFirstStop(in app: XCUIApplication) {
        let reorder = app.buttons["rideEditorReorderStops"]
        EditorUITestSupport.tap(reorder, in: app)
        let firstStopCell = app.cells.containing(
            .button, identifier: "rideEditorStop-0").firstMatch
        let remove = firstStopCell.images["minus.circle.fill"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        let commit = app.buttons["Delete"].firstMatch
        XCTAssertTrue(commit.waitForExistence(timeout: 5))
        commit.tap()
    }

    private func fillRequiredStops(
        in app: XCUIApplication,
        names: [String] = ["Tokyo", "Shinagawa"]
    ) {
        for (index, name) in names.enumerated() {
            let stop = app.descendants(matching: .any)["rideEditorStop-\(index)"].firstMatch
            for _ in 0..<6 where !stop.isHittable { app.swipeUp() }
            XCTAssertTrue(stop.waitForExistence(timeout: 5))
            stop.tap()
            let field = app.otherElements["rideEditorStopName"].textFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeText(name)
            app.navigationBars[name].buttons.firstMatch.tap()
        }
    }

    private func launch(
        sheet: String,
        language: String = "en",
        locale: String = "en_US",
        launchArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale,
            "-interface-language", language,
        ] + launchArguments
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "all"
        app.launchEnvironment["RAILMAP_UI_TEST_STATS_REGION"] = "all"
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "expanded"
        app.launchEnvironment["RAILMAP_UI_TEST_SHEET"] = sheet
        app.launch()
        if UIDevice.current.userInterfaceIdiom == .phone {
            let portrait = XCTNSPredicateExpectation(
                predicate: NSPredicate { object, _ in
                    guard let window = object as? XCUIElement else { return false }
                    return window.frame.height > window.frame.width
                },
                object: app.windows.firstMatch)
            XCTAssertEqual(XCTWaiter().wait(for: [portrait], timeout: 8), .completed,
                           "Each phone test must start from a settled portrait window.")
        }
        return app
    }
}

@MainActor
enum EditorUITestSupport {
    /// Seed named endpoints through the real route picker before advancing
    /// the new-journey wizard to its date step.
    static func seedNamedRoute(in app: XCUIApplication) {
        app.buttons["rideEditorServicePattern"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.tap()
        search.typeText("はちおうじ")
        let route = app.buttons.matching(NSPredicate(
            format: "label CONTAINS %@", "東京〜八王子")).firstMatch
        XCTAssertTrue(route.waitForExistence(timeout: 8), app.debugDescription)
        route.tap()
    }

    static func tap(
        _ element: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard element.waitForExistence(timeout: 5) else {
            XCTFail("The element to tap does not exist.", file: file, line: line)
            return
        }

        let appFrame = app.frame
        guard isUsable(appFrame) else {
            XCTFail("The application has no usable frame.", file: file, line: line)
            return
        }

        let editorForm = app.descendants(matching: .any)["rideEditorForm"].firstMatch
        for attempt in 0...8 {
            guard element.exists else {
                XCTFail("The element disappeared before it could be tapped.", file: file, line: line)
                return
            }
            let frame = element.frame
            guard isUsable(frame) else {
                XCTFail("The element has no usable frame.", file: file, line: line)
                return
            }

            if appFrame.contains(frame) {
                let center = CGPoint(x: frame.midX, y: frame.midY)
                let appOrigin = app.coordinate(withNormalizedOffset: .zero)
                appOrigin.withOffset(CGVector(
                    dx: center.x - appFrame.minX,
                    dy: center.y - appFrame.minY
                )).tap()
                return
            }

            guard frame.midX >= appFrame.minX, frame.midX <= appFrame.maxX else {
                XCTFail("The element is horizontally outside the application frame.",
                        file: file, line: line)
                return
            }
            guard attempt < 8 else {
                XCTFail("The element did not enter the visible application frame.",
                        file: file, line: line)
                return
            }
            guard editorForm.waitForExistence(timeout: 2) else {
                XCTFail("rideEditorForm is unavailable to reveal the element.",
                        file: file, line: line)
                return
            }
            let visibleForm = editorForm.frame.intersection(appFrame)
            guard isUsable(visibleForm) else {
                XCTFail("rideEditorForm has no visible scrolling area.", file: file, line: line)
                return
            }

            let scrollUp = frame.maxY > appFrame.maxY
            let distance = visibleForm.height * 0.18
            let startPoint = CGPoint(
                x: visibleForm.midX,
                y: visibleForm.midY + (scrollUp ? distance / 2 : -distance / 2))
            let endPoint = CGPoint(
                x: visibleForm.midX,
                y: visibleForm.midY + (scrollUp ? -distance / 2 : distance / 2))
            let formFrame = editorForm.frame
            let formOrigin = editorForm.coordinate(withNormalizedOffset: .zero)
            let start = formOrigin.withOffset(CGVector(
                dx: startPoint.x - formFrame.minX,
                dy: startPoint.y - formFrame.minY))
            let end = formOrigin.withOffset(CGVector(
                dx: endPoint.x - formFrame.minX,
                dy: endPoint.y - formFrame.minY))
            start.press(forDuration: 0.05, thenDragTo: end)

            let updatedFrame = element.frame
            guard isUsable(updatedFrame) else {
                XCTFail("The element lost its usable frame while rideEditorForm scrolled.",
                        file: file, line: line)
                return
            }
            let movement = updatedFrame.midY - frame.midY
            let movedTowardVisibleFrame = scrollUp ? movement < -1 : movement > 1
            if !movedTowardVisibleFrame {
                XCTFail("rideEditorForm did not move the element toward the visible frame.",
                        file: file, line: line)
                return
            }
        }
    }

    static func enableDate(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let includeDate = app.switches["Include a date"]
        guard includeDate.waitForExistence(timeout: 8) else {
            XCTFail("The Include a date row did not appear.", file: file, line: line)
            return
        }
        let childSwitch = includeDate.switches.firstMatch
        guard childSwitch.waitForExistence(timeout: 5) else {
            XCTFail("The Include a date row has no switch control.", file: file, line: line)
            return
        }
        if !switchIsOn(includeDate) {
            tap(childSwitch, in: app, file: file, line: line)
        }

        let enabled = XCTNSPredicateExpectation(
            predicate: NSPredicate { object, _ in
                guard let element = object as? XCUIElement else { return false }
                if let value = element.value as? String { return value == "1" }
                if let value = element.value as? NSNumber { return value.boolValue }
                return false
            },
            object: includeDate)
        guard XCTWaiter().wait(for: [enabled], timeout: 5) == .completed else {
            XCTFail("The Include a date switch did not turn on.", file: file, line: line)
            return
        }
        guard app.textFields["rideEditorDateInput"].waitForExistence(timeout: 5) else {
            XCTFail("The date field did not appear after enabling the date.",
                    file: file, line: line)
            return
        }
    }

    private static func isUsable(_ frame: CGRect) -> Bool {
        !frame.isNull && !frame.isInfinite && !frame.isEmpty
            && frame.origin.x.isFinite && frame.origin.y.isFinite
            && frame.width.isFinite && frame.height.isFinite
    }

    private static func switchIsOn(_ element: XCUIElement) -> Bool {
        if let value = element.value as? String { return value == "1" }
        if let value = element.value as? NSNumber { return value.boolValue }
        return false
    }
}
