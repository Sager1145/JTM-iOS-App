import RailPresentation
import XCTest

@MainActor
final class TripNotesUITests: XCTestCase {
    private let tripID = "uitest_tripnotes"

    override func setUp() { continueAfterFailure = false }

    func testNoNotesMeansNoMarkerAndNoBadge() {
        let app = launch(selecting: false)
        XCTAssertTrue(element("journeyLoadInventory", in: app).waitForExistence(timeout: 5)
                      || app.wait(for: .runningForeground, timeout: 10))
        sleep(3)
        XCTAssertFalse(element("tripNoteMarker", in: app).exists)
        XCTAssertFalse(element("tripNoteBadge", in: app).exists)
    }

    func testAddingAPickShowsBannerBeforeFormThenFullNoteLifecycle() {
        let app = launch(selecting: true)
        let add = app.buttons["tripNotesAdd"]
        XCTAssertTrue(add.waitForExistence(timeout: 30))
        XCTAssertFalse(element("tripNoteMarker", in: app).exists)
        XCTAssertFalse(element("tripNotesCard", in: app).exists, "No notes: no list card.")
        add.tap()

        // Place first: the pick banner is up and no form exists yet.
        XCTAssertTrue(element("tripNotePickBanner", in: app).waitForExistence(timeout: 10))
        XCTAssertFalse(element("tripNoteForm", in: app).exists)
        let pickState = element("tripNotePickState", in: app)
        XCTAssertTrue(pickState.waitForExistence(timeout: 5))
        // The route may still be solving, so wait for the count to settle.
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(
            format: "label == %@", "tripNotePickMode=on;visibleRides=1"), object: pickState)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 20), .completed,
                       "Other rides are hidden while picking: \(pickState.label)")

        chooseStation(named: "Tokyo", in: app)
        let form = element("tripNoteForm", in: app)
        XCTAssertTrue(form.waitForExistence(timeout: 10))
        XCTAssertFalse(pickState.exists, "The pick state goes away after Confirm.")
        XCTAssertTrue(element("tripNotePlace", in: app).label.contains("Tokyo"))

        let category = app.textFields["tripNoteCategory"]
        category.tap()
        category.typeText("Crew change")
        let text = app.textViews["tripNoteText"]
        text.tap()
        text.typeText("Driver swapped")
        app.buttons["tripNoteSave"].tap()
        XCTAssertFalse(form.waitForExistence(timeout: 1) && form.exists)

        let marker = element("tripNoteMarker", in: app)
        XCTAssertTrue(marker.waitForExistence(timeout: 15))
        let markerBefore = marker.value as? String ?? ""
        let row = element("tripNoteRow", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 10), "The notes list must show the row.")
        XCTAssertTrue(row.label.contains("Crew change"), row.label)
        XCTAssertTrue(row.label.contains("Tokyo"), row.label)

        // Edit: change the place to another station and save.
        marker.tap()
        XCTAssertTrue(element("tripNoteReadCard", in: app).waitForExistence(timeout: 5))
        app.buttons["tripNoteEdit"].tap()
        XCTAssertTrue(form.waitForExistence(timeout: 5))
        app.buttons["tripNoteChangePlace"].tap()
        XCTAssertTrue(element("tripNotePickBanner", in: app).waitForExistence(timeout: 10))
        chooseStation(named: "Shinagawa", in: app)
        XCTAssertTrue(form.waitForExistence(timeout: 10))
        XCTAssertEqual(app.textViews["tripNoteText"].value as? String, "Driver swapped",
                       "Unsaved edits survive the pick.")
        XCTAssertTrue(element("tripNotePlace", in: app).label.contains("Shinagawa"))
        app.buttons["tripNoteSave"].tap()
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (marker.value as? String ?? "") != markerBefore
        }, object: marker)
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 10), .completed,
                       "The marker's place summary must change from Tokyo to Shinagawa.")
        XCTAssertTrue((marker.value as? String ?? "").contains("Shinagawa"))
        XCTAssertTrue(row.waitForExistence(timeout: 10), "The notes list must show the row.")
        XCTAssertTrue(row.label.contains("Shinagawa"), row.label)

        // Read card, delete.
        marker.tap()
        XCTAssertTrue(element("tripNoteReadCard", in: app).waitForExistence(timeout: 5))
        app.buttons["tripNoteDelete"].tap()
        let confirm = app.buttons.matching(identifier: "tripNoteDeleteConfirm").firstMatch
        if confirm.waitForExistence(timeout: 3) { confirm.tap() }
        else { app.buttons.matching(identifier: "Delete").lastMatch.tap() }
        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: row)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed)
        XCTAssertFalse(element("tripNoteMarker", in: app).waitForExistence(timeout: 3),
                       "Deleting the last note removes its marker.")
    }

    // MARK: -

    /// The map pick's station menu, then Confirm.
    private func chooseStation(named name: String, in app: XCUIApplication) {
        let menu = element("tripNotePickStation", in: app)
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        menu.tap()
        let choice = app.buttons[name].firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        choice.tap()
        let confirm = element("tripNotePickConfirm", in: app)
        if confirm.waitForExistence(timeout: 3) { confirm.tap() }
    }

    private func launch(selecting: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.uiTestLaunch[.storageId] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-interface-language", "en"]
        app.uiTestLaunch[.storeBase64] = seededStore()
        if selecting {
            app.uiTestLaunch[.select] = tripID
            app.uiTestLaunch[.stage] = "expanded"
        }
        UITestLaunchSupport.launch(app)
        return app
    }

    private func seededStore() -> String {
        let other: [String: Any] = [
            "id": "uitest_tripnotes_other", "date": "2026-10-12", "number": "Other 2",
            "origin": "Tokyo", "destination": "Shinagawa", "region": "jp",
            "stops": [
                EditorLaunchSupport.stop("Tokyo", code: "003768", type: "origin", departure: "10:00"),
                EditorLaunchSupport.stop("Shinagawa", code: "004092", type: "destination", arrival: "10:20"),
            ],
        ]
        let train: [String: Any] = [
            "id": tripID, "date": "2026-10-12", "number": "Notes 1",
            "origin": "Tokyo", "destination": "Shinagawa", "region": "jp",
            "stops": [
                EditorLaunchSupport.stop("Tokyo", code: "003768", type: "origin", departure: "09:00"),
                EditorLaunchSupport.stop("Shinagawa", code: "004092", type: "destination", arrival: "09:20"),
            ],
        ]
        let store: [String: Any] = ["schema_version": "1.3", "trains": [train, other]]
        return try! JSONSerialization.data(withJSONObject: store, options: [.sortedKeys])
            .base64EncodedString()
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}

private extension XCUIElementQuery {
    var lastMatch: XCUIElement { element(boundBy: max(count - 1, 0)) }
}
