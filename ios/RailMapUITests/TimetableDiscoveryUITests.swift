import RailPresentation
import XCTest

@MainActor
final class TimetableDiscoveryUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testDatedEnglishSearchImportsPublishedDraftAndSavesOnlyAfterReview() {
        let app = NewTripTimetableTestSupport.launch()
        NewTripTimetableTestSupport.setDeparture(month: "September", day: 30, year: 2026, in: app)
        let ridden = app.switches["newTripRidden"]
        NewTripTimetableTestSupport.reveal(ridden, in: app)
        XCTAssertEqual(ridden.value as? String, "1")
        ridden.tap()
        NewTripTimetableTestSupport.reveal(app.buttons["newTripTimetableBrowse"], in: app)
        app.buttons["newTripTimetableBrowse"].tap()
        XCTAssertTrue(app.navigationBars["Choose a train pattern"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Cancel"].exists)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.tap()
        search.typeText("AZUSA 松本\n")
        let detail = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "timetableDetails-jr-east.azusa")).firstMatch
        NewTripTimetableTestSupport.reveal(detail, in: app, list: app.collectionViews["servicePatternList"])
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Dated multi-term train search"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        detail.tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@", "Japan time")).firstMatch.exists)
        let useDraft = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "timetableUseDraft-jr-east.azusa")).firstMatch
        XCTAssertTrue(useDraft.waitForExistence(timeout: 8))
        useDraft.tap()
        // After import the summary sits just below the fold; scroll onto its Remove button.
        let remove = app.buttons["newTripTimetableRemove"]
        NewTripTimetableTestSupport.reveal(remove, in: app, upward: false)
        XCTAssertTrue(remove.exists, app.debugDescription)
        let applied = app.descendants(matching: .any)["newTripTimetableApplied"]
        XCTAssertTrue(applied.exists, app.debugDescription)
        XCTAssertTrue(applied.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@", "あずさ")).firstMatch.exists,
                      "The applied summary must name the imported service.")
        let save = app.buttons["newTripSave"]
        XCTAssertTrue(save.exists)
        XCTAssertTrue(save.isEnabled, app.debugDescription)
        // Applying a published draft must leave the new-trip form open for review.
        let journey = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "journeyRow-")).firstMatch
        XCTAssertFalse(journey.exists, "A timetable selection must not save the journey")
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 10))
        XCTAssertTrue(journey.waitForExistence(timeout: 10), app.debugDescription)
        app.terminate()
        app.uiTestLaunch[.sheet] = ""
        app.uiTestLaunch[.tab] = "passport"
        UITestLaunchSupport.launch(app)
        let debug = app.descendants(matching: .any)["statisticsDebug"].firstMatch
        XCTAssertTrue(debug.waitForExistence(timeout: 30))
        XCTAssertTrue((debug.value as? String ?? "").hasPrefix("journeys=0;"),
                      "An explicitly unridden timetable draft must stay outside Passport after reload.")
    }

    func testCancellingLocalDateSearchKeepsDepartureDateUnchanged() {
        let app = NewTripTimetableTestSupport.launch()
        NewTripTimetableTestSupport.setDeparture(month: "September", day: 30, year: 2026, in: app)
        let departure = app.textFields["newTripDepartureDate"]
        NewTripTimetableTestSupport.reveal(departure, in: app)
        let originalDate = departure.value as? String
        XCTAssertNotNil(originalDate)
        // The timetable browser is in the one Fill in trip details sheet.
        NewTripTimetableTestSupport.reveal(app.buttons["newTripFillDetails"], in: app)
        app.buttons["newTripFillDetails"].tap()
        XCTAssertTrue(app.buttons["newTripTimetableBrowse"].waitForExistence(timeout: 8))
        app.buttons["newTripTimetableBrowse"].tap()
        let dateEditor = app.descendants(matching: .any)["servicePatternDateEditor"].firstMatch
        XCTAssertTrue(dateEditor.waitForExistence(timeout: 8))
        dateEditor.tap()
        let date = app.textFields["servicePatternDateInput"]
        XCTAssertTrue(date.waitForExistence(timeout: 8), app.debugDescription)
        date.tap()
        let old = date.value as? String ?? ""
        date.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + "2026-10-12\n")
        app.buttons["Cancel"].tap()
        NewTripTimetableTestSupport.reveal(departure, in: app)
        XCTAssertEqual(departure.value as? String, originalDate)
        NewTripTimetableTestSupport.reveal(app.buttons["newTripTimetableBrowse"], in: app)
        XCTAssertFalse(app.descendants(matching: .any)["newTripTimetableApplied"].firstMatch.exists)
    }
}

