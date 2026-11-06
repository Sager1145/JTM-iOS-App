import RailPresentation
import XCTest

/// Runs on iPhone, iPad and Mac Catalyst through their actual sheet hosts.
@MainActor
final class StationPresentationTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testStationCardOpensAndDismisses() {
        let app = XCUIApplication()
        app.uiTestLaunch[.storageId] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-interface-language", "en"]
        app.uiTestLaunch[.tab] = "all"
        app.uiTestLaunch[.stage] = "compact"
        app.uiTestLaunch[.camera] = "35.6812,139.7671,0.008"
        app.uiTestLaunch[.layers] = "network"
        UITestLaunchSupport.launch(app)
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
            expandStationCard(app)
            assertMenuCommandSize(app.buttons["stationCardShare"])
            assertMenuCommandSize(app.buttons["stationCardClose"])
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
        app.uiTestLaunch[.storageId] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-interface-language", "en"]
        app.uiTestLaunch[.tab] = "all"
        app.uiTestLaunch[.stage] = "compact"
        app.uiTestLaunch[.camera] = "35.6812,139.7671,0.008"
        app.uiTestLaunch[.layers] = "network"
        UITestLaunchSupport.launch(app)

        let station = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "東京")).firstMatch
        XCTAssertTrue(station.waitForExistence(timeout: 45))
        activate(station)
        XCTAssertTrue(app.buttons["stationOpenInMaps"].waitForExistence(timeout: 12))
        expandStationCard(app)

        // Lines precede names in the station menu. Inspect them before
        // scrolling onward; List may unmount earlier rows at xLarge.
        let line = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "stationLine.")).firstMatch
        for _ in 0..<10 where !line.exists { scrollStationDetails(app) }
        XCTAssertTrue(line.exists)

        // English map labels normally enable only romaji. The detail card
        // must also retain both Chinese spellings and both kana scripts.
        for (key, expected) in [
            ("original", "東京"), ("name.zhHant", "東京"),
            ("name.zhHans", "东京"), ("name.kana", "とうきょう"),
            ("name.katakana", "トウキョウ"), ("name.romaji", "Tōkyō"),
        ] {
            let field = app.descendants(matching: .any)
                .matching(identifier: "stationDetail.\(key)").firstMatch
            for _ in 0..<10 where !field.exists { scrollStationDetails(app) }
            XCTAssertTrue(field.exists, "Missing station detail: \(key)")
            XCTAssertTrue(field.label.contains(expected), "Wrong value for \(key): \(field.label)")
        }
        let region = app.descendants(matching: .any)
            .matching(identifier: "stationDetail.region").firstMatch
        for _ in 0..<10 where !region.exists { scrollStationDetails(app) }
        XCTAssertTrue(region.exists)
        XCTAssertTrue(region.label.contains("Japan"))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "station-complete-details"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testStationLineOpensPreviewAndReturnsToStation() {
        let app = XCUIApplication()
        app.uiTestLaunch[.storageId] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-interface-language", "en"]
        app.uiTestLaunch[.tab] = "all"
        app.uiTestLaunch[.stage] = "compact"
        app.uiTestLaunch[.camera] = "35.6812,139.7671,0.008"
        app.uiTestLaunch[.layers] = "network"
        UITestLaunchSupport.launch(app)
        let station = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "東京")).firstMatch
        XCTAssertTrue(station.waitForExistence(timeout: 45))
        activate(station)
        XCTAssertTrue(app.buttons["stationOpenInMaps"].waitForExistence(timeout: 12))
        expandStationCard(app)
        let line = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "stationLine.")).firstMatch
        for _ in 0..<8 where !line.isHittable { scrollStationDetails(app) }
        XCTAssertTrue(line.isHittable)
        activate(line)
        let locate = app.buttons["railwayLineLocate"]
        XCTAssertTrue(locate.waitForExistence(timeout: 20), "Full railway geometry must load.")
        XCTAssertTrue(locate.isEnabled)
        let close = app.buttons["railwayLineClose"]
        XCTAssertTrue(close.waitForExistence(timeout: 8))
        XCTAssertTrue(close.isHittable, "The pushed line must restore its navigation toolbar.")
