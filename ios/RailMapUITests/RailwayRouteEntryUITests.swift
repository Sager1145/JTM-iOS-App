import XCTest

@MainActor
final class RailwayRouteEntryUITests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testNewJourneyCanOpenAndCancelRailwayRouteGuide() {
        let app = launchSeededEditor()
        XCTAssertTrue(app.descendants(matching: .any)["rideEditorForm"].firstMatch.waitForExistence(timeout: 30),
                      "The seeded journey editor must open.")

        openAndCancelGuide(in: app)
        let origin = app.descendants(matching: .any)["rideEditorStop-0"].firstMatch
        let destination = app.descendants(matching: .any)["rideEditorStop-1"].firstMatch
        XCTAssertTrue(EditorUITestSupport.reveal(origin, in: app),
                      "Cancelling must retain the origin stop.")
        XCTAssertTrue(origin.exists, "Cancelling must retain the origin stop.")
        // The destination row is the next lazy stop, below the route section
        // the guide returns to. It is absent from the tree until scrolled in.
        XCTAssertTrue(EditorUITestSupport.reveal(destination, in: app, unmountedRowIsAbove: false),
                      "Cancelling must retain the destination stop.")
        XCTAssertTrue(destination.exists, "Cancelling must retain the destination stop.")
        XCTAssertFalse(app.descendants(matching: .any)["rideEditorStop-2"].firstMatch.exists,
                       "Opening and cancelling the guide must leave the draft with exactly two stops.")
    }

    func testSavedJourneyCanOpenAndCancelRailwayRouteGuide() {
        let app = launchEditor(sheet: "edit")
        XCTAssertTrue(app.descendants(matching: .any)["rideEditorForm"].firstMatch.waitForExistence(timeout: 30),
                      "The saved journey launch harness must open the edit form.")
        openAndCancelGuide(in: app)
        XCTAssertTrue(app.buttons["rideEditorCancel"].exists,
                      "Cancelling the railway guide must keep the saved journey editor open.")
    }

    func testRouteCanBeKeptPendingWithoutChoosingACandidate() {
        let app = launchEditor(sheet: "edit")
        XCTAssertTrue(app.descendants(matching: .any)["rideEditorForm"].firstMatch.waitForExistence(timeout: 30))
        let lines = app.buttons["rideEditorLines"]
        reveal(lines, in: app)
        lines.tap()
        let pending = app.buttons["routeCorrectionPending"]
        XCTAssertTrue(pending.waitForExistence(timeout: 10))
        pending.tap()
        XCTAssertTrue(pending.waitForNonExistence(timeout: 8))
        let state = app.staticTexts["Route pending confirmation"]
        reveal(state, in: app)
        XCTAssertTrue(state.exists)
        XCTAssertTrue(app.buttons["rideEditorSave"].isEnabled,
                      "Pending physical geometry must not prevent saving the journey.")
    }

    func testMapSelectionMatchesAccessibleCandidateCard() {
        let app = launchSeededEditor()
        XCTAssertTrue(app.descendants(matching: .any)["rideEditorForm"].firstMatch.waitForExistence(timeout: 30))
        let lines = app.buttons["rideEditorLines"]
        reveal(lines, in: app)
        lines.tap()
        let compare = app.buttons["routeCorrectionCompare"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: compare)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed)
        compare.tap()
        let marker = app.buttons["routeGuideMapOption-1"]
        XCTAssertTrue(marker.waitForExistence(timeout: 10))
        marker.tap()
        let firstCard = app.buttons["routeGuideOption1"]
        XCTAssertTrue(firstCard.isSelected, "Map selection must select the same VoiceOver card.")
        let secondCard = app.buttons["routeGuideOption2"]
        for _ in 0..<6 {
            if secondCard.exists && secondCard.isHittable { break }
            let scroll = app.scrollViews["routeGuideScroll"]
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.8))
                .press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.3)))
        }
        XCTAssertTrue(secondCard.isHittable)
        secondCard.tap()
        let secondMarker = app.buttons["routeGuideMapOption-2"]
        for _ in 0..<6 {
            if secondMarker.exists && secondMarker.isHittable { break }
            let scroll = app.scrollViews["routeGuideScroll"]
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.3))
                .press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.8)))
        }
        XCTAssertTrue(secondMarker.isSelected,
                      "Card selection must select the same map candidate.")
    }

    private func launchSeededEditor() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-interface-language", "en"]
        let journey: [String: Any] = [
            "id": "ui-tokyo-shinagawa",
            "number": "",
            "origin": "東京",
            "destination": "品川",
            "region": "jp",
            "visible": true,
            "stops": [
                EditorLaunchSupport.stop("東京", code: "003766", type: "origin"),
                EditorLaunchSupport.stop("品川", code: "004095", type: "destination"),
            ],
        ]
        EditorLaunchSupport.launchEditing(app, journey: journey)
        return app
    }

    private func launchEditor(sheet: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["RAILMAP_UI_TEST_STORAGE_ID"] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-interface-language", "en"]
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "all"
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "expanded"
        app.launchEnvironment["RAILMAP_UI_TEST_SHEET"] = sheet
        if sheet == "edit" {
            app.launchEnvironment["RAILMAP_UI_TEST_SAMPLE"] = "train-store"
        }
        app.launch()
        return app
    }

    private func openAndCancelGuide(in app: XCUIApplication) {
        let lines = app.buttons["rideEditorLines"]
        reveal(lines, in: app)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: lines)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 15), .completed,
                       "Railway route entry must become enabled for the journey's station codes.")
        lines.tap()
        for identifier in ["routeCorrectionFrom", "routeCorrectionTo", "routeCorrectionCompare", "routeCorrectionCancel"] {
            XCTAssertTrue(app.descendants(matching: .any)[identifier].firstMatch.waitForExistence(timeout: 8),
                          "Railway route entry must present the guided correction control \(identifier).")
        }
        let cancel = app.buttons["routeCorrectionCancel"]
        cancel.tap()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 8), "Cancel must dismiss the railway route guide.")
        XCTAssertTrue(app.descendants(matching: .any)["rideEditorForm"].firstMatch.waitForExistence(timeout: 8),
                      "The journey editor must remain open after cancelling the route guide.")
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let form = app.descendants(matching: .any)["rideEditorForm"].firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 8), "Scrolling requires the journey editor form.")
        for _ in 0..<14 {
            if element.exists && element.isHittable && element.frame.maxY < app.frame.maxY - 120 { break }
            let start = form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
            let end = form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(element.exists && element.isHittable,
                      "The editor form must reveal \(element.identifier) within fourteen scroll gestures.")
    }
}
