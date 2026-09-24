import XCTest

@MainActor
final class JourneyCompletionUITests: XCTestCase {
    func testInvalidReplyCannotApplyAndEmptyReplyIsANoOp() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-interface-language", "en"]
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "all"
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "expanded"
        app.launchEnvironment["RAILMAP_UI_TEST_SHEET"] = "new"
        app.launch()

        let next = app.buttons["rideEditorNext"]
        XCTAssertTrue(next.waitForExistence(timeout: 40))
        next.tap()
        let completion = app.buttons["rideEditorAICompletion"]
        XCTAssertTrue(completion.waitForExistence(timeout: 8))
        XCTAssertFalse(completion.isEnabled)
        for (index, name) in ["Tokyo", "Shinagawa"].enumerated() {
            let stop = app.descendants(matching: .any)["rideEditorStop-\(index)"].firstMatch
            XCTAssertTrue(stop.waitForExistence(timeout: 8))
            stop.tap()
            let field = app.otherElements["rideEditorStopName"].textFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeText(name)
            app.navigationBars[name].buttons.firstMatch.tap()
        }
        next.tap()
        let number = app.otherElements["rideEditorNumber"].textFields.firstMatch
        XCTAssertTrue(number.waitForExistence(timeout: 8))
        number.tap()
        number.typeText("Test 1\n")
        next.tap()
        let date = app.switches["Include a date"]
        XCTAssertTrue(date.waitForExistence(timeout: 8))
        // SwiftUI exposes the entire labelled row as a switch. Tap the
        // actual control on its trailing edge, then verify the binding changed.
        date.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertTrue(app.otherElements["rideEditorDateInput"].waitForExistence(timeout: 8))
        for _ in 0..<10 where !completion.isHittable { app.swipeUp() }
        XCTAssertTrue(completion.isEnabled)
        completion.tap()
        XCTAssertTrue(app.buttons["aiSubscriptionSignIn"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["aiSubscriptionComplete"].exists)
        let response = app.textViews["aiCompletionResponse"]
        for _ in 0..<6 where !response.isHittable { app.swipeUp() }
        XCTAssertTrue(response.waitForExistence(timeout: 8))
        response.tap()
        response.typeText("invalid JSON")
        let preview = app.buttons["aiCompletionPreview"]
        for _ in 0..<4 where !preview.isHittable { app.swipeUp() }
        preview.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Could not apply.")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["aiCompletionApply"].exists)

        for _ in 0..<6 where !response.isHittable { app.swipeDown() }
        response.tap()
        response.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "invalid JSON".count))
        response.typeText("{\"trains\":[]}")
        for _ in 0..<4 where !preview.isHittable { app.swipeUp() }
        preview.tap()
        let apply = app.buttons["aiCompletionApply"]
        for _ in 0..<5 where !apply.isHittable { app.swipeUp() }
        XCTAssertTrue(apply.exists)
        XCTAssertFalse(apply.isEnabled)
    }
}
