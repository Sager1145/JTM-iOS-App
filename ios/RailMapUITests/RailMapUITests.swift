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
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .phone,
            "The compact sheet gesture is a phone-window assertion.")

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
    /// full-width landscape window earns native navigation instead of a
    /// stretched phone tab bar.
    func testWideIPadUsesNativeWorkspaceSidebar() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .pad,
            "The native workspace sidebar is an iPad wide-window assertion.")

        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = launch(tab: "all", stage: "expanded")
        XCTAssertTrue(
            element("workspaceSidebar", in: app).waitForExistence(timeout: 8),
            "A wide iPad window must expose native workspace navigation.")
        XCTAssertTrue(element("workspaceTab-all", in: app).exists)
        XCTAssertTrue(element("panelHeader", in: app).exists)
        XCTAssertTrue(element("mapNetworkToggle", in: app).exists)

        let search = element("workspaceTab-search", in: app)
        XCTAssertTrue(search.exists)
        search.tap()
        XCTAssertTrue(
            element("journeySearchField", in: app).waitForExistence(timeout: 8),
            "Selecting an iPad sidebar destination must update the shared content column.")
    }

    private func launch(
        tab: String,
        stage: String,
        selectedJourney: String? = nil,
        sample: String? = nil,
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
