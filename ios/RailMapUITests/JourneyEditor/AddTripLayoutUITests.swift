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
        // Swap shares From's row instead of taking its own.
        let swap = app.buttons["newTripSwap"]
        XCTAssertTrue(swap.exists)
        XCTAssertLessThan(abs(swap.frame.midY - origin.frame.midY), origin.frame.height)

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

    // MARK: - helpers

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
