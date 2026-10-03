import XCTest

@MainActor
final class JourneyTranslationUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testOriginalNamesAreDefaultAndTranslationChoicePersists() {
        let app = launchTranslationSwitch()
        openTranslationSwitchSettings(in: app)
        let toggle = translationSwitchControl(in: app)
        if toggle.value as? String == "1" { toggle.tap() }
        assertTranslationSwitchValue("0", toggle: toggle, in: app)
        app.buttons["utilityCloseButton"].tap()

        let row = app.buttons["journeyRow-20260703_01_haruka"]
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        XCTAssertTrue(row.label.contains("はるか38号"))
        XCTAssertFalse(row.label.contains("Haruka 38"))

        openTranslationSwitchSettings(in: app)
        let enabledToggle = translationSwitchControl(in: app)
        enabledToggle.tap()
        assertTranslationSwitchValue("1", toggle: enabledToggle, in: app)
        app.buttons["utilityCloseButton"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        XCTAssertTrue(row.label.contains("Haruka 38"))
        XCTAssertTrue(row.label.contains("(特急 はるか38号"), row.label)

        app.terminate()
        app.launch()
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        openTranslationSwitchSettings(in: app)
        let persistedToggle = translationSwitchControl(in: app)
        assertTranslationSwitchValue("1", toggle: persistedToggle, in: app)
        persistedToggle.tap()
        assertTranslationSwitchValue("0", toggle: persistedToggle, in: app)
    }

