import RailPresentation
import XCTest

/// Only the date is required: a trip saved with just a day keeps both clock
/// boxes empty when it is opened again, and a clock the reader emptied stays
/// empty.
@MainActor
final class DateOnlyUITests: XCTestCase {
    private let departureTime = "newTripDepartureTime"
    private let arrivalTime = "newTripArrivalTime"

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testADateOnlyTripReopensWithBothClocksEmpty() {
        let app = NewTripTimetableTestSupport.launch()
        defer { app.terminate() }
        NewTripTimetableTestSupport.setDeparture(month: "January", day: 1, year: 2024, in: app)
        assertEmpty(departureTime, in: app, "A new trip starts with no departure clock.")
        assertEmpty(arrivalTime, in: app, "A new trip starts with no arrival clock.")

        saveShinagawaToOsaki(in: app)
        reopenFirstTrip(app)

        let date = app.textFields["newTripDepartureDate"]
        NewTripTimetableTestSupport.reveal(date, in: app)
        XCTAssertEqual(date.value as? String, "2024-01-01")
        assertEmpty(departureTime, in: app, "A date-only trip must not gain a departure clock.")
        assertEmpty(arrivalTime, in: app, "A date-only trip must not gain an arrival clock.")
    }

    func testAClockEmptiedOnReturnStaysEmptyAfterSaving() {
        let app = NewTripTimetableTestSupport.launch()
        defer { app.terminate() }
        NewTripTimetableTestSupport.setDeparture(month: "January", day: 1, year: 2024, in: app)
        NewTripTimetableTestSupport.setTime(hour: 9, minute: 30, field: "newTripDeparture", in: app)
        XCTAssertEqual(app.textFields[departureTime].value as? String, "9:30")

        let box = app.textFields[departureTime]
        box.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        box.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6) + "\n")
        let returnKey = app.keyboards.buttons["return"].firstMatch
        if returnKey.exists, returnKey.isHittable { returnKey.tap() }
        _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 3)
        assertEmpty(departureTime, in: app, "Emptying the box on Return unsets the clock.")

        saveShinagawaToOsaki(in: app)
        reopenFirstTrip(app)

        let date = app.textFields["newTripDepartureDate"]
        NewTripTimetableTestSupport.reveal(date, in: app)
        XCTAssertEqual(date.value as? String, "2024-01-01", "The emptied clock's day still counts.")
        assertEmpty(departureTime, in: app, "The emptied clock must stay empty after reopening.")
    }

    // MARK: - steps

    private func saveShinagawaToOsaki(in app: XCUIApplication) {
        pickStation(field: "newTripOrigin", query: "品川", code: "004095",
                    lineID: "jp-東日本旅客鉄道-山手線", in: app)
        pickStation(field: "newTripDestination", query: "大崎", code: "004135",
                    lineID: "jp-東日本旅客鉄道-山手線", in: app)
        let save = app.buttons["newTripSave"]
        XCTAssertTrue(waitUntilSavable(save, in: app), "Save must enable once the route is planned.")
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 20))
        // The store write is asynchronous: give it the window a reader spends
        // looking at the saved list before the relaunch proves the disk state.
        Thread.sleep(forTimeInterval: 1)
    }

    /// Relaunches on the same isolated store and opens its first trip in the editor.
    private func reopenFirstTrip(_ app: XCUIApplication) {
        app.terminate()
        app.uiTestLaunch[.sheet] = "edit"
        app.uiTestLaunch[.tab] = "all"
        UITestLaunchSupport.launch(app)
        XCTAssertTrue(app.buttons["newTripSave"].waitForExistence(timeout: 60),
                      "The saved trip must open in the editor.")
    }

    private func assertEmpty(_ identifier: String, in app: XCUIApplication, _ message: String) {
        let box = app.textFields[identifier]
        NewTripTimetableTestSupport.reveal(box, in: app)
        XCTAssertTrue(box.waitForExistence(timeout: 8), app.debugDescription)
        let isEmpty = {
            let value = box.value as? String ?? ""
            return value.isEmpty || value == box.placeholderValue
        }
        let deadline = Date().addingTimeInterval(5)
        while !isEmpty(), Date() < deadline { Thread.sleep(forTimeInterval: 0.25) }
        XCTAssertTrue(isEmpty(), "\(message) Shows: \(box.value as? String ?? "nil")")
    }

    // MARK: - station picking and saving (as JourneySaveUITests)

    private func pickStation(
        field: String, query: String, code: String, lineID: String, in app: XCUIApplication
    ) {
        let button = app.buttons[field]
        // An earlier check may have scrolled the stations off the top.
        if !button.waitForExistence(timeout: 2) {
            NewTripTimetableTestSupport.reveal(button, in: app, upward: true)
        }
        XCTAssertTrue(button.waitForExistence(timeout: 20))
        XCTAssertTrue(waitForEnabled(button, timeout: 20))
        button.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 20))
        search.tap()
        search.typeText(query)
        let row = app.buttons["newTripStation-\(lineID)-\(code)"]
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'newTripStation-'"))
            .firstMatch.waitForExistence(timeout: 20), "\(query) must list station rows.")
        var swipes = 0
        while !row.waitForExistence(timeout: swipes == 0 ? 3 : 0.5), swipes < 40 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
                .press(forDuration: 0.05,
                       thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)))
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

    private func dismissSearchKeyboard(in app: XCUIApplication) {
        let keyboard = app.keyboards.firstMatch
        guard keyboard.exists else { return }
        for label in ["Search", "検索"] {
            let key = keyboard.buttons[label]
            if key.exists, key.isHittable {
                key.tap()
                break
            }
        }
        _ = keyboard.waitForNonExistence(timeout: 2)
    }

    @discardableResult
    private func waitForEnabled(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let enabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"), object: element)
        return XCTWaiter.wait(for: [enabled], timeout: timeout) == .completed
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
