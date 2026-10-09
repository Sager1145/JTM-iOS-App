import XCTest

/// The runner seeds a separately owned container with the committed two-ride fixture.
@MainActor
final class RefactorReleaseMemoryUITests: XCTestCase {
    func testTwoRealRegionsCompleteRoutesAndStatistics() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let map = app.descendants(matching: .any)["railwayMap"]
        XCTAssertTrue(map.waitForExistence(timeout: 60), app.debugDescription)
        XCTAssertEqual(map.label, "Map")
        let routesLoaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            map.exists && map.value as? String == "Routes loaded"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [routesLoaded], timeout: 240), .completed,
                       app.debugDescription)
        // The containing status must preserve the real MKMapView and its children.
        let nativeMap = app.maps.firstMatch
        XCTAssertTrue(nativeMap.exists, app.debugDescription)
        // MapKit can expose an empty map node. Its annotation container is
        // a sibling inside the map wrapper, not a child of that map node.
        XCTAssertTrue(map.descendants(matching: .map).firstMatch.exists,
                      "The status container must preserve the native map.")
        XCTAssertTrue(map.descendants(matching: .any)["AnnotationContainer"].exists,
                      "The status container must preserve native annotations: \(app.debugDescription)")
        let all = app.tabBars.buttons["All"]
        XCTAssertTrue(all.waitForExistence(timeout: 30), app.debugDescription)
        all.tap()
        for id in ["20260722_06_sonic44",
                   "20260802_01_taoyuan_airport_mrt_express_t2_taipei"] {
            assertPhysicalRouteGenerated(id, in: app)
        }
        let stats = app.tabBars.buttons["Stats"]
        XCTAssertTrue(stats.waitForExistence(timeout: 60), app.debugDescription)
        stats.tap()
        let share = app.descendants(matching: .any)["statisticsShareButton"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            share.exists && share.isEnabled
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 180), .completed, app.debugDescription)
        let region = app.descendants(matching: .any)["regionScopeButton"]
        XCTAssertEqual(region.value as? String, "All regions")
        // Keep the same fully loaded screen for the external footprint sampler.
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate(value: false), object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 8), .timedOut)
        XCTAssertTrue(share.isEnabled)
        XCTAssertEqual(region.value as? String, "All regions")
    }

    private func assertPhysicalRouteGenerated(_ id: String, in app: XCUIApplication) {
        let row = revealRideRow(id, in: app)
        XCTAssertTrue(row.exists && row.isHittable,
                      "Missing real fixture ride \(id): \(app.debugDescription)")
        // Capture the visible tab bar before the journey menu can hide its
        // accessibility node while still covering the lower scroll region.
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.exists, app.debugDescription)
        let tabBarFrame = tabBar.frame
        row.tap()
        let selected = app.descendants(matching: .any)["selectedJourney-\(id)"].firstMatch
        XCTAssertTrue(selected.waitForExistence(timeout: 15), app.debugDescription)
        // The selected journey menu embeds production RideDetailContent. Its
        // always-present route-state header uses ios.route.resolved, whose
        // committed English wording is "Route generated".
        let resolved = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "Route generated")).firstMatch
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 15), app.debugDescription)
        for _ in 0..<50 {
            if resolved.exists && resolved.isHittable { break }
            guard dragDetailUp(scroll, above: tabBarFrame, in: app) else { break }
        }
        XCTAssertTrue(resolved.exists && resolved.isHittable,
                      "Real ride \(id) must report physical resolution in its public detail: \(app.debugDescription)")
        let back = app.descendants(matching: .any)["journeyBackToList"].firstMatch
        XCTAssertTrue(back.exists && back.isHittable, app.debugDescription)
        back.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 15), app.debugDescription)
    }

    private func revealRideRow(_ id: String, in app: XCUIApplication) -> XCUIElement {
        let all = app.tabBars.buttons["All"]
        XCTAssertTrue(all.waitForExistence(timeout: 15), app.debugDescription)
        all.tap()
        let header = app.descendants(matching: .any)["panelHeader"].firstMatch
        let viewport = app.descendants(matching: .any)["workspaceMenuViewport"].firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(viewport.waitForExistence(timeout: 15), app.debugDescription)
        // Closing a journey preserves the All panel's size and scroll position.
        // Expand that public sheet before seeking a lazily instantiated row.
        for _ in 0..<3 {
            let bar = app.tabBars.firstMatch.frame
            let visibleHeight = min(viewport.frame.maxY, bar.minY - 12) - viewport.frame.minY
            if visibleHeight >= 220 { break }
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(
                dx: header.frame.midX - app.frame.minX,
                dy: header.frame.midY - app.frame.minY))
            let end = origin.withOffset(CGVector(
                dx: header.frame.midX - app.frame.minX, dy: app.frame.height * 0.20))
            start.press(forDuration: 0.15, thenDragTo: end)
        }
        let row = app.descendants(matching: .any)["journeyRow-\(id)"].firstMatch
        let list = viewport.descendants(matching: .collectionView).firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 15), app.debugDescription)
        let tabBarFrame = app.tabBars.firstMatch.frame
        for _ in 0..<12 {
            if row.exists && row.isHittable && row.frame.maxY < tabBarFrame.minY - 8 { break }
            guard dragDetailUp(list, above: tabBarFrame, in: app) else { break }
        }
        return row
    }

    private func dragDetailUp(_ scroll: XCUIElement, above tabBarFrame: CGRect,
                              in app: XCUIApplication) -> Bool {
        var bounds = scroll.frame.intersection(app.frame)
        if tabBarFrame.intersects(bounds) {
            bounds.size.height = max(0, min(bounds.maxY, tabBarFrame.minY - 12) - bounds.minY)
        }
        for bar in app.tabBars.allElementsBoundByIndex where bar.exists && bar.frame.intersects(bounds) {
            bounds.size.height = max(0, min(bounds.maxY, bar.frame.minY - 12) - bounds.minY)
        }
        let keyboard = app.keyboards.firstMatch
        if keyboard.exists && keyboard.frame.intersects(bounds) {
            bounds.size.height = max(0, keyboard.frame.minY - bounds.minY)
        }
        bounds = bounds.insetBy(dx: 8, dy: 8)
        guard !bounds.isNull, bounds.width > 20, bounds.height > 40 else { return false }
        // Short drags keep the state header within the visible viewport and
        // start above the tab bar even when the scroll extends underneath it.
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let x = bounds.minX + bounds.width * 0.15 - app.frame.minX
        let start = origin.withOffset(CGVector(
            dx: x, dy: bounds.minY + bounds.height * 0.70 - app.frame.minY))
        let end = origin.withOffset(CGVector(
            dx: x, dy: bounds.minY + bounds.height * 0.30 - app.frame.minY))
        start.press(forDuration: 0.15, thenDragTo: end)
        return true
    }

}
