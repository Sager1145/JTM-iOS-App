import RailPresentation
import UIKit
import XCTest

/// Explicit stress coverage; ordinary test runs do not launch it.
@MainActor
final class MenuStressUITests: XCTestCase {
    private let tabs = ["Upcoming", "Stats", "All", "Search"]
    private let headers = ["Upcoming", "Stats", "All journeys", "Search & Actions"]
    private let stages = ["compact", "medium", "expanded"]
    private let query = "menu stress retained query"
    private var app: XCUIApplication?
    private var context = "launch"

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }
    override func tearDown() async throws {
        await MainActor.run {
            app?.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
        try await super.tearDown()
    }

    func testEveryDirectedTabPairTwiceFromEachInitialStage() throws {
        try requireOptIn("MENU_STRESS_TEST")
        // Euler walk over all 16 directed pairs, including all four self-pairs.
        let walk = [0, 0, 1, 0, 2, 0, 3, 1, 1, 2, 1, 3, 2, 2, 3, 3, 0]
        var restoredPairs = 0
        for stage in stages {
            let app = launch(stage: stage, tab: "upcoming")
            assertDestination(0, in: app)
            for cycle in 1...2 {
                for (source, target) in zip(walk, walk.dropFirst()) {
                    context = "initial=\(stage), cycle=\(cycle), \(tabs[source])→\(tabs[target])"
                    assertDestination(source, in: app)
                    if restoreDockStage(stage, in: app) { restoredPairs += 1 }
                    choose(target, in: app)
                    if target == 3 { assertSearchQuery(in: app) }
                }
            }
            app.terminate()
        }
        note("Completed 96 transitions: 3 launch stages × 16 directed pairs × 2 cycles. \(restoredPairs) pairs began at an asserted dock stage; \(96 - restoredPairs) have initial-stage scope only. Search opens when needed; Duo compact may intentionally promote to medium.")
    }

    func testEveryDestinationWithEveryRotationRequestFromEachInitialStage() throws {
        try requireOptIn("MENU_STRESS_TEST")
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("Catalyst uses window resizing, not device orientation requests.")
        #else
        let orientations: [UIDeviceOrientation] = [
            .portrait, .landscapeLeft, .landscapeRight, .portraitUpsideDown
        ]
        for stage in stages {
            let app = launch(stage: stage, tab: "upcoming")
            assertDestination(0, in: app)
            let duo = isDuo(in: app)
            for destination in tabs.indices {
                choose(destination, in: app)
                for orientation in orientations {
                    context = "initial=\(stage), tab=\(tabs[destination]), request=\(orientation.rawValue)"
                    XCUIDevice.shared.orientation = orientation
                    XCTAssertEqual(XCUIDevice.shared.orientation, orientation, context)
                    if !duo {
                        let landscape = UIDevice.current.userInterfaceIdiom == .pad && orientation.isLandscape
                        wait {
                            let frame = app.windows.firstMatch.frame
                            return !frame.isEmpty && (landscape ? frame.width > frame.height : frame.height > frame.width)
                        }
                    }
                    assertDestination(destination, in: app)
                    // Return through Search so every request checks retained query.
                    choose(3, in: app)
                    assertSearchQuery(in: app)
                    choose(destination, in: app)
                }
            }
            app.terminate()
        }
        note("Completed 48 orientation requests: 3 initial stages × 4 destinations × 4 requests; Search retained after each. Ordinary iPhone stays portrait; ordinary iPad window aspect matches requests. Aspect cannot distinguish left/right or portrait/upside-down. Duo requests do not establish posture changes.")
        #endif
    }

    func testOperatorCoordinatedDuoFoldAndUnfoldRetainsSearch() throws {
        try requireOptIn("MENU_STRESS_TEST")
        try requireOptIn("DUO_MENU_POSTURE_TEST")
        let app = launch(stage: "medium", tab: "search")
        assertDestination(3, in: app)
        try XCTSkipUnless(isDuo(in: app) && app.frame.width >= 600,
                          "Start on expanded Duo with a Device Hub posture operator.")
        assertSearchQuery(in: app)
        let field = app.textFields["journeySearchField"]
        field.tap()
        field.typeText(" edited")
        let retained = query + " edited"
        XCTAssertEqual(field.value as? String, retained, context)
        let expandedWidth = app.windows.firstMatch.frame.width
        context = "Duo expanded→folded with Search input"
        print("DUO_MENU_WAIT_CLOSED")
        wait(timeout: 180) { app.windows.firstMatch.frame.width < expandedWidth - 50 }
        for destination in tabs.indices { choose(destination, in: app) }
        assertSearchQuery(in: app, expected: retained)
        context = "Duo folded→expanded with Search retained"
        print("DUO_MENU_WAIT_OPEN")
        wait(timeout: 180) { abs(app.windows.firstMatch.frame.width - expandedWidth) < 2 }
        for destination in tabs.indices { choose(destination, in: app) }
        assertSearchQuery(in: app, expected: retained)
        note("Completed one operator-coordinated expanded→folded→expanded cycle; four destinations reachable and edited Search retained after each posture change.")
    }

    private func launch(stage: String, tab: String) -> XCUIApplication {
        app?.terminate()
        XCUIDevice.shared.orientation = .portrait
        context = "launch initial=\(stage), tab=\(tab)"
        let launched = XCUIApplication()
        app = launched
        launched.uiTestLaunch[.storageId] = UUID().uuidString
        launched.uiTestLaunch[.tab] = tab
        launched.uiTestLaunch[.stage] = stage
        launched.uiTestLaunch[.query] = query
        launched.uiTestLaunch[.sample] = "train-store"
        launched.uiTestLaunch[.statsRegion] = "all"
        launched.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                                    "-interface-language", "en"]
        UITestLaunchSupport.launch(launched)
        return launched
    }

    private func destination(_ index: Int, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", tabs[index])).firstMatch
    }

    private func choose(_ index: Int, in app: XCUIApplication) {
        var target = destination(index, in: app)
        let more = app.buttons["duoKeyboardMoreButton"]
        if !target.isHittable && more.exists && more.isHittable {
            more.tap()
            target = destination(index, in: app)
        }
        wait { target.exists && target.isHittable }
        target.tap()
        context += ", arrival=\(tabs[index]), actualStage=\(actualStage(in: app))"
        assertDestination(index, in: app)
    }

    private func assertDestination(_ index: Int, in app: XCUIApplication) {
        let tab = destination(index, in: app)
        let header = app.staticTexts.matching(identifier: "panelHeader")
            .matching(NSPredicate(format: "label == %@", headers[index])).firstMatch
        wait { tab.isSelected && header.exists && header.isHittable
            && !header.frame.isEmpty && app.frame.contains(header.frame) }
        XCTAssertTrue(tab.isSelected, "The requested native destination must be selected. \(context)")
        XCTAssertEqual(header.label, headers[index], context)
    }

    private func assertSearchQuery(in app: XCUIApplication, expected: String? = nil) {
        let field = app.textFields["journeySearchField"]
        if !field.isHittable {
            let toggle = app.buttons["dockPanelToggle"]
            if toggle.exists && toggle.isHittable {
                toggle.tap()
            } else {
                let header = app.staticTexts.matching(identifier: "panelHeader")
                    .matching(NSPredicate(format: "label == %@", headers[3])).firstMatch
                let start = header.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                let end = start.withOffset(CGVector(dx: 0, dy: -260))
                #if targetEnvironment(macCatalyst)
                start.click(forDuration: 0.1, thenDragTo: end)
                #else
                start.press(forDuration: 0.1, thenDragTo: end)
                #endif
            }
        }
        wait { field.exists && field.isHittable }
        XCTAssertEqual(field.value as? String, expected ?? query, context)
    }

    private func actualStage(in app: XCUIApplication) -> String {
        app.buttons["dockPanelToggle"].value as? String ?? "unexposed"
    }

    private func restoreDockStage(_ requested: String, in app: XCUIApplication) -> Bool {
        let toggle = app.buttons["dockPanelToggle"]
        guard toggle.exists, stages.contains(actualStage(in: app)) else { return false }
        for _ in 0..<3 {
            if actualStage(in: app) == requested { return true }
            let before = actualStage(in: app)
            wait { toggle.isHittable }
            toggle.tap()
            wait { self.actualStage(in: app) != before }
        }
        XCTAssertEqual(actualStage(in: app), requested, "Restore the dock stage before each pair. \(context)")
        return actualStage(in: app) == requested
    }

    private func isDuo(in app: XCUIApplication) -> Bool {
        let first = destination(0, in: app), last = destination(3, in: app)
        return first.exists && last.exists && abs(first.frame.midX - last.frame.midX) < 4
            && first.frame.maxY < last.frame.minY
    }

    private func requireOptIn(_ key: String) throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env[key] == "1" || env["TEST_RUNNER_" + key] == "1",
                          "Explicitly enable \(key)=1 for this stress case.")
    }

    private func wait(timeout: TimeInterval = 10, _ condition: @escaping () -> Bool) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        let result = XCTWaiter.wait(for: [ready], timeout: timeout)
        if result != .completed, let app {
            note("Failure: \(context), actualStage=\(actualStage(in: app))\n\(app.debugDescription)")
            let capture = XCTAttachment(screenshot: app.screenshot())
            capture.name = context
            capture.lifetime = .keepAlways
            add(capture)
        }
        XCTAssertEqual(result, .completed, context)
    }

    private func note(_ text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = "Menu stress coverage"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
