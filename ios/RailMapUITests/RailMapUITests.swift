import XCTest
import UIKit

@MainActor
final class RailMapUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testAllJourneyFinalCardClearsTabBar() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone)
        XCUIDevice.shared.orientation = .portrait

        for stage in ["medium", "expanded"] {
            let app = launch(tab: "all", stage: stage, sample: "train-store")
            XCTAssertTrue(element("journeyRow-20260703_01_haruka", in: app)
                .waitForExistence(timeout: 20))
            let date = element("journeyDateButton", in: app)
            XCTAssertTrue(date.isHittable)
            date.tap()
            let day = app.buttons.matching(NSPredicate(
                format: "label CONTAINS %@", "2026-07-03")).firstMatch
            XCTAssertTrue(day.waitForExistence(timeout: 5))
            // Native menus expose offscreen entries before they can receive
            // a tap. Reveal the actual date rather than letting tap's
            // implicit scroll leave the menu open over the panel.
            for _ in 0..<6 {
                if day.isHittable { break }
                let menus = app.collectionViews
                XCTAssertGreaterThan(menus.count, 0)
                menus.element(boundBy: menus.count - 1).swipeUp()
            }
            XCTAssertTrue(day.isHittable)
            day.tap()
            let selectedDate = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value CONTAINS %@", "2026-07-03"),
                object: date)
            XCTAssertEqual(XCTWaiter.wait(for: [selectedDate], timeout: 5), .completed)

            let viewport = element("workspaceMenuViewport", in: app)
            let tabs = app.tabBars.firstMatch
            let last = element("journeyRow-20260703_03_tokaido_main_local", in: app)
            for _ in 0..<6 {
                if last.exists {
                    let frame = last.frame
                    if !frame.isEmpty,
                       frame.minY >= viewport.frame.minY,
                       frame.maxY <= tabs.frame.minY - 12,
                       last.isHittable { break }
                }
                scrollMenuUp(viewport, above: tabs, in: app)
            }
            print("[tab-clearance] viewport=\(viewport.frame) value=\(String(describing: viewport.value)) tab=\(tabs.frame) last=\(last.frame)")
            XCTAssertTrue(last.exists)
            XCTAssertTrue(last.isHittable)
            XCTAssertGreaterThanOrEqual(last.frame.minY, viewport.frame.minY)
            XCTAssertLessThanOrEqual(
                last.frame.maxY, tabs.frame.minY - 12,
                "The entire final All journey card must scroll clear of the tab bar.")
            attach(app, named: "all-final-card-above-tab-bar-\(stage)")
            app.terminate()
        }
    }

    func testSearchDestinationAlwaysExposesAField() {
        let app = launch(tab: "search", stage: "medium")
        XCTAssertTrue(
            element("journeySearchField", in: app).waitForExistence(timeout: 8),
            "The semantic Search destination must never open without a text field.")
    }

    func testMenuContentFollowsSystemTabBar() {
        let app = launch(tab: "all", stage: "medium", sample: "train-store")
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 8))

        for index in [2, 1, 0, 3] {
            tabs.buttons.element(boundBy: index).tap()
            let viewport = element("workspaceMenuViewport", in: app)
            XCTAssertTrue(viewport.waitForExistence(timeout: 8))
            assertViewportFollowsSystemTabBar(viewport, tabs: tabs, in: app)
        }
        attach(app, named: "menu-content-under-tab-bar")
    }


    // Check excess bottom space separately from final-card clearance.
    func testPhoneMediumMenuDoesNotReserveTabBarTwice() throws {
        try assertPhoneMenuBottomGap(stage: "medium")
    }
    func testPhoneExpandedMenuDoesNotReserveTabBarTwice() throws {
        try assertPhoneMenuBottomGap(stage: "expanded")
    }
    private func assertPhoneMenuBottomGap(stage: String) throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone)
        XCUIDevice.shared.orientation = .portrait
        let app = launch(tab: "all", stage: stage, sample: "train-store")
        let viewport = element("workspaceMenuViewport", in: app)
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 8))
        XCTAssertTrue(viewport.waitForExistence(timeout: 8))
        let viewportFrame = viewport.frame
        let tabFrame = tabs.frame
        let gap = tabFrame.minY - viewportFrame.maxY
        let payload: [String: Any] = [
            "stage": stage, "viewport": [viewportFrame.minX, viewportFrame.minY, viewportFrame.width, viewportFrame.height],
            "tabBar": [tabFrame.minX, tabFrame.minY, tabFrame.width, tabFrame.height],
            "viewportToTabTopGap": gap, "tabHeight": tabFrame.height,
            "scope": "Native viewport and tab-bar frames; full-card clearance is checked separately"]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let evidence = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        evidence.name = "menu-bottom-gap-" + stage
        evidence.lifetime = .keepAlways
        add(evidence)
        attach(app, named: "menu-bottom-gap-" + stage)
        assertViewportFollowsSystemTabBar(viewport, tabs: tabs, in: app, gap: gap)
        app.terminate()
    }

    /// iOS 26+ draws a transparent bar and the menu continues beneath it.
    /// Earlier systems draw a solid bar, and the menu stops at that bar
    /// without a second reserved strip.
    private func assertViewportFollowsSystemTabBar(
        _ viewport: XCUIElement,
        tabs: XCUIElement,
        in app: XCUIApplication,
        gap: CGFloat? = nil
    ) {
        XCTAssertGreaterThan(viewport.frame.height, 0)
        XCTAssertLessThan(viewport.frame.minY, tabs.frame.minY)
        let space = gap ?? (tabs.frame.minY - viewport.frame.maxY)
        if #available(iOS 26.0, *) {
            XCTAssertGreaterThan(
                viewport.frame.maxY, tabs.frame.minY + 8,
                "On iOS 26 the menu must draw under the transparent tab bar.")
            XCTAssertLessThanOrEqual(
                viewport.frame.maxY, app.frame.maxY + 1,
                "The menu must not extend past the screen.")
        } else {
            XCTAssertGreaterThanOrEqual(
                space, -1, "The menu must stay above the solid tab bar.")
            XCTAssertLessThanOrEqual(
                space, 24, "The menu must not reserve a margin above the solid tab bar.")
        }
    }

    func testMenuBottomContentScrollsAboveTabBar() {
        let app = launch(tab: "stats", stage: "medium", sample: "train-store")
        let tabs = app.tabBars.firstMatch
        let viewport = element("workspaceMenuViewport", in: app)
        XCTAssertTrue(tabs.waitForExistence(timeout: 8))
        XCTAssertTrue(viewport.waitForExistence(timeout: 8))
        // The header enables sharing when the computed statistics publish.
        // Do not spend the reveal budget on the temporary loading layout.
        let share = element("statisticsShareButton", in: app)
        XCTAssertTrue(share.waitForExistence(timeout: 8))
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"), object: share)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 90), .completed,
                       "Statistics must publish before scrolling the completed dashboard.")
        let note = element("passportShareNote", in: app)
        for _ in 0..<12 {
            if note.exists {
                let frame = note.frame
                if !frame.isEmpty,
                   frame.minY >= viewport.frame.minY,
                   frame.maxY <= tabs.frame.minY,
                   note.isHittable { break }
            }
            // Flick this long dashboard inside its readable viewport, clear
            // of the floating tabs. Other panel tests keep their own drag.
            let frame = viewport.frame
            let top = frame.minY + 20
            let bottom = min(frame.maxY, tabs.frame.minY) - 20
            XCTAssertGreaterThan(bottom, top)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: frame.midX, dy: bottom))
            let end = origin.withOffset(CGVector(dx: frame.midX, dy: top))
            start.press(forDuration: 0.05, thenDragTo: end,
                        withVelocity: .fast, thenHoldForDuration: 0)
        }
        print("[tab-clearance] viewport=\(viewport.frame) value=\(String(describing: viewport.value)) tab=\(tabs.frame) noteExists=\(note.exists) note=\(note.exists ? String(describing: note.frame) : "absent")")
        XCTAssertTrue(note.exists)
        XCTAssertTrue(note.isHittable)
        XCTAssertGreaterThanOrEqual(note.frame.minY, viewport.frame.minY)
        XCTAssertLessThanOrEqual(
            note.frame.maxY, tabs.frame.minY,
            "The final menu content must scroll fully clear of the tab bar.")
        attach(app, named: "menu-bottom-content-visible")
    }

    /// The viewport draws under floating system tabs; its default swipe
    /// starts in that covered strip. Drag only inside the readable content.
    private func scrollMenuUp(
        _ viewport: XCUIElement, above tabs: XCUIElement, in app: XCUIApplication
    ) {
        let frame = viewport.frame
        let top = frame.minY + 20
        let bottom = min(frame.maxY, tabs.frame.minY) - 20
        XCTAssertGreaterThan(bottom, top)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: frame.midX, dy: bottom))
        let end = origin.withOffset(CGVector(dx: frame.midX, dy: top))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    func testCompactSelectedJourneyPresentsOriginalCard() throws {
#if !targetEnvironment(macCatalyst)
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone)
        let app = launch(tab: "all", stage: "compact",
                         selectedJourney: "20260703_01_haruka", sample: "train-store",
                         hiddenLayers: "terminals", mapGestures: true)
        let title = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "selectedJourney-")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 12))
        let close = element("journeyBackToList", in: app)
        XCTAssertTrue(close.isHittable)
        let map = element("railMapGestureTarget", in: app)
        XCTAssertTrue(map.waitForExistence(timeout: 8))
        map.pinch(withScale: 0.65, velocity: -1)
        XCTAssertTrue(close.exists)
        attach(app, named: "selected-endpoints-terminals-off-after-zoom-out")
        map.pinch(withScale: 1.54, velocity: 1)
        XCTAssertTrue(close.exists)
        attach(app, named: "selected-endpoints-terminals-off-after-zoom-in")
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 8))
        XCTAssertTrue(element("panelHeader", in: app).waitForExistence(timeout: 8))
