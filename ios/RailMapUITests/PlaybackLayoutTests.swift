import XCTest
import UIKit

/// Frame assertions cover collisions that existence/hittability smoke tests
/// miss when the transport, map rail and resident journey panel share a map.
@MainActor
final class PlaybackLayoutTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testPhonePortraitPlaybackControlsDoNotOverlap() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone)
        assertPlaybackLayout(orientation: .portrait, accessibilitySize: false)
    }

    func testPhonePortraitAX5PlaybackControlsDoNotOverlap() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone)
        assertPlaybackLayout(orientation: .portrait, accessibilitySize: true)
    }

    func testPhoneRotationRequestsKeepPlaybackPortrait() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone)
        assertPlaybackLayout(orientation: .portrait, accessibilitySize: false,
                             rotationRequests: [.landscapeLeft, .landscapeRight, .portraitUpsideDown])
    }

    func testPhoneAX5RotationRequestsKeepPlaybackPortrait() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone)
        assertPlaybackLayout(orientation: .portrait, accessibilitySize: true,
                             rotationRequests: [.landscapeLeft, .landscapeRight, .portraitUpsideDown])
    }

    func testIPadPlaybackControlsDoNotOverlap() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad)
        assertPlaybackLayout(orientation: .landscapeLeft, accessibilitySize: false)
    }

    func testIPadPortraitPlaybackControlsDoNotOverlap() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad)
        assertPlaybackLayout(orientation: .portrait, accessibilitySize: false)
    }

    func testIPadPortraitAX5PlaybackControlsDoNotOverlap() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad)
        assertPlaybackLayout(orientation: .portrait, accessibilitySize: true)
    }

    func testIPadAX5PlaybackControlsDoNotOverlap() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad)
        assertPlaybackLayout(orientation: .landscapeLeft, accessibilitySize: true)
    }

    private func assertPlaybackLayout(
        orientation: UIDeviceOrientation, accessibilitySize: Bool,
        rotationRequests: [UIDeviceOrientation] = []
    ) {
        XCUIDevice.shared.orientation = orientation
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchEnvironment["RAILMAP_UI_TEST_STORAGE_ID"] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if accessibilitySize {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName",
                UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
            ]
        }
        app.launchEnvironment["RAILMAP_UI_TEST_TAB"] = "all"
        app.launchEnvironment["RAILMAP_UI_TEST_STAGE"] = "compact"
        app.launchEnvironment["RAILMAP_UI_TEST_SAMPLE"] = "train-store"
        app.launchEnvironment["RAILMAP_UI_TEST_PLAYBACK"] = "1"
        // Match the video regression's explicit, longer surveyed journey;
        // asynchronous first-ready routes can finish before the hit checks.
        app.launchEnvironment["RAILMAP_UI_TEST_PLAYBACK_TRAIN_ID"] =
            "20260703_02_tokaido_shinkansen_hikari_kodama"
        if ProcessInfo.processInfo.environment["RAILMAP_UI_TEST_PLAYBACK_HIT_PROBE"] == "1" {
            app.launchEnvironment["RAILMAP_UI_TEST_PLAYBACK_HIT_PROBE"] = "1"
        }
        app.launch()
        let device = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        let direction = orientation == .portrait ? "portrait" : "landscape"
        let name = "playback-\(device)-\(direction)-\(accessibilitySize ? "ax5" : "standard")\(rotationRequests.isEmpty ? "" : "-rotation-locked")"
        defer { attachScreen(named: "\(name)-final") }

        let toggle = element("playbackPauseResume", in: app)
        XCTAssertTrue(toggle.waitForExistence(timeout: 60))
        XCTAssertEqual(app.buttons.matching(identifier: "playbackPauseResume").count, 1,
                       "Playback must expose one active pause/resume control.")
        waitForLabel("Pause", on: toggle)
        for requestedOrientation in rotationRequests {
            XCUIDevice.shared.orientation = requestedOrientation
            XCTAssertEqual(XCUIDevice.shared.orientation, requestedOrientation,
                           "The device must receive the rotation request.")
            XCTAssertGreaterThan(app.frame.height, app.frame.width,
                                 "iPhone must keep its portrait window after \(requestedOrientation).")
        }
        attachScreen(named: "\(name)-before-pause")
        let hitState = XCTAttachment(string:
            "window=\(app.frame); pause=\(toggle.frame); "
                + "enabled=\(toggle.isEnabled); hittable=\(toggle.isHittable)\n"
                + app.debugDescription)
        hitState.name = "\(name)-before-pause-hit-state"
        hitState.lifetime = .keepAlways
        add(hitState)
        toggle.tap()
        // The English catalog translates the resume action as "Play".
        waitForLabel("Play", on: toggle)
        attachScreen(named: "\(name)-paused")

        let surface = element("playbackTransportSurface", in: app)
        XCTAssertTrue(surface.waitForExistence(timeout: 8))
        let viewport = app.frame
        if orientation == .portrait {
            XCTAssertGreaterThan(viewport.height, viewport.width)
        } else {
            XCTAssertGreaterThan(viewport.width, viewport.height,
                                 "The landscape case must run in a landscape window.")
        }
        assertContained(surface.frame, in: viewport, name: "playback transport")

        let playbackIDs = [
            "playbackPrevious", "playbackPauseResume", "playbackNext",
            "playbackStopButton", "playbackFollow", "playbackSpeedSlider",
            "playbackVideoButton",
        ]
        let mapIDs = [
            "mapNetworkToggle", "mapRoutesToggle", "mapLayersButton",
            "mapInfoButton", "mapLocateToggle",
        ]
        var playbackFrames: [(name: String, frame: CGRect)] = []
        var mapFrames: [(name: String, frame: CGRect)] = []
        for identifier in playbackIDs + mapIDs {
            let control = element(identifier, in: app)
            if playbackIDs.contains(identifier) {
                XCTAssertTrue(control.waitForExistence(timeout: 8), identifier)
            } else if !control.exists {
                // Short map windows hide the rail while playback owns the
                // available height; stopping restores those controls below.
                continue
            }
            let frame = control.frame
            assertContained(frame, in: viewport, name: identifier)
            if playbackIDs.contains(identifier) {
                assertContained(frame, in: surface.frame, name: identifier)
                playbackFrames.append((identifier, frame))
            } else {
                mapFrames.append((identifier, frame))
            }
            // Previous/Next can legitimately be disabled at a queue boundary.
            if control.isEnabled {
                XCTAssertTrue(control.isHittable,
                              "\(identifier) must remain reachable.\n\(app.debugDescription)")
            }
        }

        // Every pair is checked, including the slider and Follow toggle: a
        // partly overlaid control can still report isHittable in XCTest.
        let controls = playbackFrames + mapFrames
        for first in controls.indices {
            for second in controls.indices where second > first {
                assertDisjoint(controls[first], controls[second])
            }
        }

        let header = element("panelHeader", in: app)
        XCTAssertTrue(header.waitForExistence(timeout: 8))
        assertContained(header.frame, in: viewport, name: "panelHeader")
        var panelFrames: [(name: String, frame: CGRect)] = [("panelHeader", header.frame)]
        let dockToggle = element("dockPanelToggle", in: app)
        if dockToggle.exists {
            assertContained(dockToggle.frame, in: viewport, name: "dockPanelToggle")
            panelFrames.append(("dockPanelToggle", dockToggle.frame))
        }
        // System tabs can be hidden at a compact sheet detent. Check each
        // mounted on-screen tab rather than requiring hidden content to show.
        for (index, tab) in app.tabBars.buttons.allElementsBoundByIndex.enumerated() {
            let frame = tab.frame
            if !frame.isEmpty, viewport.intersects(frame) {
                assertContained(frame, in: viewport, name: "workspace tab \(index)")
                panelFrames.append(("workspace tab \(index)", frame))
            }
        }
        for panelFrame in panelFrames {
            assertDisjoint(("playback transport", surface.frame), panelFrame)
            for control in controls { assertDisjoint(control, panelFrame) }
        }

        toggle.tap()
        waitForLabel("Pause", on: toggle)
        let stop = element("playbackStopButton", in: app)
        stop.tap()
        XCTAssertTrue(toggle.waitForNonExistence(timeout: 8),
                      "Stop must dismiss the playback controls.")
        XCTAssertTrue(surface.waitForNonExistence(timeout: 8))
        let network = element("mapNetworkToggle", in: app)
        let reachable = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in network.exists && network.isHittable },
            object: network)
        XCTAssertEqual(XCTWaiter.wait(for: [reachable], timeout: 8), .completed,
                      "Stopping playback must leave the map rail reachable.")
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func waitForLabel(_ label: String, on element: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", label), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 15), .completed,
                       "Expected playback action \(label); found \(element.label).")
    }

    private func assertContained(_ frame: CGRect, in container: CGRect, name: String) {
        XCTAssertFalse(frame.isEmpty, "\(name) has an empty frame.")
        // Accommodate fractional-point rounding at accessibility boundaries.
        XCTAssertTrue(container.insetBy(dx: -1, dy: -1).contains(frame),
                      "\(name) \(frame) escapes \(container).")
    }

    private func assertDisjoint(
        _ first: (name: String, frame: CGRect),
        _ second: (name: String, frame: CGRect)
    ) {
        let overlap = first.frame.intersection(second.frame)
        XCTAssertTrue(overlap.isNull || overlap.width <= 1 || overlap.height <= 1,
                      "\(first.name) \(first.frame) overlaps \(second.name) \(second.frame): \(overlap).")
    }

    private func attachScreen(named name: String) {
        // Physical display capture includes the map beneath the system sheet.
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
