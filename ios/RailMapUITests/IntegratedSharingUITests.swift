import XCTest

@MainActor
final class IntegratedSharingUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testBothPosterKindsPreviewInLightAndDarkWithSelectedScope() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-interface-language", "en"]
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "stats"
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "expanded"
        app.launchEnvironment["RAILMAP_UI_TEST_SAMPLE"] = "train-store"
        app.launch()

        let share = element("statisticsShareButton", in: app)
        XCTAssertTrue(share.waitForExistence(timeout: 120))
        waitUntilEnabled(share)
        let region = element("regionScopeButton", in: app)
        region.tap()
        let japan = app.buttons["Japan"]
        XCTAssertTrue(japan.waitForExistence(timeout: 5), app.debugDescription)
        japan.tap()
        XCTAssertEqual(region.value as? String, "Japan")
        let date = element("statisticsDateButton", in: app)
        date.tap()
        let day = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "2026-07-03")).firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 5), app.debugDescription)
        day.tap()
        XCTAssertTrue((date.value as? String ?? "").contains("2026-07-03"))

        for kind in ["map", "statistics"] {
            for appearance in ["Light", "Dark"] {
                waitUntilEnabled(share)
                share.tap()
                let option = element(kind + "ShareOption", in: app)
                XCTAssertTrue(option.waitForExistence(timeout: 5))
                option.tap()
                // UIKit's nested menu carries the parent menu identifier on
                // its actions. Select the visible appearance label instead.
                let choice = app.buttons["Share in " + appearance.lowercased() + " mode"]
                XCTAssertTrue(choice.waitForExistence(timeout: 5), app.debugDescription)
                choice.tap()
                let close = element("statisticsShareCloseButton", in: app)
                XCTAssertTrue(close.waitForExistence(timeout: 90), app.debugDescription)
                XCTAssertTrue(app.images.firstMatch.exists, "The preview must contain a rendered image.")
                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.name = "share-\(kind)-\(appearance)-Japan-2026-07-03"
                screenshot.lifetime = .keepAlways
                add(screenshot)
                close.tap()
                XCTAssertTrue(close.waitForNonExistence(timeout: 8))
                XCTAssertEqual(region.value as? String, "Japan")
                XCTAssertTrue((date.value as? String ?? "").contains("2026-07-03"))
            }
        }
    }

    private func waitUntilEnabled(_ element: XCUIElement) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            element.exists && element.isEnabled
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 60), .completed)
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
