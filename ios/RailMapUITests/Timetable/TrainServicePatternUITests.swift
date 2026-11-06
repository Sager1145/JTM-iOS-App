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
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        EditorLaunchSupport.launchEditing(app, journey: hachiojiJourney(date: "2026-09-27"))
        XCTAssertTrue(app.descendants(matching: .any)["newTripForm"].firstMatch.waitForExistence(timeout: 30))

        // Entry moved: fill sheet (newTripFillDetails) -> newTripTimetableBrowse; picking applies immediately.
        let fill = app.buttons["newTripFillDetails"]
        XCTAssertTrue(EditorUITestSupport.reveal(fill, in: app, maxDrags: 6), app.debugDescription)
        EditorUITestSupport.tap(fill, in: app)
        let picker = app.buttons["newTripTimetableBrowse"]
        XCTAssertTrue(picker.waitForExistence(timeout: 8), app.debugDescription)
        EditorUITestSupport.tap(picker, in: app)
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

    private func hachiojiJourney(date: String?) -> [String: Any] {
        var journey: [String: Any] = [
            "id": "ui-hachioji",
            "number": "",
            "origin": "東京",
            "destination": "八王子",
            "region": "jp",
            "visible": true,
            "stops": [
                EditorLaunchSupport.stop("東京", code: "003766", type: "origin"),
                EditorLaunchSupport.stop("新宿", code: "003700", type: "passenger_stop"),
                EditorLaunchSupport.stop("立川", code: "003634", type: "passenger_stop"),
                EditorLaunchSupport.stop("八王子", code: "003947", type: "destination"),
            ],
        ]
        if let date { journey["date"] = date }
        return journey
    }
}