#else
        throw XCTSkip("Pinch/rotate gestures are unavailable on Mac Catalyst")
#endif
    }

    func testCompactHeaderDragRevealsTheDestinationContent() throws {
        XCUIDevice.shared.orientation = .portrait
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .phone,
            "The compact sheet gesture is a phone-window assertion.")

        let app = launch(tab: "search", stage: "compact")
        let header = element("panelHeader", in: app)
        XCTAssertTrue(header.waitForExistence(timeout: 8))
        XCTAssertFalse(element("journeySearchField", in: app).isHittable,
                       "Compact menus must keep Search clear of the tab bar.")
        attach(app, named: "iphone-menu-retracted")

        let start = header.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 0, dy: -320))
        start.press(forDuration: 0.1, thenDragTo: end)

        XCTAssertTrue(
            element("journeySearchField", in: app).waitForExistence(timeout: 8),
            "Dragging the non-interactive header must move the resident system sheet.")
        assertSearchAcceptsInput(in: app)
        attach(app, named: "iphone-menu-reopened")
    }

    func testAccessibilityTypePathRemainsReachable() {
        let app = launch(
            tab: "search", stage: "expanded",
            launchArguments: [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
            ])
        XCTAssertTrue(element("panelHeader", in: app).waitForExistence(timeout: 8))
        XCTAssertTrue(element("journeySearchField", in: app).waitForExistence(timeout: 8))
    }

    func testPhoneMenuHeaderDragsInBothDirectionsRepeatedly() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone)
        XCUIDevice.shared.orientation = .portrait
        try assertRepeatedHeaderDrags(isDocked: false)
    }

    func testIPadMenuToggleKeepsOrdinaryTitleStable() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad)
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        try assertRepeatedHeaderDrags(isDocked: true)
    }

    #if targetEnvironment(macCatalyst)
    func testMacMenuToggleKeepsOrdinaryTitleStable() throws {
        try assertRepeatedHeaderDrags(isDocked: true)
    }
    #endif

    func testIPadMenuHeaderDoesNotOwnAResizeGesture() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad)
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch(tab: "search", stage: "compact")
        let header = element("panelHeader", in: app)
        let toggle = element("dockPanelToggle", in: app)
        XCTAssertTrue(header.waitForExistence(timeout: 8))
        dragHeader(header, by: -360)
        XCTAssertEqual(toggle.value as? String, "compact")
        XCTAssertFalse(element("journeySearchField", in: app).isHittable,
                       "Compact menus must keep Search clear of the tab bar.")
        toggle.tap()
        XCTAssertTrue(element("journeySearchField", in: app).waitForExistence(timeout: 8))
    }

    /// System sheets resize natively. A docked iPad or Mac menu cycles
    /// compact → half → full through its toggle. Neither path changes the
    /// title's text or font geometry.
    private func assertRepeatedHeaderDrags(isDocked: Bool) throws {
        let app = launch(tab: "search", stage: "compact")
        let header = element("panelHeader", in: app)
        let search = element("journeySearchField", in: app)
        XCTAssertTrue(header.waitForExistence(timeout: 8))
        XCTAssertFalse(search.isHittable, "The compact menu must keep Search clear of the tab bar.")
        let compactTop = header.frame.minY
        let originalLabel = header.label
        let originalHeight = header.frame.height
        let stage = element("dockPanelToggle", in: app)
        #if targetEnvironment(macCatalyst)
        let device = "mac"
        #else
        let device = isDocked ? "ipad" : "iphone"
        #endif

        for cycle in 1...2 {
            if isDocked {
                // compact → medium → expanded → compact. The toggle's
                // accessibility value is the `SheetStage` case name.
                stage.tap()
                expectation(for: NSPredicate { _, _ in
                    header.frame.minY < compactTop - 80
                        && (stage.value as? String) == "medium"
                }, evaluatedWith: header)
                waitForExpectations(timeout: 8)
                XCTAssertTrue(search.waitForExistence(timeout: 8), "Expanding the panel must reveal Search.")
                XCTAssertEqual(header.label, originalLabel)
                XCTAssertEqual(header.frame.height, originalHeight, accuracy: 1)
                let mediumTop = header.frame.minY
                XCTAssertLessThan(mediumTop, compactTop - 80, "The menu must reach the half stop.")
                XCTAssertEqual(stage.value as? String, "medium")
                attach(app, named: "\(device)-drag-medium-\(cycle)")

                stage.tap()
                expectation(for: NSPredicate { _, _ in
                    header.frame.minY < mediumTop - 80
                        && (stage.value as? String) == "expanded"
                }, evaluatedWith: header)
                waitForExpectations(timeout: 8)
                XCTAssertEqual(header.label, originalLabel)
                XCTAssertEqual(header.frame.height, originalHeight, accuracy: 1)
                let fullTop = header.frame.minY
                XCTAssertLessThan(fullTop, mediumTop - 80, "The menu must reach the full stop.")
                XCTAssertEqual(stage.value as? String, "expanded")
                attach(app, named: "\(device)-drag-open-\(cycle)")

                stage.tap()
                expectation(for: NSPredicate { _, _ in
                    abs(header.frame.minY - compactTop) <= 28
                }, evaluatedWith: header)
                waitForExpectations(timeout: 8)
                XCTAssertFalse(search.isHittable, "Collapsed Search must not overlap the tab bar.")
                XCTAssertGreaterThan(header.frame.minY, fullTop + 80)
                XCTAssertEqual(header.frame.minY, compactTop, accuracy: 28)
                XCTAssertEqual(header.frame.height, originalHeight, accuracy: 1)
                XCTAssertEqual(header.label, originalLabel)
                XCTAssertEqual(stage.value as? String, "compact")
                attach(app, named: "\(device)-drag-closed-\(cycle)")
            } else {
                dragHeader(header, by: -360)
                XCTAssertTrue(search.waitForExistence(timeout: 8), "Expanding the panel must reveal Search.")
                XCTAssertEqual(header.label, originalLabel)
                XCTAssertEqual(header.frame.height, originalHeight, accuracy: 1)
                let openTop = header.frame.minY
                XCTAssertLessThan(openTop, compactTop - 80, "The menu must physically expand after an upward drag.")
                attach(app, named: "\(device)-drag-open-\(cycle)")

                let headerFrame = header.frame
                let screen = app.frame
                let downwardDistance = min(
                    compactTop - headerFrame.minY + 70,
                    screen.maxY - headerFrame.midY - 24)
                XCTAssertGreaterThan(downwardDistance, 100)
                dragHeader(header, by: downwardDistance)
                expectation(for: NSPredicate { _, _ in
                    abs(header.frame.minY - compactTop) <= 28
                }, evaluatedWith: header)
                waitForExpectations(timeout: 8)
                XCTAssertFalse(search.isHittable, "Collapsed Search must not overlap the tab bar.")
                XCTAssertGreaterThan(header.frame.minY, openTop + 80)
                XCTAssertEqual(header.frame.minY, compactTop, accuracy: 28)
                XCTAssertEqual(header.frame.height, originalHeight, accuracy: 1)
                attach(app, named: "\(device)-drag-closed-\(cycle)")
            }
        }

        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 8))
        XCTAssertEqual(tabs.buttons.count, 4)
        tabs.buttons.element(boundBy: 2).tap()
        XCTAssertFalse(search.exists)
        tabs.buttons.element(boundBy: 3).tap()
        if !search.exists { dragHeader(header, by: -360) }
        XCTAssertTrue(search.waitForExistence(timeout: 8), "Tabs must still work after repeated drags.")
    }

    private func dragHeader(_ header: XCUIElement, by verticalDistance: CGFloat) {
        let start = header.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        #if targetEnvironment(macCatalyst)
        start.click(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: verticalDistance)))
        #else
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: verticalDistance)))
        #endif
    }

    /// This test is intentionally skipped unless the simulator's real system
    /// setting is enabled. Run `ios/tools/verify-reduce-motion-ui.sh` to set
    /// and restore that setting around this test; an app-only launch variable
    /// cannot change SwiftUI's read-only accessibility environment.
    func testSystemReduceMotionPathRemainsReachable() throws {
        let app = launch(
            tab: "search", stage: "expanded", reportsReduceMotion: true)
        let header = element("panelHeader", in: app)
        XCTAssertTrue(header.waitForExistence(timeout: 8))

        let systemState = header.value as? String
        try XCTSkipUnless(
            systemState == "enabled",
            "System Reduce Motion is disabled; run ios/tools/verify-reduce-motion-ui.sh.")

        XCTAssertTrue(element("journeySearchField", in: app).waitForExistence(timeout: 8))
    }

    func testLandscapeUsesReachableSidebarChrome() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .pad,
            "Landscape sidebar coverage belongs to iPad; iPhone remains portrait-only.")
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = launch(tab: "all", stage: "expanded")
        XCTAssertTrue(element("panelHeader", in: app).waitForExistence(timeout: 8))
        XCTAssertTrue(
            element("mapNetworkToggle", in: app).waitForExistence(timeout: 8),
            """
                The map rail must still be reachable. Asserted on a real control \
                rather than on the rail's container: a container identifier \
                propagates onto every button inside it and hides their own, so \
                `MapControlBar` no longer sets one.
                """)
    }

    func testPhoneMapRailStaysAboveMenu() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone)
        XCUIDevice.shared.orientation = .portrait

        for stage in ["compact", "medium"] {
            let app = launch(tab: "all", stage: stage)
            let header = element("panelHeader", in: app)
            XCTAssertTrue(header.waitForExistence(timeout: 8))
            assertMapRailAboveMenu(in: app, header: header)
            attach(app, named: "map-rail-\(stage)")

            let originalTop = header.frame.minY
            dragHeader(header, by: stage == "compact" ? -220 : 320)
            let moved = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in
                    abs(header.frame.minY - originalTop) > 80
                }, object: header)
            XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 8), .completed)
            assertMapRailAboveMenu(in: app, header: header)
            attach(app, named: "map-rail-\(stage)-after-drag")
            app.terminate()
        }
    }

    private func assertMapRailAboveMenu(in app: XCUIApplication, header: XCUIElement) {
        for identifier in [
            "mapNetworkToggle", "mapRoutesToggle", "mapLayersButton",
            "mapInfoButton", "mapLocateToggle",
        ] {
            let control = element(identifier, in: app)
            let clearOfMenu = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in
                    control.exists && control.isHittable
                        && !control.frame.isEmpty
                        && app.frame.insetBy(dx: -1, dy: -1).contains(control.frame)
                        // The menu surface starts above its inset title text.
                        && control.frame.maxY <= header.frame.minY - 24
                }, object: control)
            XCTAssertEqual(XCTWaiter.wait(for: [clearOfMenu], timeout: 8), .completed,
                           "\(identifier) \(control.frame) must stay above menu header \(header.frame).")
        }
    }

    /// A row opens its matching separate menu and returns to the same list.
    func testAllJourneyRowsOpenTheirMatchingJourney() {
        let app = launch(
            tab: "all", stage: "expanded", sample: "train-store")

        for id in [
            "20260703_01_haruka",
            "20260703_02_tokaido_shinkansen_hikari_kodama",
        ] {
            let row = element("journeyRow-\(id)", in: app)
            XCTAssertTrue(
                row.waitForExistence(timeout: 20),
                "The bundled journey \(id) never appeared in All Journeys.")
            XCTAssertFalse(row.label.contains("stops"), "The list card should contain ticket information only.")
            if id == "20260703_01_haruka" {
                XCTAssertTrue(row.label.contains("16:14"))
                XCTAssertTrue(row.label.contains("17:06"))
                XCTAssertFalse(row.label.contains("阪和線"))
                XCTAssertFalse(row.label.contains("Hanwa"))
                attach(app, named: "journey-ticket-summary")
            }
            row.tap()

            XCTAssertTrue(
                element("selectedJourney-\(id)", in: app).waitForExistence(timeout: 8),
                "Selecting \(id) must show that journey rather than another record.")

            let back = element("journeyBackToList", in: app)
            XCTAssertTrue(back.waitForExistence(timeout: 8))
            let title = element("selectedJourney-\(id)", in: app)
            XCTAssertLessThan(title.frame.minY, back.frame.maxY,
                              "The vehicle title must stay on the logo's header row.")
            attach(app, named: "journey-logo-side-title-\(id)")
            back.tap()
            XCTAssertTrue(row.waitForExistence(timeout: 8))
        }
    }

    func testJourneyFocusLowersMenuAndFitsAboveItsLowestEdge() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone)
        XCUIDevice.shared.orientation = .portrait
        let app = launch(tab: "all", stage: "expanded", sample: "train-store")
        // Exercise the short same-line Mishima–Numazu journey. The primary
        // action assertion below prevents a partial route from standing in
        // for the actual Locate action.
        let id = "20260703_03_tokaido_main_local"
        let row = element("journeyRow-\(id)", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        row.tap()
        let title = element("selectedJourney-\(id)", in: app)
        XCTAssertTrue(title.waitForExistence(timeout: 8))
        let lowestTop = title.frame.minY

        // Editing can temporarily remove the presented menu from view.
        element("journeyMenuEdit", in: app).tap()
        XCTAssertTrue(element("rideEditorForm", in: app).waitForExistence(timeout: 8))
        element("rideEditorCancel", in: app).tap()
        XCTAssertTrue(title.waitForExistence(timeout: 8))

        let start = title.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -330)))
        let raised = expectation(
            for: NSPredicate { _, _ in title.exists && title.frame.minY < lowestTop - 80 },
            evaluatedWith: app)
        wait(for: [raised], timeout: 8)
        let status = element("railMapRenderStatus", in: app)
        func metric(_ name: String) -> Double {
            let prefix = name + ":"
            guard let field = status.label.split(separator: ";").first(where: { $0.hasPrefix(prefix) }),
                  let value = Double(field.dropFirst(prefix.count)) else { return -1 }
            return value
        }
        let focus = element("journeyPrimaryAction", in: app)
        XCTAssertEqual(focus.label, "Locate route", "This regression must exercise the actual locate action.")
        focus.tap()
        let lowered = expectation(
            for: NSPredicate { _, _ in title.exists && title.frame.minY >= lowestTop - 3 },
            evaluatedWith: app)
        wait(for: [lowered], timeout: 8)
        XCTAssertTrue(element("journeyBackToList", in: app).exists)
        attach(app, named: "journey-focus-lowest-menu")

        element("journeyBackToList", in: app).tap()
        let header = element("panelHeader", in: app)
        XCTAssertTrue(header.waitForExistence(timeout: 8))
        XCTAssertGreaterThan(header.frame.minY, app.frame.height * 0.65,
                             "Focus must also lower the resident panel behind the menu.")
        XCTAssertTrue(status.waitForExistence(timeout: 8))
        let focused = expectation(for: NSPredicate { _, _ in
            metric("focusRevision") >= 1
                && metric("focusBottom") >= 280 && metric("focusBottom") < 350
        }, evaluatedWith: app)
        wait(for: [focused], timeout: 15)

    }

    func testExpandedMenuSlidesAwayWhenJourneyCardOpens() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone)
        XCUIDevice.shared.orientation = .portrait
        let app = launch(tab: "all", stage: "expanded", sample: "train-store", mapGestures: true)
        let header = element("panelHeader", in: app)
        let row = element("journeyRow-20260703_01_haruka", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        let originalTop = header.frame.minY
        XCTAssertLessThan(originalTop, app.frame.height * 0.25)

        for _ in 0..<2 {
            row.tap()
            let close = element("journeyBackToList", in: app)
            let title = element("selectedJourney-20260703_01_haruka", in: app)
            XCTAssertTrue(close.waitForExistence(timeout: 8))
            XCTAssertTrue(close.isHittable)
            XCTAssertGreaterThan(title.frame.minY, app.frame.height * 0.5,
                                 "The journey card must open at its own compact height.")
            XCTAssertFalse(header.isHittable)
            XCTAssertFalse(app.tabBars.firstMatch.isHittable)
            let map = element("railMapGestureTarget", in: app)
            XCTAssertTrue(map.waitForExistence(timeout: 8))
            let mapPoint = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            mapPoint.press(forDuration: 0.1, thenDragTo: mapPoint.withOffset(CGVector(dx: 30, dy: 20)))
            XCTAssertTrue(close.isHittable)
            attach(app, named: "expanded-menu-hidden-behind-journey")

            close.tap()
            let restored = expectation(for: NSPredicate { _, _ in
                header.isHittable && abs(header.frame.minY - originalTop) < 3
            }, evaluatedWith: app)
            wait(for: [restored], timeout: 8)
            XCTAssertTrue(row.isHittable)
        }
    }

    func testJourneyMenuHasNoTabBarAndRestoresOriginalList() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone)
        let app = launch(tab: "all", stage: "medium", sample: "train-store")
        let header = element("panelHeader", in: app)
        XCTAssertTrue(header.waitForExistence(timeout: 8))
        let title = header.label
        let height = header.frame.height
        for id in ["20260703_01_haruka", "20260703_02_tokaido_shinkansen_hikari_kodama"] {
            let row = element("journeyRow-\(id)", in: app)
            XCTAssertTrue(row.waitForExistence(timeout: 20))
            row.tap()
            XCTAssertTrue(element("selectedJourney-\(id)", in: app).waitForExistence(timeout: 8))
            XCTAssertFalse(app.tabBars.firstMatch.isHittable)
            XCTAssertTrue(element("journeyMenuEdit", in: app).isHittable)
            attach(app, named: "independent-menu-\(id)")
            element("journeyMenuEdit", in: app).tap()
            XCTAssertTrue(element("rideEditorForm", in: app).waitForExistence(timeout: 8))
            element("rideEditorCancel", in: app).tap()
            XCTAssertTrue(element("journeyBackToList", in: app).waitForExistence(timeout: 8))
            element("journeyBackToList", in: app).tap()
            XCTAssertTrue(row.waitForExistence(timeout: 8))
            XCTAssertEqual(header.label, title)
            XCTAssertEqual(header.frame.height, height, accuracy: 1)
            XCTAssertTrue(app.tabBars.firstMatch.isHittable)
        }
    }

    func testJourneyCardResizesAndOnlyClosesWithX() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone)
        XCUIDevice.shared.orientation = .portrait
        let app = launch(tab: "all", stage: "medium", sample: "train-store")
        let id = "20260703_01_haruka"
        let row = element("journeyRow-\(id)", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        row.tap()
        let title = element("selectedJourney-\(id)", in: app)
        let close = element("journeyBackToList", in: app)
        XCTAssertTrue(title.waitForExistence(timeout: 8))
        XCTAssertTrue(close.isHittable)
        let compactTop = title.frame.minY
        attach(app, named: "journey-original-card-compact")

        let start = title.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -330)))
        let expanded = expectation(
            for: NSPredicate { _, _ in title.exists && title.frame.minY < compactTop - 80 },
            evaluatedWith: app)
        wait(for: [expanded], timeout: 8)
        attach(app, named: "journey-original-card-expanded")

        for _ in 0..<2 {
            let top = title.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
            top.press(forDuration: 0.1, thenDragTo: app.coordinate(
                withNormalizedOffset: CGVector(dx: 0.3, dy: 0.94)))
            XCTAssertTrue(close.waitForExistence(timeout: 5),
                          "Dragging down must resize the card without dismissing it.")
        }
        let outside = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
        outside.tap()
        XCTAssertTrue(close.exists, "Tapping the map must keep the journey card open.")
        attach(app, named: "journey-original-card-after-downward-drags")
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 8))
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        XCTAssertTrue(row.isHittable)
    }

    func testWideIPadDocksThePhoneMenu() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .pad,
            "The docked-card composition is an iPad wide-window assertion.")

        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = launch(
            tab: "all", stage: "expanded", sample: "train-store",
            camera: "35.68,139.75,0.12")
        // Wait for the docked composition to actually be on screen before
        // asserting the sidebar's absence — checked first, `exists` on a
        // still-launching app is false whether or not the sidebar is gone,
        // which would pass even if the removal regressed.
        XCTAssertTrue(element("panelHeader", in: app).waitForExistence(timeout: 8))
        XCTAssertFalse(
            element("workspaceSidebar", in: app).exists,
            "The native three-column sidebar is removed; a wide iPad window docks the card.")
        XCTAssertTrue(element("mapNetworkToggle", in: app).exists)

        // The docked card forces `.horizontalSizeClass` to `.compact` so its
        // `TabView` renders the phone's bottom tab bar rather than iPadOS's
        // top capsule — four icon tabs, not a `List` sidebar and not a
        // capsule with no bar at all.
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 8))
        XCTAssertEqual(tabBar.buttons.count, 4)

        tabBar.buttons.element(boundBy: 3).tap()
        XCTAssertTrue(
            element("journeySearchField", in: app).waitForExistence(timeout: 8),
            "Tapping the docked card's own tab bar must update the shared map's content.")

        // The same resident menu can retract to its header and reopen without
        // losing the selected destination. The map remains usable throughout.
        let toggle = element("dockPanelToggle", in: app)
        XCTAssertTrue(toggle.waitForExistence(timeout: 8))
        assertSearchAcceptsInput(in: app)
        attach(app, named: "ipad-menu-expanded")
        toggle.tap()
        let compact = NSPredicate(format: "value == %@", "compact")
        expectation(for: compact, evaluatedWith: toggle)
        waitForExpectations(timeout: 8)
        let search = element("journeySearchField", in: app)
        // The stage value changes before UIKit finishes updating its hosted
        // text field and accessibility snapshot. Wait for the UI invariant,
        // retaining the same non-hittable requirement and a bounded timeout.
        let hiddenSearch = NSPredicate { _, _ in !search.isHittable }
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(
                predicate: hiddenSearch, object: search)], timeout: 8), .completed,
            "Compact menus must keep Search clear of the tab bar.")
        XCTAssertFalse(search.isHittable)
        if search.exists { XCTAssertFalse(search.isEnabled) }
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 8),
                      "Compact Search must resign keyboard focus.")
        assertNetworkToggleResponds(in: app)
        attach(app, named: "ipad-menu-retracted")

        toggle.tap()
        XCTAssertTrue(
            element("journeySearchField", in: app).waitForExistence(timeout: 8),
            "Reopening the resident menu must restore its Search destination.")
        assertNetworkToggleResponds(in: app)
        assertSearchAcceptsInput(in: app, text: " Station", expected: "Tokyo Station")
        attach(app, named: "ipad-menu-reopened")
    }

    func testWideIPadCompactMenuReopens() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad)
        // Run this invariant at both standard text and the simulator's real
        // accessibility content_size; both must reveal a usable destination.
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = launch(tab: "search", stage: "compact")
        let toggle = element("dockPanelToggle", in: app)
        XCTAssertTrue(toggle.waitForExistence(timeout: 8))
        XCTAssertEqual(toggle.value as? String, "compact")
        toggle.tap()
        expectation(for: NSPredicate(format: "value != %@", "compact"), evaluatedWith: toggle)
        waitForExpectations(timeout: 8)
        XCTAssertTrue(element("journeySearchField", in: app).waitForExistence(timeout: 8))
        assertSearchAcceptsInput(in: app)
        attach(app, named: "ipad-compact-menu-reopened")
    }

    private func assertSearchAcceptsInput(
        in app: XCUIApplication, text: String = "Tokyo", expected: String = "Tokyo"
    ) {
        let field = element("journeySearchField", in: app)
        let ready = NSPredicate(format: "isEnabled == true AND isHittable == true")
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(
                predicate: ready, object: field)], timeout: 8), .completed,
            "Expanded Search must become enabled and hittable.")
        XCTAssertTrue(field.isEnabled)
        XCTAssertTrue(field.isHittable)
        field.tap()
        field.typeText(text)
        XCTAssertEqual(field.value as? String, expected,
                       "The reopened native text field must accept input.")
    }

    private func attach(_ app: XCUIApplication, named name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func assertNetworkToggleResponds(in app: XCUIApplication) {
        let toggle = app.buttons["mapNetworkToggle"]
        let status = app.staticTexts["railMapRenderStatus"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 8))
        XCTAssertTrue(status.waitForExistence(timeout: 8))
        let original = toggle.isSelected
        for selected in [!original, original] {
            EditorUITestSupport.tap(toggle, in: app)
            let changed = XCTNSPredicateExpectation(
                predicate: NSPredicate { object, _ in
                    (object as? XCUIElement)?.isSelected == selected
                }, object: toggle)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 8), .completed)
            let prefix = selected ? "network:rendered;" : "network:off;"
            let rendered = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label BEGINSWITH %@", prefix), object: status)
            XCTAssertEqual(XCTWaiter.wait(for: [rendered], timeout: 8), .completed,
                           "The map must render the layer selected from its visible control.")
        }
    }

    private func launch(
        tab: String,
        stage: String,
        selectedJourney: String? = nil,
        sample: String? = nil,
        camera: String? = nil,
        hiddenLayers: String? = nil,
        mapGestures: Bool = false,
        reportsReduceMotion: Bool = false,
        launchArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        if ProcessInfo.processInfo.environment["RAILMAP_UI_TEST_TAB_BAR_PROBE"] == "1" {
            app.launchEnvironment["RAILMAP_UI_TEST_TAB_BAR_PROBE"] = "1"
        }
        app.launchEnvironment["RAILMAP_UI_TEST_STORAGE_ID"] = UUID().uuidString
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = tab
        app.launchEnvironment["RAILMAP_UI_TEST_STATS_REGION"] = "all"
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = stage
        if let selectedJourney {
            app.launchEnvironment["RAILMAP_UI_TEST_SELECT"] = selectedJourney
        }
        if let sample {
            app.launchEnvironment["RAILMAP_UI_TEST_SAMPLE"] = sample
        }
        if let camera {
            app.launchEnvironment["RAILMAP_UI_TEST_CAMERA"] = camera
        }
        if let hiddenLayers { app.launchEnvironment["RAILMAP_UI_TEST_LAYERS"] = hiddenLayers }
        if mapGestures { app.launchEnvironment["RAILMAP_UI_TEST_GESTURE_TARGET"] = "1" }
        if reportsReduceMotion {
            app.launchEnvironment["RAILMAP_UI_TEST_REPORT_REDUCE_MOTION"] = "1"
        }
        app.launchArguments += launchArguments
        app.launch()
        return app
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}

