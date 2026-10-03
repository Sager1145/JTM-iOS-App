import XCTest

@MainActor
final class LocalJourneyAutofillUITests: XCTestCase {
    func testEndpointsFillAnUntimedPhysicalRouteAndUndoRestoresTheDraft() {
        continueAfterFailure = false
        let app = newEditor()
        selectEndpoints(in: app, origin: "003766", destination: "004095")
        let apply = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "localJourneyApply-")).firstMatch
        let deadline = Date().addingTimeInterval(30)
        revealProposal(apply, in: app, before: deadline)
        XCTAssertTrue(apply.waitForExistence(timeout: max(0, deadline.timeIntervalSinceNow)))
        XCTAssertTrue(apply.isHittable, "The physical route proposal must be reachable before applying it.")
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

    func testKeiseiThroughServiceRemainsPendingWithoutPhysicalJunctionEvidence() {
        continueAfterFailure = false
        let app = newEditor()
        selectEndpoints(in: app, origin: "003280", destination: "004368")
        let deadline = Date().addingTimeInterval(30)
        let serviceName = "京成・都営浅草線・京急直通"
        let operatingService = app.buttons["localJourneyOperatingService"]
        revealProposal(operatingService, in: app, before: deadline)
        XCTAssertTrue(operatingService.waitForExistence(timeout: max(0, deadline.timeIntervalSinceNow)))
        XCTAssertTrue(operatingService.isHittable)
        operatingService.tap()
        let pattern = app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH %@", serviceName)).firstMatch
        XCTAssertTrue(pattern.waitForExistence(timeout: max(0, deadline.timeIntervalSinceNow)))
        pattern.tap()
        XCTAssertTrue(operatingService.label.contains(serviceName),
                      "The bundled through-service label must remain available without a physical route.")

        let empty = app.staticTexts["localJourneySearchEmpty"]
        revealProposal(empty, in: app, before: deadline)
        XCTAssertTrue(empty.waitForExistence(timeout: max(0, deadline.timeIntervalSinceNow)),
                      "Wait for the explicit completed empty search before checking candidate absence.")
        let apply = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "localJourneyApply-")).firstMatch
        XCTAssertFalse(apply.exists, "Service display metadata cannot invent cross-row physical junctions.")
        let keepPending = app.buttons["localJourneyKeepPending"]
        revealProposal(keepPending, in: app, before: deadline)
        XCTAssertTrue(keepPending.waitForExistence(timeout: max(0, deadline.timeIntervalSinceNow)))
        XCTAssertTrue(keepPending.isEnabled && keepPending.isHittable)
        keepPending.tap()
        // The new editor starts with two endpoint placeholders. Replacing
        // those visits still requires the proposal's normal manual confirmation.
        let confirmationDeadline = Date().addingTimeInterval(10)
        let confirmPending = app.sheets.firstMatch.buttons["Keep route pending confirmation"]
        XCTAssertTrue(confirmPending.waitForExistence(timeout: max(0, confirmationDeadline.timeIntervalSinceNow)))
        confirmPending.tap()
        XCTAssertTrue(keepPending.waitForNonExistence(timeout: max(0, confirmationDeadline.timeIntervalSinceNow)))
        let pending = app.staticTexts["Route pending confirmation"]
        _ = EditorUITestSupport.reveal(pending, in: app)
        XCTAssertTrue(pending.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["rideEditorLocalAutofillUndo"].exists,
                       "Keeping an unresolved route must not commit an autofilled physical path.")
        var endpointLabels: [String] = []
        for index in 0...1 {
            let endpoint = app.descendants(matching: .any)["rideEditorStop-\(index)"].firstMatch
            _ = EditorUITestSupport.reveal(endpoint, in: app)
            XCTAssertTrue(endpoint.waitForExistence(timeout: 10))
            XCTAssertFalse(endpoint.label.isEmpty)
            endpointLabels.append(endpoint.label)
        }
        XCTAssertFalse(app.descendants(matching: .any)["rideEditorStop-2"].firstMatch.exists,
                       "Pending endpoints must not acquire invented intermediate visits.")
        let next = app.buttons["rideEditorNext"]
        EditorUITestSupport.tap(next, in: app)
        let database = app.buttons["rideEditorLineServiceDatabase"]
        XCTAssertTrue(database.waitForExistence(timeout: 10))
        let serviceLeg = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "rideEditorServiceLeg-", serviceName)).firstMatch
        _ = EditorUITestSupport.reveal(serviceLeg, in: app)
        XCTAssertTrue(serviceLeg.waitForExistence(timeout: 10),
                      "The selected through-service name must survive in the pending draft.")
        saveAndReopenPendingService(serviceName, endpointLabels: endpointLabels, in: app)
    }

    private func saveAndReopenPendingService(
        _ serviceName: String, endpointLabels: [String], in app: XCUIApplication
    ) {
        let number = "PendingService-\(UUID().uuidString.prefix(8))"
        let numberField = app.otherElements["rideEditorNumber"].textFields.firstMatch
        EditorUITestSupport.tap(numberField, in: app)
        guard let oldNumber = numberField.value as? String else {
            XCTFail("The pending journey must expose its editable train number.")
            return
        }
        if !oldNumber.isEmpty && oldNumber != numberField.placeholderValue {
            numberField.press(forDuration: 1.1)
            let button = app.buttons["Select All"].firstMatch
            let menuItem = app.menuItems["Select All"].firstMatch
            if button.waitForExistence(timeout: 3) {
                button.tap()
            } else {
                XCTAssertTrue(menuItem.waitForExistence(timeout: 2))
                menuItem.tap()
            }
        }
        numberField.typeText(number + "\n")
        XCTAssertEqual(numberField.value as? String, number)
        app.buttons["rideEditorNext"].tap()
        XCTAssertTrue(app.switches["Include a date"].waitForExistence(timeout: 8))
        app.buttons["rideEditorNext"].tap()
        let save = app.buttons["rideEditorSave"]
        XCTAssertTrue(save.waitForExistence(timeout: 8))
        XCTAssertTrue(save.isEnabled, "The unresolved physical route must remain saveable as pending.")
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 8))

        app.tabBars.firstMatch.buttons.element(boundBy: 3).tap()
        let search = app.textFields["journeySearchField"]
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.tap()
        search.typeText(number)
        let rowPredicate = NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                                       "journeyRow-", number)
        let inserted = app.descendants(matching: .any).matching(rowPredicate).firstMatch
        XCTAssertTrue(inserted.waitForExistence(timeout: 15))
        // Match the normal save/relaunch regression's asynchronous store-write window.
        Thread.sleep(forTimeInterval: 1)
        app.terminate()
        app.launchEnvironment["RAILMAP_UI_TEST_SHEET"] = ""
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "search"
        app.launchEnvironment["RAILMAP_UI_TEST_QUERY"] = number
        app.launch()
        let saved = app.descendants(matching: .any).matching(rowPredicate).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 30))
        saved.press(forDuration: 1)
        let information = app.buttons["Journey information"]
        XCTAssertTrue(information.waitForExistence(timeout: 5))
        information.tap()
        let edit = app.buttons["journeyMenuEdit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 8))
        edit.tap()
        let pending = app.staticTexts["Route pending confirmation"]
        _ = EditorUITestSupport.reveal(pending, in: app)
        XCTAssertTrue(pending.waitForExistence(timeout: 10),
                      "Save/reopen must retain pending physical route confirmation.")
        for (index, label) in endpointLabels.enumerated() {
            let endpoint = app.descendants(matching: .any)["rideEditorStop-\(index)"].firstMatch
            _ = EditorUITestSupport.reveal(endpoint, in: app)
            XCTAssertTrue(endpoint.waitForExistence(timeout: 10))
            XCTAssertEqual(endpoint.label, label, "Save/reopen must preserve each ordered endpoint.")
        }
        XCTAssertFalse(app.descendants(matching: .any)["rideEditorStop-2"].firstMatch.exists)
        let serviceLeg = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "rideEditorServiceLeg-", serviceName)).firstMatch
        _ = EditorUITestSupport.reveal(serviceLeg, in: app)
        XCTAssertTrue(serviceLeg.waitForExistence(timeout: 10),
                      "Save/reopen must retain the through-service display name independently of routing.")
    }

    private func reveal(_ element: XCUIElement, in form: XCUIElement) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            form.swipeUp()
        }
    }

    private func revealProposal(_ element: XCUIElement, in app: XCUIApplication, before deadline: Date) {
        let form = app.descendants(matching: .any)["localJourneyProposalForm"].firstMatch
        guard form.waitForExistence(timeout: max(0, deadline.timeIntervalSinceNow)) else { return }
        // Candidate rows follow the ordered anchors, search warning and map.
        // Scroll the Form's gutter so its interactive map cannot consume the drag.
        for _ in 0..<8 where deadline.timeIntervalSinceNow > 0 {
            if element.exists && element.isHittable { return }
            let start = form.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.75))
                .withOffset(CGVector(dx: 8, dy: 0))
            let end = form.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.25))
                .withOffset(CGVector(dx: 8, dy: 0))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
    }

    private func newEditor() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["RAILMAP_UI_TEST_STORAGE_ID"] = UUID().uuidString
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