/// Shared only by the two new-trip timetable suites.
@MainActor
enum NewTripTimetableTestSupport {
    static func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-interface-language", "en"]
        EditorLaunchSupport.launchNewTrip(app, environment: [:])
        XCTAssertTrue(app.buttons["newTripSave"].waitForExistence(timeout: 40))
        return app
    }

    static func setDeparture(month: String, day: Int, year: Int, in app: XCUIApplication) {
        setDate(month: month, day: day, year: year, field: "newTripDeparture", in: app)
    }

    static func setArrival(month: String, day: Int, year: Int, in app: XCUIApplication) {
        setDate(month: month, day: day, year: year, field: "newTripArrival", in: app)
    }

    /// The editor's date and time are typed (TypedDateTimeField); the
    /// calendar stays behind the field's calendar button.
    static func setTime(hour: Int, minute: Int, field: String, in app: XCUIApplication) {
        type(String(format: "%d:%02d", hour, minute), into: "\(field)Time", in: app)
    }

    private static func setDate(
        month: String, day: Int, year: Int, field: String, in app: XCUIApplication
    ) {
        let months = ["January", "February", "March", "April", "May", "June", "July",
                      "August", "September", "October", "November", "December"]
        let number = (months.firstIndex(of: month) ?? 0) + 1
        type(String(format: "%04d-%02d-%02d", year, number, day), into: "\(field)Date", in: app)
    }

    private static func type(_ value: String, into identifier: String, in app: XCUIApplication) {
        let text = app.textFields[identifier]
        reveal(text, in: app)
        XCTAssertTrue(text.waitForExistence(timeout: 8), app.debugDescription)
        // The field is right-aligned: tap its trailing edge so the cursor is at the end.
        text.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        if let current = text.value as? String, !current.isEmpty, current != text.placeholderValue {
            text.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2))
        }
        text.typeText(value + "\n")
        XCTAssertEqual(text.value as? String, value, app.debugDescription)
    }

    static func reveal(
        _ element: XCUIElement, in app: XCUIApplication,
        list: XCUIElement? = nil, upward: Bool = false
    ) {
        // Save sits in the header, outside the form, so a "containing save"
        // query never matches. A downward swipe from the sheet's top also
        // collapses the sheet to a bottom detent and hides the summary.
        var searchUp = upward
        var streak = 0
        let deadline = Date().addingTimeInterval(22)
        while Date() < deadline {
            expandSheetIfNeeded(in: app)
            if element.exists {
                let frame = element.frame
                let band = app.frame.insetBy(dx: 0, dy: 90)
                if frame.width > 1, frame.height > 1, band.contains(frame) { return }
                // A large drag past the end bounces back. When the row is only
                // just off the fold, nudge a short distance toward it.
                let justOff = frame.midY < app.frame.maxY + 80 && frame.midY > app.frame.maxY - 40
                    || frame.midY > -40 && frame.midY < 140
                searchUp = frame.midY < app.frame.midY
                nudge(in: app, list: list, up: searchUp, span: justOff ? 0.12 : 0.40)
                streak = 0
                continue
            } else if streak >= 6 {
                searchUp.toggle()
                streak = 0
            }
            nudge(in: app, list: list, up: searchUp, span: 0.40)
            streak += 1
        }
        XCTAssertTrue(element.exists, app.debugDescription)
    }

    /// The new-trip sheet can rest in a short bottom detent. Drag its header
    /// up before scrolling, or the form is only a couple of rows tall.
    private static func expandSheetIfNeeded(in app: XCUIApplication) {
        let save = app.buttons["newTripSave"]
        guard save.exists, save.frame.minY > 180 else { return }
        let handle = app.coordinate(withNormalizedOffset: CGVector(
            dx: 0.5, dy: max(0.1, (save.frame.midY - 8) / app.frame.height)))
        handle.press(forDuration: 0.05,
                     thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)))
    }

    private static func nudge(in app: XCUIApplication, list: XCUIElement?, up: Bool, span: CGFloat) {
        let form = tallestList(in: app, preferred: list)
        guard form.exists, form.frame.height > 80 else { return }
        // Stay inside the list. A swipe that starts on the sheet edge resizes it.
        let travel = min(0.40, max(0.10, span))
        let startY: CGFloat = up ? 0.42 : 0.78
        let endY: CGFloat = up ? 0.42 + travel : 0.78 - travel
        let start = form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
        let end = form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: endY))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private static func tallestList(in app: XCUIApplication, preferred: XCUIElement?) -> XCUIElement {
        if let preferred, preferred.exists, preferred.frame.height > 160 { return preferred }
        // A dismissing service-pattern sheet drops out of the collection-view
        // query mid-snapshot. `allElementsBoundByIndex` then faults on the
        // missing index. Ignore that list and scroll the new-trip form.
        let forms = app.collectionViews.matching(
            NSPredicate(format: "identifier != %@", "servicePatternList"))
        if forms.count > 1 {
            let first = forms.element(boundBy: 0)
            let second = forms.element(boundBy: 1)
            if first.exists, second.exists, second.frame.height > first.frame.height {
                return second
            }
            if first.exists { return first }
        }
        return forms.firstMatch.exists ? forms.firstMatch : app.collectionViews.firstMatch
    }
}