/// The screenshot importer, as far as a test can drive it.
///
/// It stops at the picker. Everything past that point — recognising the text,
/// parsing it, resolving the stations — is covered by `TransferGuideTests` in
/// RailCore, which can be handed a layout directly instead of a photograph.
/// What only a launched app can answer is whether the door is there and
/// whether the room behind it renders, and that is what this asks.
@MainActor
final class TransferGuideImportUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testTheScreenshotImporterOpensFromTheDataWorkspace() {
        let app = XCUIApplication()
        app.launchEnvironment["RAILMAP_UI_TEST_STORAGE_ID"] = UUID().uuidString
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "all"
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "expanded"
        app.launch()

        let gear = app.descendants(matching: .any)
            .matching(identifier: "utilityMenuButton").firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: 10), "the utility menu is not reachable")
        gear.tap()

        let data = app.descendants(matching: .any)
            .matching(identifier: "utilityDataButton").firstMatch
        XCTAssertTrue(data.waitForExistence(timeout: 8), "Data is not in the utility menu")
        data.tap()

        let entry = app.descendants(matching: .any)
            .matching(identifier: "guideImportButton").firstMatch
        XCTAssertTrue(
            entry.waitForExistence(timeout: 8),
            "the screenshot importer is not offered in the Import group")
        entry.tap()

        // Both doors, because they are the only two ways in and a reader who
        // keeps screenshots in Files rather than Photos needs the second one.
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "guidePhotoPicker").firstMatch
                .waitForExistence(timeout: 8),
            "the importer opened without a way to choose a screenshot")
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "guideFilePicker").firstMatch.exists,
            "the importer offers no way to choose an image file")
    }
}
