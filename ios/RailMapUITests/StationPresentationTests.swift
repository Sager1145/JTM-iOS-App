import XCTest

/// Runs on iPhone, iPad and Mac Catalyst through their actual sheet hosts.
@MainActor
final class StationPresentationTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testStationCardOpensAndDismisses() {
        let app = XCUIApplication()
        app.launchEnvironment["RAILMAP_UI_TEST_STORAGE_ID"] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-interface-language", "en"]
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "all"
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "compact"
        app.launchEnvironment["RAILMAP_UI_TEST_CAMERA"] = "35.6812,139.7671,0.008"
        app.launchEnvironment["RAILMAP_UI_TEST_LAYERS"] = "network"
        app.launch()
        let openInMaps = app.buttons["stationOpenInMaps"]
        // Wait for a real, loaded annotation. The automatic DEBUG sheet hook
        // runs before cold network loading finishes and may select no station.
        let station = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "東京")).firstMatch
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

    func testStationCardShowsCompleteNamesAndInformation() {
        let app = XCUIApplication()
        app.launchEnvironment["RAILMAP_UI_TEST_STORAGE_ID"] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-interface-language", "en"]
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "all"
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "compact"
        app.launchEnvironment["RAILMAP_UI_TEST_CAMERA"] = "35.6812,139.7671,0.008"
        app.launchEnvironment["RAILMAP_UI_TEST_LAYERS"] = "network"
        app.launch()

        let station = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "東京")).firstMatch
        XCTAssertTrue(station.waitForExistence(timeout: 45))
        activate(station)
        XCTAssertTrue(app.buttons["stationOpenInMaps"].waitForExistence(timeout: 12))

        // English map labels normally enable only romaji. The detail card
        // must also retain both Chinese spellings and both kana scripts.
        for (key, expected) in [
            ("original", "東京"), ("name.zhHant", "東京"),
            ("name.zhHans", "东京"), ("name.kana", "とうきょう"),
            ("name.katakana", "トウキョウ"), ("name.romaji", "Tōkyō"),
        ] {
            let field = app.descendants(matching: .any)
                .matching(identifier: "stationDetail.\(key)").firstMatch
            for _ in 0..<10 where !field.exists { app.swipeUp() }
            XCTAssertTrue(field.exists, "Missing station detail: \(key)")
            XCTAssertTrue(field.label.contains(expected), "Wrong value for \(key): \(field.label)")
        }
        let line = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "stationLine.")).firstMatch
        for _ in 0..<10 where !line.exists { app.swipeUp() }
        XCTAssertTrue(line.exists)
        let region = app.descendants(matching: .any)
            .matching(identifier: "stationDetail.region").firstMatch
        for _ in 0..<10 where !region.exists { app.swipeUp() }
        XCTAssertTrue(region.exists)
        XCTAssertTrue(region.label.contains("Japan"))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "station-complete-details"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testStationLineOpensPreviewAndReturnsToStation() {
        let app = XCUIApplication()
        app.launchEnvironment["RAILMAP_UI_TEST_STORAGE_ID"] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-interface-language", "en"]
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "all"
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "compact"
        app.launchEnvironment["RAILMAP_UI_TEST_CAMERA"] = "35.6812,139.7671,0.008"
        app.launchEnvironment["RAILMAP_UI_TEST_LAYERS"] = "network"
        app.launch()
        let station = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "東京")).firstMatch
        XCTAssertTrue(station.waitForExistence(timeout: 45))
        activate(station)
        XCTAssertTrue(app.buttons["stationOpenInMaps"].waitForExistence(timeout: 12))
        let line = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "stationLine.")).firstMatch
        for _ in 0..<8 where !line.isHittable { app.swipeUp() }
        XCTAssertTrue(line.isHittable)
        activate(line)
        let locate = app.buttons["railwayLineLocate"]
        XCTAssertTrue(locate.waitForExistence(timeout: 20), "Full railway geometry must load.")
        XCTAssertTrue(locate.isEnabled)
        activate(locate)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "station-selected-railway"
        attachment.lifetime = .keepAlways
        add(attachment)
        activate(app.buttons["railwayLineClose"])
        XCTAssertTrue(app.buttons["stationCardClose"].waitForExistence(timeout: 8))
        activate(app.buttons["stationCardClose"])
        XCTAssertTrue(app.buttons["stationOpenInMaps"].waitForNonExistence(timeout: 8))
    }

    private func activate(_ element: XCUIElement) {
#if targetEnvironment(macCatalyst)
        element.click()
#else
        element.tap()
#endif
    }
}
