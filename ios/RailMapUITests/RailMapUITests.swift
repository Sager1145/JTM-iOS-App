import XCTest

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

    func testCompactSelectedJourneyKeepsHeaderAndMapControlsReachable() {
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

    func testCompactHeaderDragRevealsTheDestinationContent() {
        let app = launch(tab: "search", stage: "compact")
        let header = element("panelHeader", in: app)
        XCTAssertTrue(header.waitForExistence(timeout: 8))
        XCTAssertFalse(element("journeySearchField", in: app).exists)

        let start = header.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 0, dy: -320))
        start.press(forDuration: 0.1, thenDragTo: end)

        XCTAssertTrue(
            element("journeySearchField", in: app).waitForExistence(timeout: 8),
            "Dragging the non-interactive header must move the resident system sheet.")
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

    private func launch(
        tab: String,
        stage: String,
        selectedJourney: String? = nil,
        reportsReduceMotion: Bool = false,
        launchArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = tab
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = stage
        if let selectedJourney {
            app.launchEnvironment["RAILMAP_UI_TEST_SELECT"] = selectedJourney
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
