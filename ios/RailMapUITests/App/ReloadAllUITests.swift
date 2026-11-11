import RailPresentation
import XCTest

/// "Repair routes" from the data manager: it finishes, it can be stopped, and
/// the app is still in the foreground afterwards (no crash, no watchdog kill).
///
/// Repair reads cached routes back, so on a warm cache it can finish before
/// its progress row is ever visible. These tests therefore wait for the
/// button to come back and never require the progress row; the progress and
/// stop path of the full rebuild is covered by `rebuildResolvesAll` in
/// `RiddenRouteStoreLandingTests`.
@MainActor
final class ReloadAllUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testReloadAllCompletesWithoutCrashing() {
        let app = launchWithSample()
        openReloadRow(in: app)
        startReload(in: app)
        // The row is disabled until the repair has finished.
        waitUntilEnabled(app.buttons["reloadAllButton"], timeout: 600,
                         "Repair did not finish within 10 minutes.")
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testReloadAllCanBeStoppedMidway() {
        let app = launchWithSample()
        openReloadRow(in: app)
        startReload(in: app)
        // A repair that already finished has nothing to stop.
        let stop = app.buttons["reloadAllStop"]
        if stop.waitForExistence(timeout: 5) { stop.tap() }
        waitUntilEnabled(app.buttons["reloadAllButton"], timeout: 60,
                         "Stopping returns the row to its button.")
        // Starting again straight after a stop is the race this guards.
        startReload(in: app)
        waitUntilEnabled(app.buttons["reloadAllButton"], timeout: 600,
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

    /// Waits for the button to exist and be enabled (a running repair swaps it
    /// for its progress row, and a finished one leaves it enabled).
    private func waitUntilEnabled(_ button: XCUIElement, timeout: TimeInterval, _ message: String) {
        XCTAssertTrue(button.waitForExistence(timeout: timeout), message)
        let enabled = expectation(for: NSPredicate(format: "exists == true AND isEnabled == true"), evaluatedWith: button)
        wait(for: [enabled], timeout: timeout)
    }

    private func startReload(in app: XCUIApplication) {
        let button = app.buttons["reloadAllButton"]
        // Enabled once the store has been handed its trips.
        let enabled = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: button)
        wait(for: [enabled], timeout: 60)
        button.tap()
        let confirm = app.buttons["reloadAllConfirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 8))
        confirm.tap()
    }
}
