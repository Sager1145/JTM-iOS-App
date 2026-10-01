import XCTest

@MainActor
final class TrainTimetableUsabilityUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testAzusaDateVariantIsVisibleWithFullStopsAndSource() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "all"
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "expanded"
        app.launchEnvironment["RAILMAP_UI_TEST_SHEET"] = "new"
        app.launch()
        let next = app.buttons["rideEditorNext"]
        XCTAssertTrue(next.waitForExistence(timeout: 30))
        next.tap()
        app.buttons["rideEditorServicePattern"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.tap()
        search.typeText("はちおうじ")
        let legacy = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "東京〜八王子")).firstMatch
        XCTAssertTrue(legacy.waitForExistence(timeout: 8))
        legacy.tap()
        next.tap()
        next.tap()
        let includeDate = app.switches["Include a date"]
        XCTAssertTrue(includeDate.waitForExistence(timeout: 8))
        includeDate.switches.firstMatch.tap()
        let date = app.textFields["rideEditorDateInput"]
        XCTAssertTrue(date.waitForExistence(timeout: 8))
        let previous = date.value as? String ?? ""
        date.tap()
        date.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count) + "2026-09-27")
        app.buttons["rideEditorPrevious"].tap()
        XCTAssertTrue(app.otherElements["rideEditorNumber"].textFields.firstMatch.waitForExistence(timeout: 8))
        app.buttons["rideEditorPrevious"].tap()
        let picker = app.buttons["rideEditorServicePattern"]
        XCTAssertTrue(picker.waitForExistence(timeout: 8))
        picker.tap()
        app.buttons["rideEditorReplaceStops"].firstMatch.tap()
        let datedSearch = app.searchFields.firstMatch
        XCTAssertTrue(datedSearch.waitForExistence(timeout: 8))
        datedSearch.tap()
        datedSearch.typeText("あずさ\n")
        let detail = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "timetableDetails-jr-east.azusa")).firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 10), app.debugDescription)
        // The floating search bar can cover a row while XCTest still reports it hittable.
        for _ in 0..<8 {
            if detail.isHittable && detail.frame.maxY < app.frame.maxY - 120 { break }
            let list = app.collectionViews.firstMatch
            list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                .press(forDuration: 0.1, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        }
        XCTAssertTrue(detail.isHittable, app.debugDescription)
        detail.tap()
        let detailList = app.collectionViews["timetableDetailList"]
        XCTAssertTrue(detailList.waitForExistence(timeout: 8), app.debugDescription)
        let scrollDetailListUp = {
            let start = detailList.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
            let end = detailList.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.52))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        XCTAssertTrue(app.staticTexts["運転日: 2026-09-27 · 日本時間"].waitForExistence(timeout: 8), app.debugDescription)
        let origin = app.descendants(matching: .any).matching(identifier: "timetableStop-1").firstMatch
        XCTAssertTrue(origin.waitForExistence(timeout: 8))
        XCTAssertTrue(origin.label.contains("07:00"), origin.label)
        let last = app.descendants(matching: .any).matching(identifier: "timetableStop-12").firstMatch
        for _ in 0..<12 where !last.exists { scrollDetailListUp() }
        XCTAssertTrue(last.waitForExistence(timeout: 8))
        XCTAssertTrue(last.label.contains("松本"))
        XCTAssertTrue(last.label.contains("09:38"))
        let source = app.links.matching(NSPredicate(format: "label CONTAINS %@", "あずさ")).firstMatch
        for _ in 0..<12 where !source.exists { scrollDetailListUp() }
        XCTAssertTrue(source.waitForExistence(timeout: 8), app.debugDescription)
    }
}