    private func launchTranslationSwitch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-interface-language", "en"]
        app.launchEnvironment["RAILMAP_UI_TEST_SAMPLE"] = "train-store"
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "search"
        app.launchEnvironment["RAILMAP_UI_TEST_QUERY"] = "20260703_01_haruka"
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "expanded"
        app.launch()
        XCTAssertTrue(app.buttons["journeyRow-20260703_01_haruka"].waitForExistence(timeout: 30))
        return app
    }

    private func openTranslationSwitchSettings(in app: XCUIApplication) {
        let menu = app.descendants(matching: .any)["utilityMenuButton"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 8))
        menu.tap()
        let settings = app.buttons["utilitySettingsButton"]
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["utilityCloseButton"].waitForExistence(timeout: 8))
    }

    private func translationSwitchControl(in app: XCUIApplication) -> XCUIElement {
        let toggle = app.switches["showJourneyTranslations"]
        guard let form = app.collectionViews.allElementsBoundByIndex.first(where: { $0.isHittable }) else {
            XCTFail("The Settings Form must be visible before revealing its translation switch.")
            return toggle
        }
        XCTAssertTrue(revealTranslationSwitch(toggle, in: form, app: app, maximumDrags: 4),
                      "The translation switch must be reachable in the actual Settings Form.")
        // The identified SwiftUI Toggle spans its label and native thumb.
        // Its center is an empty gap on the recorded phone layout.
        let nativeSwitch = toggle.children(matching: .switch).firstMatch
        XCTAssertTrue(nativeSwitch.waitForExistence(timeout: 8))
        XCTAssertTrue(nativeSwitch.isHittable)
        let safeFrame = form.frame.intersection(app.frame)
        XCTAssertFalse(nativeSwitch.frame.isEmpty)
        XCTAssertTrue(safeFrame.contains(nativeSwitch.frame),
                      "The actual native switch must lie within the visible Settings Form.")
        return nativeSwitch
    }

    private func assertTranslationSwitchValue(_ expected: String, toggle: XCUIElement,
                                        in app: XCUIApplication) {
        let value = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", expected), object: toggle)
        let result = XCTWaiter.wait(for: [value], timeout: 8)
        XCTAssertEqual(result, .completed, "The native switch must reach the exact requested value.")
        XCTAssertEqual(toggle.value as? String, expected)
        XCTAssertEqual(app.switches["showJourneyTranslations"].value as? String, expected)
    }

    private func revealTranslationSwitch(_ target: XCUIElement, in form: XCUIElement, app: XCUIApplication,
                        maximumDrags: Int = 8) -> Bool {
        guard form.waitForExistence(timeout: 8) else { return false }
        for attempt in 0...maximumDrags {
            var visible = form.frame.intersection(app.frame).insetBy(dx: 0, dy: 10)
            let keyboard = app.keyboards.firstMatch
            if keyboard.exists, keyboard.frame.minY > visible.minY {
                visible.size.height = max(0, min(visible.maxY, keyboard.frame.minY - 10) - visible.minY)
            }
            guard !visible.isNull, !visible.isEmpty else { return false }
            if target.exists, target.isHittable, visible.contains(target.frame) { return true }
            guard attempt < maximumDrags else { return false }
            // Reveal lazy Form content with bounded scrolling, not input retries.
            let upward = target.exists ? target.frame.maxY > visible.maxY : true
            let halfDistance = visible.height * 0.22
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(
                dx: visible.midX - app.frame.minX,
                dy: visible.midY - app.frame.minY + (upward ? halfDistance : -halfDistance)))
            let end = origin.withOffset(CGVector(
                dx: visible.midX - app.frame.minX,
                dy: visible.midY - app.frame.minY + (upward ? -halfDistance : halfDistance)))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        return false
    }

    func testOfficialNameCanBeAppliedAndEditedWithoutChangingOriginal() {
        let app = launchOfficialNameScenario()
        openOfficialNameEditor(in: app)
        let original = app.otherElements["rideEditorNumber"].textFields.firstMatch
        XCTAssertTrue(original.waitForExistence(timeout: 45))
        replaceOfficialNameEditorField(original, with: "あずさ1号", in: app)
        // Match a date inside the bundled official English name period.
        let date = app.textFields["rideEditorDateInput"]
        XCTAssertTrue(date.waitForExistence(timeout: 8))
        replaceOfficialNameEditorField(date, with: "2026-09-30", in: app)
        let official = app.buttons["rideEditorUseOfficialEnglishName"]
        XCTAssertTrue(revealOfficialNameEditorElement(official, in: app.collectionViews["rideEditorForm"], app: app))
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: official)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 15), .completed)
        official.tap()
        let english = app.otherElements["rideEditorNumberEn"].textFields.firstMatch
        XCTAssertEqual(english.value as? String, "Azusa 1")
        replaceOfficialNameEditorField(english, with: "My Azusa journey", in: app)
        XCTAssertTrue(revealOfficialNameEditorElement(original, in: app.collectionViews["rideEditorForm"], app: app))
        XCTAssertEqual(original.value as? String, "あずさ1号")
        XCTAssertEqual(date.value as? String, "2026-09-30")
        app.buttons["rideEditorSave"].tap()
        XCTAssertTrue(app.buttons["rideEditorSave"].waitForNonExistence(timeout: 15))
        // Saving the sheet editor returns to its parent RideCard. The X is
        // the only dismissal path back to the source list in this version.
        let close = app.buttons["journeyBackToList"]
        XCTAssertTrue(close.waitForExistence(timeout: 8))
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 8))
        let row = app.buttons["journeyRow-20260703_01_haruka"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        openOfficialNameEditor(in: app)
        XCTAssertTrue(english.waitForExistence(timeout: 8))
        XCTAssertEqual(english.value as? String, "My Azusa journey")
        XCTAssertEqual(original.value as? String, "あずさ1号")
        XCTAssertEqual(date.value as? String, "2026-09-30")
        captureOfficialNameScenario(app, name: "translation-official-name-final")
    }

    private func launchOfficialNameScenario() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-interface-language", "en"]
        app.launchEnvironment["RAILMAP_UI_TEST_SAMPLE"] = "train-store"
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "search"
        app.launchEnvironment["RAILMAP_UI_TEST_QUERY"] = "20260703_01_haruka"
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "expanded"
        app.launch()
        XCTAssertTrue(app.buttons["journeyRow-20260703_01_haruka"].waitForExistence(timeout: 30))
        return app
    }

    private func openOfficialNameEditor(in app: XCUIApplication) {
        let row = app.buttons["journeyRow-20260703_01_haruka"]
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        let reachable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"), object: row)
        XCTAssertEqual(XCTWaiter.wait(for: [reachable], timeout: 8), .completed)
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "selectedJourney-20260703_01_haruka").firstMatch.waitForExistence(timeout: 8))
        let edit = app.buttons["journeyMenuEdit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 8))
        XCTAssertTrue(edit.isHittable)
        edit.tap()
        XCTAssertTrue(app.collectionViews["rideEditorForm"].waitForExistence(timeout: 8))
    }

    private func replaceOfficialNameEditorField(_ field: XCUIElement, with text: String, in app: XCUIApplication) {
        guard revealOfficialNameEditorElement(field, in: app.collectionViews["rideEditorForm"], app: app) else {
            captureOfficialNameScenario(app, name: "translation-field-not-reachable")
            XCTFail("The editor field must be visible and hittable before input.")
            return
        }
        if field.identifier == "rideEditorDateInput" {
            // The rendered date digits occupy the leading edge of this wide field,
            // so tap that visible text to acquire native keyboard focus reliably.
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        } else {
            field.tap()
        }
        guard app.keyboards.firstMatch.waitForExistence(timeout: 8) else {
            captureOfficialNameScenario(app, name: "translation-field-keyboard-missing")
            XCTFail("The native field tap did not produce keyboard focus; no typing attempted.")
            return
        }
        let current = field.value as? String ?? ""
        if !current.isEmpty && current != field.placeholderValue {
            if field.identifier == "rideEditorDateInput" {
                // The native center press landed beyond the rendered date digits.
                field.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).press(forDuration: 1.1)
            } else {
                field.press(forDuration: 1.1)
            }
            let button = app.buttons["Select All"].firstMatch
            let menuItem = app.menuItems["Select All"].firstMatch
            if button.waitForExistence(timeout: 3) {
                button.tap()
            } else if menuItem.waitForExistence(timeout: 2) {
                menuItem.tap()
            } else {
                captureOfficialNameScenario(app, name: "translation-select-all-missing")
                XCTFail("Select All is required to replace the entire existing field value.")
                return
            }
        }
        field.typeText(text)
        let exactValue = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", text), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [exactValue], timeout: 5), .completed,
                       "Input must equal the complete requested value before proceeding.")
        XCTAssertEqual(field.value as? String, text)
    }

    private func revealOfficialNameEditorElement(_ target: XCUIElement, in form: XCUIElement, app: XCUIApplication,
                        maximumDrags: Int = 8) -> Bool {
        guard form.waitForExistence(timeout: 8) else { return false }
        for attempt in 0...maximumDrags {
            var visible = form.frame.intersection(app.frame).insetBy(dx: 0, dy: 10)
            let keyboard = app.keyboards.firstMatch
            if keyboard.exists, keyboard.frame.minY > visible.minY {
                visible.size.height = max(0, min(visible.maxY, keyboard.frame.minY - 10) - visible.minY)
            }
            guard !visible.isNull, !visible.isEmpty else { return false }
            if target.exists, target.isHittable, visible.contains(target.frame) { return true }
            guard attempt < maximumDrags else { return false }
            // Reveal lazy Form content with bounded scrolling, not input retries.
            let upward = target.exists ? target.frame.maxY > visible.maxY : true
            let halfDistance = visible.height * 0.22
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(
                dx: visible.midX - app.frame.minX,
                dy: visible.midY - app.frame.minY + (upward ? halfDistance : -halfDistance)))
            let end = origin.withOffset(CGVector(
                dx: visible.midX - app.frame.minX,
                dy: visible.midY - app.frame.minY + (upward ? -halfDistance : halfDistance)))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        return false
    }

    private func captureOfficialNameScenario(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "\(name)-accessibility-tree"
        tree.lifetime = .keepAlways
        add(tree)
    }

    private func launch(sheet: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-interface-language", "en"]
        app.launchEnvironment["RAILMAP_UI_TEST_SAMPLE"] = "train-store"
        app.launchEnvironment["RAILMAP_UI_TEST_SELECT"] = "20260703_01_haruka"
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "search"
        app.launchEnvironment["RAILMAP_UI_TEST_QUERY"] = "20260703_01_haruka"
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "expanded"
        app.launchEnvironment["RAILMAP_UI_TEST_SHEET"] = sheet
        app.launch()
        return app
    }

    private func openSettings(in app: XCUIApplication) {
        let menu = app.descendants(matching: .any)["utilityMenuButton"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 8))
        menu.tap()
        app.buttons["utilitySettingsButton"].tap()
    }

    private func replace(_ field: XCUIElement, with text: String, in app: XCUIApplication) {
        EditorUITestSupport.tap(field, in: app)
        let current = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + text + "\n")
    }
}
