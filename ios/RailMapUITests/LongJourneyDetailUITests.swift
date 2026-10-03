import XCTest

@MainActor
final class LongJourneyDetailUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testLongJourneyCardOpensScrollsAndCloses() {
        assertResponsiveDetail(mode: "card", closeID: "journeyBackToList")
    }

    func testLongJourneyInformationOpensScrollsAndCloses() {
        assertResponsiveDetail(mode: "detail", closeID: "longJourneyClose")
    }

    func testLargeAdvancedSectionListExpandsWithoutRenderingEverySection() {
        let app = launch(mode: "advanced")
        let toggle = app.descendants(matching: .any)["rideDetailAdvancedToggle"].firstMatch
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 30))
        for _ in 0..<6 where !toggle.isHittable { scroll.swipeUp() }
        XCTAssertTrue(toggle.isHittable)
        toggle.tap()
        let first = app.staticTexts["rideDetailSection-0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        let sections = app.staticTexts.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "rideDetailSection-"))
        XCTAssertLessThan(sections.count, 128)
        scroll.swipeUp()
        app.buttons["longJourneyClose"].tap()
        XCTAssertTrue(app.staticTexts["longJourneyClosed"].waitForExistence(timeout: 5))
    }

    func testStationSpellingEditRebuildsDetailWithoutChangingJourneyID() {
        let app = launch(mode: "update")
        let first = app.descendants(matching: .any)["rideDetailStop-0"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 30))
        XCTAssertTrue(first.label.contains("Original line"))
        app.buttons["longJourneyUpdate"].tap()
        let refreshed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            first.exists && !first.label.contains("Original line")
        }, object: first)
        XCTAssertEqual(XCTWaiter.wait(for: [refreshed], timeout: 8), .completed,
                       "A spelling edit must re-match sections even when Train == oldTrain.")
    }

    private func assertResponsiveDetail(mode: String, closeID: String) {
        let app = launch(mode: mode)

        let first = app.descendants(matching: .any)["rideDetailStop-0"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 30))
        let rows = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "rideDetailStop-"))
        XCTAssertLessThan(rows.count, 128,
                          "Opening a 2,048-stop journey must not instantiate its entire timeline.")
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.exists)
        scroll.swipeUp()
        scroll.swipeUp()
        XCTAssertFalse(first.isHittable, "The long timeline must accept scrolling.")
        let close = app.buttons[closeID]
        XCTAssertTrue(close.isHittable, "The close control must remain responsive after scrolling.")
        close.tap()
        XCTAssertTrue(app.staticTexts["longJourneyClosed"].waitForExistence(timeout: 5))
    }

    private func launch(mode: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["RAILMAP_UI_TEST_STORAGE_ID"] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["RAILMAP_UI_TEST_LONG_DETAIL"] = mode
        app.launch()
        return app
    }
}
