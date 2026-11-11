import RailPresentation
import XCTest

@MainActor
final class TripNotesUITests: XCTestCase {
    private let tripID = "uitest_tripnotes"
    private let undatedID = "uitest_tripnotes_undated"

    override func setUp() { continueAfterFailure = false }

    func testNoNotesMeansNoBadgeAndANoteShowsExactlyOneOverviewBadge() {
        let overview = launch(selecting: false)
        waitForRoutes(in: overview)
        XCTAssertFalse(element("tripNoteMarker", in: overview).exists)
        XCTAssertFalse(element("tripNoteBadge", in: overview).exists, "No notes: no badge.")
        overview.terminate()

        let app = launch(selecting: true)
        waitForRoutes(in: app)
        let add = app.buttons["tripNotesAdd"]
        XCTAssertTrue(add.waitForExistence(timeout: 30))
        add.tap()
        XCTAssertTrue(waitForPickCount(in: app))
        chooseStation(named: "Tokyo", in: app)
        XCTAssertTrue(element("tripNoteForm", in: app).waitForExistence(timeout: 10))
        fillNote(in: app)
        app.buttons["tripNoteSave"].tap()
        XCTAssertTrue(element("tripNoteMarker", in: app).waitForExistence(timeout: 15))

        // Back to the overview: the trip card closes and the markers give way to a badge.
        let back = app.buttons["journeyBackToList"]
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        back.tap()
        let badges = app.descendants(matching: .any).matching(identifier: "tripNoteBadge")
        let one = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in badges.count == 1 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [one], timeout: 20), .completed,
                       "Exactly one overview badge expected, found \(badges.count).")
        XCTAssertTrue(badges.firstMatch.label.contains("1"), badges.firstMatch.label)
        snapshot("trip-notes-overview-badge", app)
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
        snapshot("trip-notes-1-pick", app)

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
        snapshot("trip-notes-2-form", app)
        app.buttons["tripNoteSave"].tap()
        XCTAssertFalse(form.waitForExistence(timeout: 1) && form.exists)

        let marker = element("tripNoteMarker", in: app)
        XCTAssertTrue(marker.waitForExistence(timeout: 15))
        snapshot("trip-notes-3-marker", app)
        let markerBefore = marker.value as? String ?? ""
        let row = element("tripNoteRow", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 10), "The notes list must show the row.")
        XCTAssertTrue(row.label.contains("Crew change"), row.label)
        XCTAssertTrue(row.label.contains("Tokyo"), row.label)

        // Edit: change the place to another station and save.
        marker.tap()
        XCTAssertTrue(element("tripNoteReadCard", in: app).waitForExistence(timeout: 5))
        snapshot("trip-notes-4-read-card", app)
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
        let readCard = element("tripNoteReadCard", in: app)
        let delete = readCard.descendants(matching: .button)
            .matching(identifier: "tripNoteDelete").firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "Delete belongs to the read card.")
        delete.tap()
        let confirm = app.buttons.matching(identifier: "tripNoteDeleteConfirm").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: row)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed)
        XCTAssertFalse(element("tripNoteMarker", in: app).waitForExistence(timeout: 3),
                       "Deleting the last note removes its marker.")
    }

    /// Centre pin Confirm: the camera frames the trip, so nudge the map until the pin snaps to the interval.
    func testCentrePinConfirmPlacesAnIntervalNote() {
        let app = launch(selecting: true)
        waitForRoutes(in: app)
        app.buttons["tripNotesAdd"].tap()
        XCTAssertTrue(waitForPickCount(in: app))
        let banner = element("tripNotePickBanner", in: app)
        let confirm = element("tripNotePickConfirm", in: app)
        let interval = NSPredicate(format: "label CONTAINS %@", "Tokyo → Shinagawa")
        func snapped() -> Bool {
            let expectation = XCTNSPredicateExpectation(predicate: interval, object: banner)
            return XCTWaiter.wait(for: [expectation], timeout: 4) == .completed && confirm.isEnabled
        }
        let map = app.maps.firstMatch
        var attempts = 0
        while !snapped(), attempts < 6 {
            // Alternate along the line so one of the nudges lands between the stations.
            let dy = attempts % 2 == 0 ? 0.04 : -0.08
            let from = map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            from.press(forDuration: 0.1, thenDragTo: map.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5 + dy)))
            attempts += 1
        }
        XCTAssertTrue(interval.evaluate(with: banner), "Banner: \(banner.label)")
        XCTAssertTrue(confirm.isEnabled)
        snapshot("trip-notes-centre-pin", app)
        confirm.tap()
        let form = element("tripNoteForm", in: app)
        XCTAssertTrue(form.waitForExistence(timeout: 10))
        XCTAssertTrue(element("tripNotePlace", in: app).label.contains("Tokyo → Shinagawa"),
                      element("tripNotePlace", in: app).label)
        fillNote(in: app)
        app.buttons["tripNoteSave"].tap()
        let marker = element("tripNoteMarker", in: app)
        XCTAssertTrue(marker.waitForExistence(timeout: 15))
        XCTAssertEqual(marker.value as? String, "Tokyo → Shinagawa")
    }

    /// My location, with CoreLocation stubbed to Yurakucho (on the line).
    func testMyLocationPlacesANote() {
        let app = launch(selecting: true, location: "35.6750,139.7630")
        waitForRoutes(in: app)
        app.buttons["tripNotesAdd"].tap()
        XCTAssertTrue(waitForPickCount(in: app))
        let mine = element("tripNotePickMyLocation", in: app)
        XCTAssertTrue(mine.waitForExistence(timeout: 10))
        mine.tap()
        let banner = element("tripNotePickBanner", in: app)
        let confirm = element("tripNotePickConfirm", in: app)
        let enabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isEnabled == true"), object: confirm)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 15), .completed, banner.label)
        let label = banner.label
        XCTAssertTrue(label.contains("→") || label.contains("At "), "Banner: \(label)")
        snapshot("trip-notes-my-location", app)
        confirm.tap()
        XCTAssertTrue(element("tripNoteForm", in: app).waitForExistence(timeout: 10))
        let place = element("tripNotePlace", in: app).label
        XCTAssertTrue(place.contains("→") || place.contains("At "), place)
        fillNote(in: app)
        app.buttons["tripNoteSave"].tap()
        XCTAssertTrue(element("tripNoteMarker", in: app).waitForExistence(timeout: 15))
    }

    func testTimePickerExistsHidesWithNoTimeAndDefaultSurvivesSave() {
        let app = launch(selecting: true)
        waitForRoutes(in: app)
        app.buttons["tripNotesAdd"].tap()
        XCTAssertTrue(waitForPickCount(in: app))
        chooseStation(named: "Tokyo", in: app)
        XCTAssertTrue(element("tripNoteForm", in: app).waitForExistence(timeout: 10))
        let time = element("tripNoteTime", in: app)
        let noTime = app.switches["tripNoteNoTime"]
        XCTAssertTrue(time.waitForExistence(timeout: 5), "A fresh note carries a default time.")
        XCTAssertTrue(noTime.exists)
        flip(noTime)
        snapshot("trip-notes-no-time", app)
        let hidden = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: time)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed,
                       "No time hides the picker (switch value \(noTime.value as? String ?? "nil")).")
        flip(noTime)
        XCTAssertTrue(time.waitForExistence(timeout: 5))
        snapshot("trip-notes-time", app)
        fillNote(in: app)
        app.buttons["tripNoteSave"].tap()
        let row = element("tripNoteRow", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        XCTAssertNotNil(row.label.range(of: #"\d{1,2}:\d{2}"#, options: .regularExpression),
                        "The saved default time shows on the row: \(row.label)")
    }

    /// Add note closes the details sheet, picks on the main map, then reopens details with the form.
    func testAddNoteFromDetailsSheetRunsMainMapPick() throws {
        let app = launch(selecting: true)
        waitForRoutes(in: app)
        try openDetails(in: app)
        let close = element("rideDetailClose", in: app)
        XCTAssertTrue(close.waitForExistence(timeout: 10), "Details are open.")
        tapDetailsAdd(in: app)
        let banner = element("tripNotePickBanner", in: app)
        XCTAssertTrue(banner.waitForExistence(timeout: 15), "Details Add note runs the main-map pick.")
        XCTAssertFalse(element("rideDetailClose", in: app).exists, "Details step aside during the pick.")
        XCTAssertTrue(waitForPickCount(in: app))
        chooseStation(named: "Tokyo", in: app)
        XCTAssertTrue(element("tripNoteForm", in: app).waitForExistence(timeout: 15))
        XCTAssertTrue(element("tripNotePlace", in: app).label.contains("Tokyo"))
        snapshot("trip-notes-details-form", app)
        fillNote(in: app)
        app.buttons["tripNoteSave"].tap()
        XCTAssertTrue(element("tripNoteRow", in: app).waitForExistence(timeout: 15),
                      "Confirm reopens details; the saved note is a row there.")
        XCTAssertTrue(element("rideDetailClose", in: app).exists, "The form was over the details sheet.")
    }

    /// "Add note" straight from the trip's More menu runs the main-map pick
    /// and saves a note. Skips until the trip action menu carries the item.
    func testAddNoteFromMoreMenu() throws {
        let app = launch(selecting: true)
        waitForRoutes(in: app)
        guard let add = moreMenuItem("Add note", in: app) else {
            throw XCTSkip("Enable when the trip More menu offers Add note.")
        }
        add.tap()
        XCTAssertTrue(element("tripNotePickBanner", in: app).waitForExistence(timeout: 15),
                      "Add note from More runs the main-map pick.")
        XCTAssertTrue(waitForPickCount(in: app))
        chooseStation(named: "Tokyo", in: app)
        XCTAssertTrue(element("tripNoteForm", in: app).waitForExistence(timeout: 15))
        XCTAssertTrue(element("tripNotePlace", in: app).label.contains("Tokyo"))
        fillNote(in: app)
        app.buttons["tripNoteSave"].tap()
        XCTAssertTrue(element("tripNoteMarker", in: app).waitForExistence(timeout: 15))
    }

    /// Cancelling the pick brings details back where they were, with no form.
    func testCancelledPickFromDetailsReturnsToDetailsWithoutAForm() throws {
        let app = launch(selecting: true)
        waitForRoutes(in: app)
        try openDetails(in: app)
        XCTAssertTrue(element("rideDetailClose", in: app).waitForExistence(timeout: 10))
        tapDetailsAdd(in: app)
        XCTAssertTrue(waitForPickCount(in: app))
        let cancel = element("tripNotePickCancel", in: app)
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        XCTAssertTrue(element("tripNotePickBanner", in: app).exists, "The pick runs on the main map.")
        XCTAssertFalse(element("rideDetailClose", in: app).exists, "Details stepped aside for the pick.")
        cancel.tap()
        XCTAssertTrue(element("rideDetailClose", in: app).waitForExistence(timeout: 15),
                      "Details are back after Cancel.")
        XCTAssertFalse(element("tripNoteForm", in: app).exists)
        XCTAssertFalse(element("tripNotePickBanner", in: app).exists)
    }

    func testUndatedTripPastMidnightNoteGetsDay2() {
        let app = launch(selecting: true, selectID: undatedID)
        waitForRoutes(in: app)
        let add = app.buttons["tripNotesAdd"]
        XCTAssertTrue(add.waitForExistence(timeout: 30))
        add.tap()
        XCTAssertTrue(waitForPickCount(in: app))
        chooseStation(named: "Tokyo", in: app)
        XCTAssertTrue(element("tripNoteForm", in: app).waitForExistence(timeout: 10))
        let day = element("tripNoteDay", in: app)
        XCTAssertTrue(day.waitForExistence(timeout: 5), "An undated trip's time has a Day 1 / Day 2 control.")
        // Set 12:20 AM through the picker's wheels.
        element("tripNoteTime", in: app).tap()
        let wheels = app.pickerWheels
        XCTAssertTrue(wheels.firstMatch.waitForExistence(timeout: 5))
        wheels.element(boundBy: 0).adjust(toPickerWheelValue: "12")
        wheels.element(boundBy: 1).adjust(toPickerWheelValue: "20")
        if wheels.count > 2 { wheels.element(boundBy: 2).adjust(toPickerWheelValue: "AM") }
        XCTAssertTrue(day.buttons.matching(NSPredicate(format: "label CONTAINS 'Day 2' AND isSelected == true"))
            .firstMatch.waitForExistence(timeout: 5), "Day 2 is selected for 00:20.")
        // Close the time popover (tap the title bar) so the note field can take focus.
        app.navigationBars.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        fillNote(in: app)
        app.buttons["tripNoteSave"].tap()
        let row = element("tripNoteRow", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        XCTAssertTrue(row.label.contains("+1"), row.label)
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

    /// The details sheet's own toolbar button; the trip card behind it has one with the same id.
    private func tapDetailsAdd(in app: XCUIApplication) {
        let add = app.navigationBars.buttons.matching(identifier: "tripNotesAdd").firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 10), "Details toolbar has Add note.")
        add.tap()
    }

    /// A Form switch: tapping its centre can land on the label, so hit the knob's side.
    private func flip(_ toggle: XCUIElement) {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    }

    /// A note needs a category or text to be saved.
    private func fillNote(in app: XCUIApplication) {
        let text = app.textViews["tripNoteText"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.tap()
        text.typeText("Noted")
    }

    private func waitForRoutes(in app: XCUIApplication) {
        let map = app.descendants(matching: .any)["railwayMap"]
        XCTAssertTrue(map.waitForExistence(timeout: 60), app.debugDescription)
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            map.exists && map.value as? String == "Routes loaded"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 90), .completed, "Routes never loaded.")
    }

    /// Pick mode is up and only this trip's ride is visible.
    private func waitForPickCount(in app: XCUIApplication) -> Bool {
        let state = element("tripNotePickState", in: app)
        guard state.waitForExistence(timeout: 10) else { return false }
        let one = XCTNSPredicateExpectation(predicate: NSPredicate(
            format: "label == %@", "tripNotePickMode=on;visibleRides=1"), object: state)
        return XCTWaiter.wait(for: [one], timeout: 20) == .completed
    }

    /// Opens the trip's More menu and returns the item whose label contains
    /// `label`, or nil. System menu items drop SwiftUI identifiers, so the
    /// item is found by its label (as WorkspaceEditingTests does).
    private func moreMenuItem(_ label: String, in app: XCUIApplication) -> XCUIElement? {
        let more = app.buttons["journeyMoreActions"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 20), "More menu missing.")
        more.tap()
        // The card's own Add note button (id tripNotesAdd) is not a menu item.
        let item = app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] %@ AND identifier != %@", label, "tripNotesAdd")).firstMatch
        return item.waitForExistence(timeout: 5) ? item : nil
    }

    /// Details from the card's More menu. A settled trip offers no Details on
    /// main today (JourneyPresentationResolver `resolvedRoute`), and playback
    /// closes the card, so there is no reader path to details for the seeded
    /// trip. The test skips until the trip action menu offers Details for
    /// every trip, then runs unchanged.
    private func openDetails(in app: XCUIApplication) throws {
        guard let details = moreMenuItem("detail", in: app) else {
            throw XCTSkip("Enable when the trip More menu offers Details for every trip.")
        }
        details.tap()
    }

    private func launch(selecting: Bool, location: String? = nil,
                        selectID: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.uiTestLaunch[.storageId] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-interface-language", "en"]
        app.uiTestLaunch[.storeBase64] = seededStore()
        if selecting {
            app.uiTestLaunch[.select] = selectID ?? tripID
            app.uiTestLaunch[.stage] = "expanded"
        }
        if let location { app.launchEnvironment["RAILMAP_UI_TEST_LOCATION"] = location }
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
        // No "date": departs 23:30, arrives 00:40 the next day (24:40).
        let undated: [String: Any] = [
            "id": undatedID, "number": "Undated 3",
            "origin": "Tokyo", "destination": "Shinagawa", "region": "jp",
            "stops": [
                EditorLaunchSupport.stop("Tokyo", code: "003768", type: "origin", departure: "23:30"),
                EditorLaunchSupport.stop("Shinagawa", code: "004092", type: "destination", arrival: "24:40"),
            ],
        ]
        let store: [String: Any] = ["schema_version": "1.3", "trains": [train, other, undated]]
        return try! JSONSerialization.data(withJSONObject: store, options: [.sortedKeys])
            .base64EncodedString()
    }

    /// Kept in the result bundle so the review has pictures of each step.
    private func snapshot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}

private extension XCUIElementQuery {
    var lastMatch: XCUIElement { element(boundBy: max(count - 1, 0)) }
}
