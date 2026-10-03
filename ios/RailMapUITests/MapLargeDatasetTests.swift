import XCTest

/// Exercise the real sample-import controls before loading Japan's national map.
@MainActor
final class MapLargeDatasetTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testAll287SampleJourneysWithJapanNetworkLoadingPanAndToggle() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "all"
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "medium"
        app.launchEnvironment["RAILMAP_UI_TEST_GESTURE_TARGET"] = "1"
        app.launchEnvironment["RAILMAP_UI_TEST_CAMERA"] = "37,138,24"
        app.launch()
        defer { app.terminate() }
        let status = app.staticTexts["railMapRenderStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 20))
        let toggle = app.buttons["mapNetworkToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        if toggle.isSelected { toggle.tap() }

        app.buttons["utilityMenuButton"].tap()
        let data = app.buttons["utilityDataButton"]
        XCTAssertTrue(data.waitForExistence(timeout: 10))
        data.tap()
        let samples = [
            // The data page follows Region.ordered: scroll through it once.
            "Load Macao Sample Data", "Load Hong Kong Sample Data",
            "Load Taiwan Sample Data", "Load South Korea Sample Data",
            "Load Full Sample Data", "Load New Year Grand Loop",
            "Load Tokyo Limited-Express Loop"
        ]
        for name in samples {
            let button = app.buttons[name].firstMatch
            for _ in 0..<15 {
                if button.exists && button.isHittable { break }
                app.collectionViews.firstMatch.swipeUp()
            }
            XCTAssertTrue(button.exists, "Missing sample: \(name)")
            XCTAssertTrue(button.isHittable, "Sample not reachable: \(name)")
            let enabled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                button.exists && button.isEnabled
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 30), .completed)
            button.tap()
            let imported = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                button.exists && button.isEnabled
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [imported], timeout: 30), .completed)
        }
        app.buttons["utilityCloseButton"].tap()

        func fields() -> [String: String] {
            Dictionary(status.label.split(separator: ";").compactMap { field in
                let pair = field.split(separator: ":", maxSplits: 1)
                return pair.count == 2 ? (String(pair[0]), String(pair[1])) : nil
            }, uniquingKeysWith: { _, last in last })
        }
        func record(_ name: String) {
            let attachment = XCTAttachment(string: status.label)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertEqual(app.state, .runningForeground, "App exited during \(name)")
        }
        func waitForNetwork() {
            let rendered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let state = fields()
                return state["network"] == "rendered"
                    && (Int(state["lines"] ?? "") ?? 0) > 0
                    && (Int(state["overlays"] ?? "") ?? 0) > 0
                    && state["covered"] == "1"
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [rendered], timeout: 90), .completed)
        }
        let allRides = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            fields()["rides"] == "287"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [allRides], timeout: 180), .completed,
                       "All seven samples must resolve into 287 map rides.")
        record("all-287-imported")
        // Imports deliberately focus their region. Relaunch the persisted
        // complete store to apply the Japan camera before testing its network.
        app.terminate()
        app.launch()
        XCTAssertTrue(status.waitForExistence(timeout: 20))
        let japanCamera = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let state = fields()
            let lat = Double(state["centerLat"] ?? "") ?? 0
            let lon = Double(state["centerLon"] ?? "") ?? 0
            return (36...38).contains(lat) && (137...139).contains(lon)
                && state["rides"] == "287"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [japanCamera], timeout: 180), .completed)
        let target = app.otherElements["railMapGestureTarget"]
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        let frame = target.frame
        let origin = app.coordinate(withNormalizedOffset: .zero)
        func pan(_ right: Bool) {
            let start = origin.withOffset(CGVector(dx: frame.midX, dy: frame.midY))
            let end = origin.withOffset(CGVector(dx: frame.midX + (right ? 24 : -24), dy: frame.midY))
            // End the contact before releasing, so MapKit's fling does not
            // carry a short drag thousands of kilometres outside Japan.
            start.press(forDuration: 0.1, thenDragTo: end,
                        withVelocity: .slow, thenHoldForDuration: 0.5)
        }
        if !toggle.isSelected { toggle.tap() }
        pan(false)
        record("all-287-japan-loading-pan")
        waitForNetwork()
        record("all-287-network-rendered")
        func setNetwork(_ enabled: Bool) {
            let hittable = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                toggle.exists && toggle.isHittable
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [hittable], timeout: 30), .completed,
                           "Network control must have a real hit point before tapping.")
            toggle.tap()
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                toggle.isSelected == enabled
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 15), .completed)
        }
        for index in 0..<3 {
            setNetwork(false)
            setNetwork(true)
            pan(index.isMultiple(of: 2))
            waitForNetwork()
            record("all-287-toggle-pan-\(index)")
            XCTAssertEqual(fields()["rides"], "287")
            XCTAssertTrue((30...45).contains(Double(fields()["centerLat"] ?? "") ?? 0))
            XCTAssertTrue((125...150).contains(Double(fields()["centerLon"] ?? "") ?? 0))
        }
        XCTAssertGreaterThan(Int(fields()["panCallbacks"] ?? "") ?? 0, 0,
                             "Dragging must actually move the MapKit camera.")
        XCTAssertGreaterThan(Int(fields()["gestureFrames"] ?? "") ?? 0, 0,
                             "The display-link probe must observe a real gesture.")
        // Keep the complete dataset resident long enough to catch continued loading exits.
        let residence = Date().addingTimeInterval(75)
        while Date() < residence {
            record("all-287-residence")
            Thread.sleep(forTimeInterval: 5)
        }
        XCTAssertEqual(fields()["rides"], "287")
        let screen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screen.name = "all-287-final-japan-network"
        screen.lifetime = .keepAlways
        add(screen)
    }
}
