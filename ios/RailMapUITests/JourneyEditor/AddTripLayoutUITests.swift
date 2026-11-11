import RailPresentation
import XCTest

/// The add-trip form's compact layout: quick fill first, the ticket scan one
/// tap away, and the rolling-stock and ticket fields entered on single rows.
@MainActor
final class AddTripLayoutUITests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testDisabledSaveShowsItsReasonWithoutScrolling() {
        let app = XCUIApplication()
        EditorLaunchSupport.launchNewTrip(app)
        let save = app.buttons["newTripSave"]
        XCTAssertTrue(save.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(save.isEnabled)
        let status = app.descendants(matching: .any)["newTripSaveStatus"].firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 5), "A disabled Save must say what is missing.")
        XCTAssertTrue(status.isHittable, "The reason sits under the navigation bar, not below the fold.")
    }

    func testStationPickerOpensWithTheCursorInTheSearchField() {
        let app = XCUIApplication()
        EditorLaunchSupport.launchNewTrip(app)
        let origin = app.buttons["newTripOrigin"]
        XCTAssertTrue(origin.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(waitHittable(origin))
        origin.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 8),
                      "An empty station field opens its picker ready to type.")
    }

    func testQuickFillLeadsTheFormAndScanOpensCameraOrPhotos() {
        let app = XCUIApplication()
        EditorLaunchSupport.launchNewTrip(app)
        let scan = app.buttons["newTripScanTicket"]
        let find = app.buttons["newTripFillDetails"]
        let origin = app.buttons["newTripOrigin"]
        XCTAssertTrue(scan.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(find.exists)
        XCTAssertTrue(origin.waitForExistence(timeout: 5))
        XCTAssertLessThan(scan.frame.minY, origin.frame.minY, "Quick fill comes before the stations.")
        // Swap is drawn between From and To, next to both stations it swaps.
        let swap = app.buttons["newTripSwap"]
        let destination = app.buttons["newTripDestination"]
        XCTAssertTrue(swap.exists)
        XCTAssertTrue(destination.exists)
        XCTAssertGreaterThan(swap.frame.midY, origin.frame.midY)
        XCTAssertLessThan(swap.frame.midY, destination.frame.midY)

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "add-trip-quick-fill"
        shot.lifetime = .keepAlways
        add(shot)

        XCTAssertTrue(waitHittable(scan))
        scan.tap()
        let photos = app.buttons["ticketScanPhotos"]
        XCTAssertTrue(photos.waitForExistence(timeout: 8), app.debugDescription)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(photos.waitForNonExistence(timeout: 8))
        XCTAssertTrue(scan.waitForExistence(timeout: 5))
    }

    func testVehicleAndTicketFieldsTakeTypedValues() {
        let app = XCUIApplication()
        EditorLaunchSupport.launchNewTrip(app)
        XCTAssertTrue(app.buttons["newTripSave"].waitForExistence(timeout: 20))

        // Each value is read while its row is on screen: the Form unmounts rows it scrolls past.
        type("N700", into: app.textFields["newTripSetNumber"], in: app)
        XCTAssertEqual(app.textFields["newTripSetNumber"].value as? String, "N700")
        type("16", into: app.textFields["newTripCarCount"], in: app, returns: false)
        XCTAssertEqual(app.textFields["newTripCarCount"].value as? String, "16")
        type("7", into: app.textFields["newTripRiddenCar"], in: app, returns: false)
        type("14720", into: app.textFields["newTripFare"], in: app, returns: false)
        XCTAssertEqual(app.textFields["newTripFare"].value as? String, "14720")
        XCTAssertTrue(app.staticTexts["JPY"].exists, "A Japanese fare is in yen.")
        type("12A", into: app.textFields["newTripSeat"], in: app)

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "add-trip-vehicle-and-ticket"
        shot.lifetime = .keepAlways
        add(shot)

        // Car numbers list one row per car of the set.
        let cars = app.descendants(matching: .any)["newTripCarNumbers"].firstMatch
        // Car numbers are in the section above the ticket fields just typed.
        XCTAssertTrue(EditorUITestSupport.reveal(cars, in: app, unmountedRowIsAbove: true))
        cars.tap()
        let first = app.textFields["newTripCarNumber-1"]
        XCTAssertTrue(first.waitForExistence(timeout: 8), app.debugDescription)
        first.tap()
        first.typeText("783-2001\n")
        XCTAssertEqual(first.value as? String, "783-2001")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(cars.waitForExistence(timeout: 8))
        XCTAssertTrue(cars.label.contains("783-2001"), cars.label)
    }

    /// One scan fills stations, service, time, car, seat and fare at once;
    /// each value stays editable and is tagged with its source.
    func testTicketScanFillsTheFormInOneShot() {
        let app = XCUIApplication()
        EditorLaunchSupport.launchNewTrip(app, environment: [
            UITestLaunchConfiguration.Key.ticket.rawValue:
                "東京 → 新大阪|乗車券・新幹線特急券(指定席)|のぞみ 25号|2026年11月6日(金)|10:30発 12:55着"
                + "|5号車 12番A席|普通車指定席|合計 ¥14,720",
        ])
        let filled = app.descendants(matching: .any)["newTripTicketFilled"].firstMatch
        XCTAssertTrue(filled.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(filled.label.contains("from the ticket"), filled.label)
        let origin = app.buttons["newTripOrigin"]
        XCTAssertTrue(EditorUITestSupport.reveal(origin, in: app, unmountedRowIsAbove: false))
        XCTAssertTrue(origin.label.contains("東京"), origin.label)
        let destination = app.buttons["newTripDestination"]
        XCTAssertTrue(EditorUITestSupport.reveal(destination, in: app, unmountedRowIsAbove: false))
        XCTAssertTrue(destination.label.contains("新大阪"), destination.label)

        // An actual departure is the reader's own, shown against the ticket's 10:30.
        let addActual = app.buttons["newTripAddActualTimes"]
        XCTAssertTrue(EditorUITestSupport.reveal(addActual, in: app, unmountedRowIsAbove: false))
        addActual.tap()
        let actual = app.textFields["newTripActualDeparture"]
        XCTAssertTrue(actual.waitForExistence(timeout: 5))
        XCTAssertTrue(EditorUITestSupport.reveal(actual, in: app, unmountedRowIsAbove: false))
        actual.tap()
        actual.typeText("10:35\n")
        let status = app.staticTexts["newTripActualDepartureStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(status.label, "5 min late")
        let actualShot = XCTAttachment(screenshot: app.screenshot())
        actualShot.name = "add-trip-actual-times"
        actualShot.lifetime = .keepAlways
        add(actualShot)

        let number = app.textFields["newTripNumber"]
        XCTAssertTrue(EditorUITestSupport.reveal(number, in: app, unmountedRowIsAbove: false))
        XCTAssertEqual(number.value as? String, "のぞみ25号")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "add-trip-ticket-filled-service"
        shot.lifetime = .keepAlways
        add(shot)

        let seat = app.textFields["newTripSeat"]
        XCTAssertTrue(EditorUITestSupport.reveal(seat, in: app, maxDrags: 14, unmountedRowIsAbove: false))
        XCTAssertEqual(seat.value as? String, "12A")
        let fare = app.textFields["newTripFare"]
        XCTAssertTrue(EditorUITestSupport.reveal(fare, in: app, maxDrags: 6, unmountedRowIsAbove: false))
        XCTAssertEqual(fare.value as? String, "14720")
        let car = app.textFields["newTripRiddenCar"]
        XCTAssertTrue(EditorUITestSupport.reveal(car, in: app, maxDrags: 6, unmountedRowIsAbove: true))
        XCTAssertEqual(car.value as? String, "5")
        let lower = XCTAttachment(screenshot: app.screenshot())
        lower.name = "add-trip-ticket-filled-vehicle-ticket"
        lower.lifetime = .keepAlways
        add(lower)
    }

    /// A chip sets the actual clock from the ticket's schedule; an early
    /// arrival is typed.
    func testActualTimeChipsFillFromTheTicketAndEarlyIsTyped() {
        let app = XCUIApplication()
        EditorLaunchSupport.launchNewTrip(app, environment: [
            UITestLaunchConfiguration.Key.ticket.rawValue:
                "東京 → 新大阪|乗車券・新幹線特急券(指定席)|のぞみ 25号|2026年11月6日(金)|10:30発 12:55着"
                + "|5号車 12番A席|普通車指定席|合計 ¥14,720",
        ])
        XCTAssertTrue(app.descendants(matching: .any)["newTripTicketFilled"].firstMatch.waitForExistence(timeout: 30))
        let addActual = app.buttons["newTripAddActualTimes"]
        XCTAssertTrue(EditorUITestSupport.reveal(addActual, in: app, unmountedRowIsAbove: false))
        addActual.tap()
        let plus5 = app.buttons["newTripActualDeparturePlus5"]
        XCTAssertTrue(plus5.waitForExistence(timeout: 5))
        XCTAssertTrue(EditorUITestSupport.reveal(plus5, in: app, unmountedRowIsAbove: false))
        plus5.tap()
        let departure = app.textFields["newTripActualDeparture"]
        XCTAssertTrue(departure.waitForExistence(timeout: 5))
        XCTAssertEqual(departure.value as? String, "10:35")
        let status = app.staticTexts["newTripActualDepartureStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(status.label, "5 min late")

        let arrival = app.textFields["newTripActualArrival"]
        XCTAssertTrue(EditorUITestSupport.reveal(arrival, in: app, unmountedRowIsAbove: false))
        arrival.tap()
        arrival.typeText("12:50\n")
        let early = app.staticTexts["newTripActualArrivalStatus"]
        XCTAssertTrue(early.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(early.label.contains("5 min early"), early.label)
    }

    /// Only the date is required: a trip with no time, or only an actual
    /// time, saves. With no scheduled time there is nothing to be late against.
    func testDateOnlyAndActualOnlyTripsSave() {
        let app = XCUIApplication()
        EditorLaunchSupport.launchNewTrip(app)
        pickShinagawaToOsaki(in: app)
        let save = app.buttons["newTripSave"]
        XCTAssertTrue(waitEnabled(save, timeout: 60), "A date-only trip must be savable. \(app.debugDescription)")
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 20), "Save must close the editor.")

        app.terminate()
        EditorLaunchSupport.launchNewTrip(app)
        pickShinagawaToOsaki(in: app)
        let addActual = app.buttons["newTripAddActualTimes"]
        XCTAssertTrue(EditorUITestSupport.reveal(addActual, in: app, unmountedRowIsAbove: false))
        addActual.tap()
        let departure = app.textFields["newTripActualDeparture"]
        XCTAssertTrue(departure.waitForExistence(timeout: 5))
        XCTAssertTrue(EditorUITestSupport.reveal(departure, in: app, unmountedRowIsAbove: false))
        departure.tap()
        departure.typeText("10:07\n")
        XCTAssertFalse(app.staticTexts["newTripActualDepartureStatus"].waitForExistence(timeout: 2),
                       "No scheduled time, so no delay is shown.")
        let saveActual = app.buttons["newTripSave"]
        XCTAssertTrue(waitEnabled(saveActual, timeout: 60), app.debugDescription)
        saveActual.tap()
        XCTAssertTrue(saveActual.waitForNonExistence(timeout: 20), "Save must close the editor.")
    }

    // MARK: - helpers

    private func pickShinagawaToOsaki(in app: XCUIApplication) {
        pickStation(field: "newTripOrigin", query: "品川", code: "004095",
                    lineID: "jp-東日本旅客鉄道-山手線", in: app)
        pickStation(field: "newTripDestination", query: "大崎", code: "004135",
                    lineID: "jp-東日本旅客鉄道-山手線", in: app)
    }

    private func waitEnabled(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let enabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND enabled == true"), object: element)
        return XCTWaiter.wait(for: [enabled], timeout: timeout) == .completed
    }

    /// The station sheet: search, pick the row with this line and code.
    private func pickStation(field: String, query: String, code: String, lineID: String, in app: XCUIApplication) {
        let button = app.buttons[field]
        XCTAssertTrue(EditorUITestSupport.reveal(button, in: app, maxDrags: 12, unmountedRowIsAbove: true),
                      app.debugDescription)
        XCTAssertTrue(waitEnabled(button, timeout: 40), "\(field) stays disabled until the catalog loads.")
        let previous = button.label
        button.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 20))
        search.tap()
        search.typeText(query)
        let row = app.buttons["newTripStation-\(lineID)-\(code)"]
        var swipes = 0
        while !row.waitForExistence(timeout: swipes == 0 ? 10 : 0.5), swipes < 40 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)).press(
                forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)))
            swipes += 1
        }
        XCTAssertTrue(row.exists, "No station row \(lineID)-\(code) for \(query).")
        // A tap while the search keyboard is up only resigns the field.
        if app.keyboards.firstMatch.exists {
            search.typeText("\n")
            _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 2)
        }
        row.tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForNonExistence(timeout: 8),
                      "Choosing \(query) must close station search.")
        let chosen = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", previous), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [chosen], timeout: 8), .completed, button.label)
    }

    /// A number pad has no Return key: the keyboard's Done closes it.
    private func type(_ value: String, into field: XCUIElement, in app: XCUIApplication, returns: Bool = true) {
        XCTAssertTrue(EditorUITestSupport.reveal(field, in: app, maxDrags: 12, unmountedRowIsAbove: false),
                      "\(field) must scroll into the form")
        field.tap()
        if returns {
            field.typeText(value + "\n")
        } else {
            field.typeText(value)
            let done = app.buttons["newTripKeyboardDone"]
            XCTAssertTrue(done.waitForExistence(timeout: 3), "A number pad needs a way to close it.")
            done.tap()
        }
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
    }

    private func waitHittable(_ element: XCUIElement) -> Bool {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if element.exists, element.isHittable { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }
}
