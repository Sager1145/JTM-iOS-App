import XCTest

@MainActor
final class TimetableQuickMatchUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testAutomaticLookupClearsResultsAfterDateAndServiceChanges() {
        let app = NewTripTimetableTestSupport.launch()
        // 北斗 1's published draft in the old test supplied these endpoints.
        // "函館" also matches the 函館市 tram operator, whose sections sort above 函館線.
        chooseStation("函館", code: "000455", field: "newTripOrigin",
                      lineID: "jp-北海道旅客鉄道-函館線", in: app)
        chooseStation("札幌", code: "000227", field: "newTripDestination",
                      lineID: "jp-北海道旅客鉄道-函館線", in: app)
        NewTripTimetableTestSupport.setDeparture(month: "September", day: 30, year: 2026, in: app)
        // Bundled hokuto.1.exact-2026-09-30: 函館 06:02 → 札幌 09:47.
        // Quick matching requires exact endpoint minutes on the same service day.
        NewTripTimetableTestSupport.setArrival(month: "September", day: 30, year: 2026, in: app)
        NewTripTimetableTestSupport.setTime(hour: 6, minute: 2, field: "newTripDeparture", in: app)
        NewTripTimetableTestSupport.setTime(hour: 9, minute: 47, field: "newTripArrival", in: app)
        replaceServiceName(with: "北斗", in: app)

        let matches = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "rideEditorTimetableMatch-jr-hokkaido.hokuto.1."))
        showLookup(in: app)
        XCTAssertTrue(matches.firstMatch.waitForExistence(timeout: 30), app.debugDescription)
        NewTripTimetableTestSupport.setDeparture(month: "January", day: 1, year: 1900, in: app)
        NewTripTimetableTestSupport.setDeparture(month: "September", day: 30, year: 2026, in: app)
        NewTripTimetableTestSupport.setDeparture(month: "January", day: 1, year: 1900, in: app)
        // Keep a same-day trip while changing the service date; leaving arrival
        // in 2026 produces an unparseable 126-year clock, disabling lookup.
        NewTripTimetableTestSupport.setArrival(month: "January", day: 1, year: 1900, in: app)
        showLookup(in: app)
        XCTAssertTrue(matches.firstMatch.waitForNonExistence(timeout: 15))
        let noMatch = app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@", "No train matches both endpoint stations")).firstMatch
        XCTAssertTrue(noMatch.waitForExistence(timeout: 15), app.debugDescription)
        // Move arrival first so advancing departure cannot clamp its 09:47 clock.
        NewTripTimetableTestSupport.setArrival(month: "September", day: 30, year: 2026, in: app)
        NewTripTimetableTestSupport.setDeparture(month: "September", day: 30, year: 2026, in: app)
        showLookup(in: app)
        XCTAssertTrue(matches.firstMatch.waitForExistence(timeout: 30))

        replaceServiceName(with: "No matching service", in: app)
        showLookup(in: app)
        XCTAssertTrue(noMatch.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(matches.firstMatch.exists)
        replaceServiceName(with: "北斗", in: app)
        showLookup(in: app)
        XCTAssertTrue(matches.firstMatch.waitForExistence(timeout: 30))
    }

    private func chooseStation(
        _ name: String, code: String, field: String, lineID: String, in app: XCUIApplication
    ) {
        let button = app.buttons[field]
        NewTripTimetableTestSupport.reveal(button, in: app)
        XCTAssertTrue(button.isEnabled)
        button.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.tap()
        search.typeText(name)
        let station = app.buttons["newTripStation-\(lineID)-\(code)"]
        var swipes = 0
        while !station.waitForExistence(timeout: swipes == 0 ? 3 : 0.4), swipes < 20 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(station.exists, "No newTripStation-\(lineID)-\(code) for \(name). \(app.debugDescription)")
        station.tap()
        XCTAssertTrue(search.waitForNonExistence(timeout: 8))
    }

    private func replaceServiceName(with value: String, in app: XCUIApplication) {
        let name = app.textFields["newTripLimitedExpressName"]
        NewTripTimetableTestSupport.reveal(name, in: app)
        name.tap()
        let old = name.value as? String ?? ""
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + value + "\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 8))
    }

    private func showLookup(in app: XCUIApplication) {
        NewTripTimetableTestSupport.reveal(app.buttons["rideEditorTimetableMatch"], in: app)
    }
}
