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
        app.launchEnvironment["RAILMAP_UI_TEST_STORAGE_ID"] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "search"
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "expanded"
        app.launchEnvironment["RAILMAP_UI_TEST_SAMPLE"] = "train-store"
        app.launchEnvironment["RAILMAP_UI_TEST_QUERY"] = "haruka"
        app.launch()
        let row = app.descendants(matching: .any)["journeyRow-20260703_01_haruka"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        row.tap()
        // Detail opens over Search; closing it retains the resident query.
        let back = app.buttons["journeyBackToList"]
        XCTAssertTrue(back.waitForExistence(timeout: 8))
        back.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        let search = app.textFields["journeySearchField"]
        XCTAssertEqual(search.value as? String, "haruka")
    }

    func testPlaybackCanPauseResumeAndStop() {
        let app = XCUIApplication()
        app.launchEnvironment["RAILMAP_UI_TEST_STORAGE_ID"] = UUID().uuidString
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
        // Open the known saved fixture through its native row so this isolated
        // test starts with a confirmed record identity.
        let fixtureID = "20260704_02_kodama918"
        let originalNumber = "こだま918号（Kodama 918）（918A）"
        let app = XCUIApplication()
        app.launchEnvironment["RAILMAP_UI_TEST_STORAGE_ID"] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-interface-language", "en"]
        app.launchEnvironment["RAILMAP_UI_TEST_SAMPLE"] = "train-store"
        app.launchEnvironment["RAILMAP_UI_TEST_STATS_REGION"] = "all"
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "search"
        app.launchEnvironment["RAILMAP_UI_TEST_QUERY"] = fixtureID
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "expanded"
        app.launch()
        let row = app.buttons["journeyRow-\(fixtureID)"]
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        row.tap()
        let selected = app.descendants(matching: .any)["selectedJourney-\(fixtureID)"].firstMatch
        XCTAssertTrue(selected.waitForExistence(timeout: 8))
        let edit = app.buttons["journeyMenuEdit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 30))
        XCTAssertTrue(edit.isHittable)
        edit.tap()
        let number = app.otherElements["rideEditorNumber"].textFields.firstMatch
        XCTAssertTrue(number.waitForExistence(timeout: 8))
        XCTAssertEqual(number.value as? String, originalNumber)
        EditorUITestSupport.tap(number, in: app)
        number.typeText("X\n")
        let edited = number.value as? String ?? ""
        XCTAssertNotEqual(edited, "Review")
        XCTAssertEqual(edited.replacingOccurrences(of: "X", with: ""), originalNumber,
                       "Typing must retain the complete original number.")
        XCTAssertEqual(edited.filter { $0 == "X" }.count, 1,
                       "The edited number must contain exactly the one inserted character.")
        let save = app.buttons["rideEditorSave"]
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 8))

        XCTAssertTrue(selected.waitForExistence(timeout: 15))
        let savedID = String(selected.identifier.dropFirst("selectedJourney-".count))
        XCTAssertEqual(savedID, fixtureID, "Editing must retain the saved record identity.")
        let back = app.buttons["journeyBackToList"]
        XCTAssertTrue(back.waitForExistence(timeout: 15))
        back.tap()
        // The resident Search query is the exact unchanged record ID, so it
        // continues to locate this same record after its visible number changes.
        let search = app.textFields["journeySearchField"]
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        XCTAssertEqual(search.value as? String, fixtureID)
        let savedRow = app.buttons["journeyRow-\(savedID)"]
        XCTAssertTrue(savedRow.waitForExistence(timeout: 30))
        savedRow.press(forDuration: 1)
        let information = app.buttons["Journey information"]
        XCTAssertTrue(information.waitForExistence(timeout: 5))
        information.tap()
        XCTAssertTrue(selected.waitForExistence(timeout: 8))
        XCTAssertTrue(edit.waitForExistence(timeout: 8))
        // Resolve the foreground scroll once by its Edit action, then retain
        // its position in the scroll query. A descendant predicate stops
        // resolving when that action is lazily unmounted during scrolling.
        guard let detailScrollIndex = app.scrollViews.allElementsBoundByIndex.firstIndex(where: {
            $0.buttons["journeyMenuEdit"].exists
        }) else {
            XCTFail("The foreground journey detail ScrollView must contain Edit.")
            return
        }
        let detailScroll = app.scrollViews.element(boundBy: detailScrollIndex)
        XCTAssertTrue(detailScroll.waitForExistence(timeout: 5))
        let more = detailScroll.buttons["More journey actions"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        // More shares the native action row with Edit. Require the actual
        // foreground ScrollView to contain its complete tappable bounds.
        var scrollTowardStart = false
        for _ in 0..<4 {
            let bounds = detailScroll.frame.intersection(app.frame)
            XCTAssertFalse(bounds.isEmpty)
            if more.exists {
                if bounds.contains(more.frame) { break }
                scrollTowardStart = more.frame.minY < bounds.minY
            }
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(
                dx: bounds.minX + 8 - app.frame.minX,
                dy: bounds.minY + bounds.height * (scrollTowardStart ? 0.25 : 0.75) - app.frame.minY))
            let end = origin.withOffset(CGVector(
                dx: bounds.minX + 8 - app.frame.minX,
                dy: bounds.minY + bounds.height * (scrollTowardStart ? 0.75 : 0.25) - app.frame.minY))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(more.isHittable)
        XCTAssertTrue(detailScroll.frame.intersection(app.frame).contains(more.frame), app.debugDescription)
        more.tap()
        let hide = app.buttons["Hide from map"]
        attachDiagnostics(app, named: "Detail More menu before visibility action")
        XCTAssertTrue(hide.waitForExistence(timeout: 5))
        XCTAssertTrue(hide.isHittable)
        hide.tap()
        XCTAssertTrue(selected.waitForExistence(timeout: 8))
        XCTAssertTrue(edit.isHittable)
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
            let importForm = app.collectionViews["importForm"]
            XCTAssertTrue(importForm.waitForExistence(timeout: 5))
            // The raw JSON editor can fill the visible Form. Scroll its
            // outer gutter so the lazy mode rows mount before querying them.
            for _ in 0..<8 where !anyRegion.exists {
                let bounds = importForm.frame.intersection(app.frame)
                XCTAssertFalse(bounds.isEmpty)
                let start = importForm.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: 8, dy: bounds.height * 0.7))
                start.press(forDuration: 0.05, thenDragTo: start.withOffset(
                    CGVector(dx: 0, dy: -bounds.height * 0.4)))
            }
            XCTAssertTrue(anyRegion.waitForExistence(timeout: 5))
            let forms = app.collectionViews.containing(.any, identifier: "importRegion")
            XCTAssertEqual(forms.count, 1, "Resolve the import region's own foreground Form.")
            let form = forms.firstMatch
            let navigation = app.navigationBars.containing(.button, identifier: "importCancel").firstMatch
            XCTAssertTrue(navigation.exists)
            // The outer scrollbar is a direct Form child. The JSON text editor's
            // scrollbar is nested inside its TextView and must not be used here.
            let scrollbar = form.children(matching: .other).matching(
                NSPredicate(format: "label BEGINSWITH %@", "Vertical scroll bar")).firstMatch
            XCTAssertTrue(scrollbar.exists, form.debugDescription)

            func finiteNonempty(_ frame: CGRect) -> Bool {
                !frame.isEmpty && [frame.minX, frame.minY, frame.maxX, frame.maxY].allSatisfy { $0.isFinite }
            }
            func usableFrame() -> CGRect {
                let rawFormFrame = form.frame
                // AX can report 72 + 802 as 874.0000000000001. Snap only
                // machine-roundoff at the exact window edges; real clipping
                // continues to fail the complete containment assertion.
                func snap(_ value: CGFloat, to edge: CGFloat) -> CGFloat {
                    abs(value - edge) <= max(value.ulp, edge.ulp) * 4 ? edge : value
                }
                let minX = snap(rawFormFrame.minX, to: app.frame.minX)
                let minY = snap(rawFormFrame.minY, to: app.frame.minY)
                let maxX = snap(rawFormFrame.maxX, to: app.frame.maxX)
                let maxY = snap(rawFormFrame.maxY, to: app.frame.maxY)
                let formFrame = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                let barFrame = scrollbar.frame
                if !finiteNonempty(formFrame) || !app.frame.contains(formFrame) {
                    attachDiagnostics(app, named: "Import Form geometry")
                }
                XCTAssertTrue(finiteNonempty(app.frame))
                XCTAssertTrue(finiteNonempty(formFrame) && app.frame.contains(formFrame),
                              "Import geometry: app=\(app.frame), rawForm=\(rawFormFrame), form=\(formFrame), scrollbar=\(barFrame)")
                XCTAssertTrue(finiteNonempty(barFrame) && formFrame.contains(barFrame))
                XCTAssertTrue(finiteNonempty(navigation.frame) && app.frame.contains(navigation.frame))
                var bottom = min(formFrame.maxY, barFrame.maxY)
                for actionID in ["importValidate", "importCommit"] {
                    let action = app.buttons[actionID].firstMatch
                    if action.exists {
                        XCTAssertTrue(finiteNonempty(action.frame) && app.frame.contains(action.frame))
                        bottom = min(bottom, action.frame.minY)
                    }
                }
                let top = max(formFrame.minY, barFrame.minY, navigation.frame.maxY)
                let usable = CGRect(x: formFrame.minX, y: top, width: formFrame.width, height: bottom - top)
                XCTAssertTrue(finiteNonempty(usable) && formFrame.contains(usable))
                return usable
            }

            for _ in 0..<4 {
                let usable = usableFrame()
                let regionFrame = anyRegion.frame
                XCTAssertTrue(finiteNonempty(regionFrame))
                if usable.contains(regionFrame) { break }
                // Never scroll to compensate for a native-hit failure alone.
                XCTAssertTrue(form.isHittable, form.debugDescription)
                XCTAssertTrue(scrollbar.isHittable, scrollbar.debugDescription)
                XCTAssertTrue(regionFrame.minX >= usable.minX && regionFrame.maxX <= usable.maxX)
                let distance = min(regionFrame.height, usable.height / 4)
                let direction: CGFloat = regionFrame.maxY > usable.maxY ? -1 : 1
                let startPoint = CGPoint(x: scrollbar.frame.midX, y: usable.midY)
                let endPoint = CGPoint(x: startPoint.x, y: startPoint.y + direction * distance)
                XCTAssertTrue(usable.contains(startPoint) && usable.contains(endPoint))
                let start = app.coordinate(withNormalizedOffset: .zero).withOffset(
                    CGVector(dx: startPoint.x - app.frame.minX, dy: startPoint.y - app.frame.minY))
                start.press(forDuration: 0.05, thenDragTo: start.withOffset(
                    CGVector(dx: 0, dy: direction * distance)))
            }
            XCTAssertTrue(app.frame.contains(anyRegion.frame), anyRegion.debugDescription)
            XCTAssertTrue(usableFrame().contains(anyRegion.frame), anyRegion.debugDescription)
            XCTAssertTrue(anyRegion.isHittable, anyRegion.debugDescription)

            let popupRegion = app.popUpButtons["importRegion"].firstMatch
            if popupRegion.exists {
                XCTAssertTrue(popupRegion.isHittable, popupRegion.debugDescription)
                return (popupRegion, true)
            }
            let buttonRegion = app.buttons["importRegion"].firstMatch
            XCTAssertTrue(buttonRegion.exists, anyRegion.debugDescription)
            XCTAssertTrue(buttonRegion.isHittable, buttonRegion.debugDescription)
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

    func testServiceTypeSuggestionsAndCustomVehicleInput() {
        // Train-type autocomplete is an existing-record field; new journeys
        // choose their type through the region-step Picker.
        let app = XCUIApplication()
        app.launchEnvironment["RAILMAP_UI_TEST_STORAGE_ID"] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-interface-language", "en"]
        app.launchEnvironment["RAILMAP_UI_TEST_SAMPLE"] = "train-store"
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "search"
        app.launchEnvironment["RAILMAP_UI_TEST_QUERY"] = "20260704_02_kodama918"
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "expanded"
        app.launch()
        let row = app.buttons["journeyRow-20260704_02_kodama918"]
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["selectedJourney-20260704_02_kodama918"]
            .firstMatch.waitForExistence(timeout: 8))
        let edit = app.buttons["journeyMenuEdit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 8))
        edit.tap()
        XCTAssertTrue(app.descendants(matching: .any)["rideEditorForm"].firstMatch
            .waitForExistence(timeout: 8))

        let form = app.collectionViews["rideEditorForm"]
        XCTAssertTrue(form.waitForExistence(timeout: 8))
        // This method's existing-record service fields are below the lazy Basics
        // cells. Measure native cell movement before each further upward reveal.
        func revealServiceField(_ field: XCUIElement, stage: String) -> Bool {
            func evidence(_ suffix: String) {
                attach(app, named: "service-input-\(stage)-\(suffix)")
                let targetExists = field.exists
                let targetFrame = targetExists ? field.frame : .zero
                let details = XCTAttachment(string:
                    "Form=\(form.frame); targetExists=\(targetExists); targetFrame=\(targetFrame)\n" + app.debugDescription)
                details.name = "service-input-\(stage)-\(suffix)-geometry-and-tree"
                details.lifetime = .keepAlways
                add(details)
            }
            for attempt in 0...6 {
                let formFrame = form.frame
                var visible = formFrame.intersection(app.frame).insetBy(dx: 8, dy: 8)
                let navigationBottom = app.navigationBars.allElementsBoundByIndex
                    .filter { $0.exists && $0.isHittable }.map { $0.frame.maxY }.max() ?? visible.minY
                let top = max(visible.minY, navigationBottom + 8)
                let keyboard = app.keyboards.firstMatch
                let bottom = keyboard.exists ? min(visible.maxY, keyboard.frame.minY - 8) : visible.maxY
                visible = CGRect(x: visible.minX, y: top, width: visible.width, height: max(0, bottom - top))
                guard !visible.isEmpty else {
                    evidence("empty-viewport")
                    return false
                }
                if field.exists, field.isHittable, !field.frame.isEmpty, visible.contains(field.frame) {
                    evidence("fully-revealed")
                    return true
                }
                guard attempt < 6 else {
                    evidence("bounded-reveal-exhausted")
                    return false
                }
                let cells = form.cells.allElementsBoundByIndex.filter {
                    $0.isHittable && visible.contains($0.frame)
                        && $0.frame.midY >= visible.minY + visible.height * 0.4
                }
                // Use a real lower Form cell as the gesture origin, never the
                // sheet's grabber or an application-wide swipe.
                var anchoredCell: (cell: XCUIElement, label: String)?
                for candidate in cells {
                    let uniqueLabels = candidate.staticTexts.allElementsBoundByIndex.map { $0.label }
                        .filter { !$0.isEmpty && form.staticTexts.matching(NSPredicate(format: "label == %@", $0)).count == 1 }
                    if let label = uniqueLabels.last {
                        anchoredCell = (candidate, label)
                        break
                    }
                }
                guard let anchoredCell else {
                    evidence("stable-progress-anchor-missing")
                    return false
                }
                let cell = anchoredCell.cell
                let label = anchoredCell.label
                let anchor = form.staticTexts.matching(NSPredicate(format: "label == %@", label)).firstMatch
                let oldAnchorY = anchor.frame.midY
                evidence("before-native-drag-\(attempt)")
                let origin = app.coordinate(withNormalizedOffset: .zero)
                let start = origin.withOffset(CGVector(dx: cell.frame.midX, dy: cell.frame.midY))
                let distance = min(visible.height * 0.35, cell.frame.midY - visible.minY - 8)
                guard distance > 30 else { return false }
                start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -distance)))
                evidence("after-native-drag-\(attempt)")
                guard abs(form.frame.minY - formFrame.minY) < 3,
                      abs(form.frame.height - formFrame.height) < 3 else {
                    XCTFail("The native Form must retain its viewport while revealing service inputs.")
                    return false
                }
                if anchor.exists && anchor.frame.midY >= oldAnchorY - 1 {
                    XCTFail("The native Form cell did not move upward; stop before another drag.")
                    return false
                }
                // A unique anchor leaving the lazy viewport is also recorded
                // progress, with the unchanged Form geometry in the evidence.
            }
            return false
        }
        let type = app.otherElements["rideEditorTrainType"].textFields.firstMatch
        guard revealServiceField(type, stage: "train-type") else {
            XCTFail("The existing editor train-type input must materialize fully inside its Form viewport.")
            return
        }
        EditorUITestSupport.tap(type, in: app)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        if let initial = type.value as? String,
           !initial.isEmpty && initial != type.placeholderValue {
            type.press(forDuration: 1.1)
            let selectAll = app.menuItems["Select All"].firstMatch
            let button = app.buttons["Select All"].firstMatch
            if button.waitForExistence(timeout: 3) {
                button.tap()
            } else {
                XCTAssertTrue(selectAll.waitForExistence(timeout: 2))
                selectAll.tap()
            }
        }
        type.typeText("Rap")
        XCTAssertEqual(type.value as? String, "Rap", "The complete initial train type must be replaced.")
        let rapid = app.buttons["Rapid"].firstMatch
        XCTAssertTrue(rapid.waitForExistence(timeout: 5))
        rapid.tap()
        XCTAssertEqual(type.value as? String, "Rapid")
        let vehicle = app.otherElements["rideEditorVehicleType"].textFields.firstMatch
        guard revealServiceField(vehicle, stage: "vehicle") else {
            XCTFail("The vehicle input must be fully inside the native Form viewport above the keyboard.")
            return
        }
        EditorUITestSupport.tap(vehicle, in: app)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        if let initial = vehicle.value as? String,
           !initial.isEmpty && initial != vehicle.placeholderValue {
            vehicle.press(forDuration: 1.1)
            let selectAll = app.menuItems["Select All"].firstMatch
            let button = app.buttons["Select All"].firstMatch
            if button.waitForExistence(timeout: 3) {
                button.tap()
            } else {
                XCTAssertTrue(selectAll.waitForExistence(timeout: 2))
                selectAll.tap()
            }
        }
        vehicle.typeText("E235")
        XCTAssertEqual(vehicle.value as? String, "E235")
    }

    func testTypedDateAndLineSearch() {
        // The new wizard's route control opens the physical route guide.
        // Line preferences are edited through the saved journey's catalog.
        let fixtureID = "20260727_08_narita_express"
        let app = XCUIApplication()
        app.launchEnvironment["RAILMAP_UI_TEST_STORAGE_ID"] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-interface-language", "en"]
        app.launchEnvironment["RAILMAP_UI_TEST_SAMPLE"] = "train-store"
        app.launchEnvironment["RAILMAP_UI_TEST_STATS_REGION"] = "all"
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "search"
        app.launchEnvironment["RAILMAP_UI_TEST_QUERY"] = fixtureID
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "expanded"
        app.launch()
        let row = app.buttons["journeyRow-\(fixtureID)"]
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["selectedJourney-\(fixtureID)"]
            .firstMatch.waitForExistence(timeout: 8))
        let edit = app.buttons["journeyMenuEdit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 30))
        XCTAssertTrue(edit.isHittable)
        edit.tap()
        let lines = app.descendants(matching: .any)["rideEditorPreferredLines"].firstMatch
        EditorUITestSupport.tap(lines, in: app)
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

        let date = app.textFields["rideEditorDateInput"]
        XCTAssertTrue(EditorUITestSupport.reveal(date, in: app, unmountedRowIsAbove: true), app.debugDescription)
        XCTAssertTrue(date.waitForExistence(timeout: 5))
        replaceText(in: date, with: "2026-10-12", app: app)
        XCTAssertEqual(date.value as? String, "2026-10-12")
    }



    func testAddingStopOpensItsEditorAndCancelProtectsDraft() {
        let app = XCUIApplication()
        EditorLaunchSupport.launchEditing(app, journey: seededJourney(number: "Add stop"))
        let add = app.buttons["rideEditorAddStop"]
        XCTAssertTrue(app.buttons["rideEditorCancel"].waitForExistence(timeout: 30))
        EditorUITestSupport.tap(add, in: app)
        XCTAssertTrue(app.otherElements["rideEditorStopName"].waitForExistence(timeout: 8))
        let added = app.navigationBars["Stop 3"]
        XCTAssertTrue(added.waitForExistence(timeout: 5))
        added.buttons.firstMatch.tap()
        app.buttons["rideEditorCancel"].tap()
        XCTAssertTrue(app.buttons["Discard changes"].waitForExistence(timeout: 5))
    }

    func testExplicitUnriddenStopSurvivesChoosingToday() {
        let app = XCUIApplication()
        EditorLaunchSupport.launchEditing(
            app, journey: seededJourney(number: "Ridden choice", date: "2026-12-01"))
        let origin = app.descendants(matching: .any)["rideEditorStop-0"].firstMatch
        XCTAssertTrue(app.buttons["rideEditorCancel"].waitForExistence(timeout: 30))
        EditorUITestSupport.tap(origin, in: app)

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

        let date = app.textFields["rideEditorDateInput"]
        XCTAssertTrue(EditorUITestSupport.reveal(date, in: app, unmountedRowIsAbove: true), app.debugDescription)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        replaceText(in: date, with: formatter.string(from: Date()), app: app)
        date.typeText("\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))

        XCTAssertTrue(EditorUITestSupport.reveal(origin, in: app, unmountedRowIsAbove: false),
                      app.debugDescription)
        EditorUITestSupport.tap(origin, in: app)
        let riddenAfterDate = revealRiddenControl()
        XCTAssertEqual(riddenAfterDate.value as? String, "0",
                       "Choosing today's date must not overwrite an explicit stop choice.")
    }

    func testStopDeleteUndoRestoresEndpointRolesAndRegionClearsUndo() {
        let app = XCUIApplication()
        EditorLaunchSupport.launchEditing(app, journey: seededJourney(number: "Undo stops"))

        func revealRole(_ role: String) -> XCUIElement {
            let form = app.collectionViews.firstMatch
            XCTAssertTrue(form.waitForExistence(timeout: 8))
            let picker = app.buttons["Stop type, \(role)"]
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
        XCTAssertTrue(remaining.waitForExistence(timeout: 8))
        remaining.tap()
        // Existing records keep the authored role. Promoting the new first
        // stop to Origin, and disabling that picker, happens only for a new
        // journey.
        let remainingRole = revealRole("Destination")
        XCTAssertTrue(remainingRole.isEnabled,
                      "Edit mode keeps the authored destination role and allows changing it.")
        app.navigationBars["Shinagawa"].buttons.firstMatch.tap()

        let undo = app.buttons["rideEditorUndoStops"]
        EditorUITestSupport.tap(undo, in: app)

        let origin = app.descendants(matching: .any)["rideEditorStop-0"].firstMatch
        EditorUITestSupport.tap(origin, in: app)
        let originRole = revealRole("Origin")
        XCTAssertTrue(originRole.isEnabled,
                      "Undo must restore the first stop's authored origin role.")
        app.navigationBars["Tokyo"].buttons.firstMatch.tap()

        let destination = app.descendants(matching: .any)["rideEditorStop-1"].firstMatch
        EditorUITestSupport.tap(destination, in: app)
        let destinationRole = revealRole("Destination")
        XCTAssertTrue(destinationRole.isEnabled,
                      "Undo must restore the last stop's authored destination role.")
        app.navigationBars["Shinagawa"].buttons.firstMatch.tap()

        deleteFirstStop(in: app)
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        let region = app.descendants(matching: .any)["rideEditorRegion"].firstMatch
        XCTAssertTrue(EditorUITestSupport.reveal(region, in: app, unmountedRowIsAbove: false),
                      app.debugDescription)
        region.tap()
        app.buttons["Taiwan"].firstMatch.tap()
        XCTAssertTrue(undo.waitForNonExistence(timeout: 5),
                      "Changing region must clear the stop-deletion undo.")
    }

    private func replaceText(in field: XCUIElement, with replacement: String, app: XCUIApplication) {
        let current = field.value as? String ?? ""
        field.tap()
        if !current.isEmpty && current != field.placeholderValue {
            field.press(forDuration: 1.1)
            let selectAll = app.buttons["Select All"].firstMatch
            let selectAllMenuItem = app.menuItems["Select All"].firstMatch
            if selectAll.waitForExistence(timeout: 3) {
                selectAll.tap()
            } else {
                XCTAssertTrue(selectAllMenuItem.waitForExistence(timeout: 2))
                selectAllMenuItem.tap()
            }
            field.typeText(XCUIKeyboardKey.delete.rawValue + replacement)
        } else if !replacement.isEmpty {
            field.typeText(replacement)
        }
        let value = field.value as? String ?? ""
        XCTAssertTrue(value == replacement || (replacement.isEmpty && value == field.placeholderValue),
                      "Replacing text must change the entire native value, not only the tapped cursor prefix.")
    }

    private func attach(_: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attachDiagnostics(_ app: XCUIApplication, named name: String) {
        attach(app, named: name)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = name + " accessibility hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }

    private func deleteFirstStop(in app: XCUIApplication) {
        let reorder = app.buttons["rideEditorReorderStops"]
        EditorUITestSupport.tap(reorder, in: app)
        // The explicit edit-mode minus now executes the same deletion handler
        // directly; a native second-stage Delete confirmation no longer exists.
        let remove = app.buttons["rideEditorDeleteStop-0"]
        // Edit mode animates the minus controls in; allow for a loaded simulator.
        XCTAssertTrue(remove.waitForExistence(timeout: 15))
        EditorUITestSupport.tap(remove, in: app)
        XCTAssertFalse(app.otherElements["rideEditorStopName"].textFields.firstMatch.exists,
                       "The row's minus must delete without navigating into the stop editor.")
    }

    private func seededJourney(number: String, date: String = "2026-10-12") -> [String: Any] {
        let compact = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        return [
            "id": "uitest_\(compact.prefix(12))",
            "date": date,
            "number": number,
            "origin": "Tokyo",
            "destination": "Shinagawa",
            "region": "jp",
            "stops": [
                EditorLaunchSupport.stop("Tokyo", code: "003768", type: "origin", departure: "09:00"),
                EditorLaunchSupport.stop("Shinagawa", code: "004092", type: "destination", arrival: "09:20"),
            ],
        ]
    }

    private func launch(
        sheet: String,
        language: String = "en",
        locale: String = "en_US",
        launchArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["RAILMAP_UI_TEST_STORAGE_ID"] = UUID().uuidString
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
    /// A lazy Form row must be brought into the viewport before querying it.
    static func reveal(
        _ element: XCUIElement, in app: XCUIApplication,
        maxDrags: Int = 8, unmountedRowIsAbove: Bool? = nil
    ) -> Bool {
        if element.exists, element.isHittable, isUsable(element.frame),
           app.frame.contains(element.frame) { return true }
        let form = app.descendants(matching: .any)["rideEditorForm"].firstMatch
        guard form.waitForExistence(timeout: 2) else { return false }
        XCTContext.runActivity(named: "Lazy editor control before reveal") { activity in
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.lifetime = .keepAlways
            activity.add(screenshot)
        }
        for attempt in 0..<maxDrags {
            let viewport = form.frame.intersection(app.frame)
            guard isUsable(viewport) else { return false }
            if element.exists, isUsable(element.frame), viewport.contains(element.frame) {
                return true
            }
            // An unmounted row can be above or below the current position.
            // Search both directions within the same eight-drag budget.
            let downward = element.exists
                ? element.frame.minY < viewport.minY
                : unmountedRowIsAbove ?? (attempt >= maxDrags / 2)
            let gutter = viewport.width > 20 ? viewport.minX + 8 : viewport.midX
            let start = CGPoint(x: gutter,
                y: viewport.midY + (downward ? -1 : 1) * viewport.height * 0.275)
            let end = CGPoint(x: gutter,
                y: viewport.midY + (downward ? 1 : -1) * viewport.height * 0.275)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let appFrame = app.frame
            origin.withOffset(CGVector(dx: start.x - appFrame.minX, dy: start.y - appFrame.minY))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(
                    CGVector(dx: end.x - appFrame.minX, dy: end.y - appFrame.minY)))
        }
        return element.waitForExistence(timeout: 5)
    }

    /// Seed named endpoints through the real route picker before advancing
    /// the new-journey wizard to its date step.
    static func seedNamedRoute(in app: XCUIApplication) {
        EditorUITestSupport.tap(app.buttons["rideEditorServicePattern"], in: app)
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
        _ = reveal(element, in: app)
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
