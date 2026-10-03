import XCTest

@MainActor
final class LocalJourneyAutofillUITests: XCTestCase {
    func testEndpointsFillAnUntimedPhysicalRouteAndUndoRestoresTheDraft() {
        continueAfterFailure = false
        let app = newEditor()
        selectEndpoints(in: app, origin: "003766", destination: "004095")
        let apply = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "localJourneyApply-")).firstMatch
        XCTAssertTrue(apply.waitForExistence(timeout: 30))
        apply.tap()
        let undo = app.buttons["rideEditorLocalAutofillUndo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 10))
        let form = app.collectionViews["rideEditorForm"]
        let added = app.descendants(matching: .any)["rideEditorStop-2"].firstMatch
        reveal(added, in: form)
        XCTAssertTrue(added.exists, "The local route inserts at least one physical intermediate visit.")
        EditorUITestSupport.tap(undo, in: app)
        XCTAssertFalse(app.descendants(matching: .any)["rideEditorStop-2"].firstMatch.exists)
    }

    func testKeiseiAsakusaKeikyuRouteCanBeAddedAcrossOperators() {
        continueAfterFailure = false
        let app = newEditor()
        selectEndpoints(in: app, origin: "003280", destination: "004368")
        let apply = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "localJourneyApply-")).firstMatch
        XCTAssertTrue(apply.waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@", "浅草線")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@", "京浜急行電鉄")).firstMatch.exists)
        apply.tap()
        XCTAssertTrue(app.buttons["rideEditorLocalAutofillUndo"].waitForExistence(timeout: 10))
        let next = app.buttons["rideEditorNext"]
        EditorUITestSupport.tap(next, in: app)
        let database = app.buttons["rideEditorLineServiceDatabase"]
        XCTAssertTrue(database.waitForExistence(timeout: 10))
    }

    private func reveal(_ element: XCUIElement, in form: XCUIElement) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            form.swipeUp()
        }
    }

    private func newEditor() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-interface-language", "en"]
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "all"
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "expanded"
        app.launchEnvironment["RAILMAP_UI_TEST_SHEET"] = "new"
        app.launch()
        let next = app.buttons["rideEditorNext"]
        XCTAssertTrue(next.waitForExistence(timeout: 30))
        next.tap()
        let open = app.buttons["rideEditorLocalAutofill"]
        XCTAssertTrue(open.waitForExistence(timeout: 30))
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: open)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 30), .completed)
        open.tap()
        return app
    }
    private func selectEndpoints(in app: XCUIApplication, origin: String, destination: String) {
        for (identifier, code) in [("localJourneyOrigin", origin), ("localJourneyDestination", destination)] {
            let endpoint = app.buttons[identifier]
            XCTAssertTrue(endpoint.waitForExistence(timeout: 10))
            endpoint.tap()
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 10))
            search.tap()
            search.typeText(code)
            let station = app.buttons["localJourneyStation-\(code)"]
            XCTAssertTrue(station.waitForExistence(timeout: 10))
            station.tap()
        }
    }
}
