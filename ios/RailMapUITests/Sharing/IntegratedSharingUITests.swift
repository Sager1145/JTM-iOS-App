import RailPresentation
import XCTest

@MainActor
final class IntegratedSharingUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testShareComposerExportsSelectedScope() {
        let app = XCUIApplication()
        app.uiTestLaunch[.storageId] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-interface-language", "en"]
        app.uiTestLaunch[.tab] = "stats"
        app.uiTestLaunch[.stage] = "expanded"
        app.uiTestLaunch[.sample] = "train-store"
        UITestLaunchSupport.launch(app)

        let share = element("statisticsShareButton", in: app)
        XCTAssertTrue(share.waitForExistence(timeout: 120))
        // Select the scope under test before waiting for its figures. The
        // initial all-region load is unrelated to these Japan/day posters.
        let region = element("statisticsFilterButton", in: app)
        region.tap()
        let japan = app.buttons["Japan"]
        XCTAssertTrue(japan.waitForExistence(timeout: 5), app.debugDescription)
        japan.tap()
        // Japan now opens the area submenu; choose the whole country explicitly.
        let wholeJapan = app.buttons["Japan (all)"]
        XCTAssertTrue(wholeJapan.waitForExistence(timeout: 5), app.debugDescription)
        wholeJapan.tap()
        XCTAssertTrue((region.value as? String ?? "").hasPrefix("Japan"), region.value as? String ?? "nil")
        waitUntilEnabled(share)
        let date = element("statisticsFilterButton", in: app)
        date.tap()
        // Pass 3: the period picker is the Period item of the Stats filter.
        let periodItem = app.buttons.matching(NSPredicate(format: "identifier == 'statisticsPeriodItem' OR label BEGINSWITH 'Period'")).firstMatch
        XCTAssertTrue(periodItem.waitForExistence(timeout: 5), app.debugDescription)
        periodItem.tap()
        let day = app.buttons["statisticsCalendarDay-2026-07-03"]
        // The calendar opens on its own month, independently of sample import.
        // Reach the intended recorded day using the native calendar controls.
        for _ in 0..<12 where !day.exists {
            let month = element("statisticsCalendarMonth", in: app)
            XCTAssertTrue(month.waitForExistence(timeout: 5))
            let previous = app.buttons["statisticsCalendarPrevious"]
            XCTAssertTrue(previous.exists)
            previous.tap()
        }
        XCTAssertTrue(day.waitForExistence(timeout: 5), app.debugDescription)
        day.tap()
        let done = app.buttons["statisticsScopeClose"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        let picker = element("statisticsScopePicker", in: app)
        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: picker)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 8), .completed)
        XCTAssertTrue((date.value as? String ?? "").contains("2026-07-03"))

        waitUntilEnabled(share)
        share.tap()
        XCTAssertTrue(element("shareComposerRoot", in: app).waitForExistence(timeout: 8))
        let scope = app.segmentedControls["shareScopePicker"]
        XCTAssertTrue(scope.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(scope.buttons["Statistics"].isSelected,
                      "Opening from the Stats header must preselect the Statistics scope.")
        XCTAssertTrue(element("sharePreview", in: app).waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(exportAndExpectShareSheet(in: app), app.debugDescription)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "share-composer-Japan-2026-07-03"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        dismissShareSheet(in: app)
        let close = element("shareCloseButton", in: app)
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 8))
    }

    /// Taps the composer's export button and waits for the system share sheet
    /// (UIActivityViewController), tolerating the several shapes it takes
    /// across iOS versions. Returns true once it is on screen.
    private func exportAndExpectShareSheet(in app: XCUIApplication) -> Bool {
        let export = element("shareImageButton", in: app)
        waitUntilEnabled(export)
        export.tap()
        let sheet = NSPredicate { _, _ in
            app.otherElements["ActivityListView"].exists
                || app.buttons["Copy"].exists
                || app.buttons["Save Image"].exists
                || app.sheets.firstMatch.exists
                || app.collectionViews.matching(identifier: "ActivityListView").firstMatch.exists
        }
        let shown = XCTNSPredicateExpectation(predicate: sheet, object: nil)
        return XCTWaiter.wait(for: [shown], timeout: 90) == .completed
    }

    private func dismissShareSheet(in app: XCUIApplication) {
        let close = app.buttons["Close"]
        if close.waitForExistence(timeout: 3) {
            close.tap()
        } else {
            app.swipeDown(velocity: .fast)
        }
        XCTAssertTrue(element("shareComposerRoot", in: app).waitForExistence(timeout: 10),
                      "Dismissing the share sheet must return to the composer.")
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