#if !targetEnvironment(macCatalyst)
        // Line loading requests the compact map-preview stop; return the
        // native sheet to full size before comparing screen point bounds.
        let navigation = app.navigationBars.firstMatch
        navigation.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo:
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)))
#endif
        assertMenuCommandSize(close)
        activate(locate)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "station-selected-railway"
        attachment.lifetime = .keepAlways
        add(attachment)
        let back = app.navigationBars.buttons.matching(
            NSPredicate(format: "identifier != %@", "railwayLineClose")).firstMatch
        XCTAssertTrue(back.isHittable, "Native back navigation remains available on the line.")
        activate(back)
        XCTAssertTrue(app.buttons["stationCardClose"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.navigationBars.count, 0, "Returning hides the station root toolbar again.")
        for _ in 0..<8 where !line.isHittable { scrollStationDetails(app) }
        XCTAssertTrue(line.isHittable)
        activate(line)
        XCTAssertTrue(close.waitForExistence(timeout: 8))
        activate(close)
        XCTAssertTrue(app.buttons["stationCardClose"].waitForExistence(timeout: 8))
        activate(app.buttons["stationCardClose"])
        XCTAssertTrue(app.buttons["stationOpenInMaps"].waitForNonExistence(timeout: 8))
    }

    func testStationShareOpensAndReturnsToCard() {
        let app = XCUIApplication()
        app.uiTestLaunch[.storageId] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-interface-language", "en"]
        app.uiTestLaunch[.tab] = "all"
        app.uiTestLaunch[.stage] = "compact"
        app.uiTestLaunch[.camera] = "35.6812,139.7671,0.008"
        app.uiTestLaunch[.layers] = "network"
        UITestLaunchSupport.launch(app)
        let station = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "東京")).firstMatch
        XCTAssertTrue(station.waitForExistence(timeout: 45))
        activate(station)
        let share = app.buttons["stationCardShare"]
        XCTAssertTrue(share.waitForExistence(timeout: 12))
        XCTAssertTrue(share.isHittable)
        expandStationCard(app)
        assertMenuCommandSize(share)
        activate(share)
        let closeShare = app.buttons.matching(NSPredicate(
            format: "label == %@ AND identifier != %@", "Close", "stationCardClose")).firstMatch
        XCTAssertTrue(closeShare.waitForExistence(timeout: 8), "The native share sheet must open.")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "station-native-share"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(closeShare.isHittable)
        activate(closeShare)
        XCTAssertTrue(closeShare.waitForNonExistence(timeout: 8))
        XCTAssertTrue(share.waitForExistence(timeout: 8))
        XCTAssertTrue(share.isHittable)
        activate(app.buttons["stationCardClose"])
        XCTAssertTrue(share.waitForNonExistence(timeout: 8))
    }

    private func expandStationCard(_ app: XCUIApplication) {
#if !targetEnvironment(macCatalyst)
        let header = app.otherElements["stationCardHeader"]
        XCTAssertTrue(header.waitForExistence(timeout: 8))
        let receipt = XCTAttachment(string: "medium share frame: \(app.buttons["stationCardShare"].frame); header: \(header.frame)")
        receipt.name = "station-medium-screen-geometry"
        receipt.lifetime = .keepAlways
        add(receipt)
        // Expand via the real sheet header. The system scales the entire
        // medium presentation; verify point geometry at its full-size stop.
        header.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo:
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.12)))
#endif
    }

    private func scrollStationDetails(_ app: XCUIApplication) {
        let list = app.descendants(matching: .any)["stationDetailsList"].firstMatch
        XCTAssertTrue(list.exists)
        // App-wide swipes can start on the map above a medium sheet.
        list.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.8))
            .press(forDuration: 0.05, thenDragTo:
                list.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.2)))
    }

    private func assertMenuCommandSize(_ element: XCUIElement,
                                       file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(element.frame.width, 40, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(element.frame.height, 40, accuracy: 0.5, file: file, line: line)
    }

    private func activate(_ element: XCUIElement) {
#if targetEnvironment(macCatalyst)
        element.click()
#else
        element.tap()
#endif
    }
}
