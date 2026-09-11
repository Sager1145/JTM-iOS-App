import XCTest

/// Runs on iPhone, iPad and Mac Catalyst through their actual sheet hosts.
@MainActor
final class StationPresentationTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testStationCardOpensAndDismisses() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "all"
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "compact"
        app.launchEnvironment["RAILMAP_UI_TEST_CAMERA"] = "40.735,-74.027,0.016"
        app.launchEnvironment["RAILMAP_UI_TEST_LAYERS"] = "network"
        app.launch()
        let openInMaps = app.buttons["stationOpenInMaps"]
        // Wait for a real, loaded annotation. The automatic DEBUG sheet hook
        // runs before cold network loading finishes and may select no station.
        let station = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Hoboken")).firstMatch
        XCTAssertTrue(station.waitForExistence(timeout: 45))
        for attempt in 0..<2 {
            activate(station)
            XCTAssertTrue(openInMaps.waitForExistence(timeout: 12),
                          "The station sheet must mount with its required environment objects.")
            XCTAssertEqual(app.state, .runningForeground)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "station-card-\(attempt)"
            attachment.lifetime = .keepAlways
            add(attachment)
            activate(app.buttons["stationCardClose"])
            XCTAssertTrue(openInMaps.waitForNonExistence(timeout: 8))
            XCTAssertEqual(app.state, .runningForeground)
        }
    }

    private func activate(_ element: XCUIElement) {
#if targetEnvironment(macCatalyst)
        element.click()
#else
        element.tap()
#endif
    }
}
