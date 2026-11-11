import RailPresentation
import XCTest

/// "Repair routes" from the data manager: it finishes, it can be stopped, and
/// the app is still in the foreground afterwards (no crash, no watchdog kill).
///
/// Repair reads cached routes back, so on a warm cache it can finish before
/// its progress row is ever visible. These tests therefore never require the
/// progress row. They watch the button's accessibility value instead, which is
/// the number of reloads the store has finished (or stopped): a reload is done
/// when that number has moved. The progress row of the full rebuild is covered
/// by `rebuildResolvesAll`, and Stop on a repair by `stopDuringRepairDoesNotSolve`,
/// both in `RiddenRouteStoreRepairTests`.
@MainActor
final class ReloadAllUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testReloadAllCompletesWithoutCrashing() {
        let app = launchWithSample()
        openReloadRow(in: app)
        let before = startReload(in: app)
        waitForFinished(after: before, in: app, timeout: 600,
                        "Repair did not finish within 10 minutes.")
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testReloadAllCanBeStoppedMidway() {
        let app = launchWithSample()
        openReloadRow(in: app)
        let before = startReload(in: app)
        // A repair that already finished has nothing to stop.
        let stop = app.buttons["reloadAllStop"]
        if stop.waitForExistence(timeout: 5) { stop.tap() }
        waitForFinished(after: before, in: app, timeout: 60,
                        "Stopping returns the row to its button.")
        // Starting again straight after a stop is the race this guards.
        let again = startReload(in: app)
        waitForFinished(after: again, in: app, timeout: 600,
                        "The restarted repair did not finish.")
        XCTAssertEqual(app.state, .runningForeground)
    }

    private func launchWithSample() -> XCUIApplication {
        let app = XCUIApplication()
        app.uiTestLaunch[.storageId] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-interface-language", "en"]
        app.uiTestLaunch[.sample] = "tokyo-limited-express-loop"
        UITestLaunchSupport.launch(app)
        return app
    }

    private func openReloadRow(in app: XCUIApplication) {
        let menu = app.descendants(matching: .any)["utilityMenuButton"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 30))
        menu.tap()
        let data = app.buttons["utilityDataButton"]
        XCTAssertTrue(data.waitForExistence(timeout: 8))
        data.tap()
        let button = app.buttons["reloadAllButton"]
        for _ in 0..<6 where !(button.exists && button.isHittable) { app.swipeUp() }
        XCTAssertTrue(button.waitForExistence(timeout: 8))
    }

    /// The button is back, enabled, and its value (reloads finished) has moved
    /// past `before`: the reload that was started has ended.
    private func waitForFinished(
        after before: String, in app: XCUIApplication, timeout: TimeInterval, _ message: String
    ) {
        let button = app.buttons["reloadAllButton"]
        let done = expectation(
            for: NSPredicate(format: "exists == true AND isEnabled == true AND value != %@", before),
            evaluatedWith: button)
        XCTAssertEqual(XCTWaiter().wait(for: [done], timeout: timeout), .completed, message)
    }

    /// Starts a repair and answers the finished-count it started from.
    private func startReload(in app: XCUIApplication) -> String {
        let button = app.buttons["reloadAllButton"]
        // Enabled once the store has been handed its trips.
        let enabled = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: button)
        wait(for: [enabled], timeout: 60)
        let before = (button.value as? String) ?? ""
        button.tap()
        let confirm = app.buttons["reloadAllConfirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 8))
        confirm.tap()
        return before
    }
}
