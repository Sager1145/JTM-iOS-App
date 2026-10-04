import XCTest

@MainActor
final class TrainTimetableUsabilityUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testAzusaDateVariantIsVisibleWithFullStopsAndSource() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        EditorLaunchSupport.launchEditing(app, journey: hachiojiJourney(date: "2026-09-27"))
        XCTAssertTrue(app.descendants(matching: .any)["rideEditorForm"].firstMatch.waitForExistence(timeout: 30))
        let picker = app.buttons["rideEditorServicePattern"]
        XCTAssertTrue(EditorUITestSupport.reveal(picker, in: app), app.debugDescription)
        XCTAssertTrue(picker.waitForExistence(timeout: 8))
        picker.tap()
        let replace = app.buttons["rideEditorReplaceStops"].firstMatch
        XCTAssertTrue(replace.waitForExistence(timeout: 8))
        replace.tap()
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

    private func hachiojiJourney(date: String) -> [String: Any] {
        [
            "id": "ui-hachioji",
            "number": "",
            "origin": "東京",
            "destination": "八王子",
            "region": "jp",
            "date": date,
            "visible": true,
            "stops": [
                EditorLaunchSupport.stop("東京", code: "003766", type: "origin"),
                EditorLaunchSupport.stop("新宿", code: "003700", type: "passenger_stop"),
                EditorLaunchSupport.stop("立川", code: "003634", type: "passenger_stop"),
                EditorLaunchSupport.stop("八王子", code: "003947", type: "destination"),
            ],
        ]
    }
}
