import RailPresentation
import XCTest

/// A trip with recorded actual times shows the actual clock, the scheduled one
/// struck through and a signed marker, on the list card and in the opened
/// journey's detail. Screenshots are kept for review, light and dark.
@MainActor
final class DelayDisplayUITests: XCTestCase {
    private let tripID = "uitest_delaydisplay"

    override func setUp() { continueAfterFailure = false }

    func testDelayShownOnCardAndDetailInLightMode() {
        exerciseCardAndDetail(style: nil, suffix: "light")
    }

    func testDelayShownOnCardAndDetailInDarkMode() {
        exerciseCardAndDetail(style: "Dark", suffix: "dark")
    }

    private func exerciseCardAndDetail(style: String?, suffix: String) {
        // The list card.
        let list = launch(selecting: false, style: style)
        let row = element("journeyRow-\(tripID)", in: list)
        XCTAssertTrue(row.waitForExistence(timeout: 60), list.debugDescription)
        XCTAssertTrue(row.label.contains("10:35"), row.label)
        XCTAssertTrue(row.label.contains("scheduled 10:30"), row.label)
        XCTAssertTrue(row.label.contains("5 min late"), row.label)
        XCTAssertTrue(row.label.contains("12:58"), row.label)
        XCTAssertFalse(row.label.contains("00:00"), row.label)
        snapshot("delay-card-\(suffix)", list)
        list.terminate()

        // The opened journey.
        let app = launch(selecting: true, style: style)
        let timing = element("rideCardTiming", in: app)
        XCTAssertTrue(timing.waitForExistence(timeout: 60), app.debugDescription)
        XCTAssertTrue(timing.label.contains("10:35"), timing.label)
        XCTAssertTrue(timing.label.contains("5 min late"), timing.label)
        XCTAssertTrue(timing.label.contains("3 min late"), timing.label)
        let departure = element("rideDetailDeparture", in: app)
        if !departure.exists {
            let scroll = app.scrollViews.firstMatch
            for _ in 0..<6 where !departure.exists { scroll.swipeUp() }
        }
        XCTAssertTrue(departure.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(departure.label.contains("10:35"), departure.label)
        XCTAssertTrue(departure.label.contains("scheduled 10:30"), departure.label)
        XCTAssertTrue(departure.label.contains("5 min late"), departure.label)
        snapshot("delay-detail-\(suffix)", app)
        app.terminate()
    }

    // MARK: -

    private func launch(selecting: Bool, style: String?) -> XCUIApplication {
        let app = XCUIApplication()
        app.uiTestLaunch[.storageId] = UUID().uuidString
        // The seeded trip is in the past, so it lists under History, not Upcoming.
        app.uiTestLaunch[.tab] = "all"
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-interface-language", "en"]
            + (style.map { ["-AppleInterfaceStyle", $0] } ?? [])
        app.uiTestLaunch[.storeBase64] = seededStore()
        if selecting {
            app.uiTestLaunch[.select] = tripID
            app.uiTestLaunch[.stage] = "expanded"
        }
        UITestLaunchSupport.launch(app)
        return app
    }

    /// Scheduled 10:30 / 12:55, actual 10:35 / 12:58.
    private func seededStore() -> String {
        var origin = EditorLaunchSupport.stop("Tokyo", code: "003768", type: "origin", departure: "10:30")
        origin["actual_departure"] = "10:35"
        var destination = EditorLaunchSupport.stop(
            "Shinagawa", code: "004092", type: "destination", arrival: "12:55")
        destination["actual_arrival"] = "12:58"
        let train: [String: Any] = [
            "id": tripID, "date": "2026-10-12", "number": "Delay 1",
            "origin": "Tokyo", "destination": "Shinagawa", "region": "jp",
            "stops": [origin, destination],
        ]
        let store: [String: Any] = ["schema_version": "1.3", "trains": [train]]
        return try! JSONSerialization.data(withJSONObject: store, options: [.sortedKeys])
            .base64EncodedString()
    }

    private func snapshot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
