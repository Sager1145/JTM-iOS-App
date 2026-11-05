import RailPresentation
import XCTest

/// Route entry for a saved journey happens on the one editor's map: the
/// saved route is shown as is, and picking another station replans it.
@MainActor
final class RailwayRouteEntryUITests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testSavedJourneyOpensWithItsRouteAndSavesWithoutReplanning() {
        let app = launchSeededEditor()
        let savedRoute = app.descendants(matching: .any)["newTripSavedRoute"].firstMatch
        XCTAssertTrue(savedRoute.waitForExistence(timeout: 30),
                      "A saved journey must open with its saved route. \(app.debugDescription)")
        XCTAssertFalse(app.buttons["newTripCorridor-0"].exists,
                       "An untouched saved route must not be replanned.")
        let origin = app.buttons["newTripOrigin"]
        let found = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "東京"), object: origin)
        XCTAssertEqual(XCTWaiter.wait(for: [found], timeout: 20), .completed,
                       "The saved origin must be found in the catalog. \(origin.label)")
        let firstStop = app.descendants(matching: .any)["rideEditorStop-0"].firstMatch
        XCTAssertTrue(EditorUITestSupport.reveal(firstStop, in: app, unmountedRowIsAbove: false),
                      "The saved stops must stay editable.")
        let save = app.buttons["newTripSave"]
        XCTAssertTrue(waitForEnabled(save, timeout: 20),
                      "An unchanged saved journey must be savable as it is.")
        // Nothing changed, so leaving does not ask.
        app.buttons["newTripCancel"].tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 8))
    }

    func testChangingTheDestinationReplansOnTheMapAndCancelKeepsTheSavedJourney() {
        let app = launchSeededEditor()
        XCTAssertTrue(app.descendants(matching: .any)["newTripSavedRoute"].firstMatch
            .waitForExistence(timeout: 30))
        let destination = app.buttons["newTripDestination"]
        XCTAssertTrue(waitForEnabled(destination, timeout: 20))
        destination.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any)["stationPickerMap"].firstMatch.waitForExistence(timeout: 5),
                      "The one station picker shows the map above its search.")
        search.tap()
        search.typeText("大崎")
        let row = app.buttons["newTripStation-jp-東日本旅客鉄道-山手線-004135"]
        var swipes = 0
        while !row.waitForExistence(timeout: swipes == 0 ? 3 : 0.4), swipes < 12 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(row.exists, app.debugDescription)
        row.tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForNonExistence(timeout: 8))
        XCTAssertFalse(app.descendants(matching: .any)["newTripSavedRoute"].firstMatch.exists,
                       "A new destination replaces the saved route.")
        let corridor = app.buttons["newTripCorridor-0"]
        XCTAssertTrue(corridor.waitForExistence(timeout: 30)
                      || EditorUITestSupport.reveal(corridor, in: app, unmountedRowIsAbove: false),
                      "A new destination must replan the route. \(app.debugDescription)")
        let cancel = app.buttons["newTripCancel"]
        cancel.tap()
        let discard = app.buttons["Discard changes"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5), "A replanned route is an unsaved change.")
        discard.tap()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 8))
    }

    private func launchSeededEditor() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-interface-language", "en"]
        let journey: [String: Any] = [
            "id": "ui-tokyo-shinagawa-\(UUID().uuidString.prefix(8))",
            "date": "2026-10-12",
            "number": "Route entry",
            "origin": "東京",
            "destination": "品川",
            "region": "jp",
            "visible": true,
            "stops": [
                EditorLaunchSupport.stop("東京", code: "003766", type: "origin", departure: "09:00"),
                EditorLaunchSupport.stop("品川", code: "004095", type: "destination", arrival: "09:12"),
            ],
        ]
        EditorLaunchSupport.launchEditing(app, journey: journey)
        return app
    }

    private func waitForEnabled(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let enabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND enabled == true"), object: element)
        return XCTWaiter.wait(for: [enabled], timeout: timeout) == .completed
    }
}
