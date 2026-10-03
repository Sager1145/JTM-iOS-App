import XCTest

@MainActor
final class TrainServicePatternUITests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        await MainActor.run {
            XCUIDevice.shared.orientation = .portrait
        }
    }

    func testPartialExactTripShowsSourceTimesWithoutOfferingRouteApplication() {
        let app = XCUIApplication()
        app.launchEnvironment["RAILMAP_UI_TEST_STORAGE_ID"] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "all"
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "expanded"
        app.launchEnvironment["RAILMAP_UI_TEST_SHEET"] = "new"
        app.launch()

        let next = app.buttons["rideEditorNext"]
        XCTAssertTrue(next.waitForExistence(timeout: 30))
        next.tap()
        EditorUITestSupport.tap(app.buttons["rideEditorServicePattern"], in: app)
        let initialSearch = app.searchFields.firstMatch
        XCTAssertTrue(initialSearch.waitForExistence(timeout: 8))
        initialSearch.tap()
        initialSearch.typeText("はちおうじ")
        let legacy = app.buttons.matching(NSPredicate(
            format: "label CONTAINS %@", "東京〜八王子")).firstMatch
        XCTAssertTrue(legacy.waitForExistence(timeout: 8))
        legacy.tap()
        next.tap()
        next.tap()
        EditorUITestSupport.enableDate(in: app)
        let date = app.textFields["rideEditorDateInput"]
        XCTAssertTrue(date.waitForExistence(timeout: 8))
        let oldValue = date.value as? String ?? ""
        date.tap()
        date.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,
                             count: oldValue.count) + "2026-09-27")
        app.buttons["rideEditorPrevious"].tap()
        XCTAssertTrue(app.otherElements["rideEditorNumber"].textFields.firstMatch
            .waitForExistence(timeout: 8))
        app.buttons["rideEditorPrevious"].tap()
        let picker = app.buttons["rideEditorServicePattern"]
        for _ in 0..<6 where !picker.exists { app.collectionViews.firstMatch.swipeDown() }
        XCTAssertTrue(picker.waitForExistence(timeout: 8), app.debugDescription)
        picker.tap()
        let replaceStops = app.buttons["rideEditorReplaceStops"].firstMatch
        XCTAssertTrue(replaceStops.waitForExistence(timeout: 8), app.debugDescription)
        replaceStops.tap()
        let exactSearch = app.searchFields.firstMatch
        XCTAssertTrue(exactSearch.waitForExistence(timeout: 8))
        exactSearch.tap()
        exactSearch.typeText("しなの\n")

        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@",
                                  "timetableIncompleteTrip-jr-central.shinano.1.")).firstMatch
        for _ in 0..<10 {
            if row.waitForExistence(timeout: 1) { break }
            let list = app.collectionViews.firstMatch
            list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                .press(forDuration: 0.1, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        }
        XCTAssertTrue(row.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(row.label.contains("07:00"))
        XCTAssertTrue(row.label.contains("名古屋"))
        XCTAssertTrue(row.label.contains("未確認"))
        XCTAssertEqual(app.buttons.matching(identifier: row.identifier).count, 0,
                       "Unverified route facts must remain read-only.")
        let details = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "timetableDetails-jr-central.shinano.1.")).firstMatch
        XCTAssertTrue(details.waitForExistence(timeout: 8))
        // The floating search bar can cover a row while XCTest still reports it hittable.
        for _ in 0..<8 {
            if details.isHittable && details.frame.maxY < app.frame.maxY - 120 { break }
            app.collectionViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(details.isHittable, app.debugDescription)
        details.tap()
        let originTime = app.descendants(matching: .any)
            .matching(identifier: "timetableStop-1").firstMatch
        XCTAssertTrue(originTime.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(originTime.label.contains("名古屋"))
        XCTAssertTrue(originTime.label.contains("07:00"))
        XCTAssertTrue(originTime.label.contains("掲載なし"),
                      "Missing source arrival time must not become a made-up 00:00.")
    }

    func testSelectedPatternRechecksChangedDateWithoutReplacingStops() {
        let app = XCUIApplication()
        app.launchEnvironment["RAILMAP_UI_TEST_STORAGE_ID"] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "all"
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "expanded"
        app.launchEnvironment["RAILMAP_UI_TEST_SHEET"] = "new"
        app.launch()

        let next = app.buttons["rideEditorNext"]
        XCTAssertTrue(next.waitForExistence(timeout: 30))
        next.tap()

        let picker = app.buttons["rideEditorServicePattern"]
        XCTAssertTrue(EditorUITestSupport.reveal(picker, in: app), app.debugDescription)
        XCTAssertTrue(picker.waitForExistence(timeout: 8))
        picker.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.tap()
        search.typeText("はちおうじ")
        let pattern = app.buttons.matching(NSPredicate(
            format: "label CONTAINS %@", "東京〜八王子")).firstMatch
        XCTAssertTrue(pattern.waitForExistence(timeout: 8))
        pattern.tap()

        let origin = app.descendants(matching: .any)["rideEditorStop-0"].firstMatch
        XCTAssertTrue(origin.waitForExistence(timeout: 8))
        XCTAssertTrue(origin.label.contains("東京"))
        origin.tap()

        let departure = app.textFields["rideEditorStopDeparture"]
        XCTAssertTrue(departure.waitForExistence(timeout: 8))
        departure.tap()
        departure.typeText("07:15")
        let ridden = app.switches["rideEditorStopRidden"]
        for _ in 0..<8 where !ridden.exists { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(ridden.waitForExistence(timeout: 8))
        ridden.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()

        next.tap()
        let number = app.otherElements["rideEditorNumber"].textFields.firstMatch
        XCTAssertTrue(number.waitForExistence(timeout: 8))
        next.tap()

        let includeDate = app.switches["Include a date"]
        XCTAssertTrue(includeDate.waitForExistence(timeout: 8))
        includeDate.switches.firstMatch.tap()
        let date = app.textFields["rideEditorDateInput"]
        XCTAssertTrue(date.waitForExistence(timeout: 8))
        let oldValue = date.value as? String ?? ""
        date.tap()
        date.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,
                             count: oldValue.count) + "2026-10-12")
        XCTAssertEqual(date.value as? String, "2026-10-12")
        let notice = app.descendants(matching: .any)["rideEditorPatternDateNotice"]
        // The keyboard covers a screen-wide swipe's start point; scroll
        // the editor form so its date notice is actually materialized.
        let dateForm = app.collectionViews["rideEditorForm"]
        for _ in 0..<10 where !notice.exists {
            dateForm.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
                .press(forDuration: 0.1, thenDragTo: dateForm.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)))
        }
        XCTAssertTrue(notice.waitForExistence(timeout: 8), app.debugDescription)

        app.buttons["rideEditorPrevious"].tap()
        // Each step replaces the form contents. Wait for the intermediate
        // service step before asking its newly rendered Previous button to
        // move again; two immediate taps can both target the outgoing button.
        let numberAfterDate = app.otherElements["rideEditorNumber"].textFields.firstMatch
        XCTAssertTrue(numberAfterDate.waitForExistence(timeout: 8))
        app.buttons["rideEditorPrevious"].tap()

        // Re-query after the route step is rebuilt instead of retaining the
        // element proxy resolved before the intervening service/date views.
        let originAfter = app.buttons["rideEditorStop-0"]
        XCTAssertTrue(originAfter.waitForExistence(timeout: 8))
        XCTAssertTrue(originAfter.label.contains("東京"),
                      "Changing the ride date must not rewrite selected stops.")
        originAfter.tap()
        let departureAfter = app.textFields["rideEditorStopDeparture"]
        for _ in 0..<8 where !departureAfter.exists { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(departureAfter.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertEqual((departureAfter.value as? String)?.split(separator: ":")
            .compactMap { Int($0) }, [7, 15],
            "Changing the date must preserve the edited departure time.")
        let riddenAfter = app.switches["rideEditorStopRidden"]
        for _ in 0..<8 where !riddenAfter.exists { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(riddenAfter.waitForExistence(timeout: 8))
        XCTAssertNotEqual(riddenAfter.value as? String, "1",
                          "A reader-cleared ride segment must survive the date change.")
    }
}
