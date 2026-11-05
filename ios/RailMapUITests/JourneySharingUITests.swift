import RailPresentation
import Foundation
import XCTest

@MainActor
final class JourneySharingUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testLongJourneyCardPreviewsOneImageForBothStopModesAndReturnsToSameJourney() {
        // A clearly synthetic pending record exercises a 217-row tall image.
        // It is neither production sample data nor railway/timetable evidence.
        let id = "20260729_05_sunrise_izumo"
        let app = launch(journeyID: id, syntheticLongRecord: true)
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
        exerciseBothStopModes(in: app, attachmentPrefix: "sunrise-217-stops", validatesSunrise: true)
        closeShare(in: app)

        XCTAssertTrue(selected.waitForExistence(timeout: 10))
        XCTAssertEqual(selected.label, originalTitle)
        XCTAssertTrue(share.isHittable)
        element("journeyBackToList", in: app).tap()
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["journeySearchField"].value as? String, id)
    }

    func testJourneyMenuPreviewsBothStopModesAndReturnsToSameJourney() {
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
        exerciseBothStopModes(in: app, attachmentPrefix: "journey-menu")
        closeShare(in: app)

        XCTAssertTrue(selected.waitForExistence(timeout: 10))
        XCTAssertTrue(share.isHittable)
        XCTAssertEqual(selected.label, originalTitle)
    }

    private func exerciseBothStopModes(
        in app: XCUIApplication, attachmentPrefix: String, validatesSunrise: Bool = false
    ) {
        XCTAssertTrue(element("shareComposerRoot", in: app).waitForExistence(timeout: 10))
        let picker = app.segmentedControls["shareStopsPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10), app.debugDescription)
        for (index, mode) in ["Key stops", "All stops"].enumerated() {
            let choice = picker.buttons[mode]
            XCTAssertTrue(choice.exists)
            if !choice.isSelected { choice.tap() }
            XCTAssertTrue(choice.isSelected)
            let preview = element("sharePreview", in: app)
            XCTAssertTrue(preview.waitForExistence(timeout: 30), app.debugDescription)
            let text = preview.value as? String ?? ""
            XCTAssertFalse(text.isEmpty, "The preview must expose the card's text.")
            if validatesSunrise {
                validateSunriseContent(text, allStops: mode == "All stops")
            }
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "\(attachmentPrefix)-\(index)-\(mode)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        XCTAssertTrue(exportAndExpectShareSheet(in: app), app.debugDescription)
        dismissShareSheet(in: app)
    }

    private func validateSunriseContent(_ text: String, allStops: Bool) {
        // These passenger-call labels are deliberately retained in the synthetic
        // fixture; its passing rows test rendering, not inferred rail topology.
        let stoppingStations = ["沼津", "富士", "静岡", "浜松", "姫路", "岡山", "倉敷",
                                "備中高梁", "新見", "米子", "安来", "松江", "宍道", "出雲市"]
        for station in stoppingStations {
            XCTAssertTrue(text.contains(station), "The card must retain stopping station \(station).")
        }
        XCTAssertTrue(text.contains("34:00"), "The last stop must preserve the extended service time.")
        if allStops {
            XCTAssertTrue(text.contains("片浜"), "All stops must retain recorded pass-through stations.")
        } else {
            XCTAssertFalse(text.contains("片浜"), "Key stops must omit pass-through stations.")
        }
    }

    private func closeShare(in app: XCUIApplication) {
        let close = element("shareCloseButton", in: app)
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 10))
    }


    /// Taps the composer's export button and waits for the system share sheet
    /// (UIActivityViewController), tolerating the several shapes it takes
    /// across iOS versions. Returns true once it is on screen.
    private func exportAndExpectShareSheet(in app: XCUIApplication) -> Bool {
        let export = element("shareImageButton", in: app)
        XCTAssertTrue(export.waitForExistence(timeout: 30))
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in export.isEnabled }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 60), .completed)
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

    private func launch(journeyID: String, syntheticLongRecord: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.uiTestLaunch[.storageId] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-interface-language", "en"]
        app.uiTestLaunch[.sample] = "train-store"
        if syntheticLongRecord {
            app.uiTestLaunch[.storeBase64] = syntheticLongJourney()
        }
        app.uiTestLaunch[.tab] = "search"
        app.uiTestLaunch[.query] = journeyID
        app.uiTestLaunch[.stage] = "expanded"
        UITestLaunchSupport.launch(app)
        return app
    }

    private func syntheticLongJourney() -> String {
        let calls = ["沼津", "富士", "静岡", "浜松", "姫路", "岡山", "倉敷",
                     "備中高梁", "新見", "米子", "安来", "松江", "宍道", "出雲市"]
        var stops: [[String: Any]] = []
        for (index, name) in calls.enumerated() {
            var stop: [String: Any] = [
                "name": name, "ride_segment": true,
                "stop_type": index == 0 ? "origin" : index == calls.count - 1 ? "destination" : "passenger_stop",
            ]
            if index == 0 { stop["departure"] = "23:16" }
            if index == calls.count - 1 { stop["arrival"] = "34:00" }
            stops.append(stop)
            if index == 0 {
                for row in 0..<203 {
                    stops.append([
                        "name": row == 0 ? "片浜" : String(format: "UI合成通過%03d", row),
                        "stop_type": "pass_through", "ride_segment": true,
                    ])
                }
            }
        }
        XCTAssertEqual(stops.count, 217, "The rendering stress input must remain tall.")
        let train: [String: Any] = [
            "id": "20260729_05_sunrise_izumo", "date": "2026-07-29",
            "number": "サンライズ出雲（UI合成記録）（5031M/4031M）", "train_type": "寝台特急",
            "company": "JR東海/JR西日本", "origin": "沼津", "destination": "出雲市",
            "direction": "unknown", "visible": true, "stops": stops,
            "route_confirmation": "pending",
            "notes": "UI-only synthetic rendering fixture; no timetable or physical railway evidence. 岡山まで5031M",
        ]
        let store: [String: Any] = ["schema_version": "1.3", "trains": [train]]
        return try! JSONSerialization.data(withJSONObject: store, options: [.sortedKeys]).base64EncodedString()
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
