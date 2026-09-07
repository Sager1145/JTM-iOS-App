import XCTest
import UIKit

@MainActor
final class RailMapUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testSearchDestinationAlwaysExposesAField() {
        let app = launch(tab: "search", stage: "medium")
        XCTAssertTrue(
            element("journeySearchField", in: app).waitForExistence(timeout: 8),
            "The semantic Search destination must never open without a text field.")
    }

    func testCompactSelectedJourneyKeepsHeaderAndMapControlsReachable() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .phone,
            "The compact overlay is a phone-window assertion.")

        let app = launch(tab: "all", stage: "compact", selectedJourney: "0")
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

    func testCompactHeaderDragRevealsTheDestinationContent() throws {
        XCUIDevice.shared.orientation = .portrait
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .phone,
            "The compact sheet gesture is a phone-window assertion.")

        let app = launch(tab: "search", stage: "compact")
        let header = element("panelHeader", in: app)
        XCTAssertTrue(header.waitForExistence(timeout: 8))
        XCTAssertFalse(element("journeySearchField", in: app).exists)
        attach(app, named: "iphone-menu-retracted")

        let start = header.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 0, dy: -320))
        start.press(forDuration: 0.1, thenDragTo: end)

        XCTAssertTrue(
            element("journeySearchField", in: app).waitForExistence(timeout: 8),
            "Dragging the non-interactive header must move the resident system sheet.")
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

    func testIPadMenuHeaderDragsInBothDirectionsRepeatedly() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad)
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        try assertRepeatedHeaderDrags(isDocked: true)
    }

    #if targetEnvironment(macCatalyst)
    func testMacMenuHeaderDragsInBothDirectionsRepeatedly() throws {
        try assertRepeatedHeaderDrags(isDocked: true)
    }
    #endif

    func testIPadMenuHeaderPaddingDragExpands() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad)
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch(tab: "search", stage: "compact")
        let header = element("panelHeader", in: app)
        let search = element("journeySearchField", in: app)
        XCTAssertTrue(header.waitForExistence(timeout: 8))
        XCTAssertFalse(search.exists)
        let compactTop = header.frame.minY
        // Four points above the title is visible, noninteractive header
        // padding inside the card, and should be a natural drag target.
        let start = header.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            .withOffset(CGVector(dx: 0, dy: -4))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -360)))
        XCTAssertTrue(search.waitForExistence(timeout: 8), "Dragging empty header padding must expand the menu.")
        XCTAssertLessThan(header.frame.minY, compactTop - 80)
        attach(app, named: "ipad-padding-drag-open")
    }

    /// Every height change in the two-cycle loop comes from a title drag.
    /// The separate tab check allows destination changes to open content.
    private func assertRepeatedHeaderDrags(isDocked: Bool) throws {
        let app = launch(tab: "search", stage: "compact")
        let header = element("panelHeader", in: app)
        let search = element("journeySearchField", in: app)
        XCTAssertTrue(header.waitForExistence(timeout: 8))
        XCTAssertFalse(search.exists)
        let compactTop = header.frame.minY
        let stage = element("dockPanelToggle", in: app)
        #if targetEnvironment(macCatalyst)
        let device = "mac"
        #else
        let device = isDocked ? "ipad" : "iphone"
        #endif

        for cycle in 1...2 {
            dragHeader(header, by: -360)
            XCTAssertTrue(search.waitForExistence(timeout: 8), "Upward header drag must reveal Search.")
            let openTop = header.frame.minY
            XCTAssertLessThan(openTop, compactTop - 80, "The menu must physically expand after an upward drag.")
            if isDocked { XCTAssertNotEqual(stage.value as? String, "compact") }
            attach(app, named: "\(device)-drag-open-\(cycle)")

            let headerFrame = header.frame
            let screen = app.frame
            let downwardDistance = min(
                compactTop - headerFrame.minY + 70,
                screen.maxY - headerFrame.midY - 24)
            XCTAssertGreaterThan(downwardDistance, 100)
            dragHeader(header, by: downwardDistance)
            expectation(for: NSPredicate(format: "exists == NO"), evaluatedWith: search)
            waitForExpectations(timeout: 8)
            XCTAssertGreaterThan(header.frame.minY, openTop + 80)
            XCTAssertEqual(header.frame.minY, compactTop, accuracy: 28)
            if isDocked { XCTAssertEqual(stage.value as? String, "compact") }
            attach(app, named: "\(device)-drag-closed-\(cycle)")
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

    func testLandscapeUsesReachableSidebarChrome() {
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

    /// Exercises the path the previous smoke tests skipped entirely: real
    /// rows from the bundled store, row selection, the matching resident
    /// detail card, and returning to the still-mounted list.
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
            row.tap()

            XCTAssertTrue(
                element("selectedJourney-\(id)", in: app).waitForExistence(timeout: 8),
                "Selecting \(id) must show that journey rather than another record.")

            let back = element("journeyBackToList", in: app)
            XCTAssertTrue(back.waitForExistence(timeout: 8))
            back.tap()
            XCTAssertTrue(row.waitForExistence(timeout: 8))
        }
    }

    /// Runs only when this target is explicitly sent to an iPad simulator.
    /// The default phone destination skips it; the iPad matrix verifies that a
    /// full-width landscape window docks the phone's own menu as a card over
    /// a full-window map, rather than trading it for a native three-column
    /// sidebar with iPadOS's own top tab capsule.
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
        attach(app, named: "ipad-menu-expanded")
        toggle.tap()
        let compact = NSPredicate(format: "value == %@", "compact")
        expectation(for: compact, evaluatedWith: toggle)
        waitForExpectations(timeout: 8)
        XCTAssertFalse(element("journeySearchField", in: app).exists)
        assertHittable(element("mapNetworkToggle", in: app))
        attach(app, named: "ipad-menu-retracted")

        toggle.tap()
        XCTAssertTrue(
            element("journeySearchField", in: app).waitForExistence(timeout: 8),
            "Reopening the resident menu must restore its Search destination.")
        assertHittable(element("mapNetworkToggle", in: app))
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
        attach(app, named: "ipad-compact-menu-reopened")
    }

    private func attach(_ app: XCUIApplication, named name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func assertHittable(_ element: XCUIElement) {
        expectation(for: NSPredicate(format: "hittable == YES"), evaluatedWith: element)
        waitForExpectations(timeout: 8)
    }

    private func launch(
        tab: String,
        stage: String,
        selectedJourney: String? = nil,
        sample: String? = nil,
        camera: String? = nil,
        reportsReduceMotion: Bool = false,
        launchArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = tab
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
