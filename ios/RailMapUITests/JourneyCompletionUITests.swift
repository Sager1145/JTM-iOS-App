import XCTest

@MainActor
final class JourneyCompletionUITests: XCTestCase {
    func testNewJourneyCanReachDateAndCompletionWithoutTrainNumber() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["RAILMAP_UI_TEST_STORAGE_ID"] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-interface-language", "en"]
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "all"
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "expanded"
        app.launchEnvironment["RAILMAP_UI_TEST_SHEET"] = "new"
        app.launch()

        let next = app.buttons["rideEditorNext"]
        XCTAssertTrue(next.waitForExistence(timeout: 40))
        next.tap()
        for (index, name) in ["Tokyo", "Shinagawa"].enumerated() {
            let stop = app.descendants(matching: .any)["rideEditorStop-\(index)"].firstMatch
            XCTAssertTrue(EditorUITestSupport.reveal(stop, in: app), app.debugDescription)
            XCTAssertTrue(stop.waitForExistence(timeout: 8))
            stop.tap()
            let field = app.otherElements["rideEditorStopName"].textFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeText(name)
            app.navigationBars[name].buttons.firstMatch.tap()
        }
        next.tap()
        XCTAssertTrue(app.otherElements["rideEditorNumber"].waitForExistence(timeout: 8))
        next.tap()
        XCTAssertTrue(app.switches["Include a date"].waitForExistence(timeout: 8))
        let timetable = app.buttons["rideEditorTimetableMatch"]
        let form = app.descendants(matching: .any)["rideEditorForm"].firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 8))
        XCTAssertTrue(reveal(timetable, in: form, app: app, scrolling: .up))
        XCTAssertTrue(timetable.exists)
        XCTAssertFalse(timetable.isEnabled)
    }

    func testInvalidReplyCannotApplyAndEmptyReplyIsANoOp() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["RAILMAP_UI_TEST_STORAGE_ID"] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-interface-language", "en"]
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "all"
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "expanded"
        app.launchEnvironment["RAILMAP_UI_TEST_SHEET"] = "new"
        app.launch()

        let next = app.buttons["rideEditorNext"]
        XCTAssertTrue(next.waitForExistence(timeout: 40))
        next.tap()
        let completion = app.buttons["rideEditorAICompletion"]
        // The sheet also accepts raw text imports, so it is reachable before
        // the draft is eligible for an AI request. The Form creates this row
        // lazily, so reveal it on the date step before checking reachability.
        for (index, name) in ["Tokyo", "Shinagawa"].enumerated() {
            let stop = app.descendants(matching: .any)["rideEditorStop-\(index)"].firstMatch
            XCTAssertTrue(EditorUITestSupport.reveal(stop, in: app), app.debugDescription)
            XCTAssertTrue(stop.waitForExistence(timeout: 8))
            stop.tap()
            let field = app.otherElements["rideEditorStopName"].textFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeText(name)
            app.navigationBars[name].buttons.firstMatch.tap()
        }
        next.tap()
        let number = app.otherElements["rideEditorNumber"].textFields.firstMatch
        XCTAssertTrue(number.waitForExistence(timeout: 8))
        number.tap()
        number.typeText("Test 1\n")
        next.tap()
        EditorUITestSupport.enableDate(in: app)
        XCTAssertTrue(app.textFields["rideEditorDateInput"].waitForExistence(timeout: 8))
        let editorForm = app.descendants(matching: .any)["rideEditorForm"].firstMatch
        XCTAssertTrue(editorForm.waitForExistence(timeout: 8))
        XCTAssertTrue(reveal(completion, in: editorForm, app: app, scrolling: .up))
        XCTAssertTrue(completion.isEnabled)
        tapVisible(completion, in: editorForm, app: app)
        XCTAssertTrue(app.buttons["aiSubscriptionSignIn"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["aiSubscriptionComplete"].exists)

        let form = app.descendants(matching: .any)["aiCompletionForm"].firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 8))
        let response = app.textViews["aiCompletionResponse"]
        XCTAssertTrue(reveal(response, in: form, app: app, scrolling: .up))
        tapVisible(response, in: form, app: app)
        response.typeText("invalid JSON")
        XCTAssertEqual(response.value as? String, "invalid JSON")

        let preview = app.buttons["aiCompletionPreview"]
        XCTAssertTrue(reveal(preview, in: form, app: app, scrolling: .up))
        XCTAssertTrue(preview.isEnabled)
        tapVisible(preview, in: form, app: app)

        let invalid = app.staticTexts.containing(NSPredicate(
            format: "label BEGINSWITH %@", "Could not apply.")).firstMatch
        XCTAssertTrue(reveal(invalid, in: form, app: app, scrolling: .up),
                      "Previewing invalid JSON must show the format error.")
        XCTAssertFalse(app.buttons["aiCompletionApply"].exists)

        XCTAssertTrue(reveal(response, in: form, app: app, scrolling: .down))
        tapVisible(response, in: form, app: app)
        let invalidValue = response.value as? String ?? ""
        response.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,
                                 count: invalidValue.count))
        response.typeText("{\"trains\":[]}")
        XCTAssertEqual(response.value as? String, "{\"trains\":[]}")
        XCTAssertTrue(reveal(preview, in: form, app: app, scrolling: .up))
        tapVisible(preview, in: form, app: app)

        let apply = app.buttons["aiCompletionApply"]
        XCTAssertTrue(reveal(apply, in: form, app: app, scrolling: .up),
                      "An empty trains response must render a disabled Apply action.")
        XCTAssertFalse(apply.isEnabled)
    }

    private enum FormScrollDirection {
        case up
        case down
    }

    func testIntermediateStopsAreReviewedInOrderBeforeApplyingToDraft() {
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
        XCTAssertTrue(row.waitForExistence(timeout: 40))
        row.press(forDuration: 1)
        let info = app.buttons["Journey information"]
        XCTAssertTrue(info.waitForExistence(timeout: 8))
        info.tap()
        let edit = app.buttons["journeyMenuEdit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        edit.tap()
        let editor = app.descendants(matching: .any)["rideEditorForm"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        let completion = app.buttons["rideEditorAICompletion"]
        XCTAssertTrue(reveal(completion, in: editor, app: app, scrolling: .up))
        tapVisible(completion, in: editor, app: app)
        let form = app.descendants(matching: .any)["aiCompletionForm"].firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 10))
        let response = app.textViews["aiCompletionResponse"]
        XCTAssertTrue(reveal(response, in: form, app: app, scrolling: .up))
        tapVisible(response, in: form, app: app)
        response.typeText("""
        {"trains":[{"id":"20260703_01_haruka","sources":[{"url":"https://example.com/timetable","explanation":"UI test fixture"}],"intermediate_stops":[{"after_index":0,"name":"Review stop A","arrival":"16:15","departure":"16:15"},{"after_index":0,"name":"Review stop B","arrival":"16:16","departure":"16:16"}]}]}
        """)
        let preview = app.buttons["aiCompletionPreview"]
        XCTAssertTrue(reveal(preview, in: form, app: app, scrolling: .up))
        tapVisible(preview, in: form, app: app)
        let first = app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@", "Station 1:")).firstMatch
        let second = app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@", "Station 2:")).firstMatch
        let third = app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@", "Station 3:")).firstMatch
        XCTAssertTrue(reveal(first, in: form, app: app, scrolling: .up), app.debugDescription)
        XCTAssertTrue(reveal(third, in: form, app: app, scrolling: .up), app.debugDescription)
        XCTAssertTrue(first.label.contains("関西空港"))
        XCTAssertTrue(second.label.contains("Review stop A"))
        XCTAssertTrue(third.label.contains("Review stop B"))
        XCTAssertLessThan(first.frame.minY, second.frame.minY)
        XCTAssertLessThan(second.frame.minY, third.frame.minY)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "intermediate-stop-review-order"
        shot.lifetime = .keepAlways
        add(shot)
        let apply = app.buttons["aiCompletionApply"]
        XCTAssertTrue(reveal(apply, in: form, app: app, scrolling: .up))
        XCTAssertTrue(apply.isEnabled)
        tapVisible(apply, in: form, app: app)
        XCTAssertTrue(form.waitForNonExistence(timeout: 10))
        let stop = app.buttons["rideEditorStop-1"]
        XCTAssertTrue(reveal(stop, in: editor, app: app, scrolling: .down))
        XCTAssertTrue(stop.label.contains("Review stop A"))
        tapVisible(stop, in: editor, app: app)
        let name = app.otherElements["rideEditorStopName"].textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertEqual(name.value as? String, "Review stop A")
    }

    private func reveal(
        _ element: XCUIElement,
        in form: XCUIElement,
        app: XCUIApplication,
        scrolling preferredDirection: FormScrollDirection
    ) -> Bool {
        guard form.exists else { return false }
        let attempts = form.identifier == "rideEditorForm" ? 24 : 12
        for attempt in 0...attempts {
            let visibleForm = visibleBounds(of: form, in: app)
            guard isUsable(visibleForm) else { return false }

            if element.exists {
                let frame = element.frame
                guard isUsable(frame) else { return false }
                if visibleForm.contains(frame) { return true }
            }
            guard attempt < attempts else { return false }

            let direction: FormScrollDirection
            if element.exists, element.frame.maxY > visibleForm.maxY {
                direction = .up
            } else if element.exists, element.frame.minY < visibleForm.minY {
                direction = .down
            } else {
                direction = preferredDirection
            }
            drag(form, within: visibleForm, direction: direction)
        }
        return false
    }

    private func tapVisible(
        _ element: XCUIElement,
        in form: XCUIElement,
        app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        // Keyboard and lazy Form layout can settle between reveal and tap.
        // Recheck the same complete-visibility contract immediately before
        // tapping, and scroll again if its viewport moved in the meantime.
        for _ in 0..<4 {
            guard reveal(element, in: form, app: app, scrolling: .up) else { break }
            let visibleForm = visibleBounds(of: form, in: app)
            let frame = element.frame
            guard element.exists, isUsable(frame), visibleForm.contains(frame) else { continue }
            let appFrame = app.frame
            let center = CGPoint(x: frame.midX, y: frame.midY)
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
                dx: center.x - appFrame.minX,
                dy: center.y - appFrame.minY
            )).tap()
            return
        }
        XCTFail("The AI completion control is outside the visible Form bounds.\n\(app.debugDescription)",
                file: file, line: line)
    }

    private func drag(
        _ form: XCUIElement,
        within visibleForm: CGRect,
        direction: FormScrollDirection
    ) {
        // An existing journey can have dozens of stop rows before the
        // completion section. Cover that form with larger controlled drags.
        let distance = visibleForm.height * (form.identifier == "rideEditorForm" ? 0.55 : 0.18)
        let upward = direction == .up
        let startPoint = CGPoint(
            x: visibleForm.midX,
            y: visibleForm.midY + (upward ? distance / 2 : -distance / 2))
        let endPoint = CGPoint(
            x: visibleForm.midX,
            y: visibleForm.midY + (upward ? -distance / 2 : distance / 2))
        let formFrame = form.frame
        let origin = form.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(
            dx: startPoint.x - formFrame.minX,
            dy: startPoint.y - formFrame.minY
        )).press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(
            dx: endPoint.x - formFrame.minX,
            dy: endPoint.y - formFrame.minY)))
    }

    private func visibleBounds(of form: XCUIElement, in app: XCUIApplication) -> CGRect {
        var bounds = form.frame.intersection(app.frame)
        // Lazy Form rows can retain frames underneath the navigation bar.
        // A tap there reaches the bar, even though the row exists in the tree.
        for bar in app.navigationBars.allElementsBoundByIndex where bar.exists {
            let covered = bar.frame.intersection(bounds)
            if isUsable(covered), covered.minY <= bounds.minY + 1 {
                let bottom = bounds.maxY
                bounds.origin.y = covered.maxY
                bounds.size.height = max(0, bottom - bounds.minY)
            } else if isUsable(covered), bar.frame.maxY > bounds.minY {
                let bottom = bounds.maxY
                bounds.origin.y = bar.frame.maxY
                bounds.size.height = max(0, bottom - bounds.minY)
            }
        }
        let keyboard = app.keyboards.firstMatch
        if keyboard.exists {
            let keyboardFrame = keyboard.frame.intersection(app.frame)
            if isUsable(keyboardFrame), keyboardFrame.minY > bounds.minY {
                bounds.size.height = max(0, min(bounds.maxY, keyboardFrame.minY) - bounds.minY)
            }
        }
        return bounds
    }

    private func isUsable(_ frame: CGRect) -> Bool {
        !frame.isNull && !frame.isInfinite && !frame.isEmpty
            && frame.origin.x.isFinite && frame.origin.y.isFinite
            && frame.width.isFinite && frame.height.isFinite
    }
}
