import RailPresentation
import XCTest

/// "Delete the backup" in the Data Library asks first (audit H3).
///
/// The backup is the only undo for "Delete every journey", so removing it must
/// not be one tap. The action is a private SwiftUI dialog with no view model
/// under it, so the lowest level that can pin it is the screen itself.
/// Runs on an isolated store: it deletes that store's journeys to get a backup.
@MainActor
final class DiscardBackupUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testDeletingTheBackupWaitsForConfirmation() {
        let app = XCUIApplication()
        app.uiTestLaunch[.storageId] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-interface-language", "en"]
        app.uiTestLaunch[.sample] = "tokyo-limited-express-loop"
        UITestLaunchSupport.launch(app)

        let menu = app.descendants(matching: .any)["utilityMenuButton"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 30))
        menu.tap()
        let data = app.buttons["utilityDataButton"]
        XCTAssertTrue(data.waitForExistence(timeout: 8))
        data.tap()

        // Delete every journey: that writes the backup this test deletes.
        let danger = app.descendants(matching: .any)["dangerZoneDisclosure"].firstMatch
        for _ in 0..<8 where !(danger.exists && danger.isHittable) { app.swipeUp() }
        XCTAssertTrue(danger.waitForExistence(timeout: 8))
        danger.tap()
        let deleteAll = app.buttons["deleteAllButton"]
        XCTAssertTrue(deleteAll.waitForExistence(timeout: 8))
        deleteAll.tap()
        let deleteAllConfirm = app.buttons["deleteAllConfirm"].firstMatch
        XCTAssertTrue(deleteAllConfirm.waitForExistence(timeout: 8))
        deleteAllConfirm.tap()

        let discard = app.buttons["discardBackupButton"]
        for _ in 0..<8 where !(discard.exists && discard.isHittable) { app.swipeDown() }
        XCTAssertTrue(discard.waitForExistence(timeout: 30), "The delete wrote a backup, so the row is shown.")

        // One tap opens the dialog and removes nothing.
        discard.tap()
        let confirm = app.buttons["discardBackupConfirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 8), "Deleting the backup asks first.")
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'cannot be restored'")).firstMatch
                .waitForExistence(timeout: 4),
            "The dialog says the file cannot be restored.")

        // Cancelling keeps the backup.
        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.waitForExistence(timeout: 2) { cancel.tap() } else { app.tap() }
        XCTAssertTrue(discard.waitForExistence(timeout: 8), "Cancel leaves the backup in place.")
        XCTAssertFalse(app.buttons["discardBackupConfirm"].exists)

        // Confirming deletes it.
        discard.tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 8))
        confirm.tap()
        let gone = expectation(
            for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["discardBackupButton"])
        wait(for: [gone], timeout: 15)
    }
}
