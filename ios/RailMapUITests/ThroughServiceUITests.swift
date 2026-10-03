import XCTest

@MainActor
final class ThroughServiceUITests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testSectionServiceApplyPreservesDraftNotes() {
        let app = launchNewEditor()
        let next = app.buttons["rideEditorNext"]
        XCTAssertTrue(next.waitForExistence(timeout: 40))
        next.tap()
        selectNamedRouteAndAdvance(in: app, next: next)
        XCTAssertTrue(app.otherElements["rideEditorNumber"].waitForExistence(timeout: 8))

        let form = app.collectionViews["rideEditorForm"].firstMatch
        let notes = app.textFields["rideEditorNotes"]
        sectionEnter("Keep this through-service draft note", into: notes, in: form, app: app)
        let add = app.buttons["rideEditorAddServiceLeg"]
        XCTAssertTrue(sectionReveal(add, in: form, app: app))
        add.tap()
        XCTAssertTrue(app.buttons["rideEditorApplyServiceLeg"].waitForExistence(timeout: 8))

        let sectionForm = foregroundSectionForm(in: app)
        // These two fields use their fixed English labels; the section number
        // wrapper and Apply action have explicit production accessibility IDs.
        let lines = sectionInput(label: "Line names", in: sectionForm, app: app)
        let operators = sectionInput(label: "Operator names", in: sectionForm, app: app)
        let number = sectionInput(identifier: "rideEditorSectionNumber", in: sectionForm, app: app)
        sectionEnter("UI test through line", into: lines, in: sectionForm, app: app)
        sectionEnter("UI test operator", into: operators, in: sectionForm, app: app)
        sectionEnter("9876M", into: number, in: sectionForm, app: app)
        app.buttons["rideEditorApplyServiceLeg"].tap()
        XCTAssertTrue(app.buttons["rideEditorAddServiceLeg"].waitForExistence(timeout: 8))

