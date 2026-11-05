import RailPresentation
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
        app.uiTestLaunch[.storageId] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.uiTestLaunch[.tab] = "search"
        app.uiTestLaunch[.stage] = "expanded"
        app.uiTestLaunch[.sample] = "train-store"
        app.uiTestLaunch[.query] = "haruka"
        UITestLaunchSupport.launch(app)
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
        app.uiTestLaunch[.storageId] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        // Sample journeys remain playable after their calendar dates pass.
        app.uiTestLaunch[.tab] = "all"
        app.uiTestLaunch[.sample] = "train-store"
        app.uiTestLaunch[.playback] = "1"
        UITestLaunchSupport.launch(app)
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
        app.uiTestLaunch[.storageId] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-interface-language", "en"]
        app.uiTestLaunch[.sample] = "train-store"
        app.uiTestLaunch[.statsRegion] = "all"
        app.uiTestLaunch[.tab] = "search"
        app.uiTestLaunch[.query] = fixtureID
        app.uiTestLaunch[.stage] = "expanded"
        UITestLaunchSupport.launch(app)
        let row = app.buttons["journeyRow-\(fixtureID)"]
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        row.tap()
        let selected = app.descendants(matching: .any)["selectedJourney-\(fixtureID)"].firstMatch
        XCTAssertTrue(selected.waitForExistence(timeout: 8))
        let edit = app.buttons["journeyMenuEdit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 30))
        XCTAssertTrue(edit.isHittable)
        edit.tap()
        let number = app.textFields["newTripNumber"]
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
        let save = app.buttons["newTripSave"]
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
        // Train type is now the newTripTrainType picker (autocomplete removed);
        // only the free-text vehicle input is exercised here.
        let app = XCUIApplication()
        app.uiTestLaunch[.storageId] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-interface-language", "en"]
        app.uiTestLaunch[.sample] = "train-store"
        app.uiTestLaunch[.tab] = "search"
        app.uiTestLaunch[.query] = "20260704_02_kodama918"
        app.uiTestLaunch[.stage] = "expanded"
        UITestLaunchSupport.launch(app)
        let row = app.buttons["journeyRow-20260704_02_kodama918"]
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["selectedJourney-20260704_02_kodama918"]
            .firstMatch.waitForExistence(timeout: 8))
        let edit = app.buttons["journeyMenuEdit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 8))
        edit.tap()
        XCTAssertTrue(app.descendants(matching: .any)["newTripForm"].firstMatch
            .waitForExistence(timeout: 8))

        let form = app.collectionViews["newTripForm"]
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
                let start = origin.withOffset(CGVector(
                    dx: cell.frame.midX - app.frame.minX,
                    dy: cell.frame.midY - app.frame.minY))
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

    private func launch(
        sheet: String,
        language: String = "en",
        locale: String = "en_US",
        launchArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.uiTestLaunch[.storageId] = UUID().uuidString
        app.launchArguments = [
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale,
            "-interface-language", language,
        ] + launchArguments
        app.uiTestLaunch[.tab] = "all"
        app.uiTestLaunch[.statsRegion] = "all"
        app.uiTestLaunch[.stage] = "expanded"
        app.uiTestLaunch[.sheet] = sheet
        UITestLaunchSupport.launch(app)
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
        maxDrags: Int = 8, unmountedRowIsAbove: Bool? = nil, minimumVisibleY: CGFloat? = nil
    ) -> Bool {
        if element.exists, element.isHittable, isUsable(element.frame),
           app.frame.contains(element.frame),
           minimumVisibleY.map({ element.frame.minY >= $0 }) ?? true { return true }
        let form = app.descendants(matching: .any)["newTripForm"].firstMatch
        guard form.waitForExistence(timeout: 2) else { return false }
        XCTContext.runActivity(named: "Lazy editor control before reveal") { activity in
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.lifetime = .keepAlways
            activity.add(screenshot)
        }
        for attempt in 0..<maxDrags {
            let viewport = frameBelowHeader(
                form.frame.intersection(app.frame), minimumVisibleY: minimumVisibleY)
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
        let fill = app.buttons["newTripFillDetails"]
        EditorUITestSupport.tap(fill, in: app)
        let browse = app.buttons["newTripTimetableBrowse"]
        XCTAssertTrue(browse.waitForExistence(timeout: 8), app.debugDescription)
        browse.tap()
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
        minimumVisibleY: CGFloat? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        _ = reveal(element, in: app, minimumVisibleY: minimumVisibleY)
        guard element.waitForExistence(timeout: 5) else {
            XCTFail("The element to tap does not exist.", file: file, line: line)
            return
        }

        let appFrame = app.frame
        guard isUsable(appFrame) else {
            XCTFail("The application has no usable frame.", file: file, line: line)
            return
        }

        let visibleFrame = frameBelowHeader(appFrame, minimumVisibleY: minimumVisibleY)
        guard isUsable(visibleFrame) else {
            XCTFail("The editor has no visible content below its header.", file: file, line: line)
            return
        }
        let editorForm = app.descendants(matching: .any)["newTripForm"].firstMatch
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

            if visibleFrame.contains(frame) {
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
                XCTFail("newTripForm is unavailable to reveal the element.",
                        file: file, line: line)
                return
            }
            let visibleForm = editorForm.frame.intersection(visibleFrame)
            guard isUsable(visibleForm) else {
                XCTFail("newTripForm has no visible scrolling area.", file: file, line: line)
                return
            }

            let scrollUp = frame.maxY > visibleFrame.maxY
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
                XCTFail("The element lost its usable frame while newTripForm scrolled.",
                        file: file, line: line)
                return
            }
            let movement = updatedFrame.midY - frame.midY
            let movedTowardVisibleFrame = scrollUp ? movement < -1 : movement > 1
            if !movedTowardVisibleFrame {
                XCTFail("newTripForm did not move the element toward the visible frame.",
                        file: file, line: line)
                return
            }
        }
    }

    /// Opt-in clipping preserves the existing bounds for all other callers.
    private static func frameBelowHeader(_ frame: CGRect, minimumVisibleY: CGFloat?) -> CGRect {
        guard let minimumVisibleY else { return frame }
        let top = max(frame.minY, minimumVisibleY)
        return CGRect(x: frame.minX, y: top, width: frame.width, height: max(0, frame.maxY - top))
    }

    private static func isUsable(_ frame: CGRect) -> Bool {
        !frame.isNull && !frame.isInfinite && !frame.isEmpty
            && frame.origin.x.isFinite && frame.origin.y.isFinite
            && frame.width.isFinite && frame.height.isFinite
    }
}
