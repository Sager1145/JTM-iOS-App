import XCTest

@MainActor
final class TimetableQuickMatchUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testAutomaticLookupClearsResultsAfterDateAndServiceChanges() {
        let app = XCUIApplication()
        app.launchEnvironment["RAILMAP_UI_TEST_STORAGE_ID"] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-interface-language", "en"]
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "all"
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "expanded"
        app.launchEnvironment["RAILMAP_UI_TEST_SHEET"] = "new"
        app.launch()
        let next = app.buttons["rideEditorNext"]
        XCTAssertTrue(next.waitForExistence(timeout: 40))
        next.tap()
        seedNamedRoute(in: app)
        next.tap()
        next.tap()
        EditorUITestSupport.enableDate(in: app)
        replace(app.textFields["rideEditorDateInput"], with: "2026-09-30")
        app.buttons["rideEditorPrevious"].tap()
        app.buttons["rideEditorPrevious"].tap()
        openServicePatterns(in: app, replacingStops: true)
        searchServicePatterns("北斗", in: app)
        let details = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "timetableDetails-jr-hokkaido.hokuto.1.")).firstMatch
        reveal(details, in: app.collectionViews["servicePatternList"], app: app)
        details.tap()
        let useDraft = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "timetableUseDraft-jr-hokkaido.hokuto.1.")).firstMatch
        XCTAssertTrue(useDraft.waitForExistence(timeout: 8))
        useDraft.tap()
        XCTAssertTrue(next.waitForExistence(timeout: 8))
        next.tap()
        next.tap()

        let matches = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "rideEditorTimetableMatch-jr-hokkaido.hokuto.1."))
        showLookup(in: app)
        XCTAssertTrue(matches.firstMatch.waitForExistence(timeout: 30), app.debugDescription)
        let date = app.textFields["rideEditorDateInput"]
        replace(date, with: "1900-01-01")
        replace(date, with: "2026-09-30")
        replace(date, with: "1900-01-01")
        showLookup(in: app)
        XCTAssertTrue(matches.firstMatch.waitForNonExistence(timeout: 15))
        let noMatch = app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@", "No train matches both endpoint stations")).firstMatch
        XCTAssertTrue(noMatch.waitForExistence(timeout: 15))
        replace(date, with: "2026-09-30")
        showLookup(in: app)
        XCTAssertTrue(matches.firstMatch.waitForExistence(timeout: 30))

        app.buttons["rideEditorPrevious"].tap()
        let name = app.otherElements["rideEditorLimitedExpressName"].textFields.firstMatch
        reveal(name, in: app.collectionViews["rideEditorForm"], app: app)
        replace(name, with: "北斗")
        replace(name, with: "No matching service")
        name.typeText("\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 8))
        next.tap()
        showLookup(in: app)
        XCTAssertTrue(noMatch.waitForExistence(timeout: 20))
        XCTAssertFalse(matches.firstMatch.exists)
        app.buttons["rideEditorPrevious"].tap()
        reveal(name, in: app.collectionViews["rideEditorForm"], app: app)
        replace(name, with: "北斗")
        name.typeText("\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 8))
        next.tap()
        showLookup(in: app)
        XCTAssertTrue(matches.firstMatch.waitForExistence(timeout: 30))
    }

    private func seedNamedRoute(in app: XCUIApplication) {
        openServicePatterns(in: app, replacingStops: false)
        searchServicePatterns("はちおうじ", in: app)
        let route = app.buttons.matching(NSPredicate(
            format: "label CONTAINS %@", "東京〜八王子")).firstMatch
        reveal(route, in: app.collectionViews["servicePatternList"], app: app)
        route.tap()
    }

    private func openServicePatterns(in app: XCUIApplication, replacingStops: Bool) {
        let form = app.collectionViews["rideEditorForm"]
        XCTAssertTrue(form.waitForExistence(timeout: 8), app.debugDescription)
        // The route step now starts with route-choice controls and endpoint
        // rows. Its express-stop picker sits below them in the lazy Form.
        let picker = app.buttons["rideEditorServicePattern"]
        reveal(picker, in: form, app: app)
        picker.tap()
        if replacingStops {
            let replaceStops = app.buttons["rideEditorReplaceStops"].firstMatch
            XCTAssertTrue(replaceStops.waitForExistence(timeout: 8), app.debugDescription)
            replaceStops.tap()
        }
    }

    private func searchServicePatterns(_ query: String, in app: XCUIApplication) {
        let list = app.collectionViews["servicePatternList"]
        XCTAssertTrue(list.waitForExistence(timeout: 10), app.debugDescription)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10), app.debugDescription)
        let hittable = XCTNSPredicateExpectation(
            predicate: NSPredicate { object, _ in
                (object as? XCUIElement)?.isHittable == true
            }, object: search)
        XCTAssertEqual(XCTWaiter.wait(for: [hittable], timeout: 8), .completed,
                       app.debugDescription)
        // The system search toolbar is fixed at the bottom on newer iOS.
        // Tap the field's centre instead of XCTest's partly clipped hit point,
        // and wait for input focus before dispatching any text.
        search.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 8),
                      app.debugDescription)
        search.typeText(query + "\n")
    }

    private func replace(_ field: XCUIElement, with value: String) {
        let form = XCUIApplication().collectionViews["rideEditorForm"]
        for _ in 0..<8 {
            // A partially clipped field can report hittable while its tap
            // lands beneath the sheet's navigation bar.
            if field.exists && field.isHittable && field.frame.minY > form.frame.minY + 80 { break }
            form.swipeDown()
        }
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        field.tap()
        let old = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + value)
    }

    private func showLookup(in app: XCUIApplication) {
        // The date/status rows fill the first page. Materialize the lazy
        // timetable section without tapping its manual search action.
        let button = app.buttons["rideEditorTimetableMatch"]
        let form = app.collectionViews["rideEditorForm"]
        reveal(button, in: form, app: app)
    }

    private func reveal(_ element: XCUIElement, in list: XCUIElement, app: XCUIApplication) {
        for _ in 0..<16 {
            if element.exists && element.isHittable && element.frame.maxY < app.frame.maxY - 120 { break }
            list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
                .press(forDuration: 0.1, thenDragTo: list.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42)))
        }
        XCTAssertTrue(element.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }
}