        let summary = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "rideEditorServiceLeg-", "9876M")).firstMatch
        XCTAssertTrue(sectionReveal(summary, in: form, app: app), app.debugDescription)
        XCTAssertTrue(summary.label.contains("UI test operator"))
        XCTAssertTrue(summary.label.contains("UI test through line"))
        XCTAssertTrue(sectionReveal(notes, in: form, app: app))
        XCTAssertEqual(notes.value as? String, "Keep this through-service draft note")

        // Reopening the recorded section verifies Apply updated the draft,
        // rather than merely leaving text in the dismissed section editor.
        XCTAssertTrue(sectionReveal(summary, in: form, app: app))
        summary.tap()
        XCTAssertTrue(app.buttons["rideEditorApplyServiceLeg"].waitForExistence(timeout: 8))
        XCTAssertTrue(sectionReveal(number, in: sectionForm, app: app))
        XCTAssertEqual(number.value as? String, "9876M")
        XCTAssertTrue(sectionReveal(lines, in: sectionForm, app: app))
        XCTAssertEqual(lines.value as? String, "UI test through line")
        XCTAssertTrue(sectionReveal(operators, in: sectionForm, app: app))
        XCTAssertEqual(operators.value as? String, "UI test operator")
        app.buttons["rideEditorApplyServiceLeg"].tap()
        XCTAssertTrue(sectionReveal(notes, in: form, app: app))
        XCTAssertEqual(notes.value as? String, "Keep this through-service draft note")
        let finalScreen = XCTAttachment(screenshot: app.screenshot())
        finalScreen.name = "section-service-final"
        finalScreen.lifetime = .keepAlways
        self.add(finalScreen)
        let finalTree = XCTAttachment(string: app.debugDescription)
        finalTree.name = "section-service-final-accessibility-tree"
        finalTree.lifetime = .keepAlways
        self.add(finalTree)
    }

    /// Run on a clean, signed-out test simulator. No login or query action is
    /// tapped, and no stored subscription credentials are created or deleted.
    func testStandaloneChatGPTQueryRequiresDateAndSignedInAccount() {
        let app = launchNewEditor()
        let next = app.buttons["rideEditorNext"]
        XCTAssertTrue(next.waitForExistence(timeout: 40))
        next.tap()
        let pattern = app.buttons["rideEditorServicePattern"]
        XCTAssertTrue(EditorUITestSupport.reveal(pattern, in: app), app.debugDescription)
        XCTAssertTrue(pattern.waitForExistence(timeout: 8))
        EditorUITestSupport.tap(pattern, in: app)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.tap()
        search.typeText("Hachioji\n")
        let picker = app.descendants(matching: .any)["servicePatternList"].firstMatch
        let research = app.buttons["servicePatternChatGPTQuery"]
        XCTAssertTrue(reveal(research, in: picker, app: app))
        research.tap()

        let query = app.textFields["trainResearchQuery"]
        XCTAssertTrue(query.waitForExistence(timeout: 8))
        XCTAssertEqual(query.value as? String, "Hachioji")
        guard let queryForm = app.collectionViews.allElementsBoundByIndex.first(where: {
            $0.descendants(matching: .any)["trainResearchQuery"].exists
        }) else {
            XCTFail("The opened train research query must have its own native form.")
            return
        }
        XCTAssertTrue(queryForm.waitForExistence(timeout: 8))
        let required = app.staticTexts[
            "Enter a train name, number or route and an operating date."]
        XCTAssertTrue(reveal(required, in: queryForm, app: app))
        let remarks = app.textFields["trainResearchRemarks"]
        enter("Show the official operator source for this date", into: remarks,
              in: queryForm, app: app)
        XCTAssertEqual(remarks.value as? String, "Show the official operator source for this date")
        let signIn = app.buttons["trainResearchSignIn"]
        XCTAssertTrue(reveal(signIn, in: queryForm, app: app),
                      "This test requires a clean, signed-out simulator.")
        XCTAssertTrue(signIn.isEnabled)
        assertCannotRunWithoutAccount(in: app)

        let date = app.textFields["trainResearchDate"]
        enter("2026-09-27", into: date, in: queryForm, app: app)
        XCTAssertEqual(date.value as? String, "2026-09-27")
        XCTAssertTrue(required.waitForNonExistence(timeout: 5))
        XCTAssertTrue(reveal(signIn, in: queryForm, app: app))
        assertCannotRunWithoutAccount(in: app)
        XCTAssertFalse(app.descendants(matching: .any)["trainResearchAnswer"].exists)
        XCTAssertTrue(reveal(remarks, in: queryForm, app: app))
        XCTAssertEqual(remarks.value as? String, "Show the official operator source for this date")
    }

    private func launchNewEditor() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["RAILMAP_UI_TEST_STORAGE_ID"] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-interface-language", "en"]
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "all"
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "expanded"
        app.launchEnvironment["RAILMAP_UI_TEST_SHEET"] = "new"
        app.launch()
        return app
    }

    private func assertCannotRunWithoutAccount(in app: XCUIApplication,
                                              file: StaticString = #filePath, line: UInt = #line) {
        let run = app.buttons["trainResearchRun"]
        XCTAssertTrue(!run.exists || !run.isEnabled,
                      "A signed-out query must not offer an enabled request action.",
                      file: file, line: line)
    }

    private func enter(_ value: String, into field: XCUIElement,
                       in form: XCUIElement, app: XCUIApplication,
                       file: StaticString = #filePath, line: UInt = #line) {
        guard reveal(field, in: form, app: app) else {
            XCTFail("The input field could not be revealed.", file: file, line: line)
            return
        }
        field.tap()
        let existing = field.value as? String ?? ""
        // XCTest reports a placeholder as value for empty text fields.
        let placeholder = field.placeholderValue ?? ""
        if !existing.isEmpty && existing != placeholder {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        }
        field.typeText(value)
    }

    private func reveal(_ element: XCUIElement, in form: XCUIElement,
                        app: XCUIApplication) -> Bool {
        guard form.waitForExistence(timeout: 8) else { return false }
        for attempt in 0...20 {
            var bounds = form.frame.intersection(app.frame).insetBy(dx: 0, dy: 10)
            let keyboard = app.keyboards.firstMatch
            if keyboard.exists, keyboard.frame.minY > bounds.minY {
                bounds.size.height = max(0, min(bounds.maxY, keyboard.frame.minY - 10) - bounds.minY)
            }
            guard !bounds.isEmpty && !bounds.isNull && !bounds.isInfinite else { return false }
            if element.exists, bounds.contains(element.frame), element.isHittable { return true }
            guard attempt < 20 else { return false }
            let upward: Bool
            if element.exists {
                upward = element.frame.maxY > bounds.maxY
            } else {
                // Lazy Form rows may not exist while offscreen. Try both
                // directions, including when returning to a prior input.
                upward = attempt < 10
            }
            let distance = bounds.height * 0.4
            let start = CGPoint(x: bounds.midX, y: bounds.midY + (upward ? distance / 2 : -distance / 2))
            let end = CGPoint(x: bounds.midX, y: bounds.midY + (upward ? -distance / 2 : distance / 2))
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: start.x - app.frame.minX, dy: start.y - app.frame.minY))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(
                    dx: end.x - app.frame.minX, dy: end.y - app.frame.minY)))
        }
        return false
    }
    private func selectNamedRouteAndAdvance(in app: XCUIApplication, next: XCUIElement) {
        func stop(_ reason: String) {
            let tree = XCTAttachment(string: reason + "\n" + app.debugDescription)
            tree.name = "through-service-route-to-next-guard"
            tree.lifetime = .keepAlways
            self.add(tree)
            let screen = XCTAttachment(screenshot: app.screenshot())
            screen.name = "through-service-route-to-next-guard"
            screen.lifetime = .keepAlways
            self.add(screen)
            XCTFail(reason)
        }
        let routePicker = app.buttons["rideEditorServicePattern"]
        guard EditorUITestSupport.reveal(routePicker, in: app),
              routePicker.waitForExistence(timeout: 8), routePicker.isHittable else {
            stop("Route-picker action is not reachable; no tap attempted.")
            return
        }
        EditorUITestSupport.tap(routePicker, in: app)
        let search = app.searchFields.firstMatch
        guard search.waitForExistence(timeout: 8), search.isHittable else {
            stop("Actual route search is not reachable.")
            return
        }
        EditorUITestSupport.tap(search, in: app)
        // The observed route result overlaps the active keyboard assistant.
        // Submit the real searchable field before attempting its result row.
        search.typeText("はちおうじ\n")
        guard app.keyboards.firstMatch.waitForNonExistence(timeout: 8) else {
            stop("Route search keyboard remains in front; no route/Next tap attempted.")
            return
        }
        let picker = app.collectionViews["servicePatternList"].firstMatch
        let route = picker.buttons.matching(NSPredicate(
            format: "label CONTAINS %@", "東京〜八王子")).firstMatch
        guard route.waitForExistence(timeout: 8), route.isEnabled, route.isHittable,
              picker.frame.intersection(app.frame).contains(route.frame) else {
            stop("Named route row is not fully reachable; no blind tap or reveal retry.")
            return
        }
        EditorUITestSupport.tap(route, in: app)
        guard picker.waitForNonExistence(timeout: 8) else {
            stop("Route picker did not dismiss after selection; underlying Next must not be tapped.")
            return
        }
        let form = app.collectionViews["rideEditorForm"].firstMatch
        let origin = form.buttons["rideEditorStop-0"].firstMatch
        let destination = form.buttons["rideEditorStop-3"].firstMatch
        guard origin.waitForExistence(timeout: 8), destination.waitForExistence(timeout: 8),
              !origin.label.contains("Choose departure station"),
              !destination.label.contains("Choose arrival station") else {
            stop("Selected four-station named route is not present in the actual draft.")
            return
        }
        var visible = app.frame
        if app.keyboards.firstMatch.exists {
            visible.size.height = max(0, min(visible.maxY, app.keyboards.firstMatch.frame.minY) - visible.minY)
        }
        guard next.exists, next.isEnabled, next.isHittable,
              next.frame.width > 1, next.frame.height > 1, visible.contains(next.frame) else {
            stop("Foreground wizard Next is not reachable; refusing invalid/background hit point.")
            return
        }
        // A single validated coordinate tap uses the repository's proven helper.
        EditorUITestSupport.tap(next, in: app)
    }

    private func foregroundSectionForm(in app: XCUIApplication) -> XCUIElement {
        XCTAssertTrue(app.navigationBars["Section service"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["rideEditorApplyServiceLeg"].exists)
        let candidates = app.collectionViews.allElementsBoundByIndex
        let indices = candidates.indices.filter { index in
            let candidate = candidates[index]
            return candidate.identifier != "rideEditorForm"
                && candidate.frame.intersects(app.frame)
                && (candidate.descendants(matching: .any)["rideEditorServiceFrom"].exists
                    || candidate.descendants(matching: .any)["rideEditorSectionNumber"].exists)
        }
        XCTAssertEqual(indices.count, 1, "Exactly one foreground section-service Form must be present.")
        // Retain the collection's index query: lazy endpoint rows may disappear
        // while lower fields are focused, without invalidating the Form itself.
        return app.collectionViews.element(boundBy: indices.first ?? 0)
    }

    private func sectionInput(label: String? = nil, identifier: String? = nil,
                              in form: XCUIElement, app: XCUIApplication) -> XCUIElement {
        let name = label ?? identifier ?? "section input"
        let predicate = label.map { NSPredicate(format: "label == %@", $0) }
            ?? NSPredicate(format: "identifier == %@", identifier ?? "")
        let parent = form.otherElements.matching(predicate).firstMatch
        let child = parent.textFields.firstMatch
        guard parent.waitForExistence(timeout: 5), child.waitForExistence(timeout: 5) else {
            let tree = XCTAttachment(string: "Required section input missing: \(name). Stop before reveal swipes.\n" + form.debugDescription)
            tree.name = "section-input-parent-or-child-missing"
            tree.lifetime = .keepAlways
            self.add(tree)
            let screen = XCTAttachment(screenshot: app.screenshot())
            screen.name = "section-input-parent-or-child-missing"
            screen.lifetime = .keepAlways
            self.add(screen)
            // Both test classes set continueAfterFailure=false; this failure
            // stops the case before callers can enter a reveal loop.
            XCTFail("Required foreground section input parent/child missing: \(name)")
            return child
        }
        return child
    }

    private func sectionEnter(_ value: String, into field: XCUIElement,
                       in form: XCUIElement, app: XCUIApplication,
                       file: StaticString = #filePath, line: UInt = #line) {
        guard sectionReveal(field, in: form, app: app) else {
            XCTFail("The input field could not be revealed.", file: file, line: line)
            return
        }
        field.tap()
        let existing = field.value as? String ?? ""
        // XCTest reports a placeholder as value for empty text fields.
        let placeholder = field.placeholderValue ?? ""
        if !existing.isEmpty && existing != placeholder {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        }
        field.typeText(value)
    }

    private func sectionReveal(_ element: XCUIElement, in form: XCUIElement,
                        app: XCUIApplication) -> Bool {
        guard form.waitForExistence(timeout: 8) else { return false }
        let isSectionForm = app.buttons["rideEditorApplyServiceLeg"].exists
            && form.identifier != "rideEditorForm"
        let maximumAttempts = isSectionForm ? 6 : 20
        for attempt in 0...maximumAttempts {
            var bounds = form.frame.intersection(app.frame).insetBy(dx: 0, dy: 10)
            let keyboard = app.keyboards.firstMatch
            if keyboard.exists, keyboard.frame.minY > bounds.minY {
                bounds.size.height = max(0, min(bounds.maxY, keyboard.frame.minY - 10) - bounds.minY)
            }
            guard !bounds.isEmpty && !bounds.isNull && !bounds.isInfinite else { return false }
            if element.exists, bounds.contains(element.frame), element.isHittable { return true }
            // A confirmed section input must remain an actual visible AX node.
            // Do not drag a sheet for a missing field or an in-bounds occluded field.
            if isSectionForm && (!element.exists || bounds.contains(element.frame)) {
                let tree = XCTAttachment(string: "Section field unavailable without a justified scroll.\n" + form.debugDescription)
                tree.name = "section-field-reveal-stopped"
                tree.lifetime = .keepAlways
                self.add(tree)
                let screen = XCTAttachment(screenshot: app.screenshot())
                screen.name = "section-field-reveal-stopped"
                screen.lifetime = .keepAlways
                self.add(screen)
                return false
            }
            guard attempt < maximumAttempts else { return false }
            let upward: Bool
            if element.exists {
                upward = element.frame.maxY > bounds.maxY
            } else {
                // Lazy Form rows may not exist while offscreen. Try both
                // directions, including when returning to a prior input.
                upward = attempt < 10
            }
            let distance = bounds.height * 0.4
            let start = CGPoint(x: bounds.midX, y: bounds.midY + (upward ? distance / 2 : -distance / 2))
            let end = CGPoint(x: bounds.midX, y: bounds.midY + (upward ? -distance / 2 : distance / 2))
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: start.x - app.frame.minX, dy: start.y - app.frame.minY))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(
                    dx: end.x - app.frame.minX, dy: end.y - app.frame.minY)))
        }
        return false
    }
}
