import RailPresentation
import XCTest

/// The Sample trips page in the Data Library (audit B5): a tap asks before it
/// adds anything, "Replace all trips" is a visible row, and "Remove sample
/// trips" is offered. Runs on an isolated store.
@MainActor
final class SampleTripsUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testTappingASampleAsksBeforeAdding() {
        let app = XCUIApplication()
        app.uiTestLaunch[.storageId] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-interface-language", "en"]
        UITestLaunchSupport.launch(app)

        let menu = app.descendants(matching: .any)["utilityMenuButton"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 30))
        menu.tap()
        let data = app.buttons["utilityDataButton"]
        XCTAssertTrue(data.waitForExistence(timeout: 8))
        data.tap()

        let link = app.descendants(matching: .any)["dataSampleTripsLink"].firstMatch
        for _ in 0..<8 where !(link.exists && link.isHittable) { app.swipeUp() }
        XCTAssertTrue(link.waitForExistence(timeout: 8))
        link.tap()

        let sample = app.buttons["sampleTrips-train-store"]
        XCTAssertTrue(sample.waitForExistence(timeout: 8))
        sample.tap()
        let add = app.buttons["sampleAddConfirm"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 8), "A sample asks before it adds trips.")

        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.waitForExistence(timeout: 2) { cancel.tap() } else { app.tap() }
        XCTAssertFalse(app.buttons["sampleAddConfirm"].exists, "Cancel adds nothing.")

        XCTAssertTrue(app.descendants(matching: .any)["sampleReplaceAllMenu"].firstMatch.exists,
                      "Replace all trips is a visible row.")
        for _ in 0..<4 where !app.buttons["sampleRemoveButton"].exists { app.swipeUp() }
        XCTAssertTrue(app.buttons["sampleRemoveButton"].exists, "Remove sample trips is offered.")
    }
}
