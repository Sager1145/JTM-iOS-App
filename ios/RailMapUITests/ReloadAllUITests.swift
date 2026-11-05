import RailPresentation
import XCTest

/// "Reload all trips" from Settings: it finishes, it can be stopped, and the
/// app is still in the foreground afterwards (no crash, no watchdog kill).
@MainActor
final class ReloadAllUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testReloadAllCompletesWithoutCrashing() {
        let app = launchWithSample()
        openReloadRow(in: app)
        startReload(in: app)
        XCTAssertTrue(app.descendants(matching: .any)["reloadAllProgress"].waitForExistence(timeout: 20),
                      "A running reload shows its progress.")
        // The row returns to its button only when the reload has finished.
        XCTAssertTrue(app.buttons["reloadAllButton"].waitForExistence(timeout: 600),
                      "Reload all did not finish within 10 minutes.")
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testReloadAllCanBeStoppedMidway() {
        let app = launchWithSample()
        openReloadRow(in: app)
        startReload(in: app)
        let stop = app.buttons["reloadAllStop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 20))
        stop.tap()
        XCTAssertTrue(app.buttons["reloadAllButton"].waitForExistence(timeout: 10),
                      "Stopping returns the row to its button.")
        // Starting again straight after a stop is the race this guards.
        startReload(in: app)
        XCTAssertTrue(app.descendants(matching: .any)["reloadAllProgress"].waitForExistence(timeout: 30),
                      "The restarted reload shows its progress.")
        XCTAssertTrue(app.buttons["reloadAllButton"].waitForExistence(timeout: 600))
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
        let settings = app.buttons["utilitySettingsButton"]
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        settings.tap()
        let about = app.descendants(matching: .any)["settingsDiagnosticsLink"].firstMatch
        for _ in 0..<6 where !(about.exists && about.isHittable) { app.swipeUp() }
        XCTAssertTrue(about.waitForExistence(timeout: 8))
        about.tap()
        let button = app.buttons["reloadAllButton"]
        for _ in 0..<6 where !(button.exists && button.isHittable) { app.swipeUp() }
        XCTAssertTrue(button.waitForExistence(timeout: 8))
    }

    private func startReload(in app: XCUIApplication) {
        let button = app.buttons["reloadAllButton"]
        // Enabled once the store has been handed its trips.
        let enabled = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: button)
        wait(for: [enabled], timeout: 60)
        button.tap()
        let confirm = app.buttons["reloadAllConfirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 8))
        confirm.tap()
    }
}
