import XCTest

@MainActor
final class JourneySharingUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testLongJourneyCardPreviewsOneImageForBothKindsAndReturnsToSameJourney() {
        // The bundled Sunrise journey has 217 stops. It exercises a natural
        // tall image rather than allowing a short route to hide truncation.
        let id = "20260729_05_sunrise_izumo"
        let app = launch(journeyID: id)
        let row = element("journeyRow-\(id)", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 60), app.debugDescription)
        row.tap()
        let selected = element("selectedJourney-\(id)", in: app)
        XCTAssertTrue(selected.waitForExistence(timeout: 10))
        let originalTitle = selected.label

        let share = element("journeyShareButton", in: app)
        XCTAssertTrue(share.waitForExistence(timeout: 10))
        XCTAssertTrue(share.isHittable, "An opened journey card must expose its share button.")
        share.tap()
        exerciseBothKinds(in: app, attachmentPrefix: "sunrise-217-stops", validatesSunrise: true)
        closeShare(in: app)

        XCTAssertTrue(selected.waitForExistence(timeout: 10))
        XCTAssertEqual(selected.label, originalTitle)
        XCTAssertTrue(share.isHittable)
        element("journeyBackToList", in: app).tap()
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["journeySearchField"].value as? String, id)
    }

    func testJourneyMenuPreviewsBothKindsAndReturnsToSameJourney() {
        let id = "20260703_01_haruka"
        let app = launch(journeyID: id)
        let row = element("journeyRow-\(id)", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 60), app.debugDescription)
        row.press(forDuration: 1)
        let information = app.buttons["Journey information"]
        XCTAssertTrue(information.waitForExistence(timeout: 5))
        information.tap()
        let selected = element("selectedJourney-\(id)", in: app)
        XCTAssertTrue(selected.waitForExistence(timeout: 10))
        let originalTitle = selected.label
        let share = element("journeyShareButton", in: app)
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        XCTAssertTrue(share.isHittable)
        share.tap()
        exerciseBothKinds(in: app, attachmentPrefix: "journey-menu")
        closeShare(in: app)

        XCTAssertTrue(selected.waitForExistence(timeout: 10))
        XCTAssertTrue(share.isHittable)
        XCTAssertEqual(selected.label, originalTitle)
    }

    private func exerciseBothKinds(
        in app: XCUIApplication, attachmentPrefix: String, validatesSunrise: Bool = false
    ) {
        XCTAssertTrue(element("journeyShareSheet", in: app).waitForExistence(timeout: 10))
        let picker = app.segmentedControls["journeyShareKindPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        for (index, kind) in ["Full journey", "Train information", "Full journey"].enumerated() {
            let choice = picker.buttons[kind]
            XCTAssertTrue(choice.exists)
            if !choice.isSelected { choice.tap() }
            XCTAssertTrue(choice.isSelected)
            waitForReadyPreview(in: app)
            let previews = app.descendants(matching: .any).matching(NSPredicate(
                format: "identifier BEGINSWITH %@", "journeySharePreview-"))
            XCTAssertEqual(previews.count, 1, "Each export kind must generate exactly one image.")
            XCTAssertTrue(element("journeySharePreview-0", in: app).exists)
            XCTAssertFalse(element("journeySharePreview-1", in: app).exists)
            if validatesSunrise {
                validateSunriseContent(
                    element("journeySharePreview-0", in: app).value as? String ?? "", full: kind == "Full journey")
            }
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "\(attachmentPrefix)-\(index)-\(kind)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    private func validateSunriseContent(_ text: String, full: Bool) {
        // These are every stopping station in the bundled 217-stop record.
        let stoppingStations = ["沼津", "富士", "静岡", "浜松", "姫路", "岡山", "倉敷",
                                "備中高梁", "新見", "米子", "安来", "松江", "宍道", "出雲市"]
        for station in stoppingStations {
            XCTAssertTrue(text.contains(station), "The image content must retain stopping station \(station).")
        }
        XCTAssertTrue(text.contains("34:00 (2026-07-30)"),
                      "The last stop must preserve the extended service time and its next-day date.")
        if full {
            XCTAssertTrue(text.contains("岡山まで5031M"), "Full sharing must include the journey's notes.")
            XCTAssertTrue(text.contains("片浜"), "Full sharing must retain recorded pass-through stations.")
            XCTAssertTrue(text.contains("20260729_05_sunrise_izumo"),
                          "Full sharing must include the advanced record identifier.")
        } else {
            XCTAssertFalse(text.contains("岡山まで5031M"), "Train information must omit private notes.")
            XCTAssertFalse(text.contains("片浜"), "Train information must omit pass-through stations.")
            XCTAssertFalse(text.contains("20260729_05_sunrise_izumo"),
                           "Train information must omit advanced record identifiers.")
        }
    }

    private func waitForReadyPreview(in app: XCUIApplication) {
        let send = element("journeyShareSendButton", in: app)
        let preview = element("journeySharePreview-0", in: app)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            send.exists && send.isEnabled && preview.exists && !preview.frame.isEmpty
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 90), .completed,
                       "Sharing must finish rendering before enabling Send.\n" + app.debugDescription)
    }

    private func closeShare(in app: XCUIApplication) {
        let close = element("journeyShareCloseButton", in: app)
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 10))
    }

    private func launch(journeyID: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-interface-language", "en"]
        app.launchEnvironment["RAILMAP_UI_TEST_SAMPLE"] = "train-store"
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "search"
        app.launchEnvironment["RAILMAP_UI_TEST_QUERY"] = journeyID
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "expanded"
        app.launch()
        return app
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
