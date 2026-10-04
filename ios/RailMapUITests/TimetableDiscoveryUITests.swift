import XCTest

@MainActor
final class TimetableDiscoveryUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testDatedEnglishSearchImportsPublishedDraftAndSavesOnlyAfterReview() {
        let app = NewTripTimetableTestSupport.launch()
        NewTripTimetableTestSupport.setDeparture(month: "September", day: 30, year: 2026, in: app)
        NewTripTimetableTestSupport.reveal(app.buttons["newTripTimetableBrowse"], in: app)
        app.buttons["newTripTimetableBrowse"].tap()
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
    }

    func testCancellingLocalDateSearchKeepsDepartureDateUnchanged() {
        let app = NewTripTimetableTestSupport.launch()
        NewTripTimetableTestSupport.setDeparture(month: "September", day: 30, year: 2026, in: app)
        let departure = app.datePickers["newTripDeparture"]
        NewTripTimetableTestSupport.reveal(departure, in: app)
        let originalDate = departure.value as? String
        XCTAssertNotNil(originalDate)
        NewTripTimetableTestSupport.reveal(app.buttons["newTripTimetableBrowse"], in: app)
        app.buttons["newTripTimetableBrowse"].tap()
        let dateEditor = app.descendants(matching: .any)["servicePatternDateEditor"].firstMatch
        XCTAssertTrue(dateEditor.waitForExistence(timeout: 8))
        dateEditor.tap()
        let date = app.textFields["servicePatternDateInput"]
        XCTAssertTrue(date.waitForExistence(timeout: 8), app.debugDescription)
        date.tap()
        let old = date.value as? String ?? ""
        date.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + "2026-10-12\n")
        app.buttons["キャンセル"].tap()
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

    static func setTime(hour: Int, minute: Int, field: String, in app: XCUIApplication) {
        let picker = app.datePickers[field]
        reveal(picker, in: app)
        let clock = picker.buttons.matching(NSPredicate(
            format: "label MATCHES %@", "[0-9]{1,2}:[0-9]{2}")).firstMatch
        XCTAssertTrue(clock.waitForExistence(timeout: 3), app.debugDescription)
        clock.tap()
        XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: 8), app.debugDescription)
        app.pickerWheels.element(boundBy: 0).adjust(toPickerWheelValue: String(format: "%02d", hour))
        app.pickerWheels.element(boundBy: 1).adjust(toPickerWheelValue: String(format: "%02d", minute))
        let dismiss = app.buttons["PopoverDismissRegion"]
        if dismiss.waitForExistence(timeout: 2) { dismiss.tap() }
        XCTAssertTrue(picker.buttons[String(format: "%02d:%02d", hour, minute)].exists,
                      app.debugDescription)
    }

    private static func setDate(
        month: String, day: Int, year: Int, field: String, in app: XCUIApplication
    ) {
        let departure = app.datePickers[field]
        reveal(departure, in: app)
        // Compact style shows one "Date and Time Picker" button. Tapping it opens
        // a calendar whose month control is DatePicker.Show (value "October 2026"),
        // not a button labeled with the month and year.
        let opener = departure.buttons.firstMatch
        if opener.waitForExistence(timeout: 3) { opener.tap() } else { departure.tap() }
        let show = app.buttons["DatePicker.Show"]
        XCTAssertTrue(show.waitForExistence(timeout: 8), app.debugDescription)
        let shown = (show.value as? String) ?? ""
        if !shown.contains(month) || !shown.contains(String(year)) {
            show.tap()
            XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: 8), app.debugDescription)
            app.pickerWheels.element(boundBy: 0).adjust(toPickerWheelValue: month)
            app.pickerWheels.element(boundBy: 1).adjust(toPickerWheelValue: String(year))
            // Showing the wheels replaces DatePicker.Show with DatePicker.Hide.
            let hide = app.buttons["DatePicker.Hide"]
            if hide.waitForExistence(timeout: 3) {
                hide.tap()
            } else if show.exists {
                show.tap()
            }
        }
        let dayButton = app.buttons.matching(NSPredicate(
            format: "label MATCHES %@",
            ".*\\b\(month)\\b.*\\b\(day)\\b.*")).firstMatch
        XCTAssertTrue(dayButton.waitForExistence(timeout: 8), app.debugDescription)
        dayButton.tap()
        let dismiss = app.buttons["PopoverDismissRegion"]
        if dismiss.waitForExistence(timeout: 2) { dismiss.tap() }
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
