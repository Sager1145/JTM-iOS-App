import XCTest

@MainActor
final class JourneySaveUITests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        await MainActor.run {
            XCUIDevice.shared.orientation = .portrait
        }
    }

    func testSavedJourneyIsStillPresentAfterRelaunch() {
        let number = "Persist \(UUID().uuidString.prefix(8))"
        let app = XCUIApplication()
        EditorLaunchSupport.launchNewTrip(app)
        pickStation(field: "newTripOrigin", query: "品川", code: "004095",
                    lineID: "jp-東日本旅客鉄道-山手線", in: app)
        pickStation(field: "newTripDestination", query: "大崎", code: "004135",
                    lineID: "jp-東日本旅客鉄道-山手線", in: app)
        let numberField = app.textFields["newTripNumber"]
        XCTAssertTrue(showNumber(numberField, in: app))
        typeNumber(number, into: numberField, in: app)

        let save = app.buttons["newTripSave"]
        XCTAssertTrue(waitUntilSavable(save, in: app),
                      "Save must enable once the route is planned.")
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 20))

        app.tabBars.firstMatch.buttons.element(boundBy: 3).tap()
        let savedSearch = app.textFields["journeySearchField"]
        XCTAssertTrue(savedSearch.waitForExistence(timeout: 8))
        savedSearch.tap()
        savedSearch.typeText(number)
        let inserted = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "journeyRow-", number)).firstMatch
        XCTAssertTrue(inserted.waitForExistence(timeout: 15),
                      "Saving must return to a list containing the inserted journey.")

        // The store write is asynchronous. Waiting here tests the same
        // completion window a reader naturally spends looking at the saved
        // journey before closing the app, then the relaunch proves disk state.
        Thread.sleep(forTimeInterval: 1)
        app.terminate()
        app.launchEnvironment["RAILMAP_UI_TEST_SHEET"] = ""
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "search"
        app.launchEnvironment["RAILMAP_UI_TEST_QUERY"] = number
        app.launch()

        let savedRow = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "journeyRow-", number)).firstMatch
        XCTAssertTrue(savedRow.waitForExistence(timeout: 30),
                      "A completed save must survive process termination and reload.")
        savedRow.press(forDuration: 1)
        let information = app.buttons["Journey information"]
        XCTAssertTrue(information.waitForExistence(timeout: 5))
        information.tap()
        XCTAssertTrue(app.buttons["journeyMenuEdit"].waitForExistence(timeout: 8))
        guard let detailScroll = app.scrollViews.allElementsBoundByIndex.first(where: {
            $0.descendants(matching: .any)["rideDetailStops"].exists
        }) else {
            XCTFail("The opened journey must contain its native detail scroll view.")
            return
        }
        XCTAssertTrue(detailScroll.waitForExistence(timeout: 5))
        // The typed number already matched the relaunched row above (it sits in
        // the detail header, outside this scroll view). NewTripView stores the
        // catalog's station names, so the stops keep their Japanese names.
        for value in ["品川", "大崎"] {
            let persistedValue = detailScroll.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS %@", value)).firstMatch
            for _ in 0..<6 where !persistedValue.exists { detailScroll.swipeUp() }
            XCTAssertTrue(persistedValue.waitForExistence(timeout: 5),
                          "The saved detail must retain \(value) after relaunch. \(detailScroll.debugDescription)")
        }
    }

    func testNewJourneyGroupNameCanBeEditedAfterReturningFromConfirmation() {
        let app = XCUIApplication()
        EditorLaunchSupport.launchEditing(app, journey: seededJourney(number: "Group test"))
        let create = app.buttons["createJourneyGroup"]
        XCTAssertTrue(EditorUITestSupport.reveal(create, in: app), app.debugDescription)
        XCTAssertTrue(create.waitForExistence(timeout: 8))
        create.tap()
        let name = app.textFields["journeyGroupName"]
        XCTAssertTrue(EditorUITestSupport.reveal(name, in: app))
        XCTAssertFalse(app.buttons["rideEditorSave"].isEnabled,
                       "Creating the empty group must select its unfinished draft.")
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Rail holiday\n")
        XCTAssertEqual(name.value as? String, "Rail holiday")

        // Edit mode has no confirmation step. Leaving for a stop and coming
        // back is the same draft the confirmation screen used to round-trip.
        let origin = app.descendants(matching: .any)["rideEditorStop-0"].firstMatch
        EditorUITestSupport.tap(origin, in: app)
        XCTAssertTrue(app.otherElements["rideEditorStopName"].waitForExistence(timeout: 8))
        app.navigationBars["Tokyo"].buttons.firstMatch.tap()

        XCTAssertTrue(EditorUITestSupport.reveal(name, in: app), app.debugDescription)
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Rail holiday")
        name.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        name.typeText(XCUIKeyboardKey.delete.rawValue + "s\n")
        XCTAssertEqual(name.value as? String, "Rail holidas")
        let save = app.buttons["rideEditorSave"]
        XCTAssertTrue(save.waitForExistence(timeout: 8))
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 15))
    }

    func testDirtyCancelCanKeepEditingThenDiscardDraft() {
        let unsavedName = "Unsaved \(UUID().uuidString.prefix(8))"
        let app = XCUIApplication()
        EditorLaunchSupport.launchEditing(app, journey: seededJourney(number: "Dirty cancel"))

        let origin = app.descendants(matching: .any)["rideEditorStop-0"].firstMatch
        XCTAssertTrue(app.buttons["rideEditorCancel"].waitForExistence(timeout: 30))
        EditorUITestSupport.tap(origin, in: app)
        let name = app.otherElements["rideEditorStopName"].textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        replaceText(in: name, with: unsavedName, app: app)
        XCTAssertEqual(name.value as? String, unsavedName, app.debugDescription)
        let stopNavigation = app.navigationBars[unsavedName]
        XCTAssertTrue(stopNavigation.waitForExistence(timeout: 5), app.debugDescription)
        stopNavigation.buttons.firstMatch.tap()

        let cancel = app.buttons["rideEditorCancel"]
        cancel.tap()
        let discardDialog = app.sheets.firstMatch
        XCTAssertTrue(discardDialog.waitForExistence(timeout: 5))
        // Compact confirmation dialogs expose their destructive action as a
        // button but treat tapping outside the popover as the cancel role.
        // Dismiss that way to exercise “Keep editing” without accidentally
        // finding the editor toolbar's own Cancel button behind the dialog.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.95)).tap()
        XCTAssertTrue(discardDialog.waitForNonExistence(timeout: 5))

        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        XCTAssertTrue(origin.label.contains(unsavedName),
                      "Keeping the editor open must preserve the local draft.")

        cancel.tap()
        let discard = app.buttons["Discard changes"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        discard.tap()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 8),
                      "Discarding must close the editor without committing the draft.")
        app.terminate()
        app.launchEnvironment["RAILMAP_UI_TEST_SHEET"] = ""
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "search"
        app.launchEnvironment["RAILMAP_UI_TEST_QUERY"] = unsavedName
        app.launch()
        let search = app.textFields["journeySearchField"]
        XCTAssertTrue(search.waitForExistence(timeout: 30))
        XCTAssertEqual(search.value as? String, unsavedName,
                       "The relaunch must finish applying the discard-proof query.")
        let completedEmptyState = app.staticTexts.matching(NSPredicate(
            format: "label IN %@", ["No matching journeys", "No journeys yet"])).firstMatch
        XCTAssertTrue(completedEmptyState.waitForExistence(timeout: 30),
                      "The loaded library must finish searching before absence is meaningful.")
        let discardedRow = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "journeyRow-", unsavedName)).firstMatch
        XCTAssertFalse(discardedRow.waitForExistence(timeout: 8),
                       "A discarded draft must not appear after process relaunch.")
    }

    private func seededJourney(number: String) -> [String: Any] {
        let compact = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        return [
            "id": "uitest_\(compact.prefix(12))",
            "date": "2026-10-12",
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

    private func pickStation(
        field: String, query: String, code: String, lineID: String, in app: XCUIApplication
    ) {
        let button = app.buttons[field]
        XCTAssertTrue(button.waitForExistence(timeout: 20))
        XCTAssertTrue(waitForEnabled(button, timeout: 20))
        button.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 20))
        search.tap()
        search.typeText(query)
        let row = app.buttons["newTripStation-\(lineID)-\(code)"]
        // Name search lists one row per line. A shared name can still sit below
        // earlier sections, so scroll the lazy list until that line's row exists.
        var swipes = 0
        while !row.waitForExistence(timeout: swipes == 0 ? 3 : 0.4), swipes < 12 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(row.exists, "No newTripStation-\(lineID)-\(code) for \(query). \(app.debugDescription)")
        let previousLabel = button.label
        dismissSearchKeyboard(in: app)
        row.tap()
        if app.searchFields.firstMatch.exists {
            dismissSearchKeyboard(in: app)
            if row.waitForExistence(timeout: 2) { row.tap() }
        }
        XCTAssertTrue(
            app.searchFields.firstMatch.waitForNonExistence(timeout: 5),
            "Choosing \(query) must close station search.")
        let chosen = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@", previousLabel),
            object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [chosen], timeout: 8), .completed, button.label)
    }

    /// Resign the station-search keyboard without leaving the sheet up.
    private func dismissSearchKeyboard(in app: XCUIApplication) {
        let keyboard = app.keyboards.firstMatch
        guard keyboard.exists else { return }
        for label in ["Search", "検索"] {
            let key = keyboard.buttons[label]
            if key.exists {
                key.tap()
                break
            }
        }
        _ = keyboard.waitForNonExistence(timeout: 2)
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
    }

    @discardableResult
    private func waitForEnabled(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let enabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"), object: element)
        return XCTWaiter.wait(for: [enabled], timeout: timeout) == .completed
    }

    /// Used only by the relaunch test. Form text fields report a frame but
    /// `isHittable` stays false, and `tap()` never takes keyboard focus.
    private func showNumber(_ field: XCUIElement, in app: XCUIApplication) -> Bool {
        guard app.collectionViews.firstMatch.waitForExistence(timeout: 8) else { return false }
        for _ in 0..<8 {
            if field.exists, frameInBand(field, in: app) { return true }
            let up = field.exists && field.frame.midY < app.frame.midY
            nudgeForm(in: app, up: up)
        }
        return field.exists && frameInBand(field, in: app)
    }

    private func nudgeForm(in app: XCUIApplication, up: Bool, span: CGFloat = 0.40) {
        let save = app.buttons["newTripSave"]
        if save.exists, save.frame.minY > 180 {
            let handle = app.coordinate(withNormalizedOffset: CGVector(
                dx: 0.5, dy: max(0.1, (save.frame.midY - 8) / app.frame.height)))
            handle.press(forDuration: 0.05,
                         thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)))
        }
        let lists = app.collectionViews.allElementsBoundByIndex.filter {
            $0.frame.height > 160 && !$0.searchFields.firstMatch.exists
        }
        guard let form = lists.max(by: { $0.frame.height < $1.frame.height }) ?? app.collectionViews.allElementsBoundByIndex.first,
              form.frame.height > 80 else { return }
        let travel = min(0.40, max(0.12, span))
        let startY: CGFloat = up ? 0.42 : 0.78
        let endY: CGFloat = up ? 0.42 + travel : 0.78 - travel
        let start = form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
        let end = form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: endY))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func frameInBand(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        let frame = element.frame
        guard frame.width > 1, frame.height > 1 else { return false }
        return app.frame.insetBy(dx: 0, dy: 120).contains(frame)
    }

    private func typeNumber(_ value: String, into field: XCUIElement, in app: XCUIApplication) {
        closeStationSearch(in: app)
        var focused = false
        for step in 0..<10 {
            if field.exists, field.isHittable, clearOfKeyboard(field, in: app) {
                field.tap()
                let ready = XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: field)
                if XCTWaiter.wait(for: [ready], timeout: 2) == .completed {
                    focused = true
                    break
                }
            } else if field.exists {
                // At its resting y≈560 the field has a frame but is not hittable.
                // The same field accepts a tap near y≈330. Move it up into that band.
                let keyboard = app.keyboards.firstMatch
                let ceiling: CGFloat = keyboard.exists ? keyboard.frame.minY - 40 : 430
                if field.frame.midY > ceiling {
                    nudgeForm(in: app, up: false, span: 0.28)
                } else if field.frame.midY < 200 {
                    nudgeForm(in: app, up: true, span: 0.18)
                } else {
                    nudgeForm(in: app, up: false, span: 0.12)
                }
            } else {
                nudgeForm(in: app, up: step < 5)
            }
        }
        XCTAssertTrue(focused, "The train number field must take keyboard focus. "
            + "frame=\(field.frame) hittable=\(field.isHittable) "
            + "keyboard=\(app.keyboards.firstMatch.exists)")
        field.typeText(value + "\n")
    }

    /// The station sheet is already closed. A leftover keyboard still covers the form.
    private func closeStationSearch(in app: XCUIApplication) {
        guard !app.searchFields.firstMatch.exists else { return }
        let keyboard = app.keyboards.firstMatch
        guard keyboard.exists else { return }
        for label in ["Return", "Done", "Search", "検索"] {
            let key = keyboard.buttons[label]
            if key.exists {
                key.tap()
                break
            }
        }
        _ = keyboard.waitForNonExistence(timeout: 2)
    }

    private func clearOfKeyboard(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        let frame = element.frame
        guard frame.width > 1, frame.height > 1 else { return false }
        var band = app.frame.insetBy(dx: 8, dy: 0)
        band.origin.y = 140
        let keyboard = app.keyboards.firstMatch
        let limit = keyboard.exists ? keyboard.frame.minY - 12 : app.frame.maxY - 40
        band.size.height = limit - band.origin.y
        guard band.height > 40 else { return false }
        return band.contains(frame)
    }

    /// 山手線 keeps both directions. Save stays disabled until corridor 0 is tapped.
    private func waitUntilSavable(_ save: XCUIElement, in app: XCUIApplication) -> Bool {
        if waitForEnabled(save, timeout: 5) { return true }
        let first = app.buttons["newTripCorridor-0"]
        let deadline = Date().addingTimeInterval(35)
        while Date() < deadline {
            if save.isEnabled { return true }
            if first.exists, first.isHittable {
                if !save.isEnabled { first.tap() }
                if waitForEnabled(save, timeout: 6) { return true }
            }
            nudgeForm(in: app, up: false)
        }
        return save.isEnabled
    }
}
