import RailPresentation
import XCTest

/// Dragging the resident menu between its stops is a layout change of the
/// sheet alone. The map underneath keeps its frame, its camera and its
/// installed overlays, and the floating control rail follows the sheet edge
/// without dropping out or jumping back.
@MainActor
final class SheetDragStabilityUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testDraggingThePanelThroughItsStopsDoesNotRebuildOrMoveTheMap() throws {
#if !targetEnvironment(macCatalyst)
        XCUIDevice.shared.orientation = .portrait
        let app = launch()
        let status = app.staticTexts["railMapRenderStatus"]
        waitFor(status) { self.number("rebuilds", $0) >= 1 && $0.contains("network:") }
        // Let launch-time work (region loading, camera-quiet restyle) finish
        // before taking the baseline, so only the drags are measured.
        Thread.sleep(forTimeInterval: 4)
        let before = status.label
        let header = app.descendants(matching: .any)["panelHeader"].firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        let layers = app.buttons["mapLayersButton"].firstMatch
        XCTAssertTrue(layers.waitForExistence(timeout: 10))
        let compactRail = layers.frame
        let compactHeader = header.frame
        attachScreenshot(app, "sheet-drag-0-compact")

        // Compact → half, slowly, so the sheet follows the finger frame by frame.
        drag(header, by: -(app.frame.height * 0.30), app: app)
        settle()
        attachScreenshot(app, "sheet-drag-1-half")
        XCTAssertLessThan(header.frame.minY, compactHeader.minY - 60, "The panel did not rise.")
        XCTAssertTrue(layers.exists && layers.isHittable, "The control rail must stay above the half stop.")
        // The rail rides on the sheet edge: it rises by the panel's travel.
        let rise = compactHeader.minY - header.frame.minY
        XCTAssertEqual(compactRail.minY - layers.frame.minY, rise, accuracy: 24,
                       "The control rail must follow the sheet edge.")
        XCTAssertEqual(layers.frame.minX, compactRail.minX, accuracy: 1,
                       "The control rail must not move sideways.")

        // Half → full and back down to compact.
        drag(header, by: -(app.frame.height * 0.45), app: app)
        settle()
        attachScreenshot(app, "sheet-drag-2-full")
        XCTAssertFalse(layers.isHittable, "The control rail must be hidden at the full stop.")
        drag(header, by: app.frame.height * 0.75, app: app)
        settle()
        attachScreenshot(app, "sheet-drag-3-compact")
        XCTAssertEqual(header.frame.minY, compactHeader.minY, accuracy: 4,
                       "The panel did not return to its compact stop.")
        XCTAssertEqual(layers.frame.minY, compactRail.minY, accuracy: 2,
                       "The control rail did not return to its compact position.")

        let after = status.label
        XCTAssertEqual(number("rebuilds", after), number("rebuilds", before),
                       "A panel drag rebuilt the map.\nBefore: \(before)\nAfter: \(after)")
        XCTAssertEqual(number("gestureBuilds", after), number("gestureBuilds", before))
        XCTAssertEqual(number("viewportWidth", after), number("viewportWidth", before))
        XCTAssertEqual(number("viewportHeight", after), number("viewportHeight", before),
                       "A panel drag resized the map.")
        for key in ["centerLon", "centerLat"] {
            XCTAssertEqual(number(key, after), number(key, before), accuracy: 0.0001,
                           "A panel drag moved the camera.\nBefore: \(before)\nAfter: \(after)")
        }
        XCTAssertEqual(number("distance", after), number("distance", before),
                       accuracy: max(1, number("distance", before) * 0.001))
#else
        throw XCTSkip("The resident sheet is phone-only")
#endif
    }

    private func drag(_ header: XCUIElement, by distance: CGFloat, app: XCUIApplication) {
        let start = header.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        // Slow enough that UIKit reports a stream of heights rather than a flick.
        start.press(forDuration: 0.2,
                    thenDragTo: start.withOffset(CGVector(dx: 0, dy: distance)),
                    withVelocity: 300,
                    thenHoldForDuration: 0.3)
    }

    private func settle() { Thread.sleep(forTimeInterval: 1.5) }

    private func attachScreenshot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.uiTestLaunch[.storageId] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-auto-focus-zoom", "NO"]
        app.uiTestLaunch[.tab] = "all"
        app.uiTestLaunch[.stage] = "compact"
        app.uiTestLaunch[.sample] = "train-store"
        app.uiTestLaunch[.layers] = "routes,focus"
        app.uiTestLaunch[.camera] = "35.681,139.767,0.2"
        UITestLaunchSupport.launch(app)
        return app
    }

    private func waitFor(_ status: XCUIElement, predicate: @escaping (String) -> Bool) {
        XCTAssertTrue(status.waitForExistence(timeout: 15))
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in predicate(status.label) }, object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 45), .completed, status.label)
    }

    private func number(_ key: String, _ status: String) -> Double {
        let prefix = key + ":"
        guard let field = status.split(separator: ";").first(where: { $0.hasPrefix(prefix) }),
            let value = Double(field.dropFirst(prefix.count)) else { return .nan }
        return value
    }
}
