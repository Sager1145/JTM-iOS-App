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
        let proposal = app.descendants(matching: .any)["localJourneyProposalForm"].firstMatch
        if !proposal.waitForNonExistence(timeout: 8),
           app.staticTexts["Replace authored visits?"].exists {
            let confirm = app.sheets.buttons["Fill this route"]
            if confirm.waitForExistence(timeout: 2) {
                confirm.tap()
            } else {
                app.buttons["Fill this route"].tap()
            }
        }
        XCTAssertTrue(proposal.waitForNonExistence(timeout: 8),
                      "Applying a physical route must close the proposal sheet.")
        // Undo sits in the route section. A dismissed sheet leaves that row
        // unmounted until the editor form scrolls it back into view.
        let undo = app.buttons["rideEditorLocalAutofillUndo"]
        XCTAssertTrue(EditorUITestSupport.reveal(undo, in: app, maxDrags: 16), app.debugDescription)
        XCTAssertTrue(undo.waitForExistence(timeout: 10))
        let form = app.collectionViews["rideEditorForm"]
        let added = app.descendants(matching: .any)["rideEditorStop-2"].firstMatch
        reveal(added, in: form)
        XCTAssertTrue(added.exists, "The local route inserts at least one physical intermediate visit.")
        // Scrolling to the new stop slides Undo under the navigation bar.
        // A coordinate tap then hits the bar and the draft stays filled.
        revealBelowNavigationBar(undo, in: app)
        EditorUITestSupport.tap(undo, in: app)
        XCTAssertTrue(app.descendants(matching: .any)["rideEditorStop-2"].firstMatch
            .waitForNonExistence(timeout: 8))
    }

    func testKeiseiThroughServiceCanExplicitlyKeepPendingWithReviewableCandidates() {
        continueAfterFailure = false
        let app = newEditor()
        selectEndpoints(in: app, origin: "003280", destination: "004368")
        let deadline = Date().addingTimeInterval(30)
        let serviceName = "京成本線・都営浅草線・京急空港線直通"
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

        let apply = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "localJourneyApply-")).firstMatch
        revealProposal(apply, in: app, before: deadline)
        XCTAssertTrue(apply.waitForExistence(timeout: max(0, deadline.timeIntervalSinceNow)),
                      "Compatible shared-station rows should offer a reviewable candidate.")
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
        let database = app.buttons["rideEditorLineServiceDatabase"]
        XCTAssertTrue(EditorUITestSupport.reveal(database, in: app), app.debugDescription)
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
        // The number row is in Basics, above the service leg this test just revealed.
        XCTAssertTrue(EditorUITestSupport.reveal(
            numberField, in: app, maxDrags: 24, unmountedRowIsAbove: true), app.debugDescription)
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
        app.launchEnvironment.removeValue(forKey: "RAILMAP_UI_TEST_STORE_BASE64")
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

    /// Keep a row's center clear of the inline navigation bar before a coordinate tap.
    private func revealBelowNavigationBar(_ element: XCUIElement, in app: XCUIApplication) {
        let form = app.collectionViews["rideEditorForm"]
        let bar = app.navigationBars.firstMatch
        for _ in 0..<8 {
            let floor = bar.exists ? bar.frame.maxY + 8 : app.frame.minY + 100
            if element.exists, element.isHittable, element.frame.minY >= floor,
               element.frame.maxY <= app.frame.maxY - 8 { return }
            if !element.exists || element.frame.midY < floor {
                form.swipeDown()
            } else {
                form.swipeUp()
            }
        }
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
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-interface-language", "en"]
        EditorLaunchSupport.launchEditing(app, journey: blankJapanJourney())
        XCTAssertTrue(app.descendants(matching: .any)["rideEditorForm"].firstMatch.waitForExistence(timeout: 30))
        let open = app.buttons["rideEditorLocalAutofill"]
        XCTAssertTrue(EditorUITestSupport.reveal(open, in: app), app.debugDescription)
        XCTAssertTrue(open.waitForExistence(timeout: 30))
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: open)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 30), .completed)
        open.tap()
        return app
    }

    /// Edit mode has no wizard, so the autofill sheet still starts from an empty Japan draft.
    private func blankJapanJourney() -> [String: Any] {
        [
            "id": "ui-local-autofill",
            "number": "",
            "origin": "",
            "destination": "",
            "region": "jp",
            "visible": true,
            "stops": [
                EditorLaunchSupport.stop("", code: nil, type: "origin"),
                EditorLaunchSupport.stop("", code: nil, type: "destination"),
            ],
        ]
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
