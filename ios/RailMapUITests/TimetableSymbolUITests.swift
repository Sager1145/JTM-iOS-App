import XCTest

@MainActor
final class TimetableSymbolUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testPassAndNotViaSymbolsRemainVisibleInSourceTimetable() {
        for (service, tripPrefix, expectedLabel) in [
            ("北斗", "timetableDetails-jr-hokkaido.hokuto.1.", "通過"),
            ("ハウステンボス", "timetableDetails-jr-kyushu.huis-ten-bosch.11.", "この列車は経由しません"),
        ] {
            let app = XCUIApplication()
            app.launchEnvironment["RAILMAP_UI_TEST_STORAGE_ID"] = UUID().uuidString
            app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                                   "-interface-language", "en"]
            app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "all"
            app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "expanded"
            app.launchEnvironment["RAILMAP_UI_TEST_SHEET"] = "new"
            app.launch()
            let next = app.buttons["rideEditorNext"]
            XCTAssertTrue(next.waitForExistence(timeout: 40))
            next.tap()
            EditorUITestSupport.seedNamedRoute(in: app)
            next.tap()
            next.tap()
            EditorUITestSupport.enableDate(in: app)
            let date = app.textFields["rideEditorDateInput"]
            XCTAssertTrue(date.waitForExistence(timeout: 8))
            date.tap()
            date.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,
                                 count: (date.value as? String ?? "").count) + "2026-09-30")
            app.buttons["rideEditorPrevious"].tap()
            app.buttons["rideEditorPrevious"].tap()
            app.buttons["rideEditorServicePattern"].tap()
            app.buttons["rideEditorReplaceStops"].firstMatch.tap()
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 10))
            search.tap()
            search.typeText(service + "\n")
            let detail = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", tripPrefix)).firstMatch
            for _ in 0..<16 {
                if detail.exists && detail.isHittable && detail.frame.maxY < app.frame.maxY - 120 { break }
                app.collectionViews.firstMatch.swipeUp()
            }
            XCTAssertTrue(detail.waitForExistence(timeout: 8), app.debugDescription)
            detail.tap()
            let list = app.collectionViews["timetableDetailList"]
            XCTAssertTrue(list.waitForExistence(timeout: 8))
            // The printed glyph has a spoken role label for VoiceOver.
            // Select the independent source-symbol row, then keep its image.
            let symbol = app.descendants(matching: .any).matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                "timetableSymbol-", expectedLabel)).firstMatch
            for _ in 0..<22 {
                if symbol.exists && symbol.isHittable
                    && symbol.frame.minY > list.frame.minY + 80
                    && symbol.frame.maxY < list.frame.maxY - 50 { break }
                let scrollDown = symbol.exists && symbol.frame.minY < list.frame.minY + 80
                let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: scrollDown ? 0.4 : 0.6))
                let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: scrollDown ? 0.6 : 0.4))
                start.press(forDuration: 0.1, thenDragTo: end)
            }
            XCTAssertTrue(symbol.waitForExistence(timeout: 8), app.debugDescription)
            XCTAssertTrue(symbol.isHittable)
            XCTAssertGreaterThan(symbol.frame.minY, list.frame.minY + 80)
            XCTAssertLessThan(symbol.frame.maxY, list.frame.maxY - 50)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "source-symbol-\(service)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.terminate()
        }
    }
}
